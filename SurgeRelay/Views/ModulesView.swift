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
    @State private var iconEditorContext: IconEditorContext?
    @State private var deleteCandidate: RelayModule?
    @State private var detailTab: DetailTab = .info
    @State private var contentIndex: [UUID: String] = [:]
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var backStack: [UUID?] = []
    @State private var forwardStack: [UUID?] = []
    @State private var isHistoryNavigation = false

    private enum DetailTab: Hashable { case info, preview }

    private enum SelectionKind {
        case combined(RelayPlatform)
        case module(RelayModule)
    }

    private var selectionKind: SelectionKind? {
        if let id = model.selectedModuleID {
            if let platform = RelayPlatform.from(selectionID: id) {
                return .combined(platform)
            }
            if let module = model.modules.first(where: { $0.id == id }) {
                return .module(module)
            }
        }
        return nil
    }

    private var selectedDetailTitle: String? {
        guard let selectionKind else { return nil }
        switch selectionKind {
        case let .combined(platform): return "Surge Relay 汇总 (\(platform.summaryDisplayName))"
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

    private var detailTabSwitcher: some View {
        DetailTabSegmentedControl(selection: $detailTab)
            .frame(width: 160, height: 32)
    }

    private struct DetailTabSegmentedControl: NSViewRepresentable {
        @Binding var selection: DetailTab

        func makeCoordinator() -> Coordinator {
            Coordinator(selection: $selection)
        }

        func makeNSView(context: Context) -> NSSegmentedControl {
            let control = NSSegmentedControl(
                labels: ["详情", "预览"],
                trackingMode: .selectOne,
                target: context.coordinator,
                action: #selector(Coordinator.selectionChanged(_:))
            )
            control.segmentStyle = .rounded
            control.controlSize = .regular
            configure(control)
            control.selectedSegment = segmentIndex(for: selection)
            return control
        }

        func updateNSView(_ control: NSSegmentedControl, context: Context) {
            context.coordinator.selection = $selection
            configure(control)
            control.selectedSegment = segmentIndex(for: selection)
        }

        private func configure(_ control: NSSegmentedControl) {
            control.segmentCount = 2

            control.setLabel("详情", forSegment: 0)
            control.setImage(
                NSImage(systemSymbolName: "info.circle", accessibilityDescription: "详情"),
                forSegment: 0
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: 0)
            control.setWidth(80, forSegment: 0)

            control.setLabel("预览", forSegment: 1)
            control.setImage(
                NSImage(systemSymbolName: "curlybraces", accessibilityDescription: "预览"),
                forSegment: 1
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: 1)
            control.setWidth(80, forSegment: 1)
        }

        private func segmentIndex(for tab: DetailTab) -> Int {
            switch tab {
            case .info: return 0
            case .preview: return 1
            }
        }

        final class Coordinator: NSObject {
            var selection: Binding<DetailTab>

            init(selection: Binding<DetailTab>) {
                self.selection = selection
            }

            @MainActor @objc func selectionChanged(_ sender: NSSegmentedControl) {
                switch sender.selectedSegment {
                case 0:
                    selection.wrappedValue = .info
                case 1:
                    selection.wrappedValue = .preview
                default:
                    break
                }
            }
        }
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
                        .lineLimit(4)
                        .truncationMode(.tail)
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

            if model.isWorking || model.settings.storageMode == .local {
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
                        if model.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
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
                Section("汇总模块") {
                    ForEach(model.enabledPlatforms) { platform in
                        CombinedModuleRow(platform: platform)
                            .tag(platform.selectionID)
                    }
                }

                Section("来源模块") {
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
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 4) {
                sidebarSearchBar
                        .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
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
            .safeAreaBar(edge: .bottom, spacing: 0) { statusCard }
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
                        case let .combined(platform):
                            CombinedModuleDetailView(platform: platform)
                                .opacity(detailTab == .info ? 1 : 0)
                                .allowsHitTesting(detailTab == .info)
                            CombinedPreviewPane(platform: platform, showsFindBar: detailTab == .preview)
                                .opacity(detailTab == .preview ? 1 : 0)
                                .allowsHitTesting(detailTab == .preview)
                        case let .module(module):
                            ModuleDetailView(module: module, onEdit: { presentEditor(module) }, onEditIcon: {
                                iconEditorContext = .module(module.id)
                            })
                                .opacity(detailTab == .info ? 1 : 0)
                                .allowsHitTesting(detailTab == .info)
                            ModulePreviewPane(module: module, showsFindBar: detailTab == .preview)
                                .opacity(detailTab == .preview ? 1 : 0)
                                .allowsHitTesting(detailTab == .preview)
                        }
                    }
                } else {
                    ContentUnavailableView("选择一个模块", systemImage: "sidebar.right")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.vertical, 1)
            .toolbar {
                if selectionKind != nil {
                    ToolbarItem(placement: .navigation) {
                        ModuleNavigationButtons(
                            canGoBack: !backStack.isEmpty,
                            canGoForward: !forwardStack.isEmpty,
                            goBack: goBack,
                            goForward: goForward
                        )
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarSpacer(.flexible)
                if selectionKind != nil {
                    ToolbarItem {
                        detailTabSwitcher
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
        .sheet(item: $iconEditorContext) { context in
            IconEditorView(context: context)
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
                Button("编辑模块") { presentEditor(module) }
                Button("修改图标") { iconEditorContext = .module(module.id) }
                Divider()
                Button("删除", role: .destructive) { deleteCandidate = module }
            }
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }
}

private struct CombinedModuleRow: View {
    @Environment(AppModel.self) private var model
    let platform: RelayPlatform

    var body: some View {
        HStack(spacing: 9) {
            Image(platform.summaryIconAssetName)
                .resizable()
                .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(summaryIconShape)
            .overlay {
                summaryIconShape
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Surge Relay 汇总 (\(platform.summaryDisplayName))")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                let platformModules = model.settings.modules(for: platform, globalModules: model.modules)
                Text("\(platformModules.filter(\.isEnabled).count) 个来源")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
    }

    private var summaryIconShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28 * ModuleIconView.cornerRadiusRatio, style: .continuous)
    }

}

private struct CombinedModuleDetailView: View {
    @Environment(AppModel.self) private var model
    let platform: RelayPlatform

    private var latestUpdateAt: Date? {
        let platformModules = model.settings.modules(for: platform, globalModules: model.modules)
        return platformModules.compactMap(\.lastUpdatedAt).max()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(platform.summaryIconAssetName)
                        .resizable()
                        .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 54 * ModuleIconView.cornerRadiusRatio, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 54 * ModuleIconView.cornerRadiusRatio, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Surge Relay 汇总 (\(platform.summaryDisplayName))")
                            .font(.title3.bold())
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("汇总模块信息") {
                detailRow("名称", value: "Surge Relay 汇总 (\(platform.summaryDisplayName))", icon: "square.stack.3d.up.fill")
                let platformModules = model.settings.modules(for: platform, globalModules: model.modules)
                detailRow(
                    "包含来源",
                    value: "\(platformModules.filter(\.isEnabled).count) / \(platformModules.count)",
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
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("通过 iCloud 保持 Surge Relay 同步")
                                .font(.body.weight(.medium))
                            Text("iCloud/Surge/\(model.platformFileName(for: platform))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                Section("GitHub 私有仓库") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Image("GitHubIcon")
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("通过 GitHub 保持 Surge Relay 同步")
                                    .font(.body.weight(.medium))
                                Text("经 Cloudflare Worker 分发稳定订阅")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        if let rawURL = model.combinedRawURL(for: platform) {
                            Text(rawURL.absoluteString)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            URLCopyButton(url: rawURL)
                        } else {
                            Label("完成发布配置后，这里会显示稳定订阅地址。", systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                let platformModules = model.settings.modules(for: platform, globalModules: model.modules)
                ForEach(platformModules) { module in
                    HStack(spacing: 8) {
                        ModuleIconView(module: module, size: 20)
                        Text(module.name)
                            .font(.body)
                            .lineLimit(1)
                            .textSelection(.disabled)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { module.isEnabled },
                            set: { enabled in
                                model.setPlatformModuleEnabled(platform: platform, moduleID: module.id, enabled: enabled)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                HStack {
                    Text("来源模块选择")
                    Spacer()
                    Button(model.settings.modules(for: platform, globalModules: model.modules).allSatisfy { $0.isEnabled } ? "全部停用" : "全部启用") {
                        let allEnabled = model.settings.modules(for: platform, globalModules: model.modules).allSatisfy { $0.isEnabled }
                        model.setAllPlatformModulesEnabled(platform: platform, enabled: !allEnabled)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.blue)
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
        }
        .padding(.vertical, 5)
        .opacity(module.isEnabled ? 1 : 0.55)
    }
}

private struct ModuleDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var argumentInfo = ModuleArgumentInfo()
    @State private var savedArgumentValues: [String: String] = [:]
    @State private var pendingArgumentValues: [String: String] = [:]
    
    let module: RelayModule
    let onEdit: () -> Void
    let onEditIcon: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ModuleIconView(module: module, size: 54)
                        .onTapGesture {
                            onEditIcon()
                        }
                        .help("点击修改图标")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(module.name)
                            .font(.title3.bold())
                        HStack(spacing: 10) {
                            Button("修改图标") { onEditIcon() }
                            Button("编辑模块") { onEdit() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.callout)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("模块信息") {
                    detailRow("原始地址", value: module.sourceURL, icon: "link")
                    detailRow("来源格式", value: module.sourceFormatDisplayTitle, icon: "doc.text")
                    if model.settings.storageMode == .gitHub {
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
                }

                if model.settings.storageMode == .local {
                    Section("iCloud 云盘") {
                        HStack(spacing: 14) {
                            Image("iCloudIcon")
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("输出独立模块至 iCloud 云盘")
                                    .font(.body.weight(.medium))
                                Text(individualICloudLocation)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
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
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        Text("开启后在 Surge 文件夹生成该模块的独立文件；关闭后自动删除。汇总模块不受影响。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("提示：若要自行修改模块内容，请通过右上角“预览”进行编辑。直接修改 iCloud 生成的同步文件将在下一次同步时被覆盖。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .minimumScaleFactor(0.75)
                                .layoutPriority(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            Spacer()
                            Button("恢复默认值") {
                                pendingArgumentValues = Dictionary(
                                    uniqueKeysWithValues: argumentInfo.definitions.map {
                                        ($0.key, $0.defaultValue)
                                    }
                                )
                            }
                            .disabled(!hasNonDefaultPendingArguments)
                            Button("确认") {
                                applyPendingArguments()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasPendingArgumentChanges)
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
                    Section("GitHub 私有仓库") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 14) {
                                Image("GitHubIcon")
                                    .resizable()
                                    .interpolation(.high)
                                    .antialiased(true)
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("通过 GitHub 同步独立模块")
                                        .font(.body.weight(.medium))
                                    Text("经 Cloudflare Worker 分发稳定订阅")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Divider()

                            if let rawURL = model.rawURL(for: module) {
                                Text(rawURL.absoluteString)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                URLCopyButton(url: rawURL)
                            } else {
                                Label("完成发布配置后，这里会出现该模块自己的稳定地址。", systemImage: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("提示：若要自行修改模块内容，请通过右上角“预览”进行编辑。直接修改 GitHub 里的生成模块将在下次发布时被覆盖。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
            reloadPendingArguments()
        }
    }


    private var combinedOutputLocation: String {
        return model.combinedRawURL(for: .ios)?.absoluteString ?? "等待 GitHub 发布配置"
    }

    private var individualICloudLocation: String {
        "iCloud/Surge/\(FilenameSanitizer.individualRelayName(from: module.outputFileName))"
    }

    @ViewBuilder
    private func argumentControl(_ definition: ModuleArgumentDefinition) -> some View {
        let value = argumentValue(for: definition)
        if ["true", "false"].contains(definition.defaultValue.lowercased()) {
            Toggle(definition.key, isOn: Binding(
                get: { argumentValue(for: definition).lowercased() == "true" },
                set: { enabled in
                    pendingArgumentValues[definition.key] = enabled ? "true" : "false"
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
                            pendingArgumentValues[definition.key] = newValue
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
        pendingArgumentValues[definition.key] ?? definition.defaultValue
    }

    private var hasPendingArgumentChanges: Bool {
        normalizedArgumentValues(pendingArgumentValues) != normalizedArgumentValues(savedArgumentValues)
    }

    private var hasNonDefaultPendingArguments: Bool {
        argumentInfo.definitions.contains { definition in
            normalizedValue(pendingArgumentValues[definition.key] ?? definition.defaultValue)
                != normalizedValue(definition.defaultValue)
        }
    }

    private func reloadPendingArguments() {
        let storedOverrides = model.modules.first(where: { $0.id == module.id })?.argumentOverrides
            ?? module.argumentOverrides
        let values = Dictionary(uniqueKeysWithValues: argumentInfo.definitions.map { definition in
            (definition.key, storedOverrides[definition.key] ?? definition.defaultValue)
        })
        savedArgumentValues = values
        pendingArgumentValues = values
    }

    private func applyPendingArguments() {
        let defaults = Dictionary(uniqueKeysWithValues: argumentInfo.definitions.map {
            ($0.key, $0.defaultValue)
        })
        model.setModuleArguments(
            moduleID: module.id,
            values: pendingArgumentValues,
            defaultValues: defaults
        )
        let normalized = normalizedArgumentValues(pendingArgumentValues)
        savedArgumentValues = Dictionary(uniqueKeysWithValues: argumentInfo.definitions.map { definition in
            (definition.key, normalized[definition.key] ?? definition.defaultValue)
        })
        pendingArgumentValues = savedArgumentValues
    }

    private func normalizedArgumentValues(_ values: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: argumentInfo.definitions.map { definition in
            (definition.key, normalizedValue(values[definition.key] ?? definition.defaultValue))
        })
    }

    private func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
enum IconEditorContext: Identifiable, Hashable {
    case module(UUID)
    case platform(String)

    var id: String {
        switch self {
        case let .module(id): return "module-\(id.uuidString)"
        case let .platform(p): return "platform-\(p)"
        }
    }
}

struct IconEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let context: IconEditorContext

    @State private var query = ""
    @State private var isSearching = false
    @State private var searchResults: [IconSearchResult] = []
    @State private var customURLInput = ""
    @State private var selectedIconURL: String?
    @State private var pendingIconURL: String?
    @State private var pendingIconSource: CustomIconSource = .manual
    @State private var hasPendingIconSelection = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(navigationTitle)
                        .font(.title2.bold())
                    Text(supportsAppStoreSearch ? "手动输入图片链接，或从 App Store 搜索并选择图标。" : "汇总图标仅支持手动导入图片链接。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                iconPreview
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    manualIconSection

                    if supportsAppStoreSearch {
                        appStoreSearchSection
                    }
                    if !supportsAppStoreSearch {
                        Text("汇总图标仅支持手动导入图片 (PNG 或 JPEG) 链接。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                if hasCustomIcon {
                    Button(role: .destructive) {
                        pendingIconURL = nil
                        selectedIconURL = nil
                        pendingIconSource = .manual
                        hasPendingIconSelection = true
                    } label: {
                        Label("恢复默认图标", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
                Button("完成") {
                    if pendingIconURL != currentCustomIconURL {
                        saveIcon(pendingIconURL, source: pendingIconSource)
                    } else {
                        dismiss()
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: supportsAppStoreSearch ? 540 : 320)
        .task {
            customURLInput = currentCustomIconSource == .manual ? (currentCustomIconURL ?? "") : ""
            selectedIconURL = currentCustomIconURL
            pendingIconURL = currentCustomIconURL
            pendingIconSource = currentCustomIconSource
            hasPendingIconSelection = false
            guard case let .module(id) = context,
                  let module = model.modules.first(where: { $0.id == id }) else {
                return
            }
            query = AppModel.cleanSearchQuery(module.name)
            performSearch()
        }
        .alert("保存失败", isPresented: isPresentingSaveError) {
            Button("确定", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .dialogSeverity(.critical)
    }

    private var manualIconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                    Text("手动导入")
                        .fixedSize(horizontal: true, vertical: false)

                    TextField("", text: $customURLInput, prompt: Text("https://example.com/icon.png"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                        .id("custom-icon-url-field")

                    Button("载入") {
                        let trimmed = customURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        pendingIconURL = trimmed
                        selectedIconURL = trimmed
                        pendingIconSource = .manual
                        hasPendingIconSelection = true
                    }
                    .buttonStyle(.borderedProminent)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(customURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .padding(.trailing, 4)

        }
        .padding(16)
        .background(
            .quaternary.opacity(0.35),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appStoreSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("从 App Store 搜索")
                    .font(.headline)
                regionMenu
            }

            HStack(alignment: .center, spacing: 12) {
                    TextField("", text: $query, prompt: Text("输入 App 名称或关键字"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .id("app-store-icon-search-field")
                    .onSubmit { performSearch() }

                    Button {
                        performSearch()
                    } label: {
                        Text("搜索")
                    }
                    .buttonStyle(.bordered)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .padding(.trailing, 4)

            if isSearching {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("正在搜索...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else if searchResults.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                    Text(query.isEmpty ? "请输入关键字进行搜索。" : "未找到相关图标。")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: iconGridColumns, alignment: .leading, spacing: 14) {
                    ForEach(rankedSearchResults, id: \.url) { result in
                        Button {
                            selectedIconURL = result.url
                            pendingIconURL = result.url
                            pendingIconSource = .appStore
                            hasPendingIconSelection = true
                        } label: {
                            IconSearchResultCell(
                                result: result,
                                isSelected: selectedIconURL == result.url
                            )
                        }
                        .buttonStyle(.plain)
                        .help(result.name)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .background(
            .quaternary.opacity(0.35),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var regionMenu: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }

            Menu {
                Button("🇨🇳 中国") { setSearchRegion("cn") }
                Button("🇺🇸 美国") { setSearchRegion("us") }
                Button("🇯🇵 日本") { setSearchRegion("jp") }
                Button("🇭🇰 香港") { setSearchRegion("hk") }
                Button("🇹🇼 台湾") { setSearchRegion("tw") }
            } label: {
                Text(regionEmojiAndName(model.settings.iconSearchRegion))
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(width: 78, height: 24)
    }

    @ViewBuilder
    private var iconPreview: some View {
        Group {
            if let urlString = (hasPendingIconSelection ? pendingIconURL : currentCustomIconURL),
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "shippingbox")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                defaultIconPreview
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var defaultIconPreview: some View {
        switch context {
        case let .module(id):
            if let module = model.modules.first(where: { $0.id == id }),
               let iconURL = module.iconURL,
               let url = URL(string: iconURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "shippingbox")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        case let .platform(platformID):
            Image(RelayPlatform(rawValue: platformID)?.summaryIconAssetName ?? "SummaryIOSIcon")
                .resizable()
                .scaledToFit()
        }
    }

    private let iconGridColumns = [
        GridItem(.flexible(), spacing: 14, alignment: .center),
        GridItem(.flexible(), spacing: 14, alignment: .center),
        GridItem(.flexible(), spacing: 14, alignment: .center),
        GridItem(.flexible(), spacing: 14, alignment: .center),
        GridItem(.flexible(), spacing: 14, alignment: .center),
        GridItem(.flexible(), spacing: 14, alignment: .center),
        GridItem(.flexible(), spacing: 14, alignment: .center),
        GridItem(.flexible(), spacing: 14, alignment: .center)
    ]

    private var navigationTitle: String {
        if case .module = context { return "修改模块图标" }
        return "修改汇总图标"
    }

    private var supportsAppStoreSearch: Bool {
        if case .module = context { return true }
        return false
    }

    private var currentCustomIconURL: String? {
        switch context {
        case let .module(id):
            return model.modules.first(where: { $0.id == id })?.customIconURL
        case let .platform(platformID):
            return model.settings.platformSettings[platformID]?.customIconURL
        }
    }

    private var currentCustomIconSource: CustomIconSource {
        let storedSource: CustomIconSource
        switch context {
        case let .module(id):
            storedSource = model.modules.first(where: { $0.id == id })?.customIconSource ?? .manual
        case let .platform(platformID):
            storedSource = model.settings.platformSettings[platformID]?.customIconSource ?? .manual
        }
        if storedSource == .manual,
           let url = currentCustomIconURL,
           url.localizedCaseInsensitiveContains("mzstatic.com") {
            return .appStore
        }
        return storedSource
    }

    private var rankedSearchResults: [IconSearchResult] {
        let normalizedQuery = normalizedSearchText(query)
        return searchResults.enumerated()
            .sorted { lhs, rhs in
                let leftScore = searchRank(for: lhs.element, normalizedQuery: normalizedQuery)
                let rightScore = searchRank(for: rhs.element, normalizedQuery: normalizedQuery)
                if leftScore != rightScore { return leftScore < rightScore }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var isPresentingSaveError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }

    private func setSearchRegion(_ region: String) {
        model.settings.iconSearchRegion = region
        model.saveSettings()
        performSearch()
    }

    private func performSearch() {
        let q = AppModel.cleanSearchQuery(query)
        query = q
        guard !q.isEmpty else { return }
        isSearching = true
        searchResults = []
        Task {
            searchResults = await model.searchIcons(query: q, region: model.settings.iconSearchRegion)
            isSearching = false
        }
    }

    private func saveIcon(_ url: String?, source: CustomIconSource = .manual, dismissAfterSave: Bool = true) {
        errorMessage = nil
        Task {
            do {
                switch context {
                case let .module(id):
                    try await model.updateModuleCustomIcon(id: id, customIconURL: url, source: source)
                case let .platform(platformID):
                    if let platform = RelayPlatform(rawValue: platformID) {
                        try await model.updatePlatformCustomIcon(platform: platform, customIconURL: url, source: source)
                    }
                }
                selectedIconURL = url
                pendingIconURL = url
                pendingIconSource = source
                hasPendingIconSelection = false
                if dismissAfterSave {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var hasCustomIcon: Bool {
        currentCustomIconURL != nil
    }

    private func regionEmojiAndName(_ region: String) -> String {
        switch region {
        case "cn": "🇨🇳 中国"
        case "us": "🇺🇸 美国"
        case "jp": "🇯🇵 日本"
        case "hk": "🇭🇰 香港"
        case "tw": "🇹🇼 台湾"
        default: "🇨🇳 中国"
        }
    }

    private func searchRank(for result: IconSearchResult, normalizedQuery: String) -> Int {
        let normalizedName = normalizedSearchText(result.name)
        if normalizedName == normalizedQuery { return 0 }
        if normalizedName.hasPrefix(normalizedQuery) { return 1 }
        if normalizedName.contains(normalizedQuery) { return 2 }
        return 3
    }

    private func normalizedSearchText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private struct IconSearchResultCell: View {
        let result: IconSearchResult
        let isSelected: Bool

        var body: some View {
            ZStack {
                AsyncImage(url: URL(string: result.url)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .brightness(isSelected ? -0.32 : 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .frame(width: 54, height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}
