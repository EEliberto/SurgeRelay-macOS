import SwiftUI

struct ScriptHubAdvancedOptionsView: View {
    @Binding var options: ScriptHubOptions
    @State private var expandedSections: Set<OptionSection>

    init(options: Binding<ScriptHubOptions>) {
        _options = options
        _expandedSections = State(initialValue: Self.initialExpandedSections(for: options.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("这些选项由 App 内置的 Script‑Hub 引擎执行，并随当前模块保存。留空即采用上游默认行为。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Divider()
            optionGroup(
                .scriptConversion,
                "启用脚本转换",
                description: "仅在脚本使用了来源 App 独有 API 时启用。启用后，App 会预先转换脚本并将辅助资源发布到 GitHub。"
            ) {
                keywordRow(
                    "脚本转换 1 关键词",
                    prompt: "例如：response-body.js",
                    help: "输入关键词后点按 + 添加。",
                    text: $options.scriptConversionKeywords
                )
                toggleRow("脚本转换 1：全部转换", isOn: $options.convertAllScripts)
                keywordRow(
                    "脚本转换 2 关键词",
                    prompt: "例如：response.js",
                    help: "转换 2 会为 $done(body) 包装 response。",
                    text: $options.responseScriptConversionKeywords
                )
                toggleRow("脚本转换 2：全部转换并包装 response", isOn: $options.convertAllResponseScripts)
                toggleRow("仅进行兼容性转换", isOn: $options.compatibilityOnly)
                inputRow(
                    "在脚本开头添加代码",
                    prompt: "例如：console.log(new Date().toLocaleString('zh'))",
                    help: "代码会添加到被转换脚本的开头。",
                    text: $options.prependScript,
                    multiline: true,
                    monospaced: true
                )
                nestedGroup(.scriptAdvanced, "脚本转换高级处理") {
                    inputRow("处理脚本原始内容（代码）", prompt: "例如：body = body.replace(/old/g, 'new')", text: $options.scriptEvalOriginal, multiline: true, monospaced: true)
                    inputRow("处理脚本转换后内容（代码）", prompt: "例如：body = body.replace(/old/g, 'new')", text: $options.scriptEvalConverted, multiline: true, monospaced: true)
                    inputRow("处理脚本原始内容（代码 URL）", prompt: "https://example.com/process-original.js", text: $options.scriptEvalOriginalURL)
                    inputRow("处理脚本转换后内容（代码 URL）", prompt: "https://example.com/process-converted.js", text: $options.scriptEvalConvertedURL)
                }
            }

            Divider()
            optionGroup(.rewrites, "重写相关") {
                keywordRow("保留重写关键词", prompt: "例如：login", help: "匹配的已注释重写会被启用。", text: $options.includeKeywords)
                keywordRow("排除重写关键词", prompt: "例如：tracking", help: "匹配的重写会被注释。", text: $options.excludeKeywords)
                toggleRow("将 MitM 主机名同步到 force-http-engine-hosts", isOn: $options.syncMITMToForceHTTP)
                toggleRow("剔除被注释的重写", isOn: $options.removeCommentedRewrites)
                toggleRow("保留 Map Local / echo-response 的 Header", isOn: $options.keepMapLocalHeaders)
                toggleRow("将 GitHub 脚本地址转换为 jsDelivr", isOn: $options.useJSDelivr)
            }

            Divider()
            optionGroup(.policy, "指定策略", description: "为未指定策略或使用非 Surge 内置策略的规则指定一个替代策略。") {
                inputRow("策略", prompt: "例如：DIRECT、REJECT 或你的策略组名称", text: $options.policy)
            }

            Divider()
            optionGroup(.mitm, "修改 MitM 主机名") {
                keywordRow("添加主机名", prompt: "例如：api.example.com", help: "每次添加一个主机名。", text: $options.mitmAdd, separator: ",")
                keywordRow("删除主机名", prompt: "例如：ads.example.com", text: $options.mitmRemove, separator: ",")
                inputRow("按正则删除主机名", prompt: "例如：(^|\\.)ads\\.example\\.com$", text: $options.mitmRemoveRegex, monospaced: true)
            }

            Divider()
            pairedGroup(
                .scriptName,
                "修改脚本名",
                firstTitle: "关键词锁定脚本 (njsnametarget)",
                firstPrompt: "例如：checkin",
                first: $options.scriptNameTargets,
                secondTitle: "新的脚本名 (njsname)",
                secondPrompt: "例如：签到任务",
                second: $options.scriptNames
            )

            Divider()
            pairedGroup(
                .timeout,
                "修改脚本超时",
                firstTitle: "关键词锁定脚本 (timeoutt)",
                firstPrompt: "例如：checkin",
                first: $options.timeoutTargets,
                secondTitle: "超时值 (timeoutv)",
                secondPrompt: "例如：10",
                second: $options.timeoutValues
            )

            Divider()
            pairedGroup(
                .engine,
                "修改脚本引擎（Surge）",
                firstTitle: "关键词锁定脚本 (enginet)",
                firstPrompt: "例如：legacy-script",
                first: $options.engineTargets,
                secondTitle: "引擎 (enginev)",
                secondPrompt: "例如：webview",
                second: $options.engineValues
            )

            Divider()
            pairedGroup(
                .cron,
                "修改定时任务",
                firstTitle: "关键词锁定任务 (cron)",
                firstPrompt: "例如：daily-checkin",
                first: $options.cronTargets,
                secondTitle: "Cron 表达式 (cronexp)",
                secondPrompt: "例如：0.0.8.*.*.*",
                second: $options.cronExpressions
            )

            Divider()
            pairedGroup(
                .arguments,
                "修改参数",
                firstTitle: "关键词锁定脚本 (arg)",
                firstPrompt: "例如：account-script",
                first: $options.argumentTargets,
                secondTitle: "Argument 新值 (argv)",
                secondPrompt: "例如：key=value",
                second: $options.argumentValues
            )

            Divider()
            optionGroup(.rules, "规则与请求") {
                toggleRow("IP 规则开启 no-resolve", isOn: $options.noResolve)
                keywordRow("SNI 扩展匹配关键词", prompt: "例如：DOMAIN-SUFFIX", text: $options.sniKeywords)
                keywordRow("pre-matching 关键词", prompt: "例如：REJECT", text: $options.preMatchingKeywords)
                toggleRow("开启 JQ", isOn: $options.enableJQ)
                inputRow(
                    "自定义请求 Header",
                    prompt: "User-Agent:script-hub/1.0.0\nAuthorization:token xxx",
                    help: "每行一个 Header，使用英文冒号分隔名称和值。",
                    text: $options.requestHeaders,
                    multiline: true,
                    monospaced: true
                )
            }

            Divider()
            optionGroup(.contentProcessing, "高级内容处理", isLast: true) {
                inputRow("处理原始内容（代码）", prompt: "例如：body = body.replace(/old/g, 'new')", text: $options.evalOriginal, multiline: true, monospaced: true)
                inputRow("处理转换后内容（代码）", prompt: "例如：body = body.replace(/old/g, 'new')", text: $options.evalConverted, multiline: true, monospaced: true)
                inputRow("处理原始内容（代码 URL）", prompt: "https://example.com/process-original.js", text: $options.evalOriginalURL)
                inputRow("处理转换后内容（代码 URL）", prompt: "https://example.com/process-converted.js", text: $options.evalConvertedURL)
            }
        }
    }

    private func optionGroup<Content: View>(
        _ section: OptionSection,
        _ title: String,
        description: String? = nil,
        isLast: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: section)) {
            VStack(alignment: .leading, spacing: 0) {
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                    Divider()
                }
                content()
            }
            .padding(.leading, 18)
            .padding(.top, 4)
        } label: {
            Text(title).fontWeight(.medium)
        }
        .padding(.top, 8)
        // The grouped Form already supplies the final row's bottom inset.
        .padding(.bottom, isLast ? 0 : 8)
    }

    private func nestedGroup<Content: View>(
        _ section: OptionSection,
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: section)) {
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.leading, 18)
        } label: {
            Text(title).font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func keywordRow(_ title: String, prompt: String, help: String? = nil,
                            text: Binding<String>, separator: String = "+") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RelayKeywordListEditor(title: title, prompt: prompt, keywords: Binding(
                get: { text.wrappedValue.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } },
                set: { text.wrappedValue = $0.joined(separator: separator) }
            ), caseSensitive: separator == "+")
            if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func inputRow(
        _ title: String,
        prompt: String,
        help: String? = nil,
        text: Binding<String>,
        multiline: Bool = false,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            Group {
                if multiline {
                    TextField("", text: text, prompt: Text(prompt), axis: .vertical).multilineTextAlignment(.leading)
                        .lineLimit(2...6)
                } else {
                    TextField("", text: text, prompt: Text(prompt)).multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }
    }

    private func pairedGroup(
        _ section: OptionSection,
        _ title: String,
        firstTitle: String,
        firstPrompt: String,
        first: Binding<String>,
        secondTitle: String,
        secondPrompt: String,
        second: Binding<String>
    ) -> some View {
        optionGroup(section, title, description: "每行是一组目标和值，点按 + 添加一组。") {
            RelayPairedListEditor(firstTitle: firstTitle, firstPrompt: firstPrompt, first: first,
                                  secondTitle: secondTitle, secondPrompt: secondPrompt, second: second)
        }
    }

    private func expansionBinding(for section: OptionSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    private static func initialExpandedSections(for options: ScriptHubOptions) -> Set<OptionSection> {
        let defaults = ScriptHubOptions()
        var sections: Set<OptionSection> = []
        func hasText(_ values: String...) -> Bool {
            values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        let hasScriptAdvanced = hasText(
            options.scriptEvalOriginal,
            options.scriptEvalConverted,
            options.scriptEvalOriginalURL,
            options.scriptEvalConvertedURL
        )
        if hasText(options.scriptConversionKeywords, options.responseScriptConversionKeywords, options.prependScript) ||
            options.convertAllScripts || options.convertAllResponseScripts || options.compatibilityOnly || hasScriptAdvanced {
            sections.insert(.scriptConversion)
        }
        if hasScriptAdvanced { sections.insert(.scriptAdvanced) }
        if hasText(options.includeKeywords, options.excludeKeywords) ||
            options.syncMITMToForceHTTP || options.removeCommentedRewrites != defaults.removeCommentedRewrites ||
            options.keepMapLocalHeaders || options.useJSDelivr {
            sections.insert(.rewrites)
        }
        if hasText(options.policy) { sections.insert(.policy) }
        if hasText(options.mitmAdd, options.mitmRemove, options.mitmRemoveRegex) { sections.insert(.mitm) }
        if hasText(options.scriptNameTargets, options.scriptNames) { sections.insert(.scriptName) }
        if hasText(options.timeoutTargets, options.timeoutValues) { sections.insert(.timeout) }
        if hasText(options.engineTargets, options.engineValues) { sections.insert(.engine) }
        if hasText(options.cronTargets, options.cronExpressions) { sections.insert(.cron) }
        if hasText(options.argumentTargets, options.argumentValues) { sections.insert(.arguments) }
        if hasText(options.sniKeywords, options.preMatchingKeywords, options.requestHeaders) ||
            options.noResolve || options.enableJQ != defaults.enableJQ {
            sections.insert(.rules)
        }
        if hasText(options.evalOriginal, options.evalConverted, options.evalOriginalURL, options.evalConvertedURL) {
            sections.insert(.contentProcessing)
        }
        return sections
    }

    private enum OptionSection: Hashable {
        case scriptConversion
        case scriptAdvanced
        case rewrites
        case policy
        case mitm
        case scriptName
        case timeout
        case engine
        case cron
        case arguments
        case rules
        case contentProcessing
    }
}


private struct RelayPairedListEditor: View {
    private struct Entry: Identifiable {
        let id = UUID()
        var first: String
        var second: String
    }
    let firstTitle: String
    let firstPrompt: String
    @Binding var first: String
    let secondTitle: String
    let secondPrompt: String
    @Binding var second: String
    @State private var entries: [Entry]

    init(firstTitle: String, firstPrompt: String, first: Binding<String>,
         secondTitle: String, secondPrompt: String, second: Binding<String>) {
        self.firstTitle = firstTitle; self.firstPrompt = firstPrompt; _first = first
        self.secondTitle = secondTitle; self.secondPrompt = secondPrompt; _second = second
        let targets = first.wrappedValue.isEmpty ? [] : first.wrappedValue.components(separatedBy: "+")
        let values = second.wrappedValue.isEmpty ? [] : second.wrappedValue.components(separatedBy: "+")
        // One-time editor seed; stable row IDs preserve focus while editing duplicate values.
        _entries = State(initialValue: (0..<max(targets.count, values.count)).map {
            Entry(first: $0 < targets.count ? targets[$0] : "", second: $0 < values.count ? values[$0] : "")
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($entries) { $entry in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading) {
                        Text(firstTitle).font(.caption)
                        TextField(firstPrompt, text: $entry.first).onChange(of: entry.first) { persist() }
                    }
                    VStack(alignment: .leading) {
                        Text(secondTitle).font(.caption)
                        TextField(secondPrompt, text: $entry.second).onChange(of: entry.second) { persist() }
                    }
                    .frame(maxWidth: secondTitle.contains("timeoutv") ? 100 : secondTitle.contains("enginev") ? 160 : .infinity, alignment: .leading)
                    Button("移除此组", systemImage: "minus.circle") {
                        entries.removeAll { $0.id == entry.id }; persist()
                    }.labelStyle(.iconOnly).padding(.top, 20)
                }
            }
            Button("添加一组", systemImage: "plus") { entries.append(Entry(first: "", second: "")) }
        }
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.leading)
        .padding(.vertical, 10)
    }

    private func persist() {
        let values = entries.filter { !$0.first.isEmpty || !$0.second.isEmpty }
        first = values.map(\.first).joined(separator: "+")
        second = values.map(\.second).joined(separator: "+")
    }
}
