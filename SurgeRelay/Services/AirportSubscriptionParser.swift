import Foundation

struct AirportProxyEntry: Equatable, Sendable {
    let originalName: String
    let definition: String
}

struct ProcessedAirportProxyEntry: Equatable, Sendable {
    let originalName: String
    let name: String
    let definition: String
}

struct AirportNodeProcessingRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { originalName }
    let originalName: String
    let outputName: String?
    let status: String
}

struct AirportNodeProcessingResult: Equatable, Sendable {
    let included: [ProcessedAirportProxyEntry]
    let records: [AirportNodeProcessingRecord]
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

    static func renamedNode(
        _ originalName: String,
        airportName: String,
        template: String,
        optimization: AirportNodeNameOptimization = AirportNodeNameOptimization()
    ) -> String {
        let optimizedName = optimizedNodeName(originalName, using: optimization)
        let template = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return optimizedName }
        return template
            .replacingOccurrences(of: "{airport}", with: airportName)
            .replacingOccurrences(of: "{name}", with: optimizedName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optimizedNodeName(
        _ originalName: String,
        using optimization: AirportNodeNameOptimization
    ) -> String {
        guard optimization.isEnabled else { return originalName }
        var name = originalName

        if optimization.removesEmoji {
            name.removeAll(where: isEmojiCharacter)
        }

        let terms = optimization.removalTerms
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for term in terms {
            name = name.replacingOccurrences(
                of: NSRegularExpression.escapedPattern(for: term),
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        name = name.replacingOccurrences(
            of: #"\[\s*\]|\(\s*\)|【\s*】|（\s*）"#,
            with: " ",
            options: .regularExpression
        )
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        name = name.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—_|/·•"))
        )
        return name.isEmpty ? "节点" : name
    }

    static func uniqueNodeName(_ preferredName: String, reserving usedNames: inout Set<String>) -> String {
        if usedNames.insert(preferredName.lowercased()).inserted {
            return preferredName
        }
        var index = 2
        while true {
            let candidate = "\(preferredName) \(index)"
            if usedNames.insert(candidate.lowercased()).inserted {
                return candidate
            }
            index += 1
        }
    }

    static func process(
        _ entries: [AirportProxyEntry],
        for subscription: AirportSubscription,
        reserving usedNames: inout Set<String>
    ) -> AirportNodeProcessingResult {
        let includeKeywords = normalizedKeywords(subscription.nodeProcessing.includeKeywords)
        let excludeKeywords = normalizedKeywords(subscription.nodeProcessing.excludeKeywords)
        let priorityKeywords = normalizedKeywords(subscription.nodeProcessing.sortPriorityKeywords)
        let regex = subscription.policyRegexFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [(index: Int, entry: AirportProxyEntry, preferredName: String)] = []
        var excludedRecords: [AirportNodeProcessingRecord] = []

        for (index, entry) in entries.enumerated() {
            let exclusionReason: String? = if isBuiltInDirect(entry) {
                "内置策略"
            } else if subscription.nodeProcessing.filtersMetadataNodes,
                      isSubscriptionMetadataName(entry.originalName) {
                "订阅信息"
            } else if !includeKeywords.isEmpty,
                      !containsAnyKeyword(entry.originalName, keywords: includeKeywords) {
                "不符合保留规则"
            } else if containsAnyKeyword(entry.originalName, keywords: excludeKeywords) {
                "命中排除规则"
            } else if !regex.isEmpty, !name(entry.originalName, matchesRegex: regex) {
                "未通过高级正则"
            } else {
                nil
            }

            if let exclusionReason {
                excludedRecords.append(AirportNodeProcessingRecord(
                    originalName: entry.originalName,
                    outputName: nil,
                    status: exclusionReason
                ))
                continue
            }

            let preferredName = renamedNode(
                entry.originalName,
                airportName: subscription.trimmedName,
                template: subscription.nodeNameTemplate,
                optimization: subscription.nodeNameOptimization
            )
            candidates.append((index, entry, preferredName))
        }

        switch subscription.nodeProcessing.sortOrder {
        case .original:
            break
        case .nameAscending:
            candidates.sort { lhs, rhs in
                let comparison = lhs.preferredName.localizedStandardCompare(rhs.preferredName)
                return comparison == .orderedSame ? lhs.index < rhs.index : comparison == .orderedAscending
            }
        case .nameDescending:
            candidates.sort { lhs, rhs in
                let comparison = lhs.preferredName.localizedStandardCompare(rhs.preferredName)
                return comparison == .orderedSame ? lhs.index < rhs.index : comparison == .orderedDescending
            }
        case .keywordPriority:
            candidates.sort { lhs, rhs in
                let lhsPriority = priorityIndex(for: lhs.preferredName, keywords: priorityKeywords)
                let rhsPriority = priorityIndex(for: rhs.preferredName, keywords: priorityKeywords)
                return lhsPriority == rhsPriority ? lhs.index < rhs.index : lhsPriority < rhsPriority
            }
        }

        var included: [ProcessedAirportProxyEntry] = []
        var includedRecords: [AirportNodeProcessingRecord] = []
        included.reserveCapacity(candidates.count)
        includedRecords.reserveCapacity(candidates.count)
        for candidate in candidates {
            let outputName = uniqueNodeName(candidate.preferredName, reserving: &usedNames)
            let definition = applyingProxyOverrides(
                to: candidate.entry.definition,
                options: subscription.nodeProcessing
            )
            included.append(ProcessedAirportProxyEntry(
                originalName: candidate.entry.originalName,
                name: outputName,
                definition: definition
            ))
            includedRecords.append(AirportNodeProcessingRecord(
                originalName: candidate.entry.originalName,
                outputName: outputName,
                status: outputName == candidate.entry.originalName ? "保留" : "已优化"
            ))
        }

        return AirportNodeProcessingResult(
            included: included,
            records: includedRecords + excludedRecords
        )
    }

    static func isSubscriptionMetadataName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        let keywords = [
            "traffic", "bandwidth", "expire", "expiry", "reset", "official website",
            "流量", "剩余", "到期", "过期", "重置", "官网", "网址", "套餐", "应急", "更新时间",
        ]
        return keywords.contains { normalized.contains($0) }
    }

    private static func normalizedKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private static func containsAnyKeyword(_ name: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            name.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func priorityIndex(for name: String, keywords: [String]) -> Int {
        keywords.firstIndex { keyword in
            name.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        } ?? keywords.count
    }

    private static func applyingProxyOverrides(
        to definition: String,
        options: AirportNodeProcessingOptions
    ) -> String {
        var tokens = commaSeparatedTokens(in: definition)
        guard let proxyType = tokens.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return definition
        }

        let udpTypes: Set<String> = [
            "ss", "vmess", "trojan", "snell", "socks5", "socks5-tls", "masque", "wireguard",
        ]
        let certificateTypes: Set<String> = [
            "vmess", "trojan", "https", "h2-connect", "socks5-tls", "tuic", "tuic-v5", "anytls",
            "trust-tunnel", "masque", "wireguard",
        ]

        if udpTypes.contains(proxyType), let value = options.udpRelay.boolValue {
            replaceOption(in: &tokens, aliases: ["udp-relay"], key: "udp-relay", value: value)
        }
        if let value = options.tcpFastOpen.boolValue {
            replaceOption(in: &tokens, aliases: ["tfo", "fast-open"], key: "tfo", value: value)
        }
        if certificateTypes.contains(proxyType), let value = options.skipCertificateVerification.boolValue {
            replaceOption(
                in: &tokens,
                aliases: ["skip-cert-verify"],
                key: "skip-cert-verify",
                value: value
            )
        }
        return tokens.joined(separator: ", ")
    }

    private static func replaceOption(
        in tokens: inout [String],
        aliases: Set<String>,
        key: String,
        value: Bool
    ) {
        tokens.removeAll { token in
            guard let equals = token.firstIndex(of: "=") else { return false }
            let existingKey = token[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return aliases.contains(existingKey)
        }
        tokens.append("\(key)=\(value ? "true" : "false")")
    }

    private static func commaSeparatedTokens(in value: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var isEscaped = false

        for character in value {
            if isEscaped {
                token.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                token.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                token.append(character)
                continue
            }
            if character == ",", quote == nil {
                tokens.append(token.trimmingCharacters(in: .whitespacesAndNewlines))
                token = ""
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty || !tokens.isEmpty {
            tokens.append(token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return tokens.filter { !$0.isEmpty }
    }

    private static func isEmojiCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let value = scalar.value
            return scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && value >= 0x1F000)
                || (0x1F1E6...0x1F1FF).contains(value)
                || (0x1F3FB...0x1F3FF).contains(value)
                || value == 0xFE0F
                || value == 0x200D
        }
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
