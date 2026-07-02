import AppKit
import SwiftUI

/// The module list lives directly in the sidebar of a two-column
/// NavigationSplitView (see `ModulesView`); settings are opened from the app menu.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ModulesView()
            .background(MainWindowCloseBehavior())
            .sheet(isPresented: $model.presentsConfigurationWelcome) {
                ConfigurationWelcomeView()
                    .environment(model)
            }
    }
}

private struct ConfigurationWelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedStorageMode: StorageMode?
    @State private var presentedHeight: CGFloat = 470
    @State private var hasAppeared = false
    @State private var isWorking = false
    @State private var githubRepositoryInput = ""
    @State private var githubCloudflareInput = ""

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 0) {
                hero
                    .padding(.top, 26)

                storageStep

                Spacer(minLength: 16)

                footer
                    .padding(.bottom, 22)
            }
            .padding(.horizontal, 44)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
        }
        .frame(width: 720, height: presentedHeight)
        .clipped()
        .interactiveDismissDisabled()
        .onAppear {
            let initialMode: StorageMode? = model.configurationWelcomeLoadedExistingConfiguration
                ? model.settings.storageMode
                : nil
            selectedStorageMode = initialMode
            presentedHeight = height(for: initialMode)
            githubRepositoryInput = formattedGitHubRepository
            githubCloudflareInput = model.settings.github.publicBaseURL
            withAnimation(.spring(duration: 0.58, bounce: 0.16)) {
                hasAppeared = true
            }
        }
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

                Text("选择汇总模块在设备间保持可用的方式。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

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
                    title: "iCloud 云盘",
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

    private var footer: some View {
        VStack(spacing: 14) {
            if let error = model.configurationWelcomeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        guard let selectedStorageMode else { return }
                        if selectedStorageMode == .gitHub, !applyGitHubInputs() { return }
                        isWorking = true
                        _ = await model.completeConfigurationWelcome(storageMode: selectedStorageMode)
                        isWorking = false
                    }
                } label: {
                    progressLabel(title: "完成设置")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || !canCompleteStorageStep)
                Spacer()
            }
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

    private func height(for mode: StorageMode?) -> CGFloat {
        switch mode {
        case .gitHub: 590
        case .local: 545
        case nil: 470
        }
    }

    private func selectStorageMode(_ mode: StorageMode) {
        guard selectedStorageMode != mode else { return }

        model.configurationWelcomeError = nil
        let newHeight = height(for: mode)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStorageMode = mode
            presentedHeight = newHeight
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
