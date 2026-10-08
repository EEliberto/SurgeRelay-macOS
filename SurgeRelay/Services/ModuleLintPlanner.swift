import Foundation

enum ModuleLintPlanner {
    static let maximumIssues = 500
    private static let scriptPathExpression = try? NSRegularExpression(pattern: #"script-path\s*=\s*("[^"]*"|'[^']*'|[^,\s]+)"#, options: [.caseInsensitive])
    private static let knownSections: Set<String> = [
        "general", "proxy", "proxy group", "rule", "host", "url rewrite", "header rewrite", "body rewrite",
        "map local", "script", "mitm", "panel", "ssid setting", "wireguard", "replica", "rule provider"
    ]

    static func check(files: [PublishFile], ownedModuleIDs: Set<UUID> = []) -> [ModuleLintIssue] {
        let paths = Set(files.map { normalizedPath($0.name) })
        var issues: [ModuleLintIssue] = []
        var suppressed = 0
        var suppressedError = false
        func append(_ issue: ModuleLintIssue) {
            guard issues.count < maximumIssues - 1 else {
                suppressed += 1
                suppressedError = suppressedError || issue.severity == .error
                return
            }
            issues.append(issue)
        }
        for file in files.sorted(by: { $0.name < $1.name }) where ["sgmodule", "module"].contains((file.name as NSString).pathExtension.lowercased()) {
            guard let text = String(data: file.data, encoding: .utf8) else {
                append(ModuleLintIssue(filePath: file.name, line: 1, severity: .error, code: "invalid-utf8", message: "模块正文不是有效的 UTF-8 文本。"))
                continue
            }
            var section = ""
            var sectionCount = 0
            var hasUnsectionedContent = false
            var seenLines: [String: Int] = [:]
            var seenKeys: [String: Int] = [:]
            for (index, raw) in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
                let number = index + 1
                let line = raw.trimmingCharacters(in: .whitespaces)
                func issue(_ severity: ModuleLintSeverity, _ code: String, _ message: String, relatedLine: Int? = nil) {
                    append(ModuleLintIssue(filePath: file.name, line: number, severity: severity, code: code, message: message, relatedLine: relatedLine))
                }
                if line.contains("\0") { issue(.error, "nul-character", "模块包含 NUL 字符，无法作为正常配置文本读取。") }
                if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") || line.hasPrefix("//") { continue }
                if section.isEmpty, !line.hasPrefix("[") { hasUnsectionedContent = true }
                if line.hasPrefix("[") {
                    guard let close = line.firstIndex(of: "]") else {
                        issue(.error, "malformed-section", "配置段标题缺少右方括号 ]。")
                        continue
                    }
                    let name = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces)
                    let trailing = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, !name.contains("["), trailing.isEmpty || trailing.hasPrefix("#") || trailing.hasPrefix(";") || trailing.hasPrefix("//") else {
                        issue(.error, "malformed-section", "配置段标题应使用 [段名称] 格式。")
                        continue
                    }
                    section = name.lowercased()
                    sectionCount += 1
                    if !knownSections.contains(section) { issue(.warning, "unknown-section", "未识别的配置段 [\(name)]，请核对当前 Surge 版本是否支持。") }
                    continue
                }
                guard !section.isEmpty else {
                    issue(.warning, "outside-section", "此行位于任何配置段之外，请核对是否遗漏段标题。")
                    continue
                }
                let lineKey = section + "\0" + line
                let duplicate = seenLines[lineKey]
                if let first = duplicate { issue(.warning, "duplicate-entry", "此项与第 \(first) 行重复。", relatedLine: first) }
                else { seenLines[lineKey] = number }
                if duplicate == nil, ["general", "mitm", "script", "panel"].contains(section), let equal = line.firstIndex(of: "=") {
                    let key = line[..<equal].trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty {
                        let keyIdentity = section + "\0" + key
                        if let first = seenKeys[keyIdentity] {
                            issue(.warning, "duplicate-key", "同一配置段中的键 \(key) 已在第 \(first) 行出现；请确认覆盖顺序。", relatedLine: first)
                        } else { seenKeys[keyIdentity] = number }
                    }
                }
                guard section == "script", let expression = scriptPathExpression else { continue }
                let source = line as NSString
                for match in expression.matches(in: line, range: NSRange(location: 0, length: source.length)) {
                    let captured = source.substring(with: match.range(at: 1))
                    let reference = captured.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    let components = URLComponents(string: reference)
                    let scheme = components?.scheme?.lowercased()
                    let path = (components?.percentEncodedPath.removingPercentEncoding ?? reference).replacingOccurrences(of: "\\", with: "/")
                    let parts = path.split(separator: "/").map(String.init)
                    if let offset = parts.lastIndex(of: "assets"), parts.count > offset + 2,
                       let owner = UUID(uuidString: parts[offset + 1]), ownedModuleIDs.contains(owner) {
                        let asset = parts[offset...].joined(separator: "/")
                        if !paths.contains(normalizedPath(asset)) {
                            issue(.error, "missing-owned-asset", "模块引用的受管脚本未包含在发布资源中：\(asset)")
                        }
                    } else if scheme == nil {
                        let relative = normalizedPath(((file.name as NSString).deletingLastPathComponent as NSString).appendingPathComponent(path))
                        if !paths.contains(normalizedPath(path)), !paths.contains(relative) {
                            issue(.warning, "unverified-relative-script", "未在本次文件中找到相对脚本 \(reference)；请确认发布目标已有该资源。")
                        }
                    }
                    if scheme == "http" || scheme == "https" {
                        if components?.host?.isEmpty != false || reference.contains(where: \.isWhitespace) {
                            issue(.warning, "invalid-script-url", "脚本 URL 格式可疑，请核对协议、主机和转义字符。")
                        }
                    } else if let scheme, scheme != "file" {
                        issue(.warning, "unverified-script-scheme", "脚本使用 \(scheme) 协议，请核对 Surge 是否支持。")
                    }
                }
            }
            if sectionCount == 0 {
                append(ModuleLintIssue(filePath: file.name, line: 1, severity: hasUnsectionedContent ? .error : .warning, code: "missing-section", message: hasUnsectionedContent ? "配置内容没有所属的 [配置段]。" : "模块只有注释或元数据，没有生效的配置项。"))
            }
        }
        if suppressed > 0 {
            issues.append(ModuleLintIssue(filePath: "检查摘要", line: 1, severity: suppressedError ? .error : .warning, code: "issue-limit",
                                          message: "另有 \(suppressed) 项检查结果未显示。" + (suppressedError ? "其中包含必须修复的错误。" : "")))
        }
        return issues
    }

    static func throwIfBlocking(_ issues: [ModuleLintIssue]) throws {
        guard let first = issues.first(where: { $0.severity == .error }) else { return }
        throw RelayError.invalidOutput("发布前检查未通过：\(first.filePath):\(first.line) · \(first.message)")
    }

    private static func normalizedPath(_ path: String) -> String {
        (path.replacingOccurrences(of: "\\", with: "/") as NSString).standardizingPath
    }
}
