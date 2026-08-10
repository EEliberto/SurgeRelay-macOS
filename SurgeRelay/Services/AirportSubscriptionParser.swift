import Foundation

struct AirportProxyEntry: Equatable, Sendable {
    let originalName: String
    let definition: String
}

enum AirportSubscriptionParser {
    static func proxyEntries(from data: Data) throws -> [AirportProxyEntry] {
        guard let initial = decodedText(data) else {
            throw RelayError.invalidOutput("订阅内容不是可识别的文本或 Base64 文本。")
        }
        let text = decodedBase64TextIfNeeded(initial) ?? initial
        let lines = text.components(separatedBy: .newlines)
        let proxyLines: ArraySlice<String>

        if let proxyHeader = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[Proxy]" }) {
            let start = lines.index(after: proxyHeader)
            let end = lines[start...].firstIndex(where: {
                let value = $0.trimmingCharacters(in: .whitespaces)
                return value.hasPrefix("[") && value.hasSuffix("]")
            }) ?? lines.endIndex
            proxyLines = lines[start..<end]
        } else {
            proxyLines = lines[...]
        }

        var seen = Set<String>()
        let entries = proxyLines.compactMap { line -> AirportProxyEntry? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//"),
                  let equals = trimmed.firstIndex(of: "=") else { return nil }
            let rawName = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let definition = String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !definition.isEmpty, seen.insert(name).inserted else { return nil }
            return AirportProxyEntry(originalName: name, definition: definition)
        }
        guard !entries.isEmpty else {
            throw RelayError.invalidOutput("订阅中没有找到 Surge [Proxy] 代理条目。")
        }
        return entries
    }

    /// Makes the common subscription metadata labels filterable with either
    /// their English source names or the Chinese terms users normally enter.
    static func name(_ name: String, matchesRegex pattern: String) -> Bool {
        var searchableName = name
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("traffic") { searchableName += " 流量" }
        if lowercaseName.contains("expire") || lowercaseName.contains("expiry") {
            searchableName += " 到期"
        }
        if lowercaseName.contains("reset") { searchableName += " 重置" }
        return searchableName.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func isBuiltInDirect(_ entry: AirportProxyEntry) -> Bool {
        guard entry.originalName.caseInsensitiveCompare("DIRECT") == .orderedSame else {
            return false
        }
        let policyType = entry.definition
            .split(separator: ",", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return policyType == "direct"
    }

    private static func decodedText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func decodedBase64TextIfNeeded(_ text: String) -> String? {
        guard !text.contains("[Proxy]"), !text.contains(" = ") else { return nil }
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: compact), let decoded = decodedText(data), decoded.contains("=") else {
            return nil
        }
        return decoded
    }
}
