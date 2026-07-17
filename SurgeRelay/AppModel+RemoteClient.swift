import Foundation

extension AppModel {
    var isClientMode: Bool { deviceMode == .client }

    var hasConfiguredRemoteServer: Bool { remoteManagementURL != nil }

    var isRemoteServerOperational: Bool {
        isClientMode && remoteConnectionState.isOperational
    }

    func startRemoteSessionIfNeeded() {
        guard isClientMode else { return }
        remoteSessionTask?.cancel()
        remoteSessionTask = nil

        guard let baseURL = remoteManagementURL else {
            remoteConnectionState = .idle
            clearRemoteProjection()
            isWorking = false
            statusMessage = "请设置服务器 Ponte 地址"
            presentedError = nil
            return
        }

        remoteConnectionState = .connecting
        statusMessage = "正在连接服务器…"
        presentedError = nil
        let client = RemoteManagementClient(baseURL: baseURL)
        remoteSessionTask = Task { [weak self] in
            await self?.runRemoteSession(client: client)
        }
    }

    func stopRemoteSession() {
        remoteSessionTask?.cancel()
        remoteSessionTask = nil
        remoteConnectionState = .idle
    }

    func refreshRemoteState() async {
        guard isClientMode, let baseURL = remoteManagementURL else { return }
        remoteConnectionState = .connecting
        statusMessage = "正在连接服务器…"
        do {
            let state = try await RemoteManagementClient(baseURL: baseURL).fetchState()
            applyRemoteState(state, baseURL: baseURL)
            remoteConnectionState = .connected
        } catch {
            markRemoteUnavailable(error.localizedDescription)
        }
    }

    private func runRemoteSession(client: RemoteManagementClient) async {
        var retryDelay: TimeInterval = 1
        let maxDelay: TimeInterval = 30

        while !Task.isCancelled, isClientMode {
            remoteConnectionState = .connecting
            statusMessage = "正在连接服务器…"
            presentedError = nil

            do {
                let state = try await client.fetchState()
                applyRemoteState(state, baseURL: client.baseURL)
                remoteConnectionState = .connected
                retryDelay = 1

                try await client.listenForStateEvents { [weak self] state in
                    self?.applyRemoteState(state, baseURL: client.baseURL)
                    self?.remoteConnectionState = .connected
                }
            } catch {
                if Task.isCancelled { return }
                if error is CancellationError { return }
                markRemoteUnavailable(error.localizedDescription)
            }

            guard !Task.isCancelled, isClientMode else { return }

            let jitter = Double.random(in: 0...0.3) * retryDelay
            try? await Task.sleep(for: .seconds(retryDelay + jitter))
            retryDelay = min(maxDelay, max(1, retryDelay * 2))
        }
    }

    func markRemoteUnavailable(_ message: String) {
        remoteConnectionState = .unavailable(message)
        clearRemoteProjection()
        statusMessage = "无法连接服务器"
        presentedError = nil
    }

    func clearRemoteProjection() {
        modules = []
        selectedModuleID = RelayPlatform.ios.selectionID
        isWorking = false
        synchronizingModuleID = nil
        synchronizationTotalCount = 0
        synchronizationCompletedCount = 0
    }

    func applyRemoteState(_ state: RemoteStatePayload, baseURL: URL) {
        guard isClientMode else { return }

        let previousSelection = selectedModuleID
        modules = state.modules.compactMap { $0.asRelayModule(baseURL: baseURL) }
        applyRemoteSettings(state.settings, platforms: state.platforms)
        updateHistory = state.settings.updateHistory
        upstreamState.revision = state.settings.scriptHubRevision
        upstreamState.lastCheckedAt = state.settings.scriptHubLastCheckedAt
        upstreamState.lastError = state.settings.scriptHubLastError

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
        if remote.githubTokenConfigured, githubToken.isEmpty {
            githubToken = settings.githubToken
        }
    }

    func remoteClient() throws -> RemoteManagementClient {
        guard let baseURL = remoteManagementURL else {
            throw RelayError.invalidOutput("请先在设置中配置服务器 Ponte 地址。")
        }
        return RemoteManagementClient(baseURL: baseURL)
    }

    func performRemoteMutation(_ work: (RemoteManagementClient) async throws -> Void) async {
        guard remoteConnectionState.isOperational else {
            presentedError = "服务器无响应，无法执行此操作。"
            return
        }
        do {
            try await work(try remoteClient())
            await refreshRemoteState()
        } catch {
            presentedError = error.localizedDescription
            if isClientMode {
                markRemoteUnavailable(error.localizedDescription)
                startRemoteSessionIfNeeded()
            }
        }
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
