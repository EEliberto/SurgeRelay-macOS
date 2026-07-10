import Foundation

enum ModuleMetadataParser {
    static func iconURL(in content: String, relativeTo source: String? = nil) -> URL? {
        let pattern = #"(?im)^\s*#!icon\s*=\s*(.+?)\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }

        let value = String(content[range])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !value.isEmpty else { return nil }

        let baseURL = source.flatMap(URL.init(string:))
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    /// The module's own display name from its metadata header (`#!name=…`),
    /// used by Surge `.sgmodule` and Loon plugins. Returns nil when absent
    /// (e.g. most Quantumult X rewrite `.conf` files have no name field).
    static func displayName(in content: String) -> String? {
        let pattern = #"(?im)^\s*#!\s*name\s*=\s*(.+?)\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        let value = String(content[range])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return value.isEmpty ? nil : value
    }

    static func applyingDisplayName(_ name: String, to content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let line = "#!name=\(name.trimmingCharacters(in: .whitespacesAndNewlines))"
        guard let expression = try? NSRegularExpression(pattern: #"(?im)^\s*#!name\s*=.*$"#) else {
            return line + "\n" + normalized
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        if expression.firstMatch(in: normalized, range: range) != nil {
            return expression.stringByReplacingMatches(
                in: normalized,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: line)
            )
        }
        return line + "\n" + normalized
    }
}

struct ModuleArgumentDefinition: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let defaultValue: String
}

struct ModuleArgumentInfo: Hashable, Sendable {
    var definitions: [ModuleArgumentDefinition] = []
    var helpText: String?
}

enum ModuleArgumentProcessor {
    static func info(in content: String) -> ModuleArgumentInfo {
        guard let value = metadataValue(named: "arguments", in: content) else {
            return ModuleArgumentInfo()
        }
        let definitions = parse(value).map { ModuleArgumentDefinition(key: $0.0, defaultValue: $0.1) }
        let help = metadataValue(named: "arguments-desc", in: content)
            .map { $0.replacingOccurrences(of: "\\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        return ModuleArgumentInfo(definitions: definitions, helpText: help?.isEmpty == false ? help : nil)
    }

    static func materialize(_ content: String, overrides: [String: String]) -> String {
        let info = info(in: content)
        var resolved = content.replacingOccurrences(of: "\r\n", with: "\n")
        for definition in info.definitions {
            let value = overrides[definition.key] ?? definition.defaultValue
            resolved = resolved.replacingOccurrences(of: "%\(definition.key)%", with: value)
            resolved = resolved.replacingOccurrences(of: "{{{\(definition.key)}}}", with: value)
        }

        var output: [String] = []
        var previousWasEmpty = false
        for line in resolved.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isArgumentMetadata(trimmed) { continue }
            if isCommentOnly(trimmed) { continue }
            if trimmed.isEmpty {
                guard !previousWasEmpty, !output.isEmpty else { continue }
                previousWasEmpty = true
            } else {
                previousWasEmpty = false
            }
            output.append(line)
        }
        while output.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n") + "\n"
    }

    private static func parse(_ value: String) -> [(String, String)] {
        if value.contains("=") {
            return value.split(separator: "&").compactMap { pair in
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { return nil }
                let key = String(pieces[0]).removingPercentEncoding ?? String(pieces[0])
                let value = String(pieces[1]).removingPercentEncoding ?? String(pieces[1])
                return normalizedPair(key, value)
            }
        }
        return value.split(separator: ",").compactMap { pair in
            let pieces = pair.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { return nil }
            return normalizedPair(String(pieces[0]), String(pieces[1]))
        }
    }

    private static func normalizedPair(_ key: String, _ value: String) -> (String, String)? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
        }
        return (key, value)
    }

    private static func metadataValue(named name: String, in content: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?im)^\\s*#!\\s*\(escapedName)\\s*=\\s*(.*?)\\s*$"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
              ),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[range])
    }

    private static func isArgumentMetadata(_ line: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)^#!\s*arguments(?:-desc)?\s*="#
        ) else { return false }
        return expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func isCommentOnly(_ line: String) -> Bool {
        guard !line.isEmpty, !line.hasPrefix("#!") else { return false }
        return line.hasPrefix("#") || line.hasPrefix("//") || line.hasPrefix(";")
    }
}

struct DiscoveredScriptArg: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let defaultValue: String
}

extension ModuleMetadataParser {
    static func discoverScriptArguments(in content: String) -> [DiscoveredScriptArg] {
        var results: [DiscoveredScriptArg] = []
        var inScriptSection = false
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                inScriptSection = (sectionName == "Script")
                continue
            }
            guard inScriptSection else { continue }
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let config = parts[1]
            
