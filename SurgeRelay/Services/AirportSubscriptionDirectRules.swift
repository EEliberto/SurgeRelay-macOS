import Foundation
import Darwin

/// Rules cover subscription download hosts only, never proxy server addresses or URL tokens.
enum AirportSubscriptionDirectRules {
    static let startMarker = "# >>> Surge Relay 机场订阅直连"
    static let endMarker = "# <<< Surge Relay 机场订阅直连"

    static func rules(for subscriptions: [AirportSubscription]) -> [String] {
        // Disabled node groups may still be refreshed, so include all saved subscriptions.
        let rules = subscriptions.compactMap { subscription -> String? in
            guard subscription.isConfigured,
                  let url = URL(string: subscription.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  var host = url.host?.lowercased() else { return nil }
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
            // Exact hosts avoid bypassing unrelated tenants on shared subscription/CDN domains.
            return "DOMAIN,\(host),DIRECT"
        }
        return Array(Set(rules)).sorted()
    }

    static func block(for subscriptions: [AirportSubscription]) -> String {
        ([startMarker] + rules(for: subscriptions) + [endMarker]).joined(separator: "\n")
    }

    static func updating(_ configuration: String, subscriptions: [AirportSubscription]) throws -> String {
        let newline = configuration.contains("\r\n") ? "\r\n" : "\n"
        var lines = configuration.components(separatedBy: newline)
        func trimmed(_ line: String) -> String { line.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rules = rules(for: subscriptions)
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
                } else if plainDomainRule,
                          canonicalRules.contains("DOMAIN,\(tokens[1].lowercased()),DIRECT") {
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
}
