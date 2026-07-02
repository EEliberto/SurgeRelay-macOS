import Foundation

enum FilenameSanitizer {
    static func baseName(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutExtension = trimmed.lowercased().hasSuffix(".sgmodule")
            ? String(trimmed.dropLast(".sgmodule".count))
            : trimmed
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return withoutExtension
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
    }

    static func sgmoduleName(from value: String) -> String {
        let base = baseName(from: value)
        return base.isEmpty ? "Untitled.sgmodule" : "\(base).sgmodule"
    }

    static func individualRelayName(from value: String) -> String {
        let base = baseName(from: value)
        let normalized = base.isEmpty ? "Untitled" : base
        if normalized.lowercased().hasSuffix("-surgerelay") {
            return "\(normalized).sgmodule"
        }
        return "\(normalized)-SurgeRelay.sgmodule"
    }

    static func suggestedName(from sourceURL: String) -> String {
        guard let url = URL(string: sourceURL) else { return "" }
        let candidate = url.deletingPathExtension().lastPathComponent
        return baseName(from: candidate)
    }
}
