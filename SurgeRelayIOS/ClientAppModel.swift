import Foundation
import Observation

/// Lightweight remote-only model for the iOS/iPadOS client.
/// It never hosts Script Hub, Web server, or local publish pipelines.
@MainActor
@Observable
final class ClientAppModel {
    private static let configuredKey = "SurgeRelay.iOS.hasConfiguredServer.v1"
    private static let ponteAddressKey = "SurgeRelay.ponteServerAddress.v1"
    private static let defaultManagementPort = 8787

    var modules: [RelayModule] = []
    var settings = AppSettings()
    var updateHistory: [UpdateHistoryEntry] = []
    var upstreamState = ScriptHubUpstreamState()
    var selectedModuleID: UUID?
    var isWorking = false
    var statusMessage = "准备就绪"
    var presentedError: String?
    var synchronizingModuleID: UUID?
    var synchronizationTotalCount = 0
    var synchronizationCompletedCount = 0
    var appVersion = ""
    var githubTokenConfigured = false
    var githubTokenDraft = ""

    /// Platform → subscription URL as advertised by the Mac server.
    var platformSubscriptionURLs: [RelayPlatform: String] = [:]
    /// Combined module subscription URL from the server.
    var combinedSubscriptionURL: String?
    /// Module → published URL from the server (GitHub/Cloudflare).
    var modulePublishedURLs: [UUID: String] = [:]
    /// Platform display icon URLs resolved against the management base URL.
    var platformIconURLs: [RelayPlatform: String] = [:]

    var ponteServerAddress: String {
        didSet {
            UserDefaults.standard.set(ponteServerAddress, forKey: Self.ponteAddressKey)
        }
    }

    var hasConfiguredServer: Bool {
        didSet {
            UserDefaults.standard.set(hasConfiguredServer, forKey: Self.configuredKey)
        }
    }

    var isConnected: Bool {
        hasConfiguredServer && remoteManagementURL != nil && !statusMessage.contains("无法连接")
    }

    var remoteManagementURL: URL? {
        RelayDeviceConfiguration.managementURL(
            address: ponteServerAddress,
            defaultPort: settings.webServerPort > 0 ? settings.webServerPort : Self.defaultManagementPort
        )
    }

    private var remoteSessionTask: Task<Void, Never>?

    init() {
        ponteServerAddress = UserDefaults.standard.string(forKey: Self.ponteAddressKey) ?? ""
        hasConfiguredServer = UserDefaults.standard.bool(forKey: Self.configuredKey)
        settings.webServerPort = Self.defaultManagementPort
    }

    func start() {
        guard hasConfiguredServer else {
            statusMessage = "请配置服务器 Ponte 地址"
            return
        }
        startRemoteSession()
    }

    func completeWelcome(ponteAddress: String) async throws {
        let trimmed = ponteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = RelayDeviceConfiguration.managementURL(
            address: trimmed,
            defaultPort: Self.defaultManagementPort
        ) else {
            throw RelayError.invalidOutput("请输入有效的 Surge Ponte 地址，例如 johnsmac.sgponte。")
        }
        _ = try await RemoteManagementClient(baseURL: url).fetchState()
        ponteServerAddress = trimmed
        hasConfiguredServer = true
        startRemoteSession()
    }

    func updatePonteAddress(_ address: String) async throws {
        try await completeWelcome(ponteAddress: address)
    }

    func disconnect() {
        stopRemoteSession()
        hasConfiguredServer = false
        modules = []
        updateHistory = []
        selectedModuleID = nil
        platformSubscriptionURLs = [:]
        combinedSubscriptionURL = nil
        modulePublishedURLs = [:]
        platformIconURLs = [:]
        presentedError = nil
        statusMessage = "已断开连接"
    }

    func startRemoteSession() {
        remoteSessionTask?.cancel()
        remoteSessionTask = nil

        guard let baseURL = remoteManagementURL else {
            modules = []
            isWorking = false
            statusMessage = "请设置服务器 Ponte 地址"
            presentedError = nil
            return
        }

        statusMessage = "正在连接服务器…"
        let client = RemoteManagementClient(baseURL: baseURL)
        remoteSessionTask = Task { [weak self] in
            await self?.runRemoteSession(client: client)
        }
    }

    func stopRemoteSession() {
        remoteSessionTask?.cancel()
        remoteSessionTask = nil
    }

