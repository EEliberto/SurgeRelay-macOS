import SwiftUI

struct IOSModuleDetailView: View {
    @Environment(ClientAppModel.self) private var model
    let module: RelayModule

    @State private var tab: IOSDetailTab = .info
    @State private var showingEditor = false
    @State private var showingIconEditor = false
    @State private var showingDeleteConfirm = false
    @State private var previewText = ""
    @State private var isLoadingPreview = false
    @State private var isEditingPreview = false
    @State private var previewError: String?
    @State private var arguments: [RemoteArgumentPayload] = []
    @State private var argumentHelp: String?

    var body: some View {
        Group {
            switch tab {
            case .info:
                infoForm
            case .preview:
                previewPane
            }
        }
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图", selection: $tab) {
                    ForEach(IOSDetailTab.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑模块") { showingEditor = true }
                    Button("修改图标") { showingIconEditor = true }
                    Button("删除模块", role: .destructive) { showingDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            IOSModuleEditorView(module: module)
        }
        .sheet(isPresented: $showingIconEditor) {
            IOSIconEditorView(module: module)
        }
        .confirmationDialog("删除模块？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await model.deleteModule(id: module.id) }
            }
        } message: {
            Text("此操作会从服务器移除该模块配置。")
        }
        .task(id: module.id) {
            await loadArguments()
            if tab == .preview {
                await loadPreview()
            }
        }
        .onChange(of: tab) { _, newValue in
            if newValue == .preview {
                Task { await loadPreview() }
            }
        }
    }

    private var infoForm: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    RemoteAsyncImage(urlString: module.customIconURL ?? module.iconURL)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(module.name).font(.headline)
                        Text(module.sourceFormatDisplayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("包含在总模块中", isOn: Binding(
                    get: { module.isEnabled },
                    set: { enabled in
                        Task { await model.setModuleEnabled(id: module.id, enabled: enabled) }
                    }
                ))
                Toggle("输出独立模块至 iCloud", isOn: Binding(
                    get: { module.exportsIndividualModuleToICloud },
                    set: { enabled in
                        Task { await model.setIndividualICloudExport(id: module.id, enabled: enabled) }
                    }
                ))
            }

