import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isCheckingUpdate = false
    @State private var isTesting = false
    @State private var connectionResult: ConnectionResult?
    @State private var showsWebQRCode = false
    @State private var pendingStorageMode: StorageMode?

    private enum ConnectionResult {
        case success(String)
        case failure(String)
        var message: String {
            switch self {
            case let .success(text), let .failure(text): return text
            }
        }
        var isError: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("通用") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("iCloud 云盘 · Surge")
                    Text(model.surgeDirectoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Text("配置由 App 自动保存在 Surge Relay 子文件夹中")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("自动化") {
                Picker("刷新间隔", selection: Binding(
                    get: { model.settings.refreshIntervalMinutes },
                    set: {
                        model.settings.refreshIntervalMinutes = $0
                        model.saveSettings()
                        model.restartScheduler()
                    }
                )) {
                    Text("手动").tag(0)
                    Text("每 15 分钟").tag(15)
                    Text("每小时").tag(60)
                    Text("每 6 小时").tag(360)
                    Text("每 12 小时").tag(720)
                }
                Toggle("登录时启动 Surge Relay", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("自动发布", isOn: Binding(
                    get: { model.settings.automaticallyPublish },
                    set: { model.settings.automaticallyPublish = $0; model.saveSettings() }
                ))
            }

            Section("Web 管理") {
                Toggle("启用 Web 管理", isOn: Binding(
                    get: { model.settings.webServerEnabled },
                    set: {
                        model.settings.webServerEnabled = $0
                        model.applyWebServerSettings()
                    }
                ))
                TextField("端口", value: Binding(
                    get: { model.settings.webServerPort },
                    set: { model.settings.webServerPort = $0 }
                ), format: .number.grouping(.never))
                .onChange(of: model.settings.webServerPort) { _, _ in
                    if model.settings.webServerEnabled {
                        model.applyWebServerSettings()
                    }
                }
                if let url = model.webManagementURL {
                    LabeledContent("Bonjour 地址") {
                        Text(url.absoluteString)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("打开", systemImage: "safari") { NSWorkspace.shared.open(url) }
                        Button("二维码", systemImage: "qrcode") { showsWebQRCode = true }
                    }
                }
            }

            Section("Script-Hub") {
                LabeledContent("版本") {
                    Text(model.upstreamState.revision.map { String($0.prefix(7)) } ?? "—")
                        .monospaced()
                }
                LabeledContent("上次检查") {
                    Text(model.upstreamState.lastCheckedAt?.formatted(Date.FormatStyle(
                        date: .abbreviated,
                        time: .shortened,
                        locale: Locale(identifier: "zh_CN")
                    )) ?? "尚未检查")
                        .foregroundStyle(.secondary)
                }
                TextField("上游模块", text: stringBinding(\.scriptHubModuleURL))
                Toggle("自动更新", isOn: Binding(
                    get: { model.settings.automaticallyUpdateScriptHub },
                    set: { model.settings.automaticallyUpdateScriptHub = $0; model.saveSettings() }
                ))
                HStack(spacing: 8) {
                    Button("检查更新", systemImage: "arrow.clockwise") {
                        Task {
                            isCheckingUpdate = true
                            await model.refreshScriptHub(showProgress: false)
                            isCheckingUpdate = false
                        }
                    }
                    .disabled(isCheckingUpdate)
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                        Text("正在检查…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = model.upstreamState.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section("存储位置") {
                Picker("同步方式", selection: storageModeBinding) {
                    Text("iCloud 云盘").tag(StorageMode.local)
                    Text("GitHub 私有仓库").tag(StorageMode.gitHub)
                }
                .pickerStyle(.segmented)

                if effectiveStorageMode == .local {
                    LabeledContent("汇总模块") {
                        Text(model.combinedLocalFileURL?.path ?? "等待生成")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    if pendingStorageMode == .local, model.settings.storageMode == .gitHub {
                        Text("当前仍使用 GitHub 存储。点击确认后才会切换到 iCloud，并在 Surge 文件夹生成汇总模块。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("确认切换到 iCloud") {
                                confirmStorageSwitch(to: .local)
                            }
                            .disabled(isTesting)
                            if isTesting {
                                ProgressView().controlSize(.small)
                            }
                        }
                        if let result = connectionResult {
                            Label(result.message, systemImage: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(result.isError ? .red : .green)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if effectiveStorageMode == .gitHub {
            Section("GitHub") {
                TextField("所有者", text: githubBinding(\.owner))
                TextField("仓库", text: githubBinding(\.repository))
                TextField("分支", text: githubBinding(\.branch))
                TextField("目录", text: githubBinding(\.directory))
                LabeledContent("仓库类型") {
                    switch model.settings.github.repositoryIsPrivate {
                    case .some(true): Label("私有", systemImage: "lock.fill")
                    case .some(false): Label("公开", systemImage: "globe")
                    case nil: Text("未检测").foregroundStyle(.secondary)
                    }
                }
            }

            Section("访问凭据") {
                SecureField("GitHub Token", text: $model.githubToken)
                HStack(spacing: 8) {
                    Button("保存") { model.saveGitHubToken() }
                    Button("测试连接") {
                        Task {
                            isTesting = true
                            connectionResult = nil
                            model.presentedError = nil
                            await model.testGitHub(showProgress: false)
                            isTesting = false
                            if let error = model.presentedError {
                                connectionResult = .failure(error)
                                model.presentedError = nil
                            } else {
                                connectionResult = .success(model.statusMessage)
                            }
                        }
                    }
                    .disabled(model.githubToken.isEmpty || !model.settings.github.isConfigured || isTesting)
                    if model.settings.storageMode != .gitHub {
                        Button("验证并切换") {
                            confirmStorageSwitch(to: .gitHub)
                        }
                        .disabled(model.githubToken.isEmpty || !model.settings.github.isConfigured || isTesting)
                    }
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                }
                if let result = connectionResult {
                    Label(result.message, systemImage: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(result.isError ? .red : .green)
                        .textSelection(.enabled)
                }
            }

            if effectiveStorageMode == .gitHub {
                Section("Cloudflare Worker") {
                    TextField("公共地址", text: githubBinding(\.publicBaseURL))
                    Text("GitHub 私有仓库必须通过 Cloudflare Worker 提供设备可访问的稳定订阅地址。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            }

            Section("诊断") {
                DisclosureGroup("最近更新") {
                    if model.updateHistory.isEmpty {
                        Text("暂无记录").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.updateHistory.prefix(20)) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.moduleName)
                                    Text(entry.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(entry.outcome.title)
                                        .font(.caption)
                                    Text(entry.date.formatted(Date.FormatStyle(
                                        date: .omitted,
                                        time: .shortened,
                                        locale: Locale(identifier: "zh_CN")
                                    )))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button("导出诊断…", systemImage: "square.and.arrow.up") { exportDiagnostics() }
                    Button("清除历史", role: .destructive) { model.clearUpdateHistory() }
                        .disabled(model.updateHistory.isEmpty)
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .sheet(isPresented: $showsWebQRCode) {
            if let url = model.webManagementURL {
                VStack(spacing: 18) {
                    Text("Web 管理").font(.title2.bold())
                    if let image = qrCodeImage(for: url.absoluteString) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 240, height: 240)
                    }
                    Text(url.absoluteString)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Button("完成") { showsWebQRCode = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(28)
                .frame(minWidth: 330)
            }
        }
    }

    private var storageModeBinding: Binding<StorageMode> {
        Binding(
            get: { effectiveStorageMode },
            set: { mode in
                connectionResult = nil
                if mode == model.settings.storageMode {
                    pendingStorageMode = nil
                } else {
                    pendingStorageMode = mode
                }
            }
        )
    }

    private var effectiveStorageMode: StorageMode {
        pendingStorageMode ?? model.settings.storageMode
    }

    private func confirmStorageSwitch(to mode: StorageMode) {
        Task {
            isTesting = true
            connectionResult = nil
            model.presentedError = nil
            let switched = await model.setStorageMode(mode)
            isTesting = false
            if switched {
                pendingStorageMode = nil
                connectionResult = .success(
                    mode == .gitHub
                        ? "GitHub 与 Cloudflare 已验证，本地汇总文件已安全移除"
                        : "已切换到 iCloud，汇总模块已在 Surge 文件夹中生成"
                )
            } else {
                connectionResult = .failure(model.presentedError ?? "切换失败")
                model.presentedError = nil
            }
        }
    }

    private func githubBinding(_ keyPath: WritableKeyPath<GitHubSettings, String>) -> Binding<String> {
        Binding(
            get: { model.settings.github[keyPath: keyPath] },
            set: {
                model.settings.github[keyPath: keyPath] = $0
                model.saveSettings()
            }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                model.settings[keyPath: keyPath] = $0
                model.saveSettings()
            }
        )
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Surge-Relay-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.diagnosticsData().write(to: url, options: .atomic)
        } catch {
            model.presentedError = "无法导出诊断：\(error.localizedDescription)"
        }
    }

    private func qrCodeImage(for value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
