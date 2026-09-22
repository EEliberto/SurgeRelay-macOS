import SwiftUI

struct IOSModulesSplitView: View {
    @Environment(ClientAppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            IOSModulesListView(showsNavigationLinks: false)
        } detail: {
            NavigationStack {
                IOSSelectionDetailView(selectionID: model.selectedModuleID)
            }
        }
    }
}

struct IOSModulesListView: View {
    @Environment(ClientAppModel.self) private var model
    var showsNavigationLinks = true
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var editingModule: RelayModule?

    private var filteredModules: [RelayModule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.modules }
        return model.modules.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.sourceURL.localizedCaseInsensitiveContains(query)
                || $0.outputFileName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if showsNavigationLinks {
                List {
                    Section("汇总模块") {
                        ForEach(RelayPlatform.allCases) { platform in
                            let enabled = model.settings.platformSettings[platform.rawValue]?.isEnabled ?? false
                            NavigationLink(value: platform.selectionID) {
                                platformRow(platform, enabled: enabled)
                            }
                        }
                    }
                    Section("来源模块") {
                        ForEach(filteredModules) { module in
                            NavigationLink(value: module.id) {
                                moduleRow(module)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await model.deleteModule(id: module.id) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: moveModules)
                    }
                }
            } else {
                List(selection: Binding(
                    get: { model.selectedModuleID },
                    set: { model.selectedModuleID = $0 }
                )) {
                    Section("汇总模块") {
                        ForEach(RelayPlatform.allCases) { platform in
                            let enabled = model.settings.platformSettings[platform.rawValue]?.isEnabled ?? false
                            platformRow(platform, enabled: enabled)
                                .tag(platform.selectionID)
                        }
                    }
                    Section("来源模块") {
                        ForEach(filteredModules) { module in
                            moduleRow(module)
                                .tag(module.id)
                        }
                        .onMove(perform: moveModules)
                    }
                }
            }
        }
        .navigationTitle("模块")
        .searchable(text: $searchText, prompt: "搜索模块")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingModule = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.updateAll() }
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .disabled(model.isWorking)
            }
        }
        .safeAreaBar(edge: .bottom) {
            StatusBanner()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .navigationDestination(for: UUID.self) { id in
            IOSSelectionDetailView(selectionID: id)
        }
        .sheet(isPresented: $showingEditor) {
            IOSModuleEditorView(module: editingModule)
        }
        .refreshable {
            await model.refreshRemoteState()
        }
    }

    private func moveModules(from source: IndexSet, to destination: Int) {
        guard searchText.isEmpty else { return }
        var ids = model.modules.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        Task { await model.reorderModules(ids: ids) }
    }

    private func platformRow(_ platform: RelayPlatform, enabled: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = model.platformIconURLs[platform] {
                    RemoteAsyncImage(urlString: icon, placeholderSystemImage: "square.stack.3d.up.fill")
                } else {
                    BundleImage.image(platform.summaryIconAssetName, systemFallback: "square.stack.3d.up.fill")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(platform.summaryDisplayName)
                    .font(.body.weight(.semibold))
                Text(enabled ? "已启用" : "未启用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(.rect)
    }

    private func moduleRow(_ module: RelayModule) -> some View {
        HStack(spacing: 12) {
            RemoteAsyncImage(urlString: module.customIconURL ?? module.iconURL)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(module.sourceFormatDisplayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if module.hasOverrideConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Circle()
                .fill(module.isEnabled ? Color.green.opacity(0.85) : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
        }
        .contentShape(.rect)
    }
}

struct IOSSelectionDetailView: View {
    @Environment(ClientAppModel.self) private var model
    let selectionID: UUID?

    var body: some View {
        Group {
            if let selectionID, let platform = RelayPlatform.from(selectionID: selectionID) {
                IOSCombinedDetailView(platform: platform)
            } else if let selectionID, let module = model.modules.first(where: { $0.id == selectionID }) {
                IOSModuleDetailView(module: module)
            } else {
                ContentUnavailableView(
                    "选择一个模块",
                    systemImage: "shippingbox",
                    description: Text("在左侧列表中选择汇总模块或来源模块。")
                )
            }
        }
    }
}
