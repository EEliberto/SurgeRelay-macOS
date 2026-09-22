import Foundation
import Darwin

enum AirportSubscriptionDirectRules {
    static let startMarker = "# >>> Surge Relay 机场订阅直连"
    static let endMarker = "# <<< Surge Relay 机场订阅直连"

    static func rules(
        for subscriptions: [AirportSubscription],
        proxyEntries: [AirportProxyEntry] = []
    ) -> [String] {
        // Disabled node groups may still be refreshed, so include every saved subscription.
        let sourceHosts = subscriptions.compactMap { subscription -> String? in
            guard subscription.isConfigured,
                  let url = URL(string: subscription.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let host = url.host else { return nil }
            return host
        }
        let nodeHosts = proxyEntries.compactMap { proxyServerHost(from: $0.definition) }
        return Array(Set((sourceHosts + nodeHosts).compactMap(rule(forHost:)))).sorted()
    }

    static func block(
        for subscriptions: [AirportSubscription],
        proxyEntries: [AirportProxyEntry] = []
    ) -> String {
        ([startMarker] + rules(for: subscriptions, proxyEntries: proxyEntries) + [endMarker])
            .joined(separator: "\n")
    }

    static func updating(
        _ configuration: String,
        subscriptions: [AirportSubscription],
        proxyEntries: [AirportProxyEntry] = []
    ) throws -> String {
        let newline = configuration.contains("\r\n") ? "\r\n" : "\n"
        var lines = configuration.components(separatedBy: newline)
        func trimmed(_ line: String) -> String { line.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rules = rules(for: subscriptions, proxyEntries: proxyEntries)
        let starts = lines.indices.filter { trimmed(lines[$0]) == startMarker }
        let ends = lines.indices.filter { trimmed(lines[$0]) == endMarker }
        var header = lines.firstIndex { trimmed($0).lowercased() == "[rule]" }
        if !starts.isEmpty || !ends.isEmpty {
            guard let header, starts.count == 1, ends.count == 1,
                  let start = starts.first, let end = ends.first, start > header, end > start,
                  !lines[(header + 1)...end].contains(where: {
                      let text = trimmed($0)
                      return text.hasPrefix("[") && text.hasSuffix("]")
                  }) else {
                throw RelayError.invalidOutput("机场订阅直连区块标记不完整或位置错误，未修改配置文件。")
            }
            lines.removeSubrange(starts[0]...ends[0])
        }
        if let header {
            let end = lines[(header + 1)...].firstIndex { line in
                let value = trimmed(line)
                return value.hasPrefix("[") && value.hasSuffix("]")
            } ?? lines.endIndex
            let airportLabels = Set(subscriptions.map { "# 直连策略 " + $0.trimmedName.lowercased() })
            let canonicalRules = Set(rules)
            let canonicalHosts = Set(rules.compactMap { rule in
                rule.components(separatedBy: ",").dropFirst().first?.lowercased()
            })
            var removals = Set<Int>()
            var airportLabel: Int?
            for index in (header + 1)..<end {
                let text = trimmed(lines[index])
                if text.hasPrefix("#") || text.hasPrefix("//") || text.hasPrefix(";") {
                    airportLabel = airportLabels.contains(text.lowercased()) ? index : nil
                    continue
                }
                if text.isEmpty { continue }
                let tokens = text.components(separatedBy: ",").map { trimmed($0) }
                let plainDomainRule = tokens.count == 3
                    && ["DOMAIN", "DOMAIN-SUFFIX"].contains(tokens[0].uppercased())
                    && tokens[2].uppercased() == "DIRECT"
                if plainDomainRule, let label = airportLabel {
                    // Migrate labeled legacy airport rules, replacing stale domains with
                    // the current saved URLs instead of retaining a second handwritten list.
                    removals.insert(label)
                    removals.insert(index)
                } else if plainDomainRule, canonicalHosts.contains(tokens[1].lowercased()) {
                    removals.insert(index)
                } else if canonicalRules.contains(tokens.joined(separator: ",")) {
                    removals.insert(index)
                } else {
                    airportLabel = nil
                }
            }
            for index in removals.sorted(by: >) { lines.remove(at: index) }
        }
        if rules.isEmpty { return lines.joined(separator: newline) }
        if header == nil {
            if lines.last != "" { lines.append("") }
            lines.append("[Rule]")
            header = lines.count - 1
            lines.append("")
        }
        // Reinsert at the top even if someone moved the old block below a catch-all rule.
        lines.insert(contentsOf: [startMarker] + rules + [endMarker], at: header! + 1)
        return lines.joined(separator: newline)
    }

    private static func proxyServerHost(from definition: String) -> String? {
        let tokens = commaSeparatedTokens(in: definition)
        guard tokens.count >= 3 else { return nil }
        let type = tokens[0].lowercased()
        guard !["direct", "reject", "reject-tinygif", "reject-drop"].contains(type) else { return nil }
        return unquoted(tokens[1])
    }

    private static func rule(forHost rawHost: String) -> String? {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        while host.hasSuffix(".") { host.removeLast() }
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return "IP-CIDR,\(host)/32,DIRECT,no-resolve"
        }
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            return "IP-CIDR6,\(host)/128,DIRECT,no-resolve"
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return "DOMAIN-SUFFIX,\(host),DIRECT"
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first, let last = trimmed.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func commaSeparatedTokens(in value: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false
        for character in value {
            if escaped {
                token.append(character)
                escaped = false
            } else if character == "\\" {
                token.append(character)
                escaped = true
            } else if character == "\"" || character == "'" {
                quote = quote == character ? nil : (quote == nil ? character : quote)
                token.append(character)
            } else if character == ",", quote == nil {
                tokens.append(token.trimmingCharacters(in: .whitespacesAndNewlines))
                token = ""
            } else {
                token.append(character)
            }
        }
        tokens.append(token.trimmingCharacters(in: .whitespacesAndNewlines))
        return tokens
    }
}
