import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
    }
}

private struct SettingsNavigationButtons: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            navigationButton(
                systemImage: "chevron.left",
                isEnabled: canGoBack,
                action: goBack
            )

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.22))
                .frame(width: 1, height: 17)

            navigationButton(
                systemImage: "chevron.right",
                isEnabled: canGoForward,
                action: goForward
            )
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

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isCheckingUpdate = false
    @State private var isTesting = false
    @State private var connectionResult: ConnectionResult?
    @State private var showsWebQRCode = false
    @State private var pendingStorageMode: StorageMode?
    @State private var selectedPane: SettingsPane = .general
    @State private var githubRepositoryInput = ""
    @State private var githubCloudflareInput = ""
    @State private var originalGitHubRepositoryInput = ""
    @State private var originalGitHubCloudflareInput = ""
    @State private var originalGitHubToken = ""
    @State private var didLoadGitHubDraft = false
    @State private var backStack: [SettingsPane] = []
    @State private var forwardStack: [SettingsPane] = []
    @State private var isHistoryNavigation = false

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

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case general
        case web
        case scriptHub
        case synchronization
        case diagnostics
        case about

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "通用"
            case .web: "Web 管理"
            case .scriptHub: "Script Hub"
            case .synchronization: "同步"
            case .diagnostics: "诊断"
            case .about: "关于"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .web: "network"
            case .scriptHub: "arrow.triangle.branch"
            case .synchronization: "arrow.trianglehead.2.clockwise.rotate.90"
            case .diagnostics: "stethoscope"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 225)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailView(for: selectedPane)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 12) {
                            SettingsNavigationButtons(
                                canGoBack: !backStack.isEmpty,
                                canGoForward: !forwardStack.isEmpty,
                                goBack: goBack,
                                goForward: goForward
                            )

                            Text(selectedPane.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .title)
        .background(SettingsWindowConfigurator())
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            resetNavigation()
            if SurgeRelaySettingsNavigation.consumeAboutRequest() {
                navigate(to: .about)
            }
            loadGitHubDraftIfNeeded()
        }
        .onDisappear(perform: resetNavigation)
        .onReceive(NotificationCenter.default.publisher(for: .showSurgeRelayAbout)) { _ in
            guard SurgeRelaySettingsNavigation.consumeAboutRequest() else { return }
            navigate(to: .about)
        }
        .onChange(of: selectedPane) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if isHistoryNavigation {
                isHistoryNavigation = false
                return
            }
            backStack.append(oldValue)
            forwardStack.removeAll()
        }
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

    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: generalSettings
        case .web: webSettings
        case .scriptHub: scriptHubSettings
        case .synchronization: synchronizationSettings
        case .diagnostics: diagnosticsSettings
        case .about: aboutSettings
        }
    }

    private func resetNavigation() {
        if selectedPane != .general {
            isHistoryNavigation = true
            selectedPane = .general
        }
        backStack.removeAll()
        forwardStack.removeAll()
    }

    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(selectedPane)
        isHistoryNavigation = true
        selectedPane = previous
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(selectedPane)
        isHistoryNavigation = true
        selectedPane = next
    }

    private func navigate(to pane: SettingsPane) {
        guard selectedPane != pane else { return }
        backStack.append(selectedPane)
        forwardStack.removeAll()
        isHistoryNavigation = true
        selectedPane = pane
    }

    private var generalSettings: some View {
        Form {
            Section("配置目录") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置与同步目录")
                    HStack(spacing: 10) {
                        Text("iCloud/Surge/Surge Relay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            model.openConfigurationDirectory()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 30, height: 30)
                                .contentShape(Circle())
                                .glassEffect(.regular.interactive(), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("在 Finder 中显示")
                    }
                    Text("Surge Relay 的配置与同步状态保存在 iCloud 云盘中。")
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
                Toggle("自动同步", isOn: Binding(
                    get: { model.settings.automaticallyPublish },
                    set: { model.settings.automaticallyPublish = $0; model.saveSettings() }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private var webSettings: some View {
        Form {
            Section("本地管理") {
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
        }
        .formStyle(.grouped)
    }

    private var scriptHubSettings: some View {
        Form {
            Section("上游引擎") {
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
        }
        .formStyle(.grouped)
    }

    private var synchronizationSettings: some View {
        VStack(spacing: 0) {
            Form {
                Section("同步方式") {
                    Picker("同步方式", selection: storageModeBinding) {
                        Text("iCloud 云盘").tag(StorageMode.local)
                        Text("GitHub 私有仓库").tag(StorageMode.gitHub)
                    }
                    .pickerStyle(.segmented)
                }

                if effectiveStorageMode == .local {
                    Section("iCloud 云盘") {
                        storageProviderSummary(
                            assetName: "iCloudIcon",
                            title: "通过 iCloud 保持 Surge Relay 同步",
                            detail: "汇总模块保存在 iCloud 云盘的 Surge 文件夹中，配置与同步状态由 Surge Relay 管理。"
                        )

                        if showsStableICloudStatus {
                            Label(
                                "当前通过 iCloud 云盘同步，汇总模块已在 Surge 文件夹中生成，请在 Surge 中勾选 Surge Relay 模块。",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                    }
                } else {
                    Section("GitHub 私有仓库") {
                        storageProviderSummary(
                            assetName: "GitHubIcon",
                            title: "通过私有仓库同步",
                            detail: "Surge Relay 会验证仓库权限，并通过 Cloudflare 提供设备可访问的稳定订阅。"
                        )

                        TextField("仓库地址", text: $githubRepositoryInput)
                            .onChange(of: githubRepositoryInput) { _, _ in connectionResult = nil }
                        SecureField("GitHub Token", text: Binding(
                            get: { model.githubToken },
                            set: { model.githubToken = $0 }
                        ))
                        .onChange(of: model.githubToken) { _, _ in connectionResult = nil }
                    }

                    Section("Cloudflare") {
                        TextField("公共地址", text: $githubCloudflareInput)
                            .onChange(of: githubCloudflareInput) { _, _ in connectionResult = nil }
                        Text("用于生成可在 Surge 中长期使用的稳定订阅地址。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if showsVerifiedGitHubStatus {
                            Label(
                                "GitHub 与 Cloudflare 已验证，汇总模块将通过 GitHub 私有仓库同步并通过 Cloudflare Worker 分发。",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if storageActionTitle != nil || connectionResult != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if let result = connectionResult {
                        Label(
                            result.message,
                            systemImage: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(result.isError ? .red : .green)
                        .textSelection(.enabled)
                    }

                    if let storageActionTitle {
                        HStack(spacing: 8) {
                            Spacer()
                            if isTesting {
                                ProgressView().controlSize(.small)
                            }
                            Button(storageActionTitle) { performStorageAction() }
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.capsule)
                                .controlSize(.large)
                                .disabled(storageActionDisabled)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    private func storageProviderSummary(
        assetName: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var diagnosticsSettings: some View {
        Form {
            Section {
                if model.updateHistory.isEmpty {
                    ContentUnavailableView(
                        "暂无更新记录",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("完成一次同步后，结果会显示在这里。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(model.updateHistory.prefix(20)) { entry in
                        diagnosticRow(entry)
                    }
                }
            } header: {
                Text(model.updateHistory.isEmpty ? "更新记录" : "最近 \(min(model.updateHistory.count, 20)) 条更新")
            }

            Section {
                HStack {
                    Button("导出诊断…", systemImage: "square.and.arrow.up") { exportDiagnostics() }
                    Button("清除历史", role: .destructive) { model.clearUpdateHistory() }
                        .disabled(model.updateHistory.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutSettings: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 76, height: 76)

                    VStack(spacing: 3) {
                        Text("Surge Relay")
                            .font(.title2.weight(.semibold))
                        Text("版本 \(appVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("项目") {
                aboutLink(
                    title: "Surge Relay",
                    detail: "EEliberto/SurgeRelay-macOS",
                    url: "https://github.com/EEliberto/SurgeRelay-macOS",
                    image: .asset("GitHubIcon")
                )

                aboutLink(
                    title: "Script Hub",
                    detail: "github.com/Script-Hub-Org",
                    url: "https://github.com/Script-Hub-Org",
                    image: .asset("ScriptHubIcon")
                )

                aboutLink(
                    title: "Surge",
                    detail: "nssurge.com",
                    url: "https://nssurge.com",
                    image: .asset("SurgeIcon")
                )
            }
        }
        .formStyle(.grouped)
    }

    private enum AboutLinkImage {
        case asset(String)
    }

    private func aboutLink(
        title: String,
        detail: String,
        url: String,
        image: AboutLinkImage
    ) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                switch image {
                case let .asset(name):
                    Image(name)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFill()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func diagnosticRow(_ entry: UpdateHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.moduleName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(entry.outcome.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(diagnosticColor(for: entry.outcome))
                Text(entry.date.formatted(Date.FormatStyle(
                    date: .omitted,
                    time: .shortened,
                    locale: Locale(identifier: "zh_CN")
                )))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var formattedGitHubRepository: String {
        let owner = model.settings.github.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = model.settings.github.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repository.isEmpty else { return "" }
        return "https://github.com/\(owner)/\(repository)"
    }

    private var hasGitHubConfigurationChanges: Bool {
        githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines) != originalGitHubRepositoryInput ||
            githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines) != originalGitHubCloudflareInput ||
            model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines) != originalGitHubToken
    }

    private var showsVerifiedGitHubStatus: Bool {
        model.settings.storageMode == .gitHub &&
            pendingStorageMode == nil &&
            !hasGitHubConfigurationChanges &&
            model.settings.github.repositoryIsPrivate == true &&
            model.settings.github.hasValidCloudflarePublicBaseURL
    }

    private var showsStableICloudStatus: Bool {
        model.settings.storageMode == .local && pendingStorageMode == nil
    }

    private var storageActionTitle: String? {
        if let pendingStorageMode {
            return pendingStorageMode == .gitHub
                ? "验证并切换到 GitHub"
                : "切换到 iCloud 云盘"
        }
        guard model.settings.storageMode == .gitHub else { return nil }
        return hasGitHubConfigurationChanges || model.settings.github.repositoryIsPrivate != true
            ? "验证并保存配置"
            : nil
    }

    private func loadGitHubDraftIfNeeded() {
        guard !didLoadGitHubDraft else { return }
        githubRepositoryInput = formattedGitHubRepository
        githubCloudflareInput = model.settings.github.publicBaseURL
        originalGitHubRepositoryInput = githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubCloudflareInput = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubToken = model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        didLoadGitHubDraft = true
    }

    private func markGitHubDraftAsSaved() {
        originalGitHubRepositoryInput = githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubCloudflareInput = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubToken = model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var storageActionDisabled: Bool {
        if isTesting { return true }
        let targetMode = pendingStorageMode ?? model.settings.storageMode
        guard targetMode == .gitHub else { return false }
        return parsedGitHubRepository == nil ||
            model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !hasValidCloudflareInput
    }

    private var hasValidCloudflareInput: Bool {
        let value = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return false
        }
        return true
    }

    private var parsedGitHubRepository: (owner: String, repository: String)? {
        let value = githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let path: String
        if let components = URLComponents(string: value),
           let host = components.host?.lowercased(),
           host == "github.com" || host == "www.github.com" {
            path = components.path
        } else {
            path = value
        }

        let parts = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count == 2 else { return nil }
        let owner = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = parts[1]
            .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repository.isEmpty else { return nil }
        return (owner, repository)
    }

    private func applyGitHubInputs() -> Bool {
        guard let repository = parsedGitHubRepository else {
            connectionResult = .failure("请输入有效的 GitHub 仓库地址，例如 https://github.com/owner/repository。")
            return false
        }
        guard hasValidCloudflareInput else {
            connectionResult = .failure("请输入有效的 Cloudflare 公共地址。")
            return false
        }
        model.settings.github.owner = repository.owner
        model.settings.github.repository = repository.repository
        if model.settings.github.branch.isEmpty { model.settings.github.branch = "main" }
        if model.settings.github.directory.isEmpty { model.settings.github.directory = "modules" }
        model.settings.github.publicBaseURL = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveSettings()
        return true
    }

    private func performStorageAction() {
        let targetMode = pendingStorageMode ?? model.settings.storageMode
        if targetMode == .gitHub, !applyGitHubInputs() { return }

        if let pendingStorageMode {
            confirmStorageSwitch(to: pendingStorageMode)
        } else {
            testGitHubConnection()
        }
    }

    private func testGitHubConnection() {
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
                model.saveGitHubToken()
                markGitHubDraftAsSaved()
                connectionResult = nil
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
                if mode == .gitHub {
                    markGitHubDraftAsSaved()
                    connectionResult = nil
                } else {
                    connectionResult = nil
                }
            } else {
                connectionResult = .failure(model.presentedError ?? "切换失败")
                model.presentedError = nil
            }
        }
    }

    private func diagnosticColor(for outcome: UpdateHistoryOutcome) -> Color {
        switch outcome {
        case .updated, .published: .green
        case .unchanged: .secondary
        case .cachedAfterFailure: .orange
        case .failed: .red
        }
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
