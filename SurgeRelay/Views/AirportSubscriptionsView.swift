import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AirportSubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @State private var editorRoute: AirportEditorRoute?
    @State private var previewRoute: AirportPreviewRoute?
    @State private var targetEditorRoute: ConfigurationTargetEditorRoute?
    @State private var deleteCandidate: AirportSubscription?
    @State private var refreshingID: UUID?
    @State private var confirmsWrite = false

    private var canWriteConfiguration: Bool {
        let enabled = model.airportSubscriptions.filter { $0.isEnabled && $0.isConfigured }
        return !enabled.isEmpty
            && enabled.allSatisfy { model.hasCachedAirportSubscription(id: $0.id) }
            && model.surgeConfigurationTargets.contains(where: \.isEnabled)
    }

    var body: some View {
        Form {
            Section("机场") {
                if model.airportSubscriptions.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("尚未添加机场")
                        } icon: {
                            Image("AirportSubscriptionIcon")
                                .resizable()
                                .frame(width: 44, height: 44)
                        }
                    } actions: {
                        Button("添加机场") { editorRoute = AirportEditorRoute(subscription: nil) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(model.airportSubscriptions) { subscription in
                        airportRow(subscription)
                    }
                }
            }

            Section("Surge 配置") {
                ForEach(model.surgeConfigurationTargets) { target in
                    configurationRow(target)
                }

                HStack {
                    Button("添加配置文件") { addConfigurationFiles() }
                    Spacer()
                    Button("写入配置") { confirmsWrite = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canWriteConfiguration)
                }
            }

            Section("配置预览") {
                WrappingPlainTextView(text: model.airportConfigurationPreview)
                    .frame(minHeight: 420, idealHeight: 520)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("机场订阅汇总")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editorRoute = AirportEditorRoute(subscription: nil)
                } label: {
                    Label("添加机场", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            AirportSubscriptionEditor(subscription: route.subscription)
                .environment(model)
        }
        .sheet(item: $previewRoute) { route in
            AirportSubscriptionPreview(subscriptionID: route.subscriptionID)
                .environment(model)
        }
        .sheet(item: $targetEditorRoute) { route in
            ConfigurationTargetEditor(target: route.target)
                .environment(model)
        }
        .confirmationDialog(
            "删除“\(deleteCandidate?.name ?? "")”？",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            )
        ) {
            Button("删除机场", role: .destructive) {
                guard let id = deleteCandidate?.id else { return }
                deleteCandidate = nil
                Task {
                    do {
                        try await model.removeAirportSubscriptionForCurrentMode(id: id)
                    } catch {
                        model.presentedError = error.localizedDescription
                    }
                }
            }
            Button("取消", role: .cancel) { deleteCandidate = nil }
        }
        .alert("写入 \(model.surgeConfigurationTargets.filter(\.isEnabled).count) 个配置？", isPresented: $confirmsWrite) {
            Button("取消", role: .cancel) {}
            Button("写入") { writeConfiguration() }
        }
    }

    private func airportRow(_ subscription: AirportSubscription) -> some View {
        HStack(spacing: 12) {
            airportIcon(subscription)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(subscription.isEnabled ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                    .fontWeight(.medium)
                Text(URL(string: subscription.sourceURL)?.host ?? subscription.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let date = subscription.lastUpdatedAt {
                    Text("链接更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let error = subscription.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("启用", isOn: Binding(
                get: { subscription.isEnabled },
                set: { enabled in
                    Task {
                        do {
                            try await model.setAirportSubscriptionEnabledForCurrentMode(
                                id: subscription.id,
                                enabled: enabled
                            )
                        } catch {
                            model.presentedError = error.localizedDescription
                        }
                    }
                }
            ))
            .labelsHidden()
            Button {
                refresh(subscription.id)
            } label: {
                if refreshingID == subscription.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("立即拉取并更新缓存")
            .disabled(refreshingID != nil)
            Button {
                previewRoute = AirportPreviewRoute(subscriptionID: subscription.id)
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .help(model.hasCachedAirportSubscription(id: subscription.id) ? "查看缓存内容" : "拉取并预览")
            Button("编辑") { editorRoute = AirportEditorRoute(subscription: subscription) }
            Button(role: .destructive) { deleteCandidate = subscription } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func airportIcon(_ subscription: AirportSubscription) -> some View {
        if let url = URL(string: subscription.iconURL.trimmingCharacters(in: .whitespacesAndNewlines)),
           !subscription.iconURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image("AirportSubscriptionIcon").resizable().scaledToFit()
                }
            }
        } else {
            Image("AirportSubscriptionIcon").resizable().scaledToFit()
        }
    }

    private func refresh(_ id: UUID) {
        refreshingID = id
        Task {
            defer { refreshingID = nil }
            do {
                try await model.refreshAirportSubscriptionForCurrentMode(id: id)
            } catch {
                model.presentedError = error.localizedDescription
            }
        }
    }

    private func configurationRow(_ target: SurgeConfigurationTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.url.lastPathComponent)
                    .fontWeight(.medium)
                Text(target.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("启用", isOn: Binding(
                get: { target.isEnabled },
                set: { enabled in
                    Task {
                        do {
                            try await model.setSurgeConfigurationTargetEnabledForCurrentMode(
                                id: target.id,
                                enabled: enabled
                            )
                        } catch {
                            model.presentedError = error.localizedDescription
                        }
                    }
                }
            ))
            .labelsHidden()
            Button("编辑") { targetEditorRoute = ConfigurationTargetEditorRoute(target: target) }
            Button(role: .destructive) {
                Task {
                    do {
                        try await model.removeSurgeConfigurationTargetForCurrentMode(id: target.id)
                    } catch {
                        model.presentedError = error.localizedDescription
                    }
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func addConfigurationFiles() {
        if model.isClientMode {
            targetEditorRoute = ConfigurationTargetEditorRoute(target: nil)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        model.addSurgeConfigurationTargets(panel.urls)
    }

    private func writeConfiguration() {
        Task {
            do {
                try await model.writeAirportSubscriptionsForCurrentMode()
            } catch {
                model.presentedError = error.localizedDescription
            }
        }
    }
}

private struct AirportEditorRoute: Identifiable {
    let id = UUID()
    let subscription: AirportSubscription?
}

private struct AirportPreviewRoute: Identifiable {
    let id = UUID()
    let subscriptionID: UUID
}

private struct ConfigurationTargetEditorRoute: Identifiable {
    let id = UUID()
    let target: SurgeConfigurationTarget?
}

private struct ConfigurationTargetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: SurgeConfigurationTarget?
    @State private var path: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(target: SurgeConfigurationTarget?) {
        self.target = target
        _path = State(initialValue: target?.path ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("配置文件", text: $path)
                if !model.isClientMode {
                    Button("选择文件…") { chooseFile() }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(target == nil ? "添加 Surge 配置" : "编辑 Surge 配置")
            .frame(minWidth: 520, minHeight: 190)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving)
                }
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        panel.directoryURL = URL(filePath: path).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.saveSurgeConfigurationTargetForCurrentMode(id: target?.id, path: path)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AirportSubscriptionPreview: View {
    private enum PreviewMode: Hashable {
        case changes
        case source
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let subscriptionID: UUID
    @State private var content = ""
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var previewMode = PreviewMode.changes
    @State private var processingRecords: [AirportNodeProcessingRecord] = []
    @State private var processingError: String?

    private var subscription: AirportSubscription? {
        model.airportSubscriptions.first { $0.id == subscriptionID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if content.isEmpty, isRefreshing {
                    ProgressView("正在拉取订阅…")
                } else if content.isEmpty, let errorMessage {
                    ContentUnavailableView(
                        "无法载入预览",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    VStack(spacing: 0) {
                        Picker("预览内容", selection: $previewMode) {
                            Text("处理结果").tag(PreviewMode.changes)
                            Text("原始订阅").tag(PreviewMode.source)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .padding(12)

                        Divider()

                        if previewMode == .source {
                            WrappingPlainTextView(text: content)
                        } else if let processingError {
                            ContentUnavailableView(
                                "无法生成处理预览",
                                systemImage: "exclamationmark.triangle",
                                description: Text(processingError)
                            )
                        } else {
                            AirportNodeChangesTable(records: processingRecords)
                        }
                    }
                }
            }
            .frame(minWidth: 720, minHeight: 520)
            .navigationTitle(subscription?.name ?? "订阅预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let date = subscription?.lastUpdatedAt {
                        Text("缓存于 \(date.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .task {
            await loadPreview(refresh: !model.hasCachedAirportSubscription(id: subscriptionID))
        }
    }

    private func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            content = try await model.airportSubscriptionPreviewForCurrentMode(
                id: subscriptionID,
                refresh: true
            )
            await rebuildProcessingPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPreview(refresh: Bool) async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            content = try await model.airportSubscriptionPreviewForCurrentMode(
                id: subscriptionID,
                refresh: refresh
            )
            await rebuildProcessingPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildProcessingPreview() async {
        guard let subscription, let data = content.data(using: .utf8) else {
            processingRecords = []
            return
        }
        do {
            processingRecords = try await Task.detached(priority: .userInitiated) {
                let entries = try AirportSubscriptionParser.proxyEntries(from: data)
                var usedNames = Set<String>()
                return AirportSubscriptionParser.process(
                    entries,
                    for: subscription,
                    reserving: &usedNames
                ).records
            }.value
            processingError = nil
        } catch {
            processingRecords = []
            processingError = error.localizedDescription
        }
    }
}

private struct AirportNodeChangesTable: View {
    let records: [AirportNodeProcessingRecord]

    private var includedCount: Int {
        records.lazy.filter { $0.outputName != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("保留 \(includedCount) 个，过滤 \(records.count - includedCount) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            Table(records) {
                TableColumn("原始名称") { record in
                    Text(record.originalName)
                        .lineLimit(1)
                }
                TableColumn("处理后") { record in
                    Text(record.outputName ?? "—")
                        .foregroundStyle(record.outputName == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                TableColumn("结果") { record in
                    Text(record.status)
                        .foregroundStyle(record.outputName == nil ? .secondary : .primary)
                }
                .width(ideal: 110)
            }
        }
    }
}

/// NSTextView handles large emoji-heavy subscriptions much more efficiently
/// than SwiftUI Text with text selection. Non-contiguous layout keeps offscreen
/// lines from being shaped until they are needed.
private struct WrappingPlainTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        let previousSelection = textView.selectedRange()
        textView.string = text
        let textLength = (text as NSString).length
        let location = min(previousSelection.location, textLength)
        let length = min(previousSelection.length, textLength - location)
        textView.setSelectedRange(NSRange(location: location, length: length))
    }
}

private struct AirportSubscriptionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let subscription: AirportSubscription?
    @State private var draft: AirportSubscriptionDraft
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(subscription: AirportSubscription?) {
        self.subscription = subscription
        _draft = State(initialValue: subscription.map(AirportSubscriptionDraft.init) ?? AirportSubscriptionDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("机场") {
                    TextField("名称", text: $draft.name, prompt: Text("例如 FlowerCloud"))
                    Toggle("写入 Surge 配置", isOn: $draft.isEnabled)
                }
                Section("订阅") {
                    TextField("订阅链接", text: $draft.sourceURL, prompt: Text("https://…"))
                }
                Section("节点筛选") {
                    Toggle("过滤流量、到期等订阅信息节点", isOn: $draft.nodeProcessing.filtersMetadataNodes)
                    AirportKeywordListEditor(
                        title: "只保留包含",
                        prompt: "例如 香港",
                        keywords: $draft.nodeProcessing.includeKeywords
                    )
                    AirportKeywordListEditor(
                        title: "排除包含",
                        prompt: "例如 倍率",
                        keywords: $draft.nodeProcessing.excludeKeywords
                    )
                    DisclosureGroup("高级正则") {
                        TextField(
                            "节点过滤正则",
                            text: $draft.policyRegexFilter,
                            prompt: Text("留空则不使用")
                        )
                    }
                }
                Section("节点排序") {
                    Picker("排序方式", selection: $draft.nodeProcessing.sortOrder) {
                        ForEach(AirportNodeSortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    if draft.nodeProcessing.sortOrder == .keywordPriority {
                        AirportKeywordListEditor(
                            title: "优先级",
                            prompt: "依次添加 香港、日本…",
                            keywords: $draft.nodeProcessing.sortPriorityKeywords
                        )
                    }
                }
                Section("代理属性") {
                    AirportProxyOptionsEditor(options: $draft.nodeProcessing)
                }
                Section("可选参数") {
                    TextField("节点名称模板", text: $draft.nodeNameTemplate, prompt: Text("例如 {airport} - {name}"))
                    Text("使用 {airport} 表示机场名称，{name} 表示原节点名称；留空则不重命名。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("图标地址", text: $draft.iconURL, prompt: Text("https://…"))
                }
                Section("节点名称优化") {
                    AirportNodeNameOptimizationEditor(optimization: $draft.nodeNameOptimization)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(subscription == nil ? "添加机场" : "编辑机场")
            .frame(minWidth: 580, minHeight: 650)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.saveAirportSubscriptionForCurrentMode(id: subscription?.id, draft: draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AirportKeywordListEditor: View {
    let title: String
    let prompt: String
    @Binding var keywords: [String]
    @State private var pendingKeyword = ""

    private var visibleKeywords: [String] {
        var seen = Set<String>()
        return keywords.filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    TextField(prompt, text: $pendingKeyword)
                        .onSubmit(addKeyword)
                    Button("添加", systemImage: "plus", action: addKeyword)
                        .labelStyle(.iconOnly)
                        .disabled(pendingKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: 300)
            }
            if !visibleKeywords.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(visibleKeywords, id: \.self) { keyword in
                            HStack(spacing: 4) {
                                Text(keyword)
                                Button {
                                    keywords.removeAll { $0.caseInsensitiveCompare(keyword) == .orderedSame }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("移除关键词 \(keyword)")
                            }
                            .padding(.leading, 8)
                            .padding(.trailing, 5)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func addKeyword() {
        let keyword = pendingKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty,
              !keywords.contains(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame }) else { return }
        keywords.append(keyword)
        pendingKeyword = ""
    }
}

private struct AirportProxyOptionsEditor: View {
    @Binding var options: AirportNodeProcessingOptions

    var body: some View {
        proxyOptionPicker("UDP Relay", selection: $options.udpRelay)
        proxyOptionPicker("TCP Fast Open", selection: $options.tcpFastOpen)
        proxyOptionPicker("跳过证书验证", selection: $options.skipCertificateVerification)
        Text("仅对支持该参数的代理协议生效；“跟随订阅”不会修改原始值。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func proxyOptionPicker(
        _ title: String,
        selection: Binding<AirportProxyOptionOverride>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(AirportProxyOptionOverride.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
    }
}

private struct AirportNodeNameOptimizationEditor: View {
    @Binding var optimization: AirportNodeNameOptimization

    private let exampleName = "🇭🇰 香港实验性 IEPL 专线 1"

    private var optimizedExampleName: String {
        AirportSubscriptionParser.optimizedNodeName(exampleName, using: optimization)
    }

    var body: some View {
        Toggle("自动优化节点名称", isOn: $optimization.isEnabled)
        if optimization.isEnabled {
            Toggle("移除 Emoji 与国旗", isOn: $optimization.removesEmoji)
            TextField(
                "移除关键词",
                text: $optimization.removalTerms,
                prompt: Text(AirportNodeNameOptimization.defaultRemovalTerms)
            )
            Text("使用逗号分隔，不区分大小写。")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("效果示例") {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(exampleName)
                        .foregroundStyle(.secondary)
                    Text(optimizedExampleName)
                        .fontWeight(.medium)
                }
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("优化前 \(exampleName)，优化后 \(optimizedExampleName)")
            }
        }
    }
}
