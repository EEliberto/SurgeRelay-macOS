import Foundation

enum ModuleMerger {
    private struct ParsedModule {
        var module: RelayModule
        var sections: [(name: String, lines: [String])]
        var requirements: [String]
        var system: String?
        var authors: [String]
    }

    static func merge(_ components: [(RelayModule, String)], platform: RelayPlatform, iconURL: String? = nil, engineRevision: String?) throws -> String {
        let parsed = components.map {
            parse(
                module: $0.0,
                content: SurgeModuleSanitizer.sanitize(
                    ModuleArgumentProcessor.materialize($0.1, overrides: [:])
                )
            )
        }
        guard parsed.contains(where: { !$0.sections.isEmpty }) else {
            throw RelayError.invalidOutput("没有找到可合并的 Surge 配置段。")
        }

        var output: [String] = [
            "#!name=Surge Relay (\(platform.summaryDisplayName))",
            "#!desc=由 Surge Relay 整合 \(components.count) 个模块，\(platform.summaryDisplayName) 专用。",
            "#!author=Surge Relay" + mergedAuthors(parsed),
            "#!category=Surge Relay",
        ]

        if let iconURL = iconURL {
            output.append("#!icon=\(iconURL)")
        }

        let requirements = Array(Set(parsed.flatMap(\.requirements).compactMap(sanitizeRequirement))).sorted()
        if !requirements.isEmpty {
            output.append("#!requirement=" + requirements.map { "(\($0))" }.joined(separator: " && "))
        }

        let sectionNames = orderedSectionNames(parsed)
        for sectionName in sectionNames {
            let groups = parsed.compactMap { item -> (RelayModule, [String])? in
                guard let section = item.sections.first(where: { $0.name.caseInsensitiveCompare(sectionName) == .orderedSame }) else { return nil }
                return (item.module, section.lines)
            }
            let lines = mergeLines(groups, sectionName: sectionName)
            guard !lines.isEmpty else { continue }
            output.append("")
            output.append("[\(sectionName)]")
            output.append(contentsOf: lines)
        }

        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func parse(module: RelayModule, content: String) -> ParsedModule {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var sections: [(String, [String])] = []
        var currentIndex: Int?
        var requirements: [String] = []
        var system: String?
        var authors: [String] = []

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 {
                let name = String(line.dropFirst().dropLast())
                sections.append((name, []))
                currentIndex = sections.count - 1
                continue
            }
            if let currentIndex {
                if !line.isEmpty { sections[currentIndex].1.append(raw) }
                continue
            }
            if line.hasPrefix("#!requirement=") {
                requirements.append(String(line.dropFirst("#!requirement=".count)))
            } else if line.hasPrefix("#!system=") {
                system = String(line.dropFirst("#!system=".count))
            } else if line.hasPrefix("#!author=") {
                authors.append(String(line.dropFirst("#!author=".count)))
            }
        }
        return ParsedModule(
            module: module,
            sections: sections,
            requirements: requirements,
            system: system,
            authors: authors
        )
    }

    private static func mergedAuthors(_ modules: [ParsedModule]) -> String {
        let authors = Array(Set(modules.flatMap(\.authors))).sorted()
        return authors.isEmpty ? "" : " · " + authors.joined(separator: " · ")
    }