            Section("来源") {
                LabeledContent("地址") {
                    Text(module.sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("输出文件", value: module.outputFileName)
                if let updated = module.lastUpdatedAt {
                    LabeledContent("最近更新", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
                if let error = module.lastError, !error.isEmpty {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }

            if !arguments.isEmpty {
                Section("参数") {
                    ForEach(arguments, id: \.key) { argument in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(argument.key).font(.subheadline.weight(.semibold))
                            TextField(
                                "默认：\(argument.defaultValue)",
                                text: Binding(
                                    get: { argument.value },
                                    set: { newValue in
                                        if let index = arguments.firstIndex(where: { $0.key == argument.key }) {
                                            arguments[index].value = newValue
                                        }
                                    }
                                )
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        }
                    }
                    if let argumentHelp, !argumentHelp.isEmpty {
                        Text(argumentHelp).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("保存参数") {
                        let values = Dictionary(uniqueKeysWithValues: arguments.map { ($0.key, $0.value) })
                        Task { await model.setModuleArguments(id: module.id, values: values) }
                    }
                    Button("恢复默认参数", role: .destructive) {
                        Task {
                            await model.resetModuleArguments(id: module.id)
                            await loadArguments()
                        }
                    }
                }
            }

            Section("订阅") {
                CopyableURLRow(title: "发布地址", url: model.publishedURL(for: module))
            }

            if module.hasOverrideConflict {
                Section("冲突") {
                    Text("上游内容与你的本地预览覆盖冲突。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("接受当前覆盖并清除冲突") {
                        Task { await model.acceptOverrideConflict(id: module.id) }
                    }
                }
            }
        }
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            if isLoadingPreview {
                ProgressView("正在载入预览…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let previewError {
                ContentUnavailableView("无法载入预览", systemImage: "exclamationmark.triangle", description: Text(previewError))
            } else {
                TextEditor(text: $previewText)
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(!isEditingPreview)
                    .padding(8)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if isEditingPreview {
                    Button("取消") {
                        isEditingPreview = false
                        Task { await loadPreview() }
                    }
                    Spacer()
                    Button("恢复上游") {
                        Task {
                            do {
                                previewText = try await model.restorePreviewContent(moduleID: module.id)
                                isEditingPreview = false
                            } catch {
                                previewError = error.localizedDescription
                            }
                        }
                    }
                    Button("保存") {
                        Task {
                            do {
                                try await model.savePreviewContent(moduleID: module.id, content: previewText)
                                isEditingPreview = false
                            } catch {
                                previewError = error.localizedDescription
                            }
                        }
                    }
                    .bold()
                } else {
                    Spacer()
                    Button("编辑") { isEditingPreview = true }
                        .disabled(previewText.isEmpty && previewError != nil)
                }
            }
        }
    }

    private func loadPreview() async {
        isLoadingPreview = true
        previewError = nil
        defer { isLoadingPreview = false }
        do {
            previewText = try await model.previewContent(moduleID: module.id)
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func loadArguments() async {
        do {
            let payload = try await model.moduleArguments(moduleID: module.id)
            arguments = payload.arguments
            argumentHelp = payload.help
        } catch {
            arguments = []
            argumentHelp = nil
        }
    }
}

struct IOSCombinedDetailView: View {
    @Environment(ClientAppModel.self) private var model
    let platform: RelayPlatform

    @State private var tab: IOSDetailTab = .info
    @State private var previewText = ""
    @State private var isLoadingPreview = false
    @State private var previewError: String?

    private var isEnabled: Bool {
        model.settings.platformSettings[platform.rawValue]?.isEnabled ?? false
    }

    var body: some View {
        Group {
            switch tab {
            case .info:
                Form {
                    Section {
                        Toggle("启用 \(platform.summaryDisplayName) 汇总模块", isOn: Binding(
                            get: { isEnabled },
                            set: { newValue in
                                var entry = model.settings.platformSettings[platform.rawValue] ?? PlatformSettings()
                                entry.isEnabled = newValue
                                model.settings.platformSettings[platform.rawValue] = entry
                                Task { await model.pushGeneralSettings() }
                            }
                        ))
                    }

                    Section("模块开关") {
                        ForEach(model.modules) { module in
                            Toggle(module.name, isOn: Binding(
                                get: { model.isModuleEnabled(module.id, on: platform) },
                                set: { enabled in
                                    Task {
                                        await model.setPlatformModuleEnabled(
                                            platform: platform,
                                            moduleID: module.id,
                                            enabled: enabled
                                        )
                                    }
                                }
                            ))
                            .disabled(!module.isEnabled)
                        }
                        if !model.modules.isEmpty {
                            Button("全部启用") {
                                Task { await model.setAllPlatformModulesEnabled(platform: platform, enabled: true) }
                            }
                            Button("全部关闭", role: .destructive) {
                                Task { await model.setAllPlatformModulesEnabled(platform: platform, enabled: false) }
                            }
                        }
                    }

                    Section("订阅") {
                        CopyableURLRow(title: "订阅地址", url: model.subscriptionURL(for: platform))
                    }
                }
            case .preview:
                VStack {
                    if isLoadingPreview {
                        ProgressView("正在载入预览…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let previewError {
                        ContentUnavailableView("无法载入预览", systemImage: "exclamationmark.triangle", description: Text(previewError))
                    } else {
                        ScrollView {
                            Text(previewText)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .textSelection(.enabled)
                        }
                    }
                }
                .task(id: platform) { await loadPreview() }
            }
        }
        .navigationTitle(platform.summaryDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图", selection: $tab) {
                    ForEach(IOSDetailTab.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
        .onChange(of: tab) { _, newValue in
            if newValue == .preview {
                Task { await loadPreview() }
            }
        }
    }

    private func loadPreview() async {
        isLoadingPreview = true
        previewError = nil
        defer { isLoadingPreview = false }
        do {
            previewText = try await model.combinedPreviewContent(platform: platform)
        } catch {
            previewError = error.localizedDescription
        }
    }
}
