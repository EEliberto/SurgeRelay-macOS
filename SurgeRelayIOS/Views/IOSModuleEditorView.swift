import SwiftUI

struct IOSModuleEditorView: View {
    @Environment(ClientAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let module: RelayModule?
    @State private var draft: ModuleDraft
    @State private var localError: String?
    @State private var isAdvancedExpanded: Bool
    @State private var isSaving = false

    private var isNativeSurgeModule: Bool {
        guard let url = URL(string: draft.sourceURL), !draft.sourceURL.isEmpty else {
            return draft.sourceFormat == .surge
        }
        return draft.sourceFormat.isNativeSurgeModule(for: url)
    }

    init(module: RelayModule?) {
        self.module = module
        _draft = State(initialValue: module.map(ModuleDraft.init(module:)) ?? ModuleDraft())
        _isAdvancedExpanded = State(initialValue: module.map { $0.scriptHubOptions != ScriptHubOptions() } ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("显示名称", text: $draft.name, prompt: Text("例如：YouTube 去广告"))
                    Toggle("包含在总模块中", isOn: $draft.isEnabled)
                }

                Section("来源") {
                    TextField("原始地址", text: $draft.sourceURL, prompt: Text("https://example.com/module.plugin"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Picker("来源格式", selection: $draft.sourceFormat) {
                        ForEach(ModuleSourceFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                }

                Section {
                    DisclosureGroup("高级", isExpanded: $isAdvancedExpanded) {
                        if isNativeSurgeModule {
                            Label(
                                "该地址是 Surge 模块，将直接参与合并，不经过 Script‑Hub；高级转换选项不会应用。",
                                systemImage: "arrow.triangle.branch"
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        } else {
                            ScriptHubAdvancedOptionsView(options: $draft.scriptHubOptions)
                        }
                    }
                }

                if let localError {
                    Section {
                        Text(localError).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(module == nil ? "添加模块" : "编辑模块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        if let message = draft.validationMessage {
            localError = message
            return
        }
        isSaving = true
        defer { isSaving = false }
        if let module {
            await model.updateModule(id: module.id, draft: draft)
        } else {
            await model.addModule(draft)
        }
        if model.presentedError == nil {
            dismiss()
        } else {
            localError = model.presentedError
        }
    }
}

struct IOSIconEditorView: View {
    @Environment(ClientAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let module: RelayModule
    @State private var customURL = ""
    @State private var searchQuery = ""
    @State private var results: [IconSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var pendingURL: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("预览") {
                    HStack {
                        Spacer()
                        RemoteAsyncImage(urlString: pendingURL ?? module.customIconURL ?? module.iconURL)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Spacer()
                    }
                }

                Section("自定义链接") {
                    TextField("https://example.com/icon.png", text: $customURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("载入") {
                        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        pendingURL = trimmed
                    }
                    if module.customIconURL != nil || pendingURL != nil {
                        Button("恢复默认图标", role: .destructive) {
                            pendingURL = nil
                            customURL = ""
                            Task {
                                await model.updateModuleCustomIcon(id: module.id, url: nil)
                                dismiss()
                            }
                        }
                    }
                }

                Section("App Store 搜索") {
                    HStack {
                        TextField("输入 App 名称", text: $searchQuery)
                        Button("搜索") {
                            Task { await search() }
                        }
                        .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }
                    if isSearching {
                        ProgressView()
                    }
                    ForEach(results, id: \.url) { result in
                        Button {
                            pendingURL = result.url
                            customURL = result.url
                        } label: {
                            HStack {
                                RemoteAsyncImage(urlString: result.url)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(result.name)
                                Spacer()
                                if pendingURL == result.url {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("修改图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Task {
                            await model.updateModuleCustomIcon(id: module.id, url: pendingURL)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            customURL = module.customIconURL ?? ""
            pendingURL = module.customIconURL
        }
    }

    private func search() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await model.searchIcons(
                query: searchQuery,
                region: model.settings.iconSearchRegion
            )
            if results.isEmpty {
                errorMessage = "未找到相关图标"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
