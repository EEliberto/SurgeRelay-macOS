import Foundation

actor GitHubClient {
    private enum PublishAttemptError: Error {
        case verificationFailed
        case headMoved
    }

    private struct GitHubMessage: Decodable { let message: String }
    private struct PublishManifest: Codable {
        let version: Int
        let paths: [String]
    }
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
    private struct BlobContentResponse: Decodable {
        let content: String
        let encoding: String
    }
    private struct TreeEntry: Encodable {
        let path: String
        let mode = "100644"
        let type = "blob"
        let sha: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encode(mode, forKey: .mode)
            try container.encode(type, forKey: .type)
            if let sha {
                try container.encode(sha, forKey: .sha)
            } else {
                try container.encodeNil(forKey: .sha)
            }
        }

        private enum CodingKeys: String, CodingKey { case path, mode, type, sha }
    }
    private struct TreeRequest: Encodable {
        let baseTree: String
        let tree: [TreeEntry]
        private enum CodingKeys: String, CodingKey { case baseTree = "base_tree", tree }
    }
    private struct TreeResponse: Decodable { let sha: String }
    private struct TreeListingEntry: Decodable {
        let path: String
        let type: String
        let sha: String
    }
    private struct TreeListingResponse: Decodable { let tree: [TreeListingEntry] }
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
    private let manifestFileName = ".surge-relay-manifest.json"
    private var verifiedPrivateDestinations = Set<String>()
    private var lastMutationAt: ContinuousClock.Instant?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func test(settings: GitHubSettings, token: String) async throws -> Bool {
        guard settings.isConfigured else { throw RelayError.githubNotConfigured }
        let url = try apiURL(settings: settings, fileName: nil)
        var request = URLRequest(url: url, timeoutInterval: 30)
        applyHeaders(to: &request, token: token)
        let (data, response) = try await performDataRequest(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RelayError.httpFailure(status: status, message: "无法访问该仓库。")
        }
        return try JSONDecoder().decode(RepositoryMetadata.self, from: data).isPrivate
    }

    func publish(
        files: [PublishFile],
        obsoleteFileNames: [String] = [],
        settings: GitHubSettings,
        token: String
    ) async throws -> PublishReport {
        guard settings.isConfigured else { throw RelayError.githubNotConfigured }
        guard !token.isEmpty else { throw RelayError.githubTokenMissing }
        guard !files.isEmpty else { throw RelayError.noFilesToPublish }

        // This check belongs at the upload boundary so automatic publishing and
        // future callers cannot bypass the private-repository policy.
        let destinationKey = "\(settings.owner.lowercased())/\(settings.repository.lowercased())"
        if !verifiedPrivateDestinations.contains(destinationKey) {
            guard try await test(settings: settings, token: token) else {
                throw RelayError.githubRepositoryMustBePrivate
            }
            verifiedPrivateDestinations.insert(destinationKey)
        }
        guard settings.hasValidCloudflarePublicBaseURL else {
            throw RelayError.cloudflareNotConfigured
        }

        let managedPaths = files.map(\.name).sorted()
        let manifestData = try JSONEncoder().encode(PublishManifest(version: 1, paths: managedPaths))
        let publishFiles = files + [PublishFile(name: manifestFileName, data: manifestData)]

        var repositoryPaths = Set<String>()
        for file in publishFiles {
            let path = repositoryPath(for: file.name, settings: settings)
            guard repositoryPaths.insert(path).inserted else {
                throw RelayError.invalidOutput("GitHub 发布列表包含重复路径：\(path)")
            }
        }

        let maximumAttempts = 5
        for attempt in 0..<maximumAttempts {
            do {
                return try await publishAttempt(
                    files: publishFiles,
                    obsoleteFileNames: obsoleteFileNames,
                    settings: settings,
                    token: token
                )
            } catch {
                guard attempt < maximumAttempts - 1, isRetryablePublishError(error) else {
                    if let attemptError = error as? PublishAttemptError {
                        switch attemptError {
                        case .verificationFailed:
                            throw RelayError.invalidOutput("GitHub 提交后内容校验失败，未确认发布成功。")
                        case .headMoved:
                            throw RelayError.githubRepositoryBusy(
                                retryAt: Date.now.addingTimeInterval(30 + Double.random(in: 0...15))
                            )
                        }
                    }
                    if isRepositoryConflictError(error) {
                        throw RelayError.githubRepositoryBusy(
                            retryAt: Date.now.addingTimeInterval(30 + Double.random(in: 0...15))
                        )
                    }
                    throw error
                }
                let exponentialDelay = min(1_000 * (1 << attempt), 8_000)
                let jitter = Int.random(in: 150...650)
                try await Task.sleep(for: .milliseconds(exponentialDelay + jitter))
            }
        }
        throw RelayError.invalidOutput("GitHub 发布重试次数已用尽。")
    }

    private func publishAttempt(
        files: [PublishFile],
        obsoleteFileNames: [String],
        settings: GitHubSettings,
        token: String
    ) async throws -> PublishReport {
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
        let existingTree: TreeListingResponse = try await requestJSON(
            path: "git/trees/\(headCommit.tree.sha)?recursive=1",
            method: "GET",
            settings: settings,
            token: token
        )
        let existingBlobSHAs = Dictionary(
            uniqueKeysWithValues: existingTree.tree
                .filter { $0.type == "blob" }
                .map { ($0.path, $0.sha) }
        )
        let previousManagedPaths = try await managedPaths(
            from: existingBlobSHAs,
            settings: settings,
            token: token
        )
        let desiredPaths = Set(files.map { repositoryPath(for: $0.name, settings: settings) })
        let changedFiles = files.filter { file in
            existingBlobSHAs[repositoryPath(for: file.name, settings: settings)] != file.data.gitBlobSHA1
        }
        let explicitlyObsoletePaths = files.flatMap(\.legacyNames) + obsoleteFileNames
        let deletionPaths = Set(explicitlyObsoletePaths.map { repositoryPath(for: $0, settings: settings) })
            .union(previousManagedPaths.map { repositoryPath(for: $0, settings: settings) })
            .filter { existingBlobSHAs[$0] != nil && !desiredPaths.contains($0) }
            .sorted()
        guard !changedFiles.isEmpty || !deletionPaths.isEmpty else { return PublishReport(publishedFiles: []) }

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
            let path = repositoryPath(for: file.name, settings: settings)
            entries.append(TreeEntry(path: path, sha: blob.sha))
        }
        for path in deletionPaths {
            entries.append(TreeEntry(path: path, sha: nil))
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
        // Another Mac may have advanced the same private repository while this
        // commit was being assembled. Re-read the branch before the compare-and-
        // swap update so we can rebuild on the new head instead of surfacing 422.
        let latestReference: ReferenceResponse = try await requestJSON(
            path: "git/ref/heads/\(branch)",
            method: "GET",
            settings: settings,
            token: token
        )
        guard latestReference.object.sha == headCommit.sha else {
            throw PublishAttemptError.headMoved
        }
        let updatedReference: ReferenceResponse
        do {
            updatedReference = try await requestJSON(
                path: "git/refs/heads/\(branch)",
                method: "PATCH",
                body: UpdateReferenceRequest(sha: commit.sha),
                settings: settings,
                token: token
            )
        } catch RelayError.httpFailure(let status, _) where status == 409 || status == 422 {
            // GitHub returns 422 when another writer advances the branch after
            // our preflight read. Rebuild the tree on the new HEAD.
            throw PublishAttemptError.headMoved
        }
        try Task.checkCancellation()
        guard updatedReference.object.sha == commit.sha else {
            throw PublishAttemptError.verificationFailed
        }
        let verifiedCommit: CommitResponse = try await requestJSON(
            path: "git/commits/\(updatedReference.object.sha)",
            method: "GET",
            settings: settings,
            token: token
        )
        guard verifiedCommit.sha == commit.sha, verifiedCommit.tree.sha == tree.sha else {
            throw PublishAttemptError.verificationFailed
        }
        return PublishReport(
            publishedFiles: changedFiles.map(\.name).filter { $0 != manifestFileName } + deletionPaths,
            commitSHA: commit.sha
        )
    }

    private func managedPaths(
        from existingBlobSHAs: [String: String],
        settings: GitHubSettings,
        token: String
    ) async throws -> Set<String> {
        let manifestPath = repositoryPath(for: manifestFileName, settings: settings)
        if let sha = existingBlobSHAs[manifestPath] {
            let blob: BlobContentResponse = try await requestJSON(
                path: "git/blobs/\(sha)",
                method: "GET",
                settings: settings,
                token: token
            )
            if blob.encoding.lowercased() == "base64",
               let data = Data(base64Encoded: blob.content, options: .ignoreUnknownCharacters),
               let manifest = try? JSONDecoder().decode(PublishManifest.self, from: data),
               manifest.version == 1 {
                return Set(manifest.paths)
            }
        }

        // Bootstrap cleanup for files whose names/directories have always been
        // reserved for Surge Relay. Unknown repository files remain untouched.
        let directory = settings.directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = directory.isEmpty ? "" : directory + "/"
        return Set(existingBlobSHAs.keys.compactMap { path in
            guard prefix.isEmpty || path.hasPrefix(prefix) else { return nil }
            let relative = prefix.isEmpty ? path : String(path.dropFirst(prefix.count))
            let lower = relative.lowercased()
            if lower.hasPrefix("assets/") || lower.hasSuffix("-surgerelay.sgmodule") {
                return relative
            }
            return nil
        })
    }

    private func isRetryablePublishError(_ error: Error) -> Bool {
        if error is PublishAttemptError { return true }
        return isRepositoryConflictError(error)
    }

    private func isRepositoryConflictError(_ error: Error) -> Bool {
        guard case let RelayError.httpFailure(status, message) = error else { return false }
        if status == 409 { return true }
        guard status == 422 else { return false }
        return message.localizedCaseInsensitiveContains("fast forward")
            || message.localizedCaseInsensitiveContains("reference update")
            || message.localizedCaseInsensitiveContains("sha does not match")
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
        if ["POST", "PATCH", "PUT", "DELETE"].contains(method) {
            try await pauseBeforeMutation()
        }
        let (data, response) = try await performDataRequest(request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(GitHubMessage.self, from: data).message)
                ?? String(data: data, encoding: .utf8) ?? "未知错误"
            throw RelayError.httpFailure(status: status, message: message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
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

    private func performDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        if let httpResponse = response as? HTTPURLResponse,
           shouldRetryRateLimit(response: httpResponse, data: data) {
            throw RelayError.githubRateLimited(
                retryAt: Date.now.addingTimeInterval(rateLimitDelay(response: httpResponse))
            )
        }
        return (data, response)
    }

    private func shouldRetryRateLimit(response: HTTPURLResponse, data: Data) -> Bool {
        if response.statusCode == 429 { return true }
        guard response.statusCode == 403 else { return false }
        let message = (try? JSONDecoder().decode(GitHubMessage.self, from: data).message) ?? ""
        return message.localizedCaseInsensitiveContains("rate limit")
    }

    private func rateLimitDelay(response: HTTPURLResponse) -> TimeInterval {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfter) {
            return max(seconds, 1)
        }
        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let timestamp = TimeInterval(reset) {
            return max(timestamp - Date.now.timeIntervalSince1970, 1)
        }
        // GitHub requires at least a one-minute pause for a secondary limit
        // response that does not include an explicit retry time.
        return 60 + Double.random(in: 0...10)
    }

    private func pauseBeforeMutation() async throws {
        if let lastMutationAt {
            let elapsed = lastMutationAt.duration(to: .now)
            if elapsed < .seconds(1) {
                try await Task.sleep(for: .seconds(1) - elapsed)
            }
        }
        lastMutationAt = .now
    }
}