    private static func orderedSectionNames(_ modules: [ParsedModule]) -> [String] {
        let preferred = ["General", "MITM", "Rule", "Host", "URL Rewrite", "Header Rewrite", "Body Rewrite", "Map Local", "Script"]
        var names: [String] = []
        for name in preferred where modules.contains(where: { $0.sections.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) }) {
            names.append(name)
        }
        for name in modules.flatMap({ $0.sections.map(\.name) })
        where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    private static func mergeLines(_ groups: [(RelayModule, [String])], sectionName: String) -> [String] {
        if sectionName.caseInsensitiveCompare("General") == .orderedSame {
            return mergeKeyValueLines(groups)
        }
        if sectionName.caseInsensitiveCompare("MITM") == .orderedSame {
            return mergeKeyValueLines(groups)
        }
        var output: [String] = []
        var seen = Set<String>()
        for (_, lines) in groups {
            let useful = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !isCommentOnly(trimmed)
            }
            guard !useful.isEmpty else { continue }
            for line in useful where seen.insert(line).inserted {
                output.append(line)
            }
        }
        return output
    }

    private static func mergeKeyValueLines(_ groups: [(RelayModule, [String])]) -> [String] {
        var order: [String] = []
        var values: [String: (key: String, value: String)] = [:]
        for (module, lines) in groups {
            _ = module
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty, !isCommentOnly(trimmedLine) else { continue }
                let pieces = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { continue }
                let key = pieces[0].trimmingCharacters(in: .whitespaces)
                let value = pieces[1].trimmingCharacters(in: .whitespaces)
                let normalized = key.lowercased()
                if values[normalized] == nil { order.append(normalized) }
                if let existing = values[normalized],
                   let combined = combineDirective(existing.value, value) {
                    values[normalized] = (existing.key, combined)
                } else if values[normalized] == nil {
                    // 组件数组与模块列表顺序相同；同名配置由更靠上的模块优先决定。
                    values[normalized] = (key, value)
                }
            }
        }
        return order.compactMap { values[$0].map { "\($0.key) = \($0.value)" } }
    }

    private static func combineDirective(_ lhs: String, _ rhs: String) -> String? {
        let directives = ["%APPEND%", "%INSERT%"]
        guard let leftDirective = directives.first(where: lhs.hasPrefix),
              let rightDirective = directives.first(where: rhs.hasPrefix) else { return nil }
        let left = lhs.dropFirst(leftDirective.count).trimmingCharacters(in: .whitespaces)
        let right = rhs.dropFirst(rightDirective.count).trimmingCharacters(in: .whitespaces)
        var seen = Set<String>()
        let items = (left + "," + right).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        // A merged module has one directive per key. Keep the highest-priority
        // module's placement semantics while retaining every module's values.
        return leftDirective + " " + items.joined(separator: ", ")
    }

    // 仅供预览器在内存中识别模块来源；该标识不会写入最终 sgmodule。
    static func toggleKey(for module: RelayModule) -> String {
        "Relay_" + module.id.uuidString.replacingOccurrences(of: "-", with: "")
    }

    private static func isCommentOnly(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix("//") || line.hasPrefix(";")
    }

    private static func sanitizeRequirement(_ requirement: String) -> String? {
        let deviceVariables = ["SYSTEM", "SYSTEM_VERSION", "DEVICE_MODEL"]
        guard deviceVariables.contains(where: requirement.contains) else { return requirement }
        let pattern = #"CORE_VERSION\s*(?:>=|<=|==|=|>|<)\s*[0-9]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let matches = expression.matches(in: requirement, range: NSRange(requirement.startIndex..., in: requirement))
        let coreClauses = matches.compactMap { Range($0.range, in: requirement).map { String(requirement[$0]) } }
        return coreClauses.isEmpty ? nil : coreClauses.joined(separator: " && ")
    }
}