    func refreshRemoteState() async {
        guard let baseURL = remoteManagementURL else { return }
        do {
            let state = try await RemoteManagementClient(baseURL: baseURL).fetchState()
            applyRemoteState(state, baseURL: baseURL)
        } catch {
            presentedError = error.localizedDescription
            statusMessage = "无法连接服务器"
        }
    }

    func testPonteConnection(_ address: String) async throws {
        guard let url = RelayDeviceConfiguration.managementURL(
            address: address,
            defaultPort: Self.defaultManagementPort
        ) else {
            throw RelayError.invalidOutput("请输入有效的 Surge Ponte 地址。")
        }
        _ = try await RemoteManagementClient(baseURL: url).fetchState()
    }

    // MARK: - Remote mutations

    func updateAll() async {
        await performRemoteMutation { try await $0.updateAll() }
    }

    func refreshScriptHub() async {
        await performRemoteMutation { try await $0.refreshScriptHub() }
    }

    func addModule(_ draft: ModuleDraft) async {
        await performRemoteMutation { _ = try await $0.addModule(draft) }
    }

    func updateModule(id: UUID, draft: ModuleDraft) async {
        await performRemoteMutation { _ = try await $0.updateModule(id: id, draft: draft) }
    }

    func deleteModule(id: UUID) async {
        await performRemoteMutation { try await $0.deleteModule(id: id) }
        if selectedModuleID == id {
            selectedModuleID = RelayPlatform.ios.selectionID
        }
    }

    func setModuleEnabled(id: UUID, enabled: Bool) async {
        await performRemoteMutation { try await $0.setModuleEnabled(id: id, enabled: enabled) }
    }

    func setIndividualICloudExport(id: UUID, enabled: Bool) async {
        await performRemoteMutation { try await $0.setIndividualICloudExport(id: id, enabled: enabled) }
    }

    func reorderModules(ids: [UUID]) async {
        await performRemoteMutation { try await $0.reorderModules(ids: ids) }
    }

    func setPlatformModuleEnabled(platform: RelayPlatform, moduleID: UUID, enabled: Bool) async {
        await performRemoteMutation {
            try await $0.setPlatformModuleEnabled(platform: platform, moduleID: moduleID, enabled: enabled)
        }
    }

    func setAllPlatformModulesEnabled(platform: RelayPlatform, enabled: Bool) async {
        await performRemoteMutation {
            try await $0.setAllPlatformModulesEnabled(platform: platform, enabled: enabled)
        }
    }

    func setModuleArguments(id: UUID, values: [String: String]) async {
        await performRemoteMutation { try await $0.setModuleArguments(id: id, values: values) }
    }

    func resetModuleArguments(id: UUID) async {
        await performRemoteMutation { try await $0.resetModuleArguments(id: id) }
    }

    func updateModuleCustomIcon(id: UUID, url: String?) async {
        await performRemoteMutation { try await $0.updateModuleCustomIcon(id: id, url: url) }
    }

    func acceptOverrideConflict(id: UUID) async {
        await performRemoteMutation { try await $0.acceptOverrideConflict(id: id) }
    }

    func previewContent(moduleID: UUID) async throws -> String {
        try await remoteClient().previewContent(moduleID: moduleID)
    }

    func savePreviewContent(moduleID: UUID, content: String) async throws {
        try await remoteClient().savePreviewContent(moduleID: moduleID, content: content)
        await refreshRemoteState()
    }

    func restorePreviewContent(moduleID: UUID) async throws -> String {
        let content = try await remoteClient().restorePreviewContent(moduleID: moduleID)
        await refreshRemoteState()
        return content
    }

    func combinedPreviewContent(platform: RelayPlatform) async throws -> String {
        try await remoteClient().combinedPreviewContent(platform: platform)
    }

    func moduleArguments(moduleID: UUID) async throws -> RemoteArgumentsPayload {
        try await remoteClient().moduleArguments(moduleID: moduleID)
    }

    func searchIcons(query: String, region: String?) async throws -> [IconSearchResult] {
        try await remoteClient().searchIcons(query: query, region: region)
    }

    func pushGeneralSettings() async {
        var platforms: [String: Bool] = [:]
        for platform in RelayPlatform.allCases {
            platforms[platform.rawValue] = settings.platformSettings[platform.rawValue]?.isEnabled ?? false
        }
        await performRemoteMutation {
            try await $0.pushGeneralSettings(
                refreshIntervalMinutes: settings.refreshIntervalMinutes,
                automaticallyPublish: settings.automaticallyPublish,
                iconSearchRegion: settings.iconSearchRegion,
                platforms: platforms
            )
        }
    }