            let configParts = config.components(separatedBy: ",")
            for part in configParts {
                let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedPart.hasPrefix("argument=") {
                    let defaultValue = String(trimmedPart.dropFirst("argument=".count))
                    results.append(DiscoveredScriptArg(name: name, defaultValue: defaultValue))
                    break
                }
            }
        }
        return results
    }

    static func extractUniquePolicies(in content: String) -> [String] {
        var policies: Set<String> = []
        var inRuleSection = false
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                inRuleSection = (sectionName == "Rule")
                continue
            }
            guard inRuleSection else { continue }
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            let parts = line.components(separatedBy: ",")
            if parts.count >= 3 {
                let policy = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                policies.insert(policy)
            }
        }
        return Array(policies).sorted()
    }
    
    static func extractOverrides(original: String, edited: String) -> (
        argumentOverrides: [String: String],
        policyOverrides: [String: String],
        customRules: [String],
        customMitM: [String]
    ) {
        let originalSections = parseSections(from: original)
        let editedSections = parseSections(from: edited)
        
        // 1. Script arguments
        let originalScripts = parseScripts(from: originalSections["Script"] ?? [])
        let editedScripts = parseScripts(from: editedSections["Script"] ?? [])
        var argumentOverrides: [String: String] = [:]
        for (name, editedConfig) in editedScripts {
            let editedArg = extractArgument(from: editedConfig)
            let originalArg = originalScripts[name].flatMap { extractArgument(from: $0) }
            if editedArg != originalArg {
                argumentOverrides[name] = editedArg ?? ""
            }
        }
        
        // 2. Policy mapping
        let originalRules = parseRules(from: originalSections["Rule"] ?? [])
        let editedRules = parseRules(from: editedSections["Rule"] ?? [])
        var policyOverrides: [String: String] = [:]
        for (key, editedPolicy) in editedRules {
            if let originalPolicy = originalRules[key] {
                if editedPolicy != originalPolicy {
                    policyOverrides[originalPolicy] = editedPolicy
                }
            }
        }
        
        // 3. Custom rules
        var customRules: [String] = []
        for line in editedSections["Rule"] ?? [] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            let parts = trimmed.components(separatedBy: ",")
            if parts.count >= 3 {
                let matchKey = parts[0...1].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ",")
                if originalRules[matchKey] == nil {
                    customRules.append(trimmed)
                }
            } else if parts.count == 2 {
                let matchKey = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if originalRules[matchKey] == nil {
                    customRules.append(trimmed)
                }
            }
        }
        
        // 4. Custom MitM
        let originalMitM = parseMitM(from: originalSections["MitM"] ?? [])
        let editedMitM = parseMitM(from: editedSections["MitM"] ?? [])
        let customMitM = editedMitM.subtracting(originalMitM).sorted()
        
        return (argumentOverrides, policyOverrides, customRules, customMitM)
    }
    
    private static func parseSections(from content: String) -> [String: [String]] {
        var sections: [String: [String]] = [:]
        var currentSection = ""
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# *******") ||
               trimmed.hasPrefix("# !WARNING") ||
               trimmed.hasPrefix("# This file") ||
               trimmed.hasPrefix("# will be") ||
               trimmed.hasPrefix("# To customize") ||
               trimmed.hasPrefix("# !警告") ||
               trimmed.hasPrefix("# 本文件由") ||
               trimmed.hasPrefix("# 如需自行") ||
               trimmed.hasPrefix("# 如需个性化") ||
               trimmed.isEmpty && currentSection.isEmpty {
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if !currentSection.isEmpty {
                sections[currentSection, default: []].append(line)
            }
        }
        return sections
    }
    
    private static func parseScripts(from lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let config = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                result[name] = config
            }
        }
        return result
    }
    
    private static func extractArgument(from config: String) -> String? {
        let configParts = config.components(separatedBy: ",")
        for part in configParts {
            let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPart.hasPrefix("argument=") {
                return String(trimmedPart.dropFirst("argument=".count))
            }
        }
        return nil
    }
    
    private static func parseRules(from lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            let parts = trimmed.components(separatedBy: ",")
            if parts.count >= 3 {
                let matchKey = parts[0...1].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ",")
                let policy = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                result[matchKey] = policy
            }
        }
        return result
    }
    
    private static func parseMitM(from lines: [String]) -> Set<String> {
        var hostnames: Set<String> = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            if trimmed.contains("hostname") {
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let config = parts[1].replacingOccurrences(of: "%APPEND%", with: "")
                    let names = config.components(separatedBy: ",")
                    for name in names {
                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !n.isEmpty {
                            hostnames.insert(n)
                        }
                    }
                }
            }
        }
        return hostnames
    }
    
    static func stripWarningHeader(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var filteredLines: [String] = []
        var skipEmpty = true
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("# ***") ||
               lower.hasPrefix("# !warning") ||
               lower.hasPrefix("# this file") ||
               lower.hasPrefix("# to this file") ||
               lower.hasPrefix("# to customize") ||
               lower.hasPrefix("# !警告") ||
               lower.hasPrefix("# 本文件由") ||
               lower.hasPrefix("# 如需自行") ||
               lower.hasPrefix("# 如需个性化") ||
               lower == "#" {
                continue
            }
            if skipEmpty && trimmed.isEmpty {
                continue
            }
            skipEmpty = false
            filteredLines.append(line)
        }
        return filteredLines.joined(separator: "\n")
    }
}