actor ModuleProcessingWorker {
    func materialize(
        _ content: String,
        overrides: [String: String],
        policyOverrides: [String: String] = [:],
        customRules: [String] = [],
        customMitM: [String] = []
    ) -> String {
        var resolved = ModuleArgumentProcessor.materialize(content, overrides: overrides)
        
        var sections: [String: [String]] = [:]
        var currentSection = ""
        var originalLineOrder: [String] = []
        
        let lines = resolved.components(separatedBy: "\n")
        
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
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                sections[currentSection] = []
                originalLineOrder.append("[\(currentSection)]")
            } else if !currentSection.isEmpty {
                sections[currentSection]?.append(line)
            } else {
                originalLineOrder.append(line)
            }
        }
        
        if let scriptLines = sections["Script"] {
            var updatedScriptLines: [String] = []
            for line in scriptLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                    updatedScriptLines.append(line)
                    continue
                }
                
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    updatedScriptLines.append(line)
                    continue
                }
                let scriptName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let scriptConfig = parts[1]
                
                if let overrideArg = overrides[scriptName] {
                    var configParts = scriptConfig.components(separatedBy: ",")
                    var argIndex = -1
                    for (index, part) in configParts.enumerated() {
                        let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedPart.hasPrefix("argument=") {
                            argIndex = index
                            break
                        }
                    }
                    
                    if argIndex >= 0 {
                        configParts[argIndex] = "argument=\(overrideArg)"
                    } else {
                        configParts.append("argument=\(overrideArg)")
                    }
                    let newConfig = configParts.joined(separator: ",")
                    updatedScriptLines.append("\(scriptName) =\(newConfig)")
                } else {
                    updatedScriptLines.append(line)
                }
            }
            sections["Script"] = updatedScriptLines
        }
        
        var updatedRuleLines: [String] = []
        if let ruleLines = sections["Rule"] {
            for line in ruleLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                    updatedRuleLines.append(line)
                    continue
                }
                
                var ruleParts = line.components(separatedBy: ",")
                if ruleParts.count >= 3 {
                    let policyIndex = 2
                    let originalPolicy = ruleParts[policyIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    if let mappedPolicy = policyOverrides[originalPolicy] {
                        ruleParts[policyIndex] = mappedPolicy
                        updatedRuleLines.append(ruleParts.joined(separator: ","))
                        continue
                    }
                }
                updatedRuleLines.append(line)
            }
        }
        
        for customRule in customRules {
            updatedRuleLines.append(customRule)
        }
        
        if !updatedRuleLines.isEmpty || !customRules.isEmpty {
            if sections["Rule"] == nil {
                sections["Rule"] = []
                originalLineOrder.append("[Rule]")
            }
            sections["Rule"] = updatedRuleLines
        }
        
        if !customMitM.isEmpty {
            var updatedMitmLines: [String] = []
            var hostnameLineIndex = -1
            
            let mitmLines = sections["MitM"] ?? []
            for (index, line) in mitmLines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("hostname") {
                    hostnameLineIndex = index
                    break
                }
            }
            
            if hostnameLineIndex >= 0 {
                let hostnameLine = mitmLines[hostnameLineIndex]
                let parts = hostnameLine.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let currentHostnames = parts[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    var newHostnames = currentHostnames
                    for host in customMitM {
                        if !newHostnames.contains(host) {
                            newHostnames.append(host)
                        }
                    }
                    let newHostnameLine = "hostname = \(newHostnames.joined(separator: ", "))"
                    var newMitmLines = mitmLines
                    newMitmLines[hostnameLineIndex] = newHostnameLine
                    sections["MitM"] = newMitmLines
                }
            } else {
                var newMitmLines = mitmLines
                newMitmLines.append("hostname = \(customMitM.joined(separator: ", "))")
                sections["MitM"] = newMitmLines
                if sections["MitM"] == nil {
                    originalLineOrder.append("[MitM]")
                }
            }
        }
        
        var reconstructed: [String] = []

        let warningHeader = """
        # **************************************************************************
        # !WARNING: DO NOT EDIT THIS FILE ON DISK DIRECTLY.
        # This file is automatically generated by Surge Relay. Any direct edits
        # to this file will be overwritten and lost during the next update/sync.
        # To customize, please edit via the "Preview" tab inside Surge Relay.
        #
        # !警告：请勿在磁盘上直接修改此文件。
        # 本文件由 Surge Relay 自动生成，直接在此修改的内容将在下一次同步或更新时被覆盖。
        # 如需自行修改模块内容，请通过 Surge Relay 右上角的“预览”进行编辑。
        # **************************************************************************
        """

        // Keep #! metadata (name/desc/author/...) above the warning, then a blank
        // line, then the warning block, then the rest of the module.
        var headerEnd = 0
        for (index, item) in originalLineOrder.enumerated() {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#!") {
                headerEnd = index + 1
            } else if trimmed.isEmpty, headerEnd == index {
                headerEnd = index + 1
            } else {
                break
            }
        }

        let headerLines = originalLineOrder.prefix(headerEnd)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        reconstructed.append(contentsOf: headerLines)
        if !headerLines.isEmpty {
            reconstructed.append("")
        }
        reconstructed.append(warningHeader)

        for item in originalLineOrder.dropFirst(headerEnd) {
            if item.hasPrefix("[") && item.hasSuffix("]") {
                let sectionName = String(item.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                reconstructed.append(item)
                if let secLines = sections[sectionName] {
                    reconstructed.append(contentsOf: secLines)
                }
            } else {
                reconstructed.append(item)
            }
        }

        return reconstructed.joined(separator: "\n")
    }

    func argumentInfo(in content: String) -> ModuleArgumentInfo {
        ModuleArgumentProcessor.info(in: content)
    }

    func applyingDisplayName(_ name: String, to content: String) -> String {
        ModuleMetadataParser.applyingDisplayName(name, to: content)
    }

    func iconURL(in content: String, relativeTo source: String?) -> URL? {
        ModuleMetadataParser.iconURL(in: content, relativeTo: source)
    }

    func contentFingerprint(of content: String, assets: [GeneratedAsset]) -> String {
        var data = Data(content.utf8)
        for asset in assets.sorted(by: { $0.relativePath < $1.relativePath }) {
            data.append(0)
            data.append(contentsOf: asset.relativePath.utf8)
            data.append(0)
            data.append(asset.data)
        }
        return data.sha256String
    }

    func merge(_ components: [(RelayModule, String)], platform: RelayPlatform, iconURL: String? = nil, engineRevision: String?) throws -> String {
        try ModuleMerger.merge(components, platform: platform, iconURL: iconURL, engineRevision: engineRevision)
    }
}