    func pushScriptHubSettings() async {
        await performRemoteMutation {
            try await $0.pushScriptHubSettings(
                moduleURL: settings.scriptHubModuleURL,
                automaticallyUpdate: settings.automaticallyUpdateScriptHub
            )
        }
    }

    func pushSyncSettings(includeToken: Bool) async {
        let repository = "\(settings.github.owner)/\(settings.github.repository)"
        let token = includeToken ? githubTokenDraft : nil
        await performRemoteMutation {
            try await $0.pushSyncSettings(
                storageMode: settings.storageMode.rawValue,
                githubRepository: repository,
                githubToken: token,
                githubPublicBaseURL: settings.github.publicBaseURL
            )
        }
    }

    func testSyncSettings(includeToken: Bool) async throws {
        let repository = "\(settings.github.owner)/\(settings.github.repository)"
        let token = includeToken ? githubTokenDraft : nil
        try await remoteClient().testSyncSettings(
            storageMode: settings.storageMode.rawValue,
            githubRepository: repository,
            githubToken: token,
            githubPublicBaseURL: settings.github.publicBaseURL
        )
    }

    func clearDiagnostics() async {
        await performRemoteMutation { try await $0.clearDiagnostics() }
    }

    func dismissPresentedError() {
        presentedError = nil
        Task {
            try? await remoteClient().dismissActivityError()
        }
    }

    func subscriptionURL(for platform: RelayPlatform) -> String? {
        platformSubscriptionURLs[platform] ?? combinedSubscriptionURL
    }

    func publishedURL(for module: RelayModule) -> String? {
        modulePublishedURLs[module.id]
    }

    func isModuleEnabled(_ moduleID: UUID, on platform: RelayPlatform) -> Bool {
        let entry = settings.platformSettings[platform.rawValue] ?? PlatformSettings()
        guard let module = modules.first(where: { $0.id == moduleID }) else { return false }
        return module.isEnabled && !entry.disabledModules.contains(moduleID)
    }

    // MARK: - Internals

