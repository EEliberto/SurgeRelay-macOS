import SwiftUI

struct IOSSettingsView: View {
    @Environment(ClientAppModel.self) private var model
    @State private var ponteDraft = ""
    @State private var isTestingConnection = false
    @State private var connectionMessage: String?
    @State private var isSaving = false
    @State private var syncMessage: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                StatusBanner()
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Ponte 地址", text: $ponteDraft, prompt: Text("johnsmac.sgponte"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await testAndSaveConnection() }
                } label: {
                    HStack {
                        if isTestingConnection { ProgressView() }
                        Text("测试并保存连接")
                    }
                }
                .disabled(ponteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingConnection)
                if let connectionMessage {
                    Text(connectionMessage)
                        .font(.footnote)
                        .foregroundStyle(connectionMessage.contains("成功") ? .green : .red)
                }
                Button("断开连接", role: .destructive) {
                    model.disconnect()
                }
            } header: {
                Text("连接")
            } footer: {
                Text("设备角色固定为客户端。Ponte 地址仅保存在本机，不会同步到其他设备。")
            }

            Section {
                Stepper(
                    "自动刷新：\(model.settings.refreshIntervalMinutes) 分钟",
                    value: $model.settings.refreshIntervalMinutes,
                    in: 0...1440,
                    step: 15
                )
                Toggle("自动同步发布", isOn: $model.settings.automaticallyPublish)
                Picker("图标搜索地区", selection: $model.settings.iconSearchRegion) {
                    Text("中国大陆").tag("cn")
                    Text("美国").tag("us")
                    Text("日本").tag("jp")
                    Text("香港").tag("hk")
                    Text("台湾").tag("tw")
                }
                Button("保存通用设置") {
                    Task {
                        isSaving = true
                        await model.pushGeneralSettings()
                        isSaving = false
                    }
                }
            } header: {
                Text("服务器 · 通用")
            } footer: {
                Text("这些设置会写入 Mac 服务器，不会在本机执行转换或发布。")
            }

            Section("服务器 · 平台") {
                ForEach(RelayPlatform.allCases) { platform in
                    Toggle(platform.summaryDisplayName, isOn: Binding(
                        get: { model.settings.platformSettings[platform.rawValue]?.isEnabled ?? false },
                        set: { newValue in
                            var entry = model.settings.platformSettings[platform.rawValue] ?? PlatformSettings()
                            entry.isEnabled = newValue
                            model.settings.platformSettings[platform.rawValue] = entry
                        }
                    ))
                }
                Button("保存平台设置") {
                    Task { await model.pushGeneralSettings() }
                }
            }

            Section("服务器 · Script Hub") {
                TextField("模块地址", text: $model.settings.scriptHubModuleURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Toggle("自动更新 Script Hub", isOn: $model.settings.automaticallyUpdateScriptHub)
                if let revision = model.upstreamState.revision {
                    LabeledContent("版本", value: revision)
                }
                if let error = model.upstreamState.lastError, !error.isEmpty {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button("保存 Script Hub 设置") {
                    Task { await model.pushScriptHubSettings() }
                }
                Button("立即刷新 Script Hub") {
                    Task { await model.refreshScriptHub() }
                }
            }

            Section {
                Picker("同步方式", selection: $model.settings.storageMode) {
                    Text("iCloud 云盘").tag(StorageMode.local)
                    Text("GitHub").tag(StorageMode.gitHub)
                }
                if model.settings.storageMode == .gitHub {
                    TextField("所有者", text: $model.settings.github.owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("仓库", text: $model.settings.github.repository)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Cloudflare 公共地址", text: $model.settings.github.publicBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField(
                        model.githubTokenConfigured ? "已配置 Token（留空则保持不变）" : "GitHub Token",
                        text: $model.githubTokenDraft
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                Button("测试同步设置") {
                    Task {
                        do {
                            try await model.testSyncSettings(includeToken: !model.githubTokenDraft.isEmpty)
                            syncMessage = "测试成功"
                        } catch {
                            syncMessage = error.localizedDescription
                        }
                    }
                }
                Button("保存同步设置") {
                    Task {
                        await model.pushSyncSettings(includeToken: !model.githubTokenDraft.isEmpty)
                        if model.presentedError == nil {
                            syncMessage = "已保存"
                            model.githubTokenDraft = ""
                        }
                    }
                }
                if let syncMessage {
                    Text(syncMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("服务器 · 同步")
            } footer: {
                Text(model.settings.storageMode == .local
                     ? "iCloud 路径由 Mac 服务器管理；客户端只负责下发配置。"
                     : "GitHub Token 只会发送到你的 Mac 服务器，不会保存在此 iPhone/iPad。")
            }

            Section("诊断") {
                LabeledContent("服务器版本", value: model.appVersion.isEmpty ? "—" : model.appVersion)
                LabeledContent("模块数量", value: "\(model.modules.count)")
                if model.updateHistory.isEmpty {
                    Text("暂无更新记录").foregroundStyle(.secondary)
                } else {
                    ForEach(model.updateHistory.prefix(20)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.moduleName).font(.subheadline.weight(.semibold))
                            Text("\(entry.outcome.title) · \(entry.message)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("清空诊断记录", role: .destructive) {
                    Task { await model.clearDiagnostics() }
                }
                Button("立即更新全部") {
                    Task { await model.updateAll() }
                }
            }

            Section("关于") {
                LabeledContent("客户端版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Link(destination: URL(string: "https://github.com/EEliberto/SurgeRelay-macOS")!) {
                    Label("Surge Relay on GitHub", systemImage: "link")
                }
            }
        }
        .navigationTitle("设置")
        .onAppear {
            ponteDraft = model.ponteServerAddress
        }
    }

    private func testAndSaveConnection() async {
        connectionMessage = nil
        isTestingConnection = true
        defer { isTestingConnection = false }
        do {
            try await model.updatePonteAddress(ponteDraft)
            connectionMessage = "连接成功，已保存"
        } catch {
            connectionMessage = error.localizedDescription
        }
    }
}
