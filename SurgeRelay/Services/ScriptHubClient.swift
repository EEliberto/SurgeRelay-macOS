import Foundation

actor ScriptHubClient {
    private let engineStore: EngineStore
    private let embeddedEngine: EmbeddedScriptHubEngine
    private let session: URLSession

    init(
        engineStore: EngineStore = EngineStore(),
        embeddedEngine: EmbeddedScriptHubEngine = EmbeddedScriptHubEngine(),
        session: URLSession = .shared
    ) {
        self.engineStore = engineStore
        self.embeddedEngine = embeddedEngine
        self.session = session
    }

    func conversionURL(module: RelayModule, baseURL: String) throws -> URL {
        guard let sourceURL = URL(string: module.sourceURL),
              ["http", "https"].contains(sourceURL.scheme?.lowercased()) else {
            throw RelayError.invalidSourceURL
        }

        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmedBase.hasPrefix("http://") || trimmedBase.hasPrefix("https://") else {
            throw RelayError.invalidServiceURL
        }

        let source = sourceURL.absoluteString.components(separatedBy: "#").first ?? sourceURL.absoluteString
        let fileName = FilenameSanitizer.baseName(from: module.outputFileName)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "module"
        let type = module.sourceFormat.scriptHubType(for: sourceURL)
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "target", value: "surge-module")
        ] + module.scriptHubOptions.queryItems()
        guard let query = components.percentEncodedQuery else { throw RelayError.invalidServiceURL }
        let raw = "\(trimmedBase)/file/_start_/\(source)/_end_/\(fileName).sgmodule?\(query)"

        guard let url = URL(string: raw) else { throw RelayError.invalidServiceURL }
        return url
    }

    func convert(module: RelayModule, github: GitHubSettings? = nil) async throws -> ConversionResult {
        guard let sourceURL = URL(string: module.sourceURL),
              ["http", "https"].contains(sourceURL.scheme?.lowercased()) else { throw RelayError.invalidSourceURL }
        if module.sourceFormat.isNativeSurgeModule(for: sourceURL) {
            var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
            request.setValue("SurgeRelay/0.1", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               let retry = SourceRetryAfterError.response(http, requestedURL: sourceURL) { throw retry }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let content = String(data: data, encoding: .utf8) ?? ""
            guard (200..<300).contains(status) else {
                throw RelayError.httpFailure(status: status, message: String(content.prefix(240)))
            }
            let namedContent = ModuleMetadataParser.applyingDisplayName(module.name, to: content)
            let sanitized = SurgeModuleSanitizer.sanitize(namedContent)
            try validate(sanitized)
            return ConversionResult(content: sanitized, requestURL: sourceURL)
        }
        let url = try conversionURL(module: module, baseURL: "http://script.hub")
        let script = try await engineStore.script(named: "Rewrite-Parser.js")
        let converter = try await engineStore.script(named: "script-converter.js")
        let content = try await embeddedEngine.convert(
            script: script,
            scriptConverterScript: converter,
            requestURL: url
        )
        let materialized = try await materializeConvertedScripts(
            in: content,
            module: module,
            converterScript: converter,
            github: github
        )
        let namedContent = ModuleMetadataParser.applyingDisplayName(module.name, to: materialized.content)
        let sanitized = SurgeModuleSanitizer.sanitize(namedContent)
        try validate(sanitized)
        return ConversionResult(content: sanitized, requestURL: url, assets: materialized.assets)
    }

    func validate(_ content: String) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RelayError.invalidOutput("服务器返回了空内容。") }
        if trimmed.contains("Script Hub 重写转换: ❌") || trimmed.hasPrefix("<!DOCTYPE html") {
            throw RelayError.invalidOutput(String(trimmed.prefix(240)))
        }
        let markers = ["#!name=", "[General]", "[MITM]", "[Script]", "[URL Rewrite]", "[Header Rewrite]", "[Rule]"]
        guard markers.contains(where: trimmed.contains) else {
            throw RelayError.invalidOutput("没有检测到 Surge 模块标记或可用配置段。")
        }
    }

    private func materializeConvertedScripts(
        in content: String,
        module: RelayModule,
        converterScript: String,
        github: GitHubSettings?
    ) async throws -> (content: String, assets: [GeneratedAsset]) {
        let pattern = #"script-path\s*=\s*(http://script\.hub/convert/_start_/.*?/_end_/[^,\s]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return (content, [])
        }
        let matches = expression.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let urls = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
        let uniqueURLs = Array(Set(urls)).sorted()
        guard !uniqueURLs.isEmpty else { return (content, []) }
        guard let github, github.isConfigured else {
            throw RelayError.invalidOutput("启用“脚本转换”后，需要先在 GitHub 发布中配置仓库，以托管转换后的脚本文件。")
        }

        var rewritten = content
        var assets: [GeneratedAsset] = []
        for source in uniqueURLs {
            guard let requestURL = URL(string: source) else { throw RelayError.invalidServiceURL }
            let converted = try await embeddedEngine.convert(script: converterScript, requestURL: requestURL)
            guard !converted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RelayError.invalidOutput("脚本转换返回了空内容。")
            }
            let hash = String(Data(source.utf8).sha256String.prefix(12))
            let tail = source.components(separatedBy: "/_end_/").last?.components(separatedBy: "?").first ?? "script.js"
            var fileName = FilenameSanitizer.baseName(from: tail.removingPercentEncoding ?? tail)
            if fileName.isEmpty { fileName = "script.js" }
            if !fileName.lowercased().hasSuffix(".js") { fileName += ".js" }
            let relativePath = "assets/\(module.id.uuidString.lowercased())/\(hash)-\(fileName)"
            guard let remoteURL = github.publicURL(for: relativePath) else {
                throw RelayError.invalidOutput("私有仓库需要先配置 Cloudflare Worker 公共地址，才能发布转换后的脚本。")
            }
            rewritten = rewritten.replacingOccurrences(of: source, with: remoteURL.absoluteString)
            assets.append(GeneratedAsset(relativePath: relativePath, data: Data(converted.utf8)))
        }
        return (rewritten, assets)
    }
}

actor SourceRevisionService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(_ module: RelayModule) async throws -> SourceRevisionResult {
        guard let url = URL(string: module.sourceURL),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw RelayError.invalidSourceURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 45)
        request.setValue("SurgeRelay/1.0", forHTTPHeaderField: "User-Agent")
        if let etag = module.sourceETag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = module.sourceLastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RelayError.invalidOutput("来源没有返回有效的 HTTP 响应。")
        }
        if let retry = SourceRetryAfterError.response(http, requestedURL: url) { throw retry }
        if http.statusCode == 304, let hash = module.sourceContentHash {
            return .unchanged(SourceRevisionSnapshot(
                etag: module.sourceETag,
                lastModified: module.sourceLastModified,
                contentHash: hash,
                checkedAt: .now
            ))
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(240)) } ?? "来源检查失败。"
            throw RelayError.httpFailure(status: http.statusCode, message: message)
        }
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else {
            throw RelayError.invalidOutput("来源文件为空或超过 20 MB。")
        }
        let snapshot = SourceRevisionSnapshot(
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            contentHash: data.sha256String,
            checkedAt: .now
        )
        return snapshot.contentHash == module.sourceContentHash ? .unchanged(snapshot) : .changed(snapshot)
    }
}
