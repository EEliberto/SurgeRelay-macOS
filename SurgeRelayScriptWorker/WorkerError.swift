import Foundation
// The helper shares no app model or UI dependencies.
enum RelayError: LocalizedError {
    case invalidSourceURL
    case invalidOutput(String)
    case httpFailure(status: Int, message: String)
    var errorDescription: String? {
        switch self {
        case .invalidSourceURL: "来源地址无效。"
        case .invalidOutput(let message): message
        case .httpFailure(let status, let message): "HTTP \(status)：\(message)"
        }
    }
}
