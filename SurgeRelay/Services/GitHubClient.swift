import Foundation

actor GitHubClient {
    private struct ExistingContent: Decodable { let sha: String }
    private struct GitHubMessage: Decodable { let message: String }
    private struct RepositoryMetadata: Decodable {
        let isPrivate: Bool
        private enum CodingKeys: String, CodingKey { case isPrivate = "private" }
    }
    private struct GitObject: Codable { let sha: String }
    private struct ReferenceResponse: Decodable { let object: GitObject }
    private struct CommitResponse: Decodable {
        let sha: String
        let tree: GitObject
    }
    private struct BlobRequest: Encodable {
        let content: String
        let encoding = "base64"
    }
    private struct BlobResponse: Decodable { let sha: String }
    private struct TreeEntry: Encodable {
        let path: String
        let mode = "100644"
        let type = "blob"
        let sha: String
    }
    private struct TreeRequest: Encodable {
        let baseTree: String
        let tree: [TreeEntry]
        private enum CodingKeys: String, CodingKey { case baseTree = "base_tree", tree }
    }
    private struct TreeResponse: Decodable { let sha: String }
    private struct CommitRequest: Encodable {
        let message: String
        let tree: String
        let parents: [String]
    }
    private struct UpdateReferenceRequest: Encodable {
        let sha: String
        let force = false
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func test(settings: GitHubSettings, token: String) async throws -> Bool {
        guard settings.isConfigured else { throw RelayError.githubNotConfigured }
        let url = try apiURL(settings: settings, fileName: nil)
        var request = URLRequest(url: url, timeoutInterval: 30)
        applyHeaders(to: &request, token: token)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RelayError.httpFailure(status: status, message: "无法访问该仓库。")
        }
        return try JSONDecoder().decode(RepositoryMetadata.self, from: data).isPrivate
    }

    func publish(files: [PublishFile], settings: GitHubSettings, token: String) async throws -> PublishReport {
        guard settings.isConfigured else { throw RelayError.githubNotConfigured }
        guard !token.isEmpty else { throw RelayError.githubTokenMissing }
        guard !files.isEmpty else { throw RelayError.noFilesToPublish }

        // This check belongs at the upload boundary so automatic publishing and
        // future callers cannot bypass the private-repository policy.
        guard try await test(settings: settings, token: token) else {
            throw RelayError.githubRepositoryMustBePrivate
        }
        guard settings.hasValidCloudflarePublicBaseURL else {
            throw RelayError.cloudflareNotConfigured
        }

        var changedFiles: [PublishFile] = []
        for file in files {
            try Task.checkCancellation()
            let sha = try await existingSHA(fileName: file.name, settings: settings, token: token)
            if sha != file.data.gitBlobSHA1 { changedFiles.append(file) }
        }
        guard !changedFiles.isEmpty else { return PublishReport(publishedFiles: []) }

        let branch = encodedPathComponent(settings.branch)
        let reference: ReferenceResponse = try await requestJSON(
            path: "git/ref/heads/\(branch)",
            method: "GET",
            settings: settings,
            token: token
        )
        let headCommit: CommitResponse = try await requestJSON(
            path: "git/commits/\(reference.object.sha)",
            method: "GET",
            settings: settings,
            token: token
        )
        var entries: [TreeEntry] = []
        for file in changedFiles {
            try Task.checkCancellation()
            let blob: BlobResponse = try await requestJSON(
                path: "git/blobs",
                method: "POST",
                body: BlobRequest(content: file.data.base64EncodedString()),
                settings: settings,
                token: token
            )
            entries.append(TreeEntry(path: repositoryPath(for: file.name, settings: settings), sha: blob.sha))
        }
        let tree: TreeResponse = try await requestJSON(
            path: "git/trees",
            method: "POST",
            body: TreeRequest(baseTree: headCommit.tree.sha, tree: entries),
            settings: settings,
            token: token
        )
        let commit: CommitResponse = try await requestJSON(
            path: "git/commits",
            method: "POST",
            body: CommitRequest(
                message: "Update \(changedFiles.count) files via Surge Relay",
                tree: tree.sha,
                parents: [headCommit.sha]
            ),
            settings: settings,
            token: token
        )
        let _: ReferenceResponse = try await requestJSON(
            path: "git/refs/heads/\(branch)",
            method: "PATCH",
            body: UpdateReferenceRequest(sha: commit.sha),
            settings: settings,
            token: token
        )
        try Task.checkCancellation()
        return PublishReport(publishedFiles: changedFiles.map(\.name), commitSHA: commit.sha)
    }

    private func requestJSON<Response: Decodable>(
        path: String,
        method: String,
        settings: GitHubSettings,
        token: String
    ) async throws -> Response {
        try await requestJSON(path: path, method: method, bodyData: nil, settings: settings, token: token)
    }

    private func requestJSON<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        settings: GitHubSettings,
        token: String
    ) async throws -> Response {
        try await requestJSON(
            path: path,
            method: method,
            bodyData: JSONEncoder().encode(body),
            settings: settings,
            token: token
        )
    }

    private func requestJSON<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        settings: GitHubSettings,
        token: String
    ) async throws -> Response {
        let url = try apiURL(settings: settings, suffix: path)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        applyHeaders(to: &request, token: token)
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(GitHubMessage.self, from: data).message)
                ?? String(data: data, encoding: .utf8) ?? "未知错误"
            throw RelayError.httpFailure(status: status, message: message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func existingSHA(fileName: String, settings: GitHubSettings, token: String) async throws -> String? {
        var components = URLComponents(url: try apiURL(settings: settings, fileName: fileName), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "ref", value: settings.branch)]
        guard let url = components?.url else { throw RelayError.githubNotConfigured }
        var request = URLRequest(url: url, timeoutInterval: 30)
        applyHeaders(to: &request, token: token)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(GitHubMessage.self, from: data).message) ?? "GitHub 查询失败。"
            throw RelayError.httpFailure(status: status, message: message)
        }
        return try JSONDecoder().decode(ExistingContent.self, from: data).sha
    }

    private func apiURL(settings: GitHubSettings, fileName: String?) throws -> URL {
        var path = "https://api.github.com/repos/\(settings.owner)/\(settings.repository)"
        if let fileName {
            let directory = settings.directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let fullPath = [directory, fileName].filter { !$0.isEmpty }.joined(separator: "/")
            path += "/contents/\(fullPath)"
        }
        guard let url = URL(string: path) else { throw RelayError.githubNotConfigured }
        return url
    }

    private func apiURL(settings: GitHubSettings, suffix: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com/repos/\(settings.owner)/\(settings.repository)/\(suffix)") else {
            throw RelayError.githubNotConfigured
        }
        return url
    }

    private func repositoryPath(for fileName: String, settings: GitHubSettings) -> String {
        let directory = settings.directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [directory, fileName].filter { !$0.isEmpty }.joined(separator: "/")
    }

    private func encodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func applyHeaders(to request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SurgeRelay/1.0", forHTTPHeaderField: "User-Agent")
    }
}