    private func runRemoteSession(client: RemoteManagementClient) async {
        var retryDelay: TimeInterval = 2
        let maximumRetryDelay: TimeInterval = 30

        while !Task.isCancelled, hasConfiguredServer {
            var shouldResetBackoff = false
            do {
                let state = try await client.fetchState()
                applyRemoteState(state, baseURL: client.baseURL)
                let connectedAt = Date.now

                do {
                    try await client.listenForStateEvents { [weak self] state in
                        self?.applyRemoteState(state, baseURL: client.baseURL)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    statusMessage = "实时同步中断，正在重连…"
                    if Date.now.timeIntervalSince(connectedAt) >= 30 {
                        shouldResetBackoff = true
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                presentedError = error.localizedDescription
                statusMessage = "无法连接服务器"
            }

            guard !Task.isCancelled, hasConfiguredServer else { return }
            if shouldResetBackoff {
                retryDelay = 2
            }
            let jitter = Double.random(in: 0...(retryDelay * 0.25))
            try? await Task.sleep(for: .seconds(retryDelay + jitter))
            retryDelay = shouldResetBackoff ? 2 : min(maximumRetryDelay, retryDelay * 2)
        }
    }

    private func applyRemoteState(_ state: RemoteStatePayload, baseURL: URL) {
        let previousSelection = selectedModuleID
        modules = state.modules.compactMap { $0.asRelayModule(baseURL: baseURL) }

        var published: [UUID: String] = [:]
        for payload in state.modules {
            if let id = UUID(uuidString: payload.id), let url = payload.publishedURL, !url.isEmpty {
                published[id] = url
            }
        }
        modulePublishedURLs = published
        combinedSubscriptionURL = state.combined.subscriptionURL

        var platformURLs: [RelayPlatform: String] = [:]
        var platformIcons: [RelayPlatform: String] = [:]
        for platformPayload in state.platforms {
            guard let platform = RelayPlatform(rawValue: platformPayload.id) else { continue }
            if let url = platformPayload.subscriptionURL, !url.isEmpty {
                platformURLs[platform] = url
            }
            if let absolute = absoluteURLString(platformPayload.iconURL, baseURL: baseURL)
                ?? absoluteURLString(platformPayload.customIconURL, baseURL: baseURL) {
                platformIcons[platform] = absolute
            }
        }
        platformSubscriptionURLs = platformURLs
        platformIconURLs = platformIcons

        applyRemoteSettings(state.settings, platforms: state.platforms)
        updateHistory = state.settings.updateHistory
        upstreamState.revision = state.settings.scriptHubRevision
        upstreamState.lastCheckedAt = state.settings.scriptHubLastCheckedAt
        upstreamState.lastError = state.settings.scriptHubLastError
        appVersion = state.settings.appVersion
        githubTokenConfigured = state.settings.githubTokenConfigured

        isWorking = state.activity.isWorking
        statusMessage = state.activity.status
        presentedError = state.activity.error
        if let current = state.activity.currentModuleID, let uuid = UUID(uuidString: current) {
            synchronizingModuleID = uuid
        } else {
            synchronizingModuleID = nil
        }
        if let progress = state.activity.progress, progress.isFinite {
            synchronizationTotalCount = 100
            synchronizationCompletedCount = Int((progress * 100).rounded())
        } else {
            synchronizationTotalCount = 0
            synchronizationCompletedCount = 0
        }

        if let previousSelection,
           modules.contains(where: { $0.id == previousSelection })
            || RelayPlatform.from(selectionID: previousSelection) != nil {
            selectedModuleID = previousSelection
        } else if selectedModuleID == nil || !(
            modules.contains(where: { $0.id == selectedModuleID })
                || (selectedModuleID.map { RelayPlatform.from(selectionID: $0) != nil } ?? false)
        ) {
            selectedModuleID = RelayPlatform.ios.selectionID
        }
    }

    private func applyRemoteSettings(_ remote: RemoteSettingsPayload, platforms: [RemotePlatformPayload]) {
        var next = settings
        next.refreshIntervalMinutes = remote.refreshIntervalMinutes
        next.automaticallyPublish = remote.automaticallyPublish
        next.iconSearchRegion = remote.iconSearchRegion
        next.webServerEnabled = remote.webServerEnabled
        next.webServerPort = remote.webServerPort
        next.scriptHubModuleURL = remote.scriptHubModuleURL
        next.automaticallyUpdateScriptHub = remote.automaticallyUpdateScriptHub
        if let mode = StorageMode(rawValue: remote.storageMode) {
            next.storageMode = mode
        }
        next.github.publicBaseURL = remote.githubPublicBaseURL
        next.github.repositoryIsPrivate = remote.githubRepositoryIsPrivate
        if let parsed = Self.parseGitHubRepository(remote.githubRepository) {
            next.github.owner = parsed.owner
            next.github.repository = parsed.repository
        }

        var platformSettings = next.platformSettings
        let moduleIDs = Set(modules.map(\.id))
        for platform in platforms {
            guard let relayPlatform = RelayPlatform(rawValue: platform.id) else { continue }
            var entry = platformSettings[relayPlatform.rawValue] ?? PlatformSettings()
            entry.isEnabled = platform.isEnabled
            let enabled = Set(platform.enabledModules.compactMap(UUID.init(uuidString:)))
            entry.disabledModules = moduleIDs.subtracting(enabled)
            entry.customIconURL = platform.customIconURL
            platformSettings[relayPlatform.rawValue] = entry
        }
        for (raw, isEnabled) in remote.platforms {
            var entry = platformSettings[raw] ?? PlatformSettings()
            entry.isEnabled = isEnabled
            platformSettings[raw] = entry
        }
        next.platformSettings = platformSettings
        settings = next
    }

    private func remoteClient() throws -> RemoteManagementClient {
        guard let baseURL = remoteManagementURL else {
            throw RelayError.invalidOutput("请先配置服务器 Ponte 地址。")
        }
        return RemoteManagementClient(baseURL: baseURL)
    }

    private func performRemoteMutation(_ work: (RemoteManagementClient) async throws -> Void) async {
        do {
            try await work(try remoteClient())
            await refreshRemoteState()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func absoluteURLString(_ value: String?, baseURL: URL) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString
    }

    private static func parseGitHubRepository(_ value: String) -> (owner: String, repository: String)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let path: String
        if let url = URL(string: trimmed), let host = url.host?.lowercased(), host == "github.com" {
            path = url.path
        } else {
            path = trimmed
                .replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: "http://github.com/", with: "")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repository = parts[1]
            .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
        guard !owner.isEmpty, !repository.isEmpty else { return nil }
        return (owner, repository)
    }
}
