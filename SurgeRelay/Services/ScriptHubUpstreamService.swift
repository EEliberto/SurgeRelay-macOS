import Foundation

actor ScriptHubUpstreamService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchManagedModule(from source: String, previousRevision: String?) async throws -> UpstreamUpdateResult {
        guard let url = URL(string: source) else { throw RelayError.invalidSourceURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.setValue("SurgeRelay/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(status) else {
            throw RelayError.httpFailure(status: status, message: String(body.prefix(240)))
        }
        guard body.contains("script.hub"), body.contains("script-path=") else {
            throw RelayError.invalidOutput("上游文件不是可识别的 Script Hub Surge 模块。")
        }

        var revisionMaterial = data
        var scripts: [String: Data] = [:]
        for scriptURL in scriptURLs(in: body) {
            var scriptRequest = URLRequest(url: scriptURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
            scriptRequest.setValue("SurgeRelay/0.1", forHTTPHeaderField: "User-Agent")
            let (scriptData, scriptResponse) = try await session.data(for: scriptRequest)
            let scriptStatus = (scriptResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(scriptStatus), !scriptData.isEmpty else {
                throw RelayError.httpFailure(status: scriptStatus, message: "无法检查上游脚本 \(scriptURL.lastPathComponent)。")
            }
            revisionMaterial.append(scriptData)
            scripts[scriptURL.lastPathComponent] = scriptData
        }

        let revision = String(revisionMaterial.sha256String.prefix(12))
        guard scripts["Rewrite-Parser.js"] != nil else {
            throw RelayError.invalidOutput("上游模块没有引用 Rewrite-Parser.js。")
        }
        return UpstreamUpdateResult(revision: revision, changed: revision != previousRevision, scripts: scripts)
    }

    private func scriptURLs(in module: String) -> [URL] {
        let pattern = #"script-path=(https://raw\.githubusercontent\.com/[^,\s?]+)(?:\?[^,\s]*)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = expression.matches(in: module, range: NSRange(module.startIndex..., in: module))
        var seen = Set<String>()
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: module) else { return nil }
            let value = String(module[range])
            guard seen.insert(value).inserted else { return nil }
            return URL(string: value)
        }
    }

}
