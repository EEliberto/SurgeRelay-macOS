import Foundation

enum ModuleLintSeverity: String, Codable, Hashable, Sendable {
    case error, warning

    var title: String { self == .error ? "错误" : "提醒" }
}

struct ModuleLintIssue: Identifiable, Codable, Hashable, Sendable {
    var filePath: String
    var line: Int
    var severity: ModuleLintSeverity
    var code: String
    var message: String
    var relatedLine: Int? = nil

    var id: String { "\(filePath):\(line):\(code):\(message)" }
}
