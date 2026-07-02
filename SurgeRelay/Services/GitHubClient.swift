import Foundation

actor GitHubClient {
    private enum PublishAttemptError: Error {
        case verificationFailed
    }

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

        var repositoryPaths = Set<String>()
        for file in files {
            let path = repositoryPath(for: file.name, settings: settings)
            guard repositoryPaths.insert(path).inserted else {
                throw RelayError.invalidOutput("GitHub 发布列表包含重复路径：\(path)")
            }
        }

        for attempt in 0..<3 {
            do {
                return try await publishAttempt(files: files, settings: settings, token: token)
            } catch {
                guard attempt < 2, isRetryablePublishError(error) else {
                    if error is PublishAttemptError {
                        throw RelayError.invalidOutput("GitHub 提交后内容校验失败，未确认发布成功。")
                    }
                    throw error
                }
                try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
            }
        }
        throw RelayError.invalidOutput("GitHub 发布重试次数已用尽。")
    }

    private func publishAttempt(
        files: [PublishFile],
        settings: GitHubSettings,
        token: String
    ) async throws -> PublishReport {
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
        var expectedBlobSHAs: [String: String] = [:]
        for file in changedFiles {
            try Task.checkCancellation()
            let blob: BlobResponse = try await requestJSON(
                path: "git/blobs",
                method: "POST",
                body: BlobRequest(content: file.data.base64EncodedString()),
                settings: settings,
                token: token
            )
            let path = repositoryPath(for: file.name, settings: settings)
            entries.append(TreeEntry(path: path, sha: blob.sha))
            expectedBlobSHAs[file.name] = blob.sha
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
        let updatedReference: ReferenceResponse = try await requestJSON(
            path: "git/refs/heads/\(branch)",
            method: "PATCH",
            body: UpdateReferenceRequest(sha: commit.sha),
            settings: settings,
            token: token
        )
        try Task.checkCancellation()
        guard updatedReference.object.sha == commit.sha else {
            throw PublishAttemptError.verificationFailed
        }

        for file in changedFiles {
            let remoteSHA = try await existingSHA(fileName: file.name, settings: settings, token: token)
            guard remoteSHA == expectedBlobSHAs[file.name] else {
                throw PublishAttemptError.verificationFailed
            }
        }
        return PublishReport(publishedFiles: changedFiles.map(\.name), commitSHA: commit.sha)
    }

    private func isRetryablePublishError(_ error: Error) -> Bool {
        if error is PublishAttemptError { return true }
        if case let RelayError.httpFailure(status, _) = error {
            return status == 409 || status == 422
        }
        return false
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
