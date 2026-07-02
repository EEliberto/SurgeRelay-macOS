import AppKit
import SwiftUI

private struct ModuleNavigationButtons: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            navigationButton(systemImage: "chevron.left", isEnabled: canGoBack, action: goBack)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.22))
                .frame(width: 1, height: 17)

            navigationButton(systemImage: "chevron.right", isEnabled: canGoForward, action: goForward)
        }
        .frame(width: 72, height: 32)
        .glassEffect(.regular, in: Capsule())
    }

    private func navigationButton(
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 35, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.28))
        .disabled(!isEnabled)
    }
}

struct ModulesView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var editorRoute: ModuleEditorRoute?
    @State private var deleteCandidate: RelayModule?
    @State private var detailTab: DetailTab = .info
    @State private var contentIndex: [UUID: String] = [:]
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var backStack: [UUID?] = []
    @State private var forwardStack: [UUID?] = []
    @State private var isHistoryNavigation = false

    private enum DetailTab: Hashable { case info, preview }

    private enum SelectionKind {
        case combined
        case module(RelayModule)
    }

    private var selectionKind: SelectionKind? {
        if model.selectedModuleID == AppModel.combinedModuleSelectionID { return .combined }
        if let id = model.selectedModuleID,
           let module = model.modules.first(where: { $0.id == id }) {
            return .module(module)
        }
        return nil
    }

    private var selectedDetailTitle: String? {
        guard let selectionKind else { return nil }
        switch selectionKind {
        case .combined: return "Surge Relay 汇总"
        case let .module(module): return module.name
        }
    }

    private var filteredModules: [RelayModule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.modules }
        return model.modules.filter { searchableText(for: $0).contains(query) }
    }

    private func searchableText(for module: RelayModule) -> String {
        var parts = [
            module.name,
            module.sourceURL,
            module.outputFileName,
            module.sourceFormatDisplayTitle,
        ]
        parts.append(contentsOf: module.argumentOverrides.flatMap { [$0.key, $0.value] })
        if let data = try? JSONEncoder().encode(module.scriptHubOptions),
           let text = String(data: data, encoding: .utf8) {
            parts.append(text)
        }
        if let content = contentIndex[module.id] {
            parts.append(content)
        }
        return parts.joined(separator: "\n").lowercased()
    }

    private var contentIndexToken: String {
        model.modules.map { "\($0.id.uuidString)\($0.contentHash ?? "")" }.joined()
    }

    private func rebuildContentIndex() async {
        var index: [UUID: String] = [:]
        for module in model.modules {
            if let content = try? await model.previewContent(for: module) {
                index[module.id] = content.lowercased()
            }
        }
        contentIndex = index
    }

    /// Floating status / latest-update card pinned to the bottom of the sidebar.
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.presentedError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button {
                        model.presentedError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }

            if model.isWorking {
                if let name = synchronizingModuleName, model.synchronizationTotalCount > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(name)
                                .lineLimit(1)
                                .contentTransition(.identity)
                            Spacer(minLength: 4)
                            Text("\(synchronizationPercentage)%")
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(synchronizationPercentage)))
                                .animation(.smooth(duration: 0.25), value: synchronizationPercentage)
                        }
                        .font(.caption)
                        ProgressView(value: synchronizationProgress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .animation(.smooth(duration: 0.25), value: synchronizationProgress)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.statusMessage)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
                Divider()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("最新更新时间")
                    .font(.caption.weight(.medium))
                Text(latestUpdateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .animation(.snappy, value: model.isWorking)
        .animation(.snappy, value: model.presentedError)
    }

    private var latestUpdateText: String {
        guard let date = model.modules.compactMap(\.lastUpdatedAt).max() else { return "尚未更新" }
        return date.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: Locale(identifier: "zh_CN")
        ))
    }

    private var synchronizingModuleName: String? {
        guard let id = model.synchronizingModuleID else { return nil }
        return model.modules.first(where: { $0.id == id })?.name
    }

    private var synchronizationProgress: Double {
        guard model.synchronizationTotalCount > 0 else { return 0 }
        return min(
            max(Double(model.synchronizationCompletedCount) / Double(model.synchronizationTotalCount), 0),
            1
        )
    }

    private var synchronizationPercentage: Int {
        Int((synchronizationProgress * 100).rounded())
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $model.selectedModuleID) {
                Section {
                    CombinedModuleRow()
                        .tag(AppModel.combinedModuleSelectionID)
                }

                Section {
                if searchText.isEmpty {
                    ForEach(model.modules) { module in
                        moduleRow(module)
                    }
                    .onMove { offsets, destination in
                        model.moveModules(fromOffsets: offsets, toOffset: destination)
                    }
                } else {
                    ForEach(filteredModules) { module in
                        moduleRow(module)
                    }
                }
                }
            }
            .overlay {
                if filteredModules.isEmpty {
                    ContentUnavailableView(
                        model.modules.isEmpty ? "还没有模块" : "没有搜索结果",
                        systemImage: "shippingbox",
                        description: Text(model.modules.isEmpty ? "添加第一个原始地址，Surge Relay 会把所有来源合并成一份总模块。" : "换个关键词试试。")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) { statusCard }
            .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 380)
            .navigationTitle("模块")
            .toolbar {
                if columnVisibility != .detailOnly {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            editorRoute = ModuleEditorRoute(module: nil)
                        } label: {
                            Label("添加模块", systemImage: "plus")
                        }
                        Button {
                            Task { await model.updateAll() }
                        } label: {
                            Label("更新全部", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.modules.isEmpty || model.isWorking)
                    }
                }
            }
        } detail: {
            Group {
                if let kind = selectionKind {
                    // Keep both panes mounted and just toggle opacity, so switching
                    // tabs never destroys/recreates (and re-loads) the code preview
                    // view — that recreation is what caused the white flash.
                    ZStack {
                        switch kind {
                        case .combined:
                            CombinedModuleDetailView()
                                .opacity(detailTab == .info ? 1 : 0)
                                .allowsHitTesting(detailTab == .info)
                            CombinedPreviewPane()
                                .opacity(detailTab == .preview ? 1 : 0)
                                .allowsHitTesting(detailTab == .preview)
                        case let .module(module):
                            ModuleDetailView(module: module, onEdit: { presentEditor(module) })
                                .opacity(detailTab == .info ? 1 : 0)
                                .allowsHitTesting(detailTab == .info)
                            ModulePreviewPane(module: module)
                                .opacity(detailTab == .preview ? 1 : 0)
                                .allowsHitTesting(detailTab == .preview)
                        }
                    }
                } else {
                    ContentUnavailableView("选择一个模块", systemImage: "sidebar.right")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .searchable(text: $searchText, prompt: "搜索")
            .toolbar {
                if let selectedDetailTitle {
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 12) {
                            ModuleNavigationButtons(
                                canGoBack: !backStack.isEmpty,
                                canGoForward: !forwardStack.isEmpty,
                                goBack: goBack,
                                goForward: goForward
                            )

                            Text(selectedDetailTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 280, alignment: .leading)
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarSpacer(.flexible)
                if selectionKind != nil {
                    ToolbarItem {
                        Picker("视图", selection: $detailTab) {
                            Image(systemName: "info.circle")
                                .accessibilityLabel("详情")
                                .tag(DetailTab.info)
                            Image(systemName: "curlybraces")
                                .accessibilityLabel("预览")
                                .tag(DetailTab.preview)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
        }
        .onChange(of: model.selectedModuleID) { oldValue, newValue in
            detailTab = .info
            guard oldValue != newValue else { return }
            if isHistoryNavigation {
                isHistoryNavigation = false
                return
            }
            backStack.append(oldValue)
            forwardStack.removeAll()
        }
        .task(id: contentIndexToken) { await rebuildContentIndex() }
        .sheet(item: $editorRoute) { route in
            ModuleEditorView(module: route.module)
                .environment(model)
        }
        .confirmationDialog(
            "删除“\(deleteCandidate?.name ?? "")”？",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            )
        ) {
            Button("删除来源并重新合并", role: .destructive) {
                guard let id = deleteCandidate?.id else { return }
                deleteCandidate = nil
                Task { await model.deleteModule(id: id) }
            }
            Button("取消", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("该来源会从总模块中移除；GitHub 上的旧版本会保留到下次发布。")
        }
    }

    private func presentEditor(_ module: RelayModule) {
        editorRoute = ModuleEditorRoute(module: module)
    }

    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(model.selectedModuleID)
        isHistoryNavigation = true
        model.selectedModuleID = previous
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(model.selectedModuleID)
        isHistoryNavigation = true
        model.selectedModuleID = next
    }

    @ViewBuilder
    private func moduleRow(_ module: RelayModule) -> some View {
        ModuleRow(module: module)
            .tag(module.id)
            .contextMenu {
                Button("编辑") { presentEditor(module) }
                Divider()
                Button("删除", role: .destructive) { deleteCandidate = module }
            }
    }
}

private struct CombinedModuleRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 9) {
            Image("SummaryIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(summaryIconShape)
                .overlay {
                    summaryIconShape
                        .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("Surge Relay 汇总")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("\(model.modules.filter(\.isEnabled).count) 个来源 · 总模块订阅")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 7)
    }

    private var summaryIconShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28 * ModuleIconView.cornerRadiusRatio, style: .continuous)
    }
}

private struct CombinedModuleDetailView: View {
    @Environment(AppModel.self) private var model

    private var latestUpdateAt: Date? {
        model.modules.compactMap(\.lastUpdatedAt).max()
    }

    var body: some View {
        Form {
            Section("汇总模块") {
                detailRow("名称", value: "Surge Relay 汇总", icon: "square.stack.3d.up.fill")
                detailRow(
                    "包含来源",
                    value: "\(model.modules.filter(\.isEnabled).count) / \(model.modules.count)",
                    icon: "shippingbox"
                )
                detailRow(
                    "最新更新",
                    value: latestUpdateAt?.formatted(Date.FormatStyle(
                        date: .long,
                        time: .standard,
                        locale: Locale(identifier: "zh_CN")
                    )) ?? "尚未更新",
                    icon: "clock"
                )
            }

            if model.settings.storageMode == .local {
                Section("iCloud 云盘") {
                    HStack(spacing: 14) {
                        Image("iCloudIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("通过 iCloud 保持 Surge Relay 同步")
                                .font(.body.weight(.medium))
                            Text("iCloud/Surge/Surge-Relay.sgmodule")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                Section("总模块订阅地址") {
                    if let rawURL = model.combinedRawURL {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(rawURL.absoluteString)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            URLCopyButton(url: rawURL)
                        }
                    } else {
                        Label("完成发布配置后，这里会显示稳定订阅地址。", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Label(label, systemImage: icon)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ModuleEditorRoute: Identifiable {
    let id: UUID
    let module: RelayModule?

    init(module: RelayModule?) {
        self.module = module
        id = module?.id ?? UUID()
    }
}

private struct ModuleRow: View {
    @Environment(AppModel.self) private var model
    let module: RelayModule

    var body: some View {
        HStack(spacing: 9) {
            ModuleIconView(module: module, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.name).fontWeight(.medium).lineLimit(1)
                Text(module.sourceFormatDisplayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if module.state == .updating {
                ProgressView()
                    .controlSize(.small)
            }
            Toggle("包含", isOn: Binding(
                get: { module.isEnabled },
                set: { model.setModuleEnabled(id: module.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 5)
        .opacity(module.isEnabled ? 1 : 0.55)
    }
}

private struct ModuleDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var argumentInfo = ModuleArgumentInfo()
    let module: RelayModule
    let onEdit: () -> Void

    var body: some View {
        Form {
                Section("模块信息") {
                    detailRow("原始地址", value: module.sourceURL, icon: "link")
                    detailRow("来源格式", value: module.sourceFormatDisplayTitle, icon: "doc.text")
                    if model.settings.storageMode == .local {
                        detailRow(
                            "同步方式",
                            value: "通过 iCloud 同步至 Surge-Relay.sgmodule",
                            icon: "icloud.fill"
                        )
                    } else {
                        detailRow(
                            "汇总订阅",
                            value: combinedOutputLocation,
                            icon: "square.stack.3d.up"
                        )
                    }
                    detailRow(
                        "上次更新",
                        value: module.lastUpdatedAt?.formatted(Date.FormatStyle(
                            date: .long,
                            time: .standard,
                            locale: Locale(identifier: "zh_CN")
                        )) ?? "从未更新",
                        icon: "clock"
                    )
                    Button("编辑模块…", systemImage: "pencil", action: onEdit)
                }

                if model.settings.storageMode == .local {
                    Section("iCloud 云盘") {
                        Toggle(
                            "输出独立模块至 iCloud 云盘",
                            isOn: Binding(
                                get: {
                                    model.modules.first(where: { $0.id == module.id })?
                                        .exportsIndividualModuleToICloud
                                        ?? module.exportsIndividualModuleToICloud
                                },
                                set: { enabled in
                                    Task {
                                        await model.setModuleIndividualICloudExport(
                                            id: module.id,
                                            enabled: enabled
                                        )
                                    }
                                }
                            )
                        )
                        Text("开启后在 Surge 文件夹生成该模块的独立文件；关闭后自动删除。汇总模块不受影响。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let summary = module.scriptHubOptions.configuredSummary {
                    Section("高级设置") {
                        Label {
                            Text(summary)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }

                if !argumentInfo.definitions.isEmpty {
                    Section("模块参数") {
                        ForEach(argumentInfo.definitions) { definition in
                            argumentControl(definition)
                        }
                        HStack {
                            Text("修改会立即应用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复默认值") {
                                model.resetModuleArguments(moduleID: module.id)
                            }
                            .disabled(module.argumentOverrides.isEmpty)
                        }
                        if let help = argumentInfo.helpText {
                            DisclosureGroup("参数说明") {
                                Text(help)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }

                if model.settings.storageMode == .gitHub {
                    Section(model.settings.github.repositoryIsPrivate == true ? "Cloudflare" : "GitHub") {
                        if let rawURL = model.rawURL(for: module) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(rawURL.absoluteString)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                HStack {
                                    URLCopyButton(url: rawURL)
                                }
                            }
                        } else {
                            Label("完成发布配置后，这里会出现该模块自己的稳定地址。", systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = module.lastError {
                    Section("最近一次更新失败") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("更新失败", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error).textSelection(.enabled)
                            Text("如果该来源有缓存，总模块会继续沿用它上一次成功版本。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if module.hasOverrideConflict {
                    Section("本地编辑冲突") {
                        Label("上游模块已经变化，本地编辑仍在使用。请前往“预览”比较后决定保留或恢复。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

        }
        .formStyle(.grouped)
        .task(id: "\(module.id.uuidString)-\(module.contentHash ?? "")") {
            argumentInfo = await model.moduleArgumentInfo(for: module)
        }
    }

    private var combinedOutputLocation: String {
        return model.combinedRawURL?.absoluteString ?? "等待 GitHub 发布配置"
    }

    @ViewBuilder
    private func argumentControl(_ definition: ModuleArgumentDefinition) -> some View {
        let value = argumentValue(for: definition)
        if ["true", "false"].contains(definition.defaultValue.lowercased()) {
            Toggle(definition.key, isOn: Binding(
                get: { argumentValue(for: definition).lowercased() == "true" },
                set: { enabled in
                    model.setModuleArgument(
                        moduleID: module.id,
                        key: definition.key,
                        value: enabled ? "true" : "false",
                        defaultValue: definition.defaultValue
                    )
                }
            ))
            .toggleStyle(.switch)
        } else {
            LabeledContent(definition.key) {
                TextField(
                    "",
                    text: Binding(
                        get: { argumentValue(for: definition) },
                        set: { newValue in
                            model.setModuleArgument(
                                moduleID: module.id,
                                key: definition.key,
                                value: newValue,
                                defaultValue: definition.defaultValue
                            )
                        }
                    ),
                    prompt: Text(definition.defaultValue)
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 180)
            }
            .help("默认值：\(definition.defaultValue)；当前值：\(value)")
        }
    }

    private func argumentValue(for definition: ModuleArgumentDefinition) -> String {
        model.modules.first(where: { $0.id == module.id })?.argumentOverrides[definition.key]
            ?? definition.defaultValue
    }

    private func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Label(label, systemImage: icon)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
