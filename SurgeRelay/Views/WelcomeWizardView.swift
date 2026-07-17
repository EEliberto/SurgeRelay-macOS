import AppKit
import SwiftUI

/// Two-step welcome: choose this Mac's role, then storage (server) or finish
/// after verifying Ponte (client). Matches the original storage UI on step two.
struct WelcomeWizardView: View {
    @Environment(AppModel.self) private var model

    @State private var step: WelcomeStep = .role
    @State private var selectedDeviceMode: RelayDeviceMode?
    @State private var selectedStorageMode: StorageMode?
    @State private var presentedHeight: CGFloat = 470
    @State private var hasAppeared = false
    @State private var isWorking = false
    @State private var isTestingPonte = false
    @State private var hasVerifiedPonteConnection = false
    @State private var ponteServerAddressInput = ""
    @State private var githubRepositoryInput = ""
    @State private var githubCloudflareInput = ""

    private enum WelcomeStep {
        case role
        case storage
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 0) {
                hero
                    .padding(.top, 26)

                Group {
                    switch step {
                    case .role:
                        roleStep
                    case .storage:
                        storageStep
                    }
                }
                // Glass + selection stroke extend past the card bounds.
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

                Spacer(minLength: 12)

                footer
                    .padding(.bottom, 22)
            }
            .padding(.horizontal, 40)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)

            if step == .storage {
                backButton
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    .transition(.opacity)
            }
        }
        .frame(width: 720, height: presentedHeight)
        .interactiveDismissDisabled(!model.configurationWelcomeAllowsDismiss)
        .animation(.easeInOut(duration: 0.18), value: step == .storage)
        .onAppear {
            configureInitialState()
            withAnimation(.spring(duration: 0.58, bounce: 0.16)) {
                hasAppeared = true
            }
        }
    }

    private var backButton: some View {
        Button {
            goBackToRole()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .help("返回")
        .accessibilityLabel("返回")
        .glassEffect(.regular.interactive(), in: Circle())
        .keyboardShortcut(.cancelAction)
    }

    private var hero: some View {
        VStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)

            VStack(spacing: 6) {
                Text("欢迎使用 Surge Relay")
                    .font(.system(size: 29, weight: .bold))
                    .tracking(-0.5)

                Text(heroSubtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var heroSubtitle: String {
        switch step {
        case .role:
            "选择此 Mac 作为服务器还是客户端。"
        case .storage:
            "选择汇总模块在设备间保持可用的方式。"
        }
    }

    // MARK: - Role step

    private var roleStep: some View {
        VStack(spacing: 18) {
            if model.configurationWelcomeLoadedExistingConfiguration {
                Label("检测到 iCloud 中已有 Surge Relay 配置", systemImage: "icloud.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                deviceModeChoice(
                    mode: .server,
                    title: "服务器",
                    detail: "在此 Mac 管理模块，并接受其他设备通过 Ponte 连接",
                    systemImage: "server.rack"
                )
                deviceModeChoice(
                    mode: .client,
                    title: "客户端",
                    detail: "连接另一台服务器 Mac，通过 Ponte 远程管理",
                    systemImage: "laptopcomputer.and.iphone"
                )
            }

            if selectedDeviceMode == .client {
                ponteConfiguration
            } else if selectedDeviceMode == nil {
                Label("请选择此 Mac 的角色后继续", systemImage: "arrow.up.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 24)
    }

    private func deviceModeChoice(
        mode: RelayDeviceMode,
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        Button {
            selectDeviceMode(mode)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(selectedDeviceMode == mode ? Color.accentColor : Color.secondary)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: selectedDeviceMode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedDeviceMode == mode ? Color.accentColor : Color.secondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 90)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selectedDeviceMode == mode ? Color.accentColor.opacity(0.75) : .clear, lineWidth: 2)
        }
    }

    private var ponteConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 11) {
                Text("服务器 Ponte 地址（必填）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("johnsmac.sgponte", text: $ponteServerAddressInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: ponteServerAddressInput) { _, _ in
                            hasVerifiedPonteConnection = false
                            model.configurationWelcomeError = nil
                        }

                    Button {
                        Task { await testPonteConnection() }
                    } label: {
                        if isTestingPonte {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("测试连接")
                        }
                    }
                    .disabled(isTestingPonte || candidatePonteManagementURL == nil)
                }

                Text("必须成功连接服务器后才能进入。可随时改回服务器端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(17)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if hasVerifiedPonteConnection {
                Label("Ponte 服务器连接成功", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private var candidatePonteManagementURL: URL? {
        RelayDeviceConfiguration.managementURL(
            address: ponteServerAddressInput,
            defaultPort: model.settings.webServerPort
        )
    }

    // MARK: - Storage step (original welcome UI)

    private var storageStep: some View {
        VStack(spacing: 18) {
            if model.configurationWelcomeLoadedExistingConfiguration {
                Label("已读取 Surge Relay 中的现有配置", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            }

            HStack(spacing: 16) {
                storageChoice(
                    mode: .local,
                    title: "iCloud 云盘 (推荐)",
                    detail: "在 Surge 文件夹生成汇总模块",
                    assetName: "iCloudIcon"
                )
                storageChoice(
                    mode: .gitHub,
                    title: "GitHub 私有仓库",
                    detail: "通过 Cloudflare 提供稳定订阅",
                    assetName: "GitHubIcon"
                )
            }

            if selectedStorageMode == .gitHub {
                githubConfiguration
            } else if selectedStorageMode == .local {
                HStack(alignment: .top, spacing: 16) {
                    Image("iCloudIcon")
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("通过 iCloud 保持 Surge Relay 同步")
                                .font(.title3.weight(.semibold))
                            Text("汇总模块存入 iCloud 云盘的 Surge 文件夹，配置与同步状态由 Surge Relay 管理。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                            Text("完成设置后，前往 Surge“模块”添加一次，后续即可自动保持更新。")
                                .font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Color.accentColor.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Label("请选择一种同步方式后继续", systemImage: "arrow.up.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 24)
    }

    private func storageChoice(
        mode: StorageMode,
        title: String,
        detail: String,
        assetName: String
    ) -> some View {
        Button {
            selectStorageMode(mode)
        } label: {
            HStack(spacing: 13) {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: selectedStorageMode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedStorageMode == mode ? Color.accentColor : Color.secondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 82)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selectedStorageMode == mode ? Color.accentColor.opacity(0.75) : .clear, lineWidth: 2)
        }
    }

    private var githubConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 11) {
                githubField("仓库地址（必填）") {
                    TextField("https://github.com/owner/repository", text: $githubRepositoryInput)
                }
                githubField("GitHub Token（必填）") {
                    SecureField("", text: Binding(
                        get: { model.githubToken },
                        set: { model.githubToken = $0 }
                    ))
                }
                githubField("Cloudflare Worker 公共地址（必填）") {
                    TextField("https://example.workers.dev", text: $githubCloudflareInput)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(17)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Label("仓库必须为私有；Cloudflare 地址用于生成设备可访问的稳定订阅。", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func githubField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            if let error = model.configurationWelcomeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await advance() }
            } label: {
                progressLabel(title: primaryButtonTitle)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isWorking || !canAdvance)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .role:
            selectedDeviceMode == .client ? "完成设置" : "继续"
        case .storage:
            "完成设置"
        }
    }

    private func progressLabel(title: String) -> some View {
        HStack(spacing: 8) {
            if isWorking {
                ProgressView().controlSize(.small)
            }
            Text(title)
        }
        .frame(minWidth: 96)
    }

    // MARK: - Actions

    private func configureInitialState() {
        let prefersClient = model.configurationWelcomeLoadedExistingConfiguration
            || model.deviceMode == .client
        let initialMode: RelayDeviceMode? = prefersClient ? .client : nil
        selectedDeviceMode = initialMode
        ponteServerAddressInput = model.ponteServerAddress
        hasVerifiedPonteConnection = model.deviceMode == .client && model.hasConfiguredRemoteServer
        githubRepositoryInput = formattedGitHubRepository
        githubCloudflareInput = model.settings.github.publicBaseURL
        step = .role
        if model.configurationWelcomeLoadedExistingConfiguration {
            selectedStorageMode = model.settings.storageMode
        }
        refreshHeight()
    }

    private func selectDeviceMode(_ mode: RelayDeviceMode) {
        guard selectedDeviceMode != mode else { return }
        model.configurationWelcomeError = nil
        if mode == .client {
            hasVerifiedPonteConnection = false
        }
        selectedDeviceMode = mode
        refreshHeight()
    }

    private func selectStorageMode(_ mode: StorageMode) {
        guard selectedStorageMode != mode else { return }
        model.configurationWelcomeError = nil
        selectedStorageMode = mode
        refreshHeight()
    }

    private func goBackToRole() {
        model.configurationWelcomeError = nil
        step = .role
        refreshHeight()
    }

    private func refreshHeight() {
        applyHeight(min(idealContentHeight, maxUsableHeight))
    }

    private var idealContentHeight: CGFloat {
        switch step {
        case .role:
            switch selectedDeviceMode {
            case .client: return hasVerifiedPonteConnection ? 560 : 540
            case .server: return 500
            case nil: return 470
            }
        case .storage:
            switch selectedStorageMode {
            case .gitHub: return 640
            case .local: return 580
            case nil: return 500
            }
        }
    }

    private var maxUsableHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height
            ?? NSScreen.screens.map(\.visibleFrame.height).max()
            ?? 700
        return max(420, visible - 48)
    }

    private func applyHeight(_ newHeight: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentedHeight = newHeight
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .role:
            guard let selectedDeviceMode else { return false }
            if selectedDeviceMode == .client {
                return hasVerifiedPonteConnection && candidatePonteManagementURL != nil
            }
            return true
        case .storage:
            return canCompleteStorageStep
        }
    }

    private func advance() async {
        switch step {
        case .role:
            guard let selectedDeviceMode else { return }
            if selectedDeviceMode == .client {
                isWorking = true
                let succeeded = await model.completeClientWelcome(ponteAddress: ponteServerAddressInput)
                isWorking = false
                if succeeded {
                    hasVerifiedPonteConnection = true
                }
                return
            }
            model.configurationWelcomeError = nil
            if selectedStorageMode == nil, model.configurationWelcomeLoadedExistingConfiguration {
                selectedStorageMode = model.settings.storageMode
            }
            step = .storage
            refreshHeight()
        case .storage:
            guard let selectedStorageMode else { return }
            if selectedStorageMode == .gitHub, !applyGitHubInputs() { return }
            isWorking = true
            _ = await model.completeConfigurationWelcome(storageMode: selectedStorageMode)
            isWorking = false
        }
    }

    private func testPonteConnection() async {
        model.configurationWelcomeError = nil
        isTestingPonte = true
        defer { isTestingPonte = false }
        do {
            try await model.testPonteServer(address: ponteServerAddressInput)
            ponteServerAddressInput = model.ponteServerAddress
            hasVerifiedPonteConnection = true
            refreshHeight()
        } catch {
            hasVerifiedPonteConnection = false
            model.configurationWelcomeError = error.localizedDescription
        }
    }

    private var canCompleteStorageStep: Bool {
        guard let selectedStorageMode else { return false }
        guard selectedStorageMode == .gitHub else { return true }
        return parsedGitHubRepository != nil
            && !model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasValidCloudflareInput
    }

    private var formattedGitHubRepository: String {
        let owner = model.settings.github.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = model.settings.github.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repository.isEmpty else { return "" }
        return "https://github.com/\(owner)/\(repository)"
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

    private func applyGitHubInputs() -> Bool {
        guard let repository = parsedGitHubRepository else {
            model.configurationWelcomeError = "请输入有效的 GitHub 仓库地址，例如 https://github.com/owner/repository。"
            return false
        }
        guard hasValidCloudflareInput else {
            model.configurationWelcomeError = "请输入有效的 Cloudflare 公共地址。"
            return false
        }

        model.settings.github.owner = repository.owner
        model.settings.github.repository = repository.repository
        model.settings.github.branch = "main"
        model.settings.github.directory = "modules"
        model.settings.github.publicBaseURL = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveSettings()
        return true
    }
}
