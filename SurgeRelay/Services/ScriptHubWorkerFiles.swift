import Foundation

struct ScriptHubWorkerRequest: Codable {
    let requestURL: URL
    let hasConverter: Bool
    var capturesMetrics: Bool? = nil
}

struct ScriptHubWorkerResponse: Codable {
    let succeeded: Bool
    let error: String?
    var retryAfter: SourceRetryAfterError? = nil
    var stageMetrics: [StageMetric]? = nil
}

enum ScriptHubWorkerFiles {
    static let maximumScriptBytes = 20 * 1024 * 1024
    static let maximumOutputBytes = 20 * 1024 * 1024
    static let maximumMetadataBytes = 64 * 1024
    static let requestName = "request.json"
    static let scriptName = "parser.js"
    static let converterName = "converter.js"
    static let outputName = "output.txt"
    static let responseName = "response.json"

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            throw RelayError.invalidOutput("Script-Hub helper 文件超过 \(maximumBytes / 1024) KB 限制。")
        }
        return data
    }
}