enum SurgeModuleSanitizer {
    private struct Section {
        var header: String
        var name: String
        var lines: [String]
    }

    static func sanitize(_ content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let input = normalized.components(separatedBy: "\n")
        var preamble: [String] = []
        var sections: [Section] = []
        var currentIndex: Int?
        var generatedScripts: [String] = []

        for rawLine in input {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 {
                let name = String(trimmed.dropFirst().dropLast())
                sections.append(Section(header: trimmed, name: name, lines: []))
                currentIndex = sections.count - 1
                continue
            }

            guard let currentIndex else {
                preamble.append(rawLine)
                continue
            }

            let sectionName = sections[currentIndex].name
            if sectionName.caseInsensitiveCompare("Body Rewrite") == .orderedSame,
               isEmptyBodyRewrite(trimmed) {
                continue
            }
            if sectionName.caseInsensitiveCompare("Map Local") == .orderedSame,
               let script = convertedLoonScript(from: trimmed, existing: existingScriptNames(in: sections) + generatedScripts) {
                if !generatedScripts.contains(script) {
                    generatedScripts.append(script)
                }
                continue
            }
            sections[currentIndex].lines.append(rawLine)
        }

        if !generatedScripts.isEmpty {
            if let index = sections.firstIndex(where: { $0.name.caseInsensitiveCompare("Script") == .orderedSame }) {
                if !sections[index].lines.isEmpty,
                   sections[index].lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    sections[index].lines.append("")
                }
                sections[index].lines.append(contentsOf: generatedScripts)
            } else {
                sections.append(Section(header: "[Script]", name: "Script", lines: generatedScripts))
            }
        }

        var output = preamble
        for section in sections {
            if !output.isEmpty,
               output.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                output.append("")
            }
            output.append(section.header)
            output.append(contentsOf: section.lines)
        }
        while output.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            output.removeLast()
        }
        return output.joined(separator: "\n") + "\n"
    }

    private static func isEmptyBodyRewrite(_ line: String) -> Bool {
        guard line.range(
            of: #"^http-(?:request|response)(?:-jq)?\s+\S+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else { return false }
        let parts = line.split(
            maxSplits: 2,
            omittingEmptySubsequences: true,
            whereSeparator: \.isWhitespace
        )
        guard parts.count == 3 else { return true }
        let value = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts[0].lowercased().hasSuffix("-jq") else { return value.isEmpty }
        let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return unquoted.isEmpty
    }

    private static func convertedLoonScript(from line: String, existing: [String]) -> String? {
        let pattern = #"^(.+?)\s+url\s+script-(request|response)-(body|header)\s+(https?://\S+)(?:\s+.*)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let patternRange = Range(match.range(at: 1), in: line),
              let directionRange = Range(match.range(at: 2), in: line),
              let bodyRange = Range(match.range(at: 3), in: line),
              let urlRange = Range(match.range(at: 4), in: line) else { return nil }

        let urlString = String(line[urlRange])
        let baseName = URL(string: urlString)?.deletingPathExtension().lastPathComponent ?? ""
        let identifier = uniqueScriptName(from: baseName, existing: existing)
        let direction = String(line[directionRange]).lowercased()
        let requiresBody = String(line[bodyRange]).caseInsensitiveCompare("body") == .orderedSame ? "1" : "0"
        return "\(identifier) = type=http-\(direction), pattern=\(line[patternRange]), requires-body=\(requiresBody), script-path=\(urlString)"
    }

    private static func existingScriptNames(in sections: [Section]) -> [String] {
        guard let script = sections.first(where: { $0.name.caseInsensitiveCompare("Script") == .orderedSame }) else {
            return []
        }
        return script.lines.compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func uniqueScriptName(from raw: String, existing: [String]) -> String {
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || "_-".unicodeScalars.contains(scalar)
                ? Character(String(scalar))
                : "_"
        }
        let trimmed = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let base = trimmed.isEmpty ? "converted_script" : trimmed
        let unavailable = Set(existing.map { name in
            name.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? name.lowercased()
        })
        guard unavailable.contains(base.lowercased()) else { return base }
        var suffix = 2
        while unavailable.contains("\(base)_\(suffix)".lowercased()) { suffix += 1 }
        return "\(base)_\(suffix)"
    }
}
