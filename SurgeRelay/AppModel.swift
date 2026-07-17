import AppKit
import Foundation
import Observation
import CryptoKit

@MainActor
@Observable
final class AppModel {
    static let combinedModuleSelectionID = RelayPlatform.ios.selectionID

    var modules: [RelayModule]
    var settings: AppSettings
    var upstreamState: ScriptHubUpstreamState
    var selectedModuleID: UUID?
    var isWorking = false
    var statusMessage = "准备就绪"
    var presentedError: String?
    var githubToken: String
    var navigationRequest: SidebarDestination?
    /// First-run setup presentation state.
    var presentsConfigurationWelcome = false
    var configurationWelcomeError: String?
    var configurationWelcomeLoadedExistingConfiguration = false
    /// When true, the welcome sheet can be dismissed (menu-bar review entry).
    var configurationWelcomeAllowsDismiss = false
    var synchronizationCompletedCount = 0
    var synchronizationTotalCount = 0
    var synchronizingModuleID: UUID?
    var webServerState: WebServerRuntimeState = .stopped
    var updateHistory: [UpdateHistoryEntry]
    var deviceMode: RelayDeviceMode
    var ponteServerAddress: String

    @ObservationIgnored private let scriptHubClient = ScriptHubClient()
    @ObservationIgnored private let sourceRevisionService = SourceRevisionService()
    @ObservationIgnored private let upstreamService = ScriptHubUpstreamService()
    @ObservationIgnored private let engineStore = EngineStore()
    @ObservationIgnored private let githubClient = GitHubClient()
    @ObservationIgnored private let fileStore = ModuleFileStore()
    @ObservationIgnored private let iconStore = ModuleIconStore()
    @ObservationIgnored private let processingWorker = ModuleProcessingWorker()
    @ObservationIgnored private let webServer = WebManagementServer()
    @ObservationIgnored private var schedulerTask: Task<Void, Never>?
    @ObservationIgnored private var synchronizationTask: Task<Void, Never>?
    @ObservationIgnored private var synchronizationRequestID = UUID()
    @ObservationIgnored private var combinedRebuildTask: Task<Void, Never>?
    @ObservationIgnored private var automaticUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var automaticPublishTask: Task<Void, Never>?
    @ObservationIgnored private var individualOutputMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var individualOutputMutationsInProgress = Set<UUID>()
    @ObservationIgnored private var activeWorkToken: UUID?
    @ObservationIgnored private var localChangeGeneration = 0
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var configurationExistedBeforeLaunch = false
    @ObservationIgnored var remoteSessionTask: Task<Void, Never>?
    @ObservationIgnored private var pendingModuleUpdateIDs = Set<UUID>()

    private func beginWork() -> UUID? {
        guard activeWorkToken == nil else { return nil }
        let token = UUID()
        activeWorkToken = token
        isWorking = true
        return token
    }

    private func endWork(_ token: UUID) {
        guard activeWorkToken == token else { return }
        activeWorkToken = nil
        isWorking = false
    }

    init() {
        let defaultConfiguration = URL(
            filePath: AppSettings.defaultConfigurationDirectory,
            directoryHint: .isDirectory
        )
        configurationExistedBeforeLaunch = ["settings.json", "modules.json", "script-hub-state.json"].contains { name in
            FileManager.default.fileExists(atPath: defaultConfiguration.appending(path: name).path)
        }
        var loadedSettings = PersistenceStore.loadSettings()
        if loadedSettings.github.owner.isEmpty { loadedSettings.github.owner = "EEliberto" }
        if loadedSettings.github.repository.isEmpty { loadedSettings.github.repository = "Surge-Relay" }
        if loadedSettings.github.branch.isEmpty { loadedSettings.github.branch = "main" }
        if loadedSettings.github.directory.isEmpty { loadedSettings.github.directory = "modules" }
        loadedSettings.localModuleDirectory = AppSettings.surgeDirectory(
            forSelectedDirectory: URL(
                filePath: loadedSettings.localModuleDirectory,
                directoryHint: .isDirectory
            )
        ).path
        var loadedModules = Self.normalizedModuleNaming(
            PersistenceStore.loadModules(),
            combinedFileName: loadedSettings.combinedModuleFileName
        )
        var migrated = false
        for i in 0..<loadedModules.count {
            if !loadedModules[i].isEnabled {
                let id = loadedModules[i].id
                loadedModules[i].isEnabled = true
                migrated = true
                for platform in RelayPlatform.allCases {
                    var platSettings = loadedSettings.platformSettings[platform.rawValue] ?? PlatformSettings()
                    platSettings.disabledModules.insert(id)
                    loadedSettings.platformSettings[platform.rawValue] = platSettings
                }
            }
        }
        modules = loadedModules
        settings = loadedSettings
        upstreamState = PersistenceStore.loadUpstreamState()
        updateHistory = PersistenceStore.loadUpdateHistory()
        githubToken = loadedSettings.githubToken
        deviceMode = RelayDeviceConfiguration.mode
        ponteServerAddress = RelayDeviceConfiguration.ponteServerAddress
        selectedModuleID = RelayPlatform.ios.selectionID
        PersistenceStore.saveSettings(loadedSettings)
        try? PersistenceStore.saveModules(loadedModules)
    }

    func start() async {
        guard !hasStarted else { return }

        let needsWelcome = !PersistenceStore.hasCompletedInitialSetup
            || (deviceMode == .client && !hasConfiguredRemoteServer)

        if needsWelcome {
            NSApp.activate(ignoringOtherApps: true)
            configurationWelcomeAllowsDismiss = false
            configurationWelcomeError = nil
            if !PersistenceStore.hasCompletedInitialSetup {
                PersistenceStore.markInitialSetupPending()
                if !PersistenceStore.hasSelectedConfigurationDirectory {
                    do {
                        try prepareDefaultConfigurationDestination()
                    } catch {
                        configurationWelcomeError = "无法准备 iCloud 云盘中的 Surge Relay 文件夹：\(error.localizedDescription)"
                    }
                } else {
                    configurationWelcomeLoadedExistingConfiguration = PersistenceStore.initialSetupLoadedExistingConfiguration
                }
            } else {
                configurationWelcomeLoadedExistingConfiguration =
                    configurationExistedBeforeLaunch
                    || PersistenceStore.initialSetupLoadedExistingConfiguration
            }
            presentsConfigurationWelcome = true
            if deviceMode == .client {
                webServer.stop()
                webServerState = .stopped
                modules = []
            }
            return
        }

        if deviceMode == .client {
            webServer.stop()
            webServerState = .stopped
            modules = []
            startRemoteSessionIfNeeded()
            return
        }
        await startRuntime()
    }

    private func startRuntime() async {
        guard !hasStarted, deviceMode == .server else { return }
        hasStarted = true
        applyWebServerSettings(persist: false)
        restartScheduler()
        if settings.storageMode == .gitHub {
            for platform in RelayPlatform.allCases {
                try? await fileStore.removeExportedCombined(
                    fromDirectory: settings.localModuleDirectory,
                    fileName: platformFileName(for: platform)
                )
            }
        }
        Task {
            do {
                try await fileStore.prepareStorage()
            } catch {
                presentedError = "无法初始化缓存目录：\(error.localizedDescription)"
            }
            await reconcileIndividualICloudOutputs()
            restartIndividualOutputMonitor()
            await refreshModuleMetadataFromCache()
            let missingEngine = !(await engineStore.hasScript(named: "Rewrite-Parser.js"))
            if await shouldUpdateModulesOnLaunch() {
                await updateAll()
            } else if missingEngine || (
                settings.automaticallyUpdateScriptHub
                    && RefreshPolicy.isDue(
                        lastUpdatedAt: upstreamState.lastCheckedAt,
                        intervalMinutes: settings.refreshIntervalMinutes
                    )
            ) {
                await refreshScriptHub(showProgress: false)
            } else if modules.contains(where: \.isEnabled) {
                if settings.storageMode == .local {
                    statusMessage = "正在同步到 iCloud…"
                    let rebuilt = await rebuildCombinedFromCache()
                    if rebuilt { statusMessage = "已是最新。" }
                } else {
                    statusMessage = "已是最新。"
                }
            }
        }
    }

    private func prepareDefaultConfigurationDestination() throws {
        let surgeDirectory = URL(
            filePath: AppSettings.defaultSurgeDirectory,
            directoryHint: .isDirectory
        ).standardizedFileURL
        let configurationDirectory = AppSettings.configurationDirectory(forSurgeDirectory: surgeDirectory)
        try PersistenceStore.selectConfigurationDirectory(configurationDirectory.path)
        reloadConfigurationFromSelectedDirectory()
        settings.localModuleDirectory = surgeDirectory.path
        saveSettings()
        configurationWelcomeLoadedExistingConfiguration = configurationExistedBeforeLaunch
        PersistenceStore.setInitialSetupLoadedExistingConfiguration(configurationExistedBeforeLaunch)
        statusMessage = configurationExistedBeforeLaunch ? "已读取 Surge Relay 中的现有配置" : "已准备 iCloud 云盘存储"
    }

    func completeConfigurationWelcome(storageMode: StorageMode) async -> Bool {
        configurationWelcomeError = nil
        if storageMode == .gitHub {
            do {
                try await validateGitHubDestination()
            } catch {
                configurationWelcomeError = error.localizedDescription
                return false
            }
        }
        if deviceMode != .server {
            stopRemoteSession()
            deviceMode = .server
            RelayDeviceConfiguration.mode = .server
        }
        settings.storageMode = storageMode
        saveSettings()
        PersistenceStore.markInitialSetupCompleted()
        configurationWelcomeAllowsDismiss = false
        presentsConfigurationWelcome = false
        await startRuntime()
        if storageMode == .local {
            await rebuildCombinedFromCache()
        } else {
            for platform in RelayPlatform.allCases {
                try? await fileStore.removeExportedCombined(
                    fromDirectory: settings.localModuleDirectory,
                    fileName: platformFileName(for: platform)
                )
            }
            await removeAllExportedIndividualModules()
        }
        return true
    }

    func completeClientWelcome(ponteAddress: String) async -> Bool {
        configurationWelcomeError = nil
        do {
            try await testPonteServer(address: ponteAddress)
        } catch {
            configurationWelcomeError = error.localizedDescription
            return false
        }
        if deviceMode != .client {
            await setDeviceMode(.client)
        } else {
            startRemoteSessionIfNeeded()
        }
        PersistenceStore.markInitialSetupCompleted()
        configurationWelcomeAllowsDismiss = false
        presentsConfigurationWelcome = false
        statusMessage = "已切换到客户端模式"
        return true
    }

    func presentWelcomeWizard(allowDismiss: Bool = false) {
        configurationWelcomeError = nil
        configurationWelcomeAllowsDismiss = allowDismiss
        configurationWelcomeLoadedExistingConfiguration =
            configurationExistedBeforeLaunch
            || PersistenceStore.initialSetupLoadedExistingConfiguration
        presentsConfigurationWelcome = true
    }

    func presentConfigurationWelcomeForDebugging() {
        presentWelcomeWizard(allowDismiss: true)
        configurationWelcomeLoadedExistingConfiguration = true
    }

    private func reloadConfigurationFromSelectedDirectory() {
        var loadedSettings = PersistenceStore.loadSettings()
        if loadedSettings.github.owner.isEmpty { loadedSettings.github.owner = "EEliberto" }
        if loadedSettings.github.repository.isEmpty { loadedSettings.github.repository = "Surge-Relay" }
        if loadedSettings.github.branch.isEmpty { loadedSettings.github.branch = "main" }
        if loadedSettings.github.directory.isEmpty { loadedSettings.github.directory = "modules" }
        settings = loadedSettings
        modules = Self.normalizedModuleNaming(
            PersistenceStore.loadModules(),
            combinedFileName: loadedSettings.combinedModuleFileName
        )
        upstreamState = PersistenceStore.loadUpstreamState()
        updateHistory = PersistenceStore.loadUpdateHistory()
        githubToken = loadedSettings.githubToken
        selectedModuleID = RelayPlatform.ios.selectionID
    }

    private func shouldUpdateModulesOnLaunch() async -> Bool {
        let enabledModules = modules.filter(\.isEnabled)
        guard !enabledModules.isEmpty else { return false }

        for module in enabledModules {
            if module.lastUpdatedAt == nil { return true }
            if !(await fileStore.hasComponent(id: module.id)) { return true }
        }

        let oldestUpdate = enabledModules.compactMap(\.lastUpdatedAt).min()
        return RefreshPolicy.isDue(
            lastUpdatedAt: oldestUpdate,
            intervalMinutes: settings.refreshIntervalMinutes
        )
    }

    func saveSettings() {
        if isClientMode {
            Task { await pushRemoteGeneralSettings() }
            return
        }
        settings.githubToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settings.automaticallyPublish {
            automaticPublishTask?.cancel()
        }
        PersistenceStore.saveSettings(settings)
    }

    func pushRemoteGeneralSettings() async {
        guard isClientMode else { return }
        var platforms: [String: Bool] = [:]
        for platform in RelayPlatform.allCases {
            platforms[platform.rawValue] = settings.platformSettings[platform.rawValue]?.isEnabled ?? false
        }
        await performRemoteMutation { client in
            try await client.pushGeneralSettings(
                refreshIntervalMinutes: settings.refreshIntervalMinutes,
                automaticallyPublish: settings.automaticallyPublish,
                iconSearchRegion: settings.iconSearchRegion,
                platforms: platforms
            )
        }
    }

    func saveGitHubToken() {
        githubToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.githubToken = githubToken
        if isClientMode {
            Task { await pushRemoteSyncSettings() }
            statusMessage = githubToken.isEmpty ? "GitHub Token 已清除" : "GitHub Token 已保存到服务器"
            return
        }
        PersistenceStore.saveSettings(settings)
        statusMessage = githubToken.isEmpty ? "GitHub Token 已从同步配置移除" : "GitHub Token 已保存到 iCloud 配置"
    }

    func pushRemoteScriptHubSettings() async {
        guard isClientMode else { return }
        await performRemoteMutation { client in
            try await client.pushScriptHubSettings(
                moduleURL: settings.scriptHubModuleURL,
                automaticallyUpdate: settings.automaticallyUpdateScriptHub
            )
        }
    }

    func pushRemoteSyncSettings(includeToken: Bool = true) async {
        guard isClientMode else { return }
        let repository = "https://github.com/\(settings.github.owner)/\(settings.github.repository)"
        await performRemoteMutation { client in
            try await client.pushSyncSettings(
                storageMode: settings.storageMode.rawValue,
                githubRepository: repository,
                githubToken: includeToken ? githubToken : nil,
                githubPublicBaseURL: settings.github.publicBaseURL
            )
        }
    }

    func applyWebServerSettings(persist: Bool = true) {
        guard (1...65_535).contains(settings.webServerPort),
              let port = UInt16(exactly: settings.webServerPort) else {
            webServerState = .failed("端口必须在 1–65535 之间。")
            return
        }
        if persist { saveSettings() }
        webServer.stop()
        guard deviceMode == .server, settings.webServerEnabled else {
            webServerState = .stopped
            return
        }

        let configuration = WebServerConfiguration(port: port)
        do {
            try webServer.start(
                configuration: configuration,
                stateHandler: { [weak self] state in
                    Task { @MainActor [weak self] in self?.webServerState = state }
                },
                eventHandler: { [weak self] in
                    guard let self else { return "{}" }
                    return await WebManagementAPI.eventPayload(model: self)
                },
                requestHandler: { [weak self] request in
                    if !request.path.hasPrefix("/api/") {
                        return WebManagementAPI.assetResponse(for: request.path)
                    }
                    guard let self else {
                        return .error(status: 500, message: "Surge Relay 已停止。")
                    }
                    return await WebManagementAPI.response(for: request, model: self)
                }
            )
        } catch {
            webServerState = .failed(error.localizedDescription)
        }
    }

    func setDeviceMode(_ mode: RelayDeviceMode) async {
        guard deviceMode != mode else { return }
        deviceMode = mode
        RelayDeviceConfiguration.mode = mode
        if mode == .client {
            schedulerTask?.cancel()
            synchronizationTask?.cancel()
            combinedRebuildTask?.cancel()
            automaticUpdateTask?.cancel()
            automaticPublishTask?.cancel()
            individualOutputMonitorTask?.cancel()
            webServer.stop()
            webServerState = .stopped
            hasStarted = false
            activeWorkToken = nil
            isWorking = false
            synchronizationCompletedCount = 0
            synchronizationTotalCount = 0
            synchronizingModuleID = nil
            modules = []
            startRemoteSessionIfNeeded()
            statusMessage = remoteManagementURL == nil ? "请设置服务器 Ponte 地址" : "已切换到客户端模式"
        } else {
            stopRemoteSession()
            reloadConfigurationFromSelectedDirectory()
            await start()
        }
    }

    func setPonteServerAddress(_ address: String) {
        ponteServerAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        RelayDeviceConfiguration.ponteServerAddress = ponteServerAddress
        if isClientMode {
            startRemoteSessionIfNeeded()
        }
        statusMessage = remoteManagementURL == nil ? "请设置有效的服务器 Ponte 地址" : "服务器地址已保存"
    }

    var remoteManagementURL: URL? {
        RelayDeviceConfiguration.managementURL(
            address: ponteServerAddress,
            defaultPort: settings.webServerPort
        )
    }

    func testPonteServer(address: String) async throws {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = RelayDeviceConfiguration.managementURL(
            address: normalizedAddress,
            defaultPort: settings.webServerPort
        ),
              let stateURL = URL(string: "api/state", relativeTo: baseURL)?.absoluteURL else {
            throw RelayError.invalidOutput("请输入有效的 Ponte 地址，例如 johnsmac.sgponte。")
        }
        var request = URLRequest(
            url: stateURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["modules"] != nil, payload["settings"] != nil else {
            throw RelayError.invalidOutput("服务器没有返回有效的 Surge Relay 状态。")
        }
        setPonteServerAddress(normalizedAddress)
        statusMessage = "Ponte 服务器连接成功"
    }


    var configurationDirectoryPath: String {
        PersistenceStore.configurationDirectoryURL.path
    }

    var surgeDirectoryPath: String {
        AppSettings.surgeDirectory(
            forSelectedDirectory: URL(
                filePath: settings.localModuleDirectory,
                directoryHint: .isDirectory
            )
        ).path
    }

    func setStorageMode(_ mode: StorageMode) async -> Bool {
        guard settings.storageMode != mode else { return true }
        if isClientMode {
            settings.storageMode = mode
            await pushRemoteSyncSettings()
            return presentedError == nil
        }
        if mode == .gitHub {
            do {
                try await validateGitHubDestination()
            } catch {
                presentedError = error.localizedDescription
                return false
            }
        }
        settings.storageMode = mode
        saveSettings()
        if mode == .local {
            await rebuildCombinedFromCache()
            restartIndividualOutputMonitor()
        } else {
            individualOutputMonitorTask?.cancel()
            // Remove only the platform-specific files generated by Surge Relay.
            // ModuleFileStore verifies the managed header before deleting, so a
            // user-owned .sgmodule with the same name is left untouched.
            for platform in RelayPlatform.allCases {
                try? await fileStore.removeExportedCombined(
                    fromDirectory: settings.localModuleDirectory,
                    fileName: platformFileName(for: platform)
                )
            }
            await removeAllExportedIndividualModules()
        }
        return true
    }

    func openConfigurationDirectory() {
        NSWorkspace.shared.open(PersistenceStore.configurationDirectoryURL)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            settings.launchAtLogin = enabled
            if !isClientMode {
                settings.githubToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                PersistenceStore.saveSettings(settings)
            }
        } catch {
            settings.launchAtLogin = false
            presentedError = "无法更改登录启动设置：\(error.localizedDescription)"
        }
    }

    func restartScheduler() {
        schedulerTask?.cancel()
        guard !isClientMode, settings.refreshIntervalMinutes > 0 else { return }
        let seconds = settings.refreshIntervalMinutes * 60
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.updateAll()
            }
        }
    }

    func addModule(from draft: ModuleDraft) async throws {
        if isClientMode {
            let client = try remoteClient()
            statusMessage = try await client.addModule(draft)
            await refreshRemoteState()
            return
        }
        if let message = draft.validationMessage { throw RelayError.invalidOutput(message) }
        let source = draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modules.contains(where: { ModuleSourceIdentity.matches($0.sourceURL, source) }) else {
            throw RelayError.duplicateSourceURL
        }
        let module = RelayModule(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: source,
            sourceFormat: draft.sourceFormat,
            outputFileName: uniqueOutputFileName(for: draft, source: source),
            isEnabled: draft.isEnabled,
            scriptHubOptions: draft.scriptHubOptions,
            detectedSourceFormat: detectedFormat(for: draft.sourceFormat, source: source)
        )
        registerLocalChange()
        modules.append(module)
        selectedModuleID = module.id
        try persistModules()
        statusMessage = "已添加 \(module.name)，正在后台更新"
        scheduleModuleUpdate(id: module.id)
    }

    func updateModule(id: UUID, from draft: ModuleDraft) async throws {
        if isClientMode {
            let client = try remoteClient()
            statusMessage = try await client.updateModule(id: id, draft: draft)
            await refreshRemoteState()
            return
        }
        if let message = draft.validationMessage { throw RelayError.invalidOutput(message) }
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modules.contains(where: {
            $0.id != id && ModuleSourceIdentity.matches($0.sourceURL, source)
        }) else {
            throw RelayError.duplicateSourceURL
        }
        let outputFileName = uniqueOutputFileName(for: draft, source: source, excluding: id)
        let detectedSourceFormat = detectedFormat(for: draft.sourceFormat, source: source)
        let current = modules[index]
        guard current.name != name ||
                current.sourceURL != source ||
                current.sourceFormat != draft.sourceFormat ||
                current.outputFileName != outputFileName ||
                current.isEnabled != draft.isEnabled ||
                current.scriptHubOptions != draft.scriptHubOptions else {
            statusMessage = "没有需要保存的更改"
            return
        }
        registerLocalChange()
        let nameChanged = current.name != name
        let sourceChanged = modules[index].sourceURL != source ||
            modules[index].sourceFormat != draft.sourceFormat ||
            modules[index].scriptHubOptions != draft.scriptHubOptions
        let previousOutputFileName = modules[index].outputFileName
        modules[index].name = name
        modules[index].sourceURL = source
        modules[index].sourceFormat = draft.sourceFormat
        modules[index].outputFileName = outputFileName
        modules[index].isEnabled = draft.isEnabled
        modules[index].scriptHubOptions = draft.scriptHubOptions
        modules[index].detectedSourceFormat = detectedSourceFormat
        if sourceChanged || nameChanged {
            modules[index].state = .never
            modules[index].lastError = nil
            modules[index].sourceETag = nil
            modules[index].sourceLastModified = nil
            modules[index].sourceContentHash = nil
            modules[index].sourceCheckedAt = nil
            modules[index].conversionEngineRevision = nil
        }
        if sourceChanged {
            modules[index].iconURL = nil
            Task { try? await iconStore.removeIcon(for: id) }
        }
        try persistModules()
        if current.exportsIndividualModuleToICloud,
           previousOutputFileName != outputFileName {
            let updatedModule = modules[index]
            Task {
                individualOutputMutationsInProgress.insert(id)
                defer { individualOutputMutationsInProgress.remove(id) }
                do {
                    try await exportIndividualICloudModule(updatedModule)
                    try await removeExportedIndividualFiles(
                        moduleID: id,
                        outputFileName: previousOutputFileName
                    )
                } catch {
                    presentedError = error.localizedDescription
                }
            }
        }
        statusMessage = "已保存 \(modules[index].name)，正在后台更新"
        if modules[index].isEnabled {
            scheduleModuleUpdate(id: id)
        } else {
            scheduleCombinedRebuild()
        }
    }

    func setModuleEnabled(id: UUID, enabled: Bool) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        guard modules[index].isEnabled != enabled else { return }
        if isClientMode {
            modules[index].isEnabled = enabled
            Task {
                await performRemoteMutation { client in
                    try await client.setModuleEnabled(id: id, enabled: enabled)
                }
            }
            return
        }
        registerLocalChange()
        modules[index].isEnabled = enabled
        try? persistModules()
        statusMessage = enabled ? "已启用 \(modules[index].name)，正在后台更新" : "已停用 \(modules[index].name)，正在自动合并"
        if enabled {
            scheduleModuleUpdate(id: id)
        } else {
            scheduleCombinedRebuild()
        }
    }

    func setModuleIndividualICloudExport(id: UUID, enabled: Bool) async {
        if isClientMode {
            await performRemoteMutation { client in
                try await client.setIndividualICloudExport(id: id, enabled: enabled)
            }
            return
        }
        guard settings.storageMode == .local,
              let index = modules.firstIndex(where: { $0.id == id }),
              modules[index].exportsIndividualModuleToICloud != enabled else { return }
        registerLocalChange()
        modules[index].exportsIndividualModuleToICloud = enabled
        individualOutputMutationsInProgress.insert(id)
        defer { individualOutputMutationsInProgress.remove(id) }
        do {
            try persistModules()
            let module = modules[index]
            if enabled {
                if await fileStore.hasComponent(id: id) {
                    try await exportIndividualICloudModule(module)
                    statusMessage = "已输出 \(module.name) 的独立模块"
                } else {
                    statusMessage = "正在生成 \(module.name) 的独立模块"
                    await updateAll()
                }
            } else {
                try await removeExportedIndividualFiles(
                    moduleID: module.id,
                    outputFileName: module.outputFileName
                )
                statusMessage = "已停止输出 \(module.name) 的独立模块"
            }
        } catch {
            modules[index].exportsIndividualModuleToICloud.toggle()
            try? persistModules()
            presentedError = error.localizedDescription
        }
    }

    func moveModules(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let reordered = ModuleOrdering.moving(modules, fromOffsets: offsets, toOffset: destination)
        guard reordered != modules else { return }
        modules = reordered
        if isClientMode {
            Task {
                await performRemoteMutation { client in
                    try await client.reorderModules(ids: reordered.map(\.id))
                }
            }
            return
        }
        registerLocalChange()
        do {
            try persistModules()
            statusMessage = "已调整模块优先级，正在重新合并"
            scheduleCombinedRebuild()
        } catch {
            presentedError = "保存模块顺序失败：\(error.localizedDescription)"
        }
    }

    func reorderModules(ids: [UUID]) {
        guard ids.count == modules.count,
              Set(ids) == Set(modules.map(\.id)) else { return }
        let lookup = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        let reordered = ids.compactMap { lookup[$0] }
        guard reordered != modules else { return }
        modules = reordered
        if isClientMode {
            Task {
                await performRemoteMutation { client in
                    try await client.reorderModules(ids: ids)
                }
            }
            return
        }
        registerLocalChange()
        do {
            try persistModules()
            statusMessage = "已调整模块优先级，正在重新合并"
            scheduleCombinedRebuild()
        } catch {
            presentedError = "保存模块顺序失败：\(error.localizedDescription)"
        }
    }

    func deleteModule(id: UUID) async {
        if isClientMode {
            await performRemoteMutation { client in
                try await client.deleteModule(id: id)
            }
            return
        }
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        registerLocalChange()
        let module = modules.remove(at: index)
        try? await removeExportedIndividualFiles(
            moduleID: module.id,
            outputFileName: module.outputFileName
        )
        try? await fileStore.removeComponent(id: id)
        try? await fileStore.removeAssets(id: id)
        try? await iconStore.removeIcon(for: id)
        try? persistModules()
        selectedModuleID = modules.first?.id
        await rebuildCombinedFromCache()
        statusMessage = "已删除 \(module.name)，总模块已重新合并"
    }

    func updateAll() async {
        if isClientMode {
            await performRemoteMutation { client in
                try await client.updateAll()
            }
            return
        }
        pendingModuleUpdateIDs.removeAll()
        automaticUpdateTask?.cancel()
        await runSynchronization(limitingTo: nil)
    }

    func updateModules(ids: [UUID]) async {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return }
        if isClientMode {
            await updateAll()
            return
        }
        await runSynchronization(limitingTo: Set(uniqueIDs))
    }

    private func runSynchronization(limitingTo moduleIDs: Set<UUID>?) async {
        synchronizationTask?.cancel()
        combinedRebuildTask?.cancel()
        automaticPublishTask?.cancel()
        let requestID = UUID()
        synchronizationRequestID = requestID
        statusMessage = synchronizationInProgressMessage
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.synchronizationRequestID == requestID else { return }
            while self.isWorking, !Task.isCancelled, self.synchronizationRequestID == requestID {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, self.synchronizationRequestID == requestID else { return }
            await self.performSynchronization(limitingTo: moduleIDs)
        }
        synchronizationTask = task
        await task.value
    }

    private func performSynchronization(limitingTo moduleIDs: Set<UUID>? = nil) async {
        let synchronizationModules = modules.filter {
            shouldSynchronizeModule($0) && (moduleIDs?.contains($0.id) ?? true)
        }
        guard let workToken = beginWork() else { return }
        guard !synchronizationModules.isEmpty else {
            endWork(workToken)
            statusMessage = "已是最新。"
            return
        }
        automaticPublishTask?.cancel()
        let updateGeneration = localChangeGeneration
        synchronizationCompletedCount = 0
        synchronizationTotalCount = synchronizationModules.count
        synchronizingModuleID = nil
        defer {
            synchronizingModuleID = nil
            endWork(workToken)
        }

        let missingEngine = !(await engineStore.hasScript(named: "Rewrite-Parser.js"))
        if settings.automaticallyUpdateScriptHub || missingEngine {
            await refreshScriptHubInternal(updatesStatus: false)
        }
        guard updateGeneration == localChangeGeneration, !Task.isCancelled else {
            return
        }

        var components: [(RelayModule, String)] = []
        var failures = 0
        var missingCache: [String] = []
        var synchronizationErrors: [String] = []
        var newHistory: [UpdateHistoryEntry] = []

        for moduleValue in synchronizationModules {
            var module = moduleValue
            let startedAt = Date.now
            var revisionSnapshot: SourceRevisionSnapshot?
            synchronizingModuleID = module.id
            setState(id: module.id, state: .updating, error: nil)
            do {
                let hasCache = await fileStore.hasComponent(id: module.id)
                let sourceURL = URL(string: module.sourceURL)
                let nativeModule = sourceURL.map { module.sourceFormat.isNativeSurgeModule(for: $0) } ?? false
                let engineChanged = !nativeModule && module.conversionEngineRevision != upstreamState.revision
                if hasCache {
                    do {
                        let revision = try await sourceRevisionService.check(module)
                        switch revision {
                        case let .unchanged(snapshot):
                            revisionSnapshot = snapshot
                            if !engineChanged {
                                module.sourceETag = snapshot.etag
                                module.sourceLastModified = snapshot.lastModified
                                module.sourceContentHash = snapshot.contentHash
                                module.sourceCheckedAt = snapshot.checkedAt
                                module.state = .current
                                module.lastError = nil
                                replace(module)
                                let cached = try await fileStore.readComponent(id: module.id)
                                let materialized = await processingWorker.materialize(
                                    cached,
                                    overrides: module.argumentOverrides,
                                    policyOverrides: module.policyOverrides,
                                    customRules: module.customRules,
                                    customMitM: module.customMitM
                                )
                                if module.isEnabled {
                                    components.append((module, materialized))
                                }
                                newHistory.append(UpdateHistoryEntry(
                                    moduleID: module.id,
                                    moduleName: module.name,
                                    outcome: .unchanged,
                                    duration: Date.now.timeIntervalSince(startedAt),
                                    message: "来源内容没有变化"
                                ))
                                synchronizationCompletedCount += 1
                                await Task.yield()
                                continue
                            }
                        case let .changed(snapshot):
                            revisionSnapshot = snapshot
                        }
                    } catch {
                        // A failed lightweight check must not prevent the normal conversion path.
                    }
                }
                let result = try await scriptHubClient.convert(
                    module: module,
                    github: settings.github.isConfigured ? settings.github : nil
                )
                guard updateGeneration == localChangeGeneration, !Task.isCancelled,
                      let currentIndex = modules.firstIndex(where: { $0.id == module.id }),
                      shouldSynchronizeModule(modules[currentIndex]) else {
                    return
                }
                try await fileStore.replaceAssets(result.assets, id: module.id)
                try await fileStore.writeComponent(result.content, id: module.id)
                let effectiveContent = try await fileStore.readComponent(id: module.id)
                guard updateGeneration == localChangeGeneration, !Task.isCancelled,
                      let latestIndex = modules.firstIndex(where: { $0.id == module.id }),
                      shouldSynchronizeModule(modules[latestIndex]) else {
                    return
                }
                module = modules[latestIndex]
                if let revisionSnapshot {
                    module.sourceETag = revisionSnapshot.etag
                    module.sourceLastModified = revisionSnapshot.lastModified
                    module.sourceContentHash = revisionSnapshot.contentHash
                    module.sourceCheckedAt = revisionSnapshot.checkedAt
                } else {
                    module.sourceCheckedAt = .now
                }
                module.conversionEngineRevision = nativeModule ? nil : upstreamState.revision
                let convertedContent = try await fileStore.readConvertedComponent(id: module.id)
                if await fileStore.hasOverride(id: module.id) {
                    let materialized = await processingWorker.materialize(
                        convertedContent,
                        overrides: module.argumentOverrides,
                        policyOverrides: module.policyOverrides,
                        customRules: module.customRules,
                        customMitM: module.customMitM
                    )
                    try? await fileStore.writeComponentOverride(materialized, id: module.id)
                    module.overrideBaseHash = Data(convertedContent.utf8).sha256String
                    module.hasOverrideConflict = false
                } else {
                    module.hasOverrideConflict = false
                }
                let detectedIcon = await processingWorker.iconURL(
                    in: effectiveContent,
                    relativeTo: module.sourceURL
                )
                module.iconURL = detectedIcon?.absoluteString
                module.detectedSourceFormat = detectedFormat(for: module.sourceFormat, source: module.sourceURL)
                if let customStr = module.customIconURL, let customURL = URL(string: customStr) {
                    try? await iconStore.cacheIcon(from: customURL, for: module.id, force: true)
                } else if let detectedIcon {
                    try? await iconStore.cacheIcon(from: detectedIcon, for: module.id, force: true)
                } else {
                    try? await iconStore.removeIcon(for: module.id)
                }
                let nextContentHash = await processingWorker.contentFingerprint(
                    of: effectiveContent,
                    assets: result.assets
                )
                let moduleContentChanged = module.contentHash != nextContentHash
                module.contentHash = nextContentHash
                module.lastUpdatedAt = .now
                module.state = .current
                module.lastError = nil
                replace(module)
                newHistory.append(UpdateHistoryEntry(
                    moduleID: module.id,
                    moduleName: module.name,
                    outcome: .updated,
                    duration: Date.now.timeIntervalSince(startedAt),
                    message: module.hasOverrideConflict ? "上游已更新，本地编辑需要确认" : "转换完成",
                    contentChanged: moduleContentChanged
                ))
                let materialized = await processingWorker.materialize(
                    effectiveContent,
                    overrides: module.argumentOverrides
                )
                if module.isEnabled {
                    components.append((module, materialized))
                }
            } catch {
                guard updateGeneration == localChangeGeneration, !Task.isCancelled else {
                    return
                }
                failures += 1
                synchronizationErrors.append("\(module.name)：\(error.localizedDescription)")
                setState(id: module.id, state: .failed, error: error.localizedDescription)
                if let cached = try? await fileStore.readComponent(id: module.id) {
                    let current = modules.first(where: { $0.id == module.id }) ?? module
                    let materialized = await processingWorker.materialize(
                        cached,
                        overrides: current.argumentOverrides
                    )
                    if current.isEnabled {
                        components.append((current, materialized))
                    }
                    newHistory.append(UpdateHistoryEntry(
                        moduleID: module.id,
                        moduleName: module.name,
                        outcome: .cachedAfterFailure,
                        duration: Date.now.timeIntervalSince(startedAt),
                        message: diagnosticDescription(for: error),
                        usedCache: true
                    ))
                } else {
                    if module.isEnabled {
                        missingCache.append(module.name)
                    }
                    newHistory.append(UpdateHistoryEntry(
                        moduleID: module.id,
                        moduleName: module.name,
                        outcome: .failed,
                        duration: Date.now.timeIntervalSince(startedAt),
                        message: diagnosticDescription(for: error)
                    ))
                }
            }
            synchronizationCompletedCount += 1
            await Task.yield()
        }
        recordHistory(newHistory)
        try? persistModules()

        guard updateGeneration == localChangeGeneration, !Task.isCancelled else {
            return
        }

        guard missingCache.isEmpty else {
            setSynchronizationFailure("\(missingCache.joined(separator: "、")) 尚无可用缓存")
            presentedError = "以下来源首次转换失败，因此没有覆盖当前总模块：\n\(missingCache.joined(separator: "\n"))"
            return
        }

        do {
            let success = await rebuildCombinedFromCache()
            guard updateGeneration == localChangeGeneration, !Task.isCancelled else {
                return
            }
            if success, settings.storageMode == .gitHub {
                _ = try await publishAllInternal()
            }
            if failures == 0 {
                statusMessage = "已是最新。"
            } else {
                setSynchronizationFailure(synchronizationErrors.first ?? "\(failures) 个来源更新错误")
            }
        } catch {
            guard !Task.isCancelled else { return }
            setSynchronizationFailure(error.localizedDescription)
            presentedError = "同步失败：\(error.localizedDescription)"
        }
    }

    private var synchronizationInProgressMessage: String {
        settings.storageMode == .gitHub ? "正在同步到 Github…" : "正在同步到 iCloud…"
    }

    private func setSynchronizationFailure(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuated = trimmed.hasSuffix("。") || trimmed.hasSuffix(".") ? trimmed : trimmed + "。"
        statusMessage = "同步失败，\(punctuated)"
    }

    func update(moduleID: UUID) async {
        await updateModules(ids: [moduleID])
    }

    /// Queue a background conversion for one module without blocking the UI or
    /// re-checking every other source. Further edits coalesce into the same pass.
    private func scheduleModuleUpdate(id: UUID) {
        pendingModuleUpdateIDs.insert(id)
        kickPendingModuleUpdates()
    }

    private func kickPendingModuleUpdates() {
        automaticUpdateTask?.cancel()
        automaticUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            while self.isWorking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            let toUpdate = self.pendingModuleUpdateIDs
            guard !toUpdate.isEmpty else { return }
            let generationBefore = self.localChangeGeneration
            await self.updateModules(ids: Array(toUpdate))
            if self.localChangeGeneration == generationBefore {
                self.pendingModuleUpdateIDs.subtract(toUpdate)
            }
            if !self.pendingModuleUpdateIDs.isEmpty {
                self.kickPendingModuleUpdates()
            }
        }
    }

    private func scheduleAutomaticPublish() {
        guard settings.storageMode == .gitHub, settings.automaticallyPublish, settings.github.isConfigured, !githubToken.isEmpty else { return }
        automaticPublishTask?.cancel()
        automaticPublishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled, let self else { return }
            while self.isWorking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled,
                  self.settings.storageMode == .gitHub,
                  self.settings.automaticallyPublish,
                  self.settings.github.isConfigured,
                  !self.githubToken.isEmpty else { return }
            guard let workToken = self.beginWork() else { return }
            self.statusMessage = "正在同步到 Github…"
            defer { self.endWork(workToken) }
            do {
                let report = try await self.publishAllInternal()
                guard !Task.isCancelled else { return }
                self.statusMessage = "已是最新。"
                if let commit = report.commitSHA {
                    self.recordHistory([UpdateHistoryEntry(
                        moduleName: "GitHub",
                        outcome: .published,
                        duration: 0,
                        message: "原子提交 \(commit.prefix(8))"
                    )])
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.setSynchronizationFailure(error.localizedDescription)
                self.presentedError = "GitHub 自动同步失败：\(error.localizedDescription)"
            }
        }
    }

    func refreshScriptHub(showProgress: Bool = true) async {
        if isClientMode {
            await performRemoteMutation { client in
                try await client.refreshScriptHub()
            }
            return
        }
        guard !isWorking || !showProgress else { return }
        let workToken = showProgress ? beginWork() : nil
        guard !showProgress || workToken != nil else { return }
        await refreshScriptHubInternal(updatesStatus: true)
        if let workToken { endWork(workToken) }
    }

    private func refreshScriptHubInternal(updatesStatus: Bool) async {
        if updatesStatus { statusMessage = "正在更新 App 内置 Script Hub 引擎…" }
        do {
            let result = try await upstreamService.fetchManagedModule(
                from: settings.scriptHubModuleURL,
                previousRevision: upstreamState.revision
            )
            let missing = !(await engineStore.hasScript(named: "Rewrite-Parser.js"))
            if result.changed || missing {
                try await engineStore.save(scripts: result.scripts)
                upstreamState.lastUpdatedAt = .now
            }
            upstreamState.revision = result.revision
            upstreamState.lastCheckedAt = .now
            upstreamState.lastError = nil
            PersistenceStore.saveUpstreamState(upstreamState)
            if updatesStatus {
                statusMessage = result.changed ? "内置 Script Hub 引擎已更新至 \(result.revision)" : "内置 Script Hub 引擎已是最新"
            }
        } catch {
            upstreamState.lastCheckedAt = .now
            upstreamState.lastError = error.localizedDescription
            PersistenceStore.saveUpstreamState(upstreamState)
            let hasCache = await engineStore.hasScript(named: "Rewrite-Parser.js")
            if updatesStatus {
                statusMessage = hasCache ? "上游检查失败，继续使用 App 内缓存引擎" : "内置转换引擎尚不可用"
            }
        }
    }

    func testGitHub(showProgress: Bool = true) async {
        if isClientMode {
            let repository = "https://github.com/\(settings.github.owner)/\(settings.github.repository)"
            await performRemoteMutation { client in
                try await client.testSyncSettings(
                    storageMode: settings.storageMode.rawValue,
                    githubRepository: repository,
                    githubToken: githubToken,
                    githubPublicBaseURL: settings.github.publicBaseURL
                )
            }
            return
        }
        guard !isWorking || !showProgress else { return }
        let workToken = showProgress ? beginWork() : nil
        guard !showProgress || workToken != nil else { return }
        defer { if let workToken { endWork(workToken) } }
        do {
            try await validateGitHubDestination(publishCurrentModule: false)
            saveSettings()
            statusMessage = "GitHub 私有仓库与 Cloudflare 发布链路验证成功"
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func validateGitHubDestination(publishCurrentModule: Bool = true) async throws {
        githubToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.github.isConfigured else { throw RelayError.githubNotConfigured }
        guard !githubToken.isEmpty else { throw RelayError.githubTokenMissing }
        guard settings.github.hasValidCloudflarePublicBaseURL else {
            throw RelayError.cloudflareNotConfigured
        }

        let isPrivate = try await githubClient.test(settings: settings.github, token: githubToken)
        guard isPrivate else { throw RelayError.githubRepositoryMustBePrivate }
        settings.github.repositoryIsPrivate = true

        if publishCurrentModule, await fileStore.hasCombined() {
            _ = try await publishAllInternal()
        } else {
            try await verifyCloudflareEndpoint()
        }
    }

    private func verifyCloudflareEndpoint() async throws {
        let value = settings.github.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value) else { throw RelayError.cloudflareNotConfigured }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<500).contains(status) else {
            throw RelayError.httpFailure(status: status, message: "Cloudflare Worker 地址不可用。")
        }
    }

    private func verifyCloudflarePublishedModule(expected: Data, platform: RelayPlatform) async throws {
        let fileName = platformFileName(for: platform)
        guard let url = settings.github.publicURL(for: fileName) else {
            throw RelayError.cloudflareNotConfigured
        }

        for attempt in 0..<4 {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), data == expected { return }
            if attempt < 3 { try await Task.sleep(for: .seconds(1)) }
        }
        throw RelayError.invalidOutput("Cloudflare 尚未返回刚发布的 \(platform.rawValue) 汇总模块，本地文件已保留。")
    }

    func publishAll() async {
        guard !isWorking else { return }
        automaticPublishTask?.cancel()
        guard let workToken = beginWork() else { return }
        statusMessage = "正在同步到 Github…"
        defer { endWork(workToken) }
        do {
            _ = try await publishAllInternal()
            statusMessage = "已是最新。"
        } catch {
            setSynchronizationFailure(error.localizedDescription)
            presentedError = error.localizedDescription
        }
    }

    private func publishAllInternal() async throws -> PublishReport {
        try Task.checkCancellation()
        guard settings.github.hasValidCloudflarePublicBaseURL else {
            throw RelayError.cloudflareNotConfigured
        }
        var files: [PublishFile] = []
        var verificationSteps: [(data: Data, platform: RelayPlatform)] = []
        let enabledPlats = settings.enabledPlatforms
        for platform in enabledPlats {
            let fileName = platformFileName(for: platform)
            let data = try await fileStore.readCombined(platform: platform)
            files.append(PublishFile(name: fileName, data: data))
            verificationSteps.append((data, platform))
        }
        for module in modules {
            try Task.checkCancellation()
            guard let content = try? await fileStore.readComponent(id: module.id) else { continue }
            let materialized = await processingWorker.materialize(
                content,
                overrides: module.argumentOverrides,
                policyOverrides: module.policyOverrides,
                customRules: module.customRules,
                customMitM: module.customMitM
            )
            let namedContent = await processingWorker.applyingDisplayName(module.name, to: materialized)
            let individualFileName = individualICloudFileName(for: module.outputFileName)
            let legacyFileName = FilenameSanitizer.sgmoduleName(from: module.outputFileName)
            let publishContent = Self.surgeRelayCategorizedModuleContent(namedContent)
            files.append(PublishFile(
                name: individualFileName,
                data: Data(publishContent.utf8),
                legacyNames: legacyFileName == individualFileName ? [] : [legacyFileName]
            ))
        }
        let assets = try await fileStore.generatedAssetFiles()
        let report = try await githubClient.publish(
            files: files + assets,
            settings: settings.github,
            token: githubToken
        )
        if settings.github.repositoryIsPrivate != true {
            settings.github.repositoryIsPrivate = true
            saveSettings()
        }
        for step in verificationSteps {
            try await verifyCloudflarePublishedModule(expected: step.data, platform: step.platform)
        }
        return report
    }

    private func scheduleCombinedRebuild() {
        synchronizationTask?.cancel()
        combinedRebuildTask?.cancel()
        automaticPublishTask?.cancel()
        let willSynchronize = settings.storageMode == .local || settings.automaticallyPublish
        if willSynchronize { statusMessage = synchronizationInProgressMessage }
        combinedRebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            while self.isWorking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            let rebuilt = await self.rebuildCombinedFromCache()
            guard !Task.isCancelled else { return }
            if rebuilt, self.settings.storageMode == .local {
                self.statusMessage = "已是最新。"
            }
        }
    }

    @discardableResult
    private func rebuildCombinedFromCache() async -> Bool {
        let rebuildGeneration = localChangeGeneration
        let enabledPlats = settings.enabledPlatforms

        if enabledPlats.isEmpty {
            try? await fileStore.removeCombined()
            if settings.storageMode == .local {
                for platform in RelayPlatform.allCases {
                    try? await fileStore.removeExportedCombined(
                        fromDirectory: settings.localModuleDirectory,
                        fileName: platformFileName(for: platform)
                    )
                }
                try? await syncIndividualICloudExports()
            }
            return true
        }

        var allSucceeded = true

        for platform in enabledPlats {
            let platformModules = settings.modules(for: platform, globalModules: modules)
            let enabledModules = platformModules.filter(\.isEnabled)
            
            guard !enabledModules.isEmpty else {
                try? await fileStore.removeCombined(platform: platform)
                if settings.storageMode == .local {
                    try? await fileStore.removeExportedCombined(
                        fromDirectory: settings.localModuleDirectory,
                        fileName: platformFileName(for: platform)
                    )
                }
                continue
            }

            var components: [(RelayModule, String)] = []
            for module in enabledModules {
                guard let content = try? await fileStore.readComponent(id: module.id) else {
                    allSucceeded = false
                    continue
                }
                let materialized = await processingWorker.materialize(
                    content,
                    overrides: module.argumentOverrides
                )
                components.append((module, materialized))
            }

            do {
                try await writeCombinedModule(components, platform: platform)
            } catch {
                presentedError = "\(platform.rawValue) 自动合并失败：\(error.localizedDescription)"
                setSynchronizationFailure(error.localizedDescription)
                allSucceeded = false
            }
        }

        // Clean up disabled platforms
        for platform in RelayPlatform.allCases where !enabledPlats.contains(platform) {
            try? await fileStore.removeCombined(platform: platform)
            if settings.storageMode == .local {
                try? await fileStore.removeExportedCombined(
                    fromDirectory: settings.localModuleDirectory,
                    fileName: platformFileName(for: platform)
                )
            }
        }

        if settings.storageMode == .local {
            try? await syncIndividualICloudExports()
        }

        guard rebuildGeneration == localChangeGeneration else {
            return await rebuildCombinedFromCache()
        }

        scheduleAutomaticPublish()
        return allSucceeded
    }

    private func writeCombinedModule(_ components: [(RelayModule, String)], platform: RelayPlatform) async throws {
        let merged = try await processingWorker.merge(
            components,
            platform: platform,
            iconURL: nil,
            engineRevision: upstreamState.revision
        )
        try await fileStore.writeCombined(merged, platform: platform)
        if settings.storageMode == .local {
            try await fileStore.exportCombined(
                merged,
                toDirectory: settings.localModuleDirectory,
                fileName: platformFileName(for: platform)
            )
        }
    }

    private func refreshModuleMetadataFromCache() async {
        var changed = false
        for moduleValue in modules {
            guard let content = try? await fileStore.readComponent(id: moduleValue.id) else { continue }
            var module = moduleValue
            if await fileStore.hasOverride(id: module.id), module.overrideBaseHash == nil,
               let converted = try? await fileStore.readConvertedComponent(id: module.id) {
                module.overrideBaseHash = Data(converted.utf8).sha256String
                changed = true
            }
            let detectedIcon = await processingWorker.iconURL(in: content, relativeTo: module.sourceURL)
            let value = detectedIcon?.absoluteString
            let iconChanged = module.iconURL != value
            if iconChanged {
                module.iconURL = value
            }
            let resolvedFormat = detectedFormat(for: module.sourceFormat, source: module.sourceURL)
            let formatChanged = module.detectedSourceFormat != resolvedFormat
            if formatChanged { module.detectedSourceFormat = resolvedFormat }
            if iconChanged || formatChanged {
                replace(module)
                changed = true
            }
            if let customStr = module.customIconURL, let customURL = URL(string: customStr) {
                try? await iconStore.cacheIcon(from: customURL, for: module.id, force: iconChanged)
            } else if let detectedIcon {
                try? await iconStore.cacheIcon(from: detectedIcon, for: module.id, force: iconChanged)
            } else {
                try? await iconStore.removeIcon(for: module.id)
            }
        }
        if changed { try? persistModules() }
    }

    private func shouldSynchronizeModule(_ module: RelayModule) -> Bool {
        module.isEnabled || (settings.storageMode == .local && module.exportsIndividualModuleToICloud)
    }

    private func exportIndividualICloudModule(_ module: RelayModule) async throws {
        let content = try await fileStore.readComponent(id: module.id)
        let materialized = await processingWorker.materialize(
            content,
            overrides: module.argumentOverrides,
            policyOverrides: module.policyOverrides,
            customRules: module.customRules,
            customMitM: module.customMitM
        )
        let namedContent = await processingWorker.applyingDisplayName(module.name, to: materialized)
        let exportContent = Self.surgeRelayCategorizedModuleContent(namedContent)
        try await fileStore.exportIndividual(
            exportContent,
            moduleID: module.id,
            toDirectory: settings.localModuleDirectory,
            fileName: individualICloudFileName(for: module.outputFileName)
        )
        let legacyFileName = FilenameSanitizer.sgmoduleName(from: module.outputFileName)
        if legacyFileName != individualICloudFileName(for: module.outputFileName) {
            try await fileStore.removeExportedIndividual(
                fromDirectory: settings.localModuleDirectory,
                fileName: legacyFileName,
                moduleID: module.id
            )
        }
    }

    private func syncIndividualICloudExports() async throws {
        guard settings.storageMode == .local else { return }
        var disabledMissingOutputs = false
        for index in modules.indices {
            let module = modules[index]
            if module.exportsIndividualModuleToICloud {
                guard await fileStore.hasComponent(id: module.id) else { continue }
                let exists = await fileStore.hasExportedIndividual(
                    inDirectory: settings.localModuleDirectory,
                    fileName: individualICloudFileName(for: module.outputFileName),
                    moduleID: module.id
                )
                let hasLegacyOutput = await fileStore.hasExportedIndividual(
                    inDirectory: settings.localModuleDirectory,
                    fileName: FilenameSanitizer.sgmoduleName(from: module.outputFileName),
                    moduleID: module.id
                )
                guard exists || hasLegacyOutput || individualOutputMutationsInProgress.contains(module.id) else {
                    modules[index].exportsIndividualModuleToICloud = false
                    disabledMissingOutputs = true
                    continue
                }
                try await exportIndividualICloudModule(module)
            } else {
                try await removeExportedIndividualFiles(
                    moduleID: module.id,
                    outputFileName: module.outputFileName
                )
            }
        }
        if disabledMissingOutputs { try persistModules() }
    }

    private func removeAllExportedIndividualModules() async {
        var changed = false
        for index in modules.indices {
            let module = modules[index]
            try? await removeExportedIndividualFiles(
                moduleID: module.id,
                outputFileName: module.outputFileName
            )
            if modules[index].exportsIndividualModuleToICloud {
                modules[index].exportsIndividualModuleToICloud = false
                changed = true
            }
        }
        if changed { try? persistModules() }
    }

    private func individualICloudFileName(for outputFileName: String) -> String {
        FilenameSanitizer.individualRelayName(from: outputFileName)
    }

    nonisolated static func surgeRelayCategorizedModuleContent(_ content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        let name = lines.first { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("#!name=") }
        let desc = lines.first { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("#!desc=") }
        lines.removeAll {
            let lower = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return lower.hasPrefix("#!name=") || lower.hasPrefix("#!desc=") || lower.hasPrefix("#!category=")
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        var header = [name, desc].compactMap { $0 }
        header.append("#!category=Surge Relay")
        return (header + [body]).filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
    }

    private func removeExportedIndividualFiles(moduleID: UUID, outputFileName: String) async throws {
        let targetFileName = individualICloudFileName(for: outputFileName)
        try await fileStore.removeExportedIndividual(
            fromDirectory: settings.localModuleDirectory,
            fileName: targetFileName,
            moduleID: moduleID
        )
        let legacyFileName = FilenameSanitizer.sgmoduleName(from: outputFileName)
        if legacyFileName != targetFileName {
            try await fileStore.removeExportedIndividual(
                fromDirectory: settings.localModuleDirectory,
                fileName: legacyFileName,
                moduleID: moduleID
            )
        }
    }

    private func restartIndividualOutputMonitor() {
        individualOutputMonitorTask?.cancel()
        guard settings.storageMode == .local else { return }
        individualOutputMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.reconcileIndividualICloudOutputs()
            }
        }
    }

    private func reconcileIndividualICloudOutputs() async {
        guard settings.storageMode == .local else { return }
        var removedNames: [String] = []
        for index in modules.indices
        where modules[index].exportsIndividualModuleToICloud
            && !individualOutputMutationsInProgress.contains(modules[index].id) {
            let module = modules[index]
            let targetExists = await fileStore.hasExportedIndividual(
                inDirectory: settings.localModuleDirectory,
                fileName: individualICloudFileName(for: module.outputFileName),
                moduleID: module.id
            )
            if targetExists { continue }

            let legacyExists = await fileStore.hasExportedIndividual(
                inDirectory: settings.localModuleDirectory,
                fileName: module.outputFileName,
                moduleID: module.id
            )
            if legacyExists, await fileStore.hasComponent(id: module.id) {
                do {
                    try await exportIndividualICloudModule(module)
                    continue
                } catch {
                    presentedError = error.localizedDescription
                    continue
                }
            }

            modules[index].exportsIndividualModuleToICloud = false
            removedNames.append(module.name)
        }
        guard !removedNames.isEmpty else { return }
        try? persistModules()
        statusMessage = removedNames.count == 1
            ? "检测到独立模块已删除，已关闭 \(removedNames[0]) 的 iCloud 输出"
            : "检测到独立模块已删除，已关闭 \(removedNames.count) 个 iCloud 输出"
    }

    var enabledPlatforms: [RelayPlatform] {
        settings.enabledPlatforms
    }

    func platformFileName(for platform: RelayPlatform) -> String {
        let cleanName = FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName)
        if platform == .ios {
            return cleanName
        }
        let base = FilenameSanitizer.baseName(from: settings.combinedModuleFileName)
        return "\(base)-\(platform.rawValue).sgmodule"
    }

    func combinedRawURL(for platform: RelayPlatform) -> URL? {
        settings.publishedURL(for: platformFileName(for: platform))
    }

    func combinedLocalFileURL(for platform: RelayPlatform) -> URL? {
        settings.localCombinedModuleURL(for: platform)
    }

    var webManagementURL: URL? {
        guard deviceMode == .server, settings.webServerEnabled else { return nil }
        var host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if !host.contains(".") { host += ".local" }
        return URL(string: "http://\(host):\(settings.webServerPort)/")
    }

    func rawURL(for module: RelayModule) -> URL? {
        settings.publishedURL(for: individualICloudFileName(for: module.outputFileName))
    }

    func rawComponentContent(id: UUID) async throws -> String {
        try await fileStore.readComponent(id: id)
    }

    func previewContent(for module: RelayModule) async throws -> String {
        if isClientMode {
            return try await remoteClient().previewContent(moduleID: module.id)
        }
        let content = try await fileStore.readComponent(id: module.id)
        let materialized = await processingWorker.materialize(
            content,
            overrides: module.argumentOverrides,
            policyOverrides: module.policyOverrides,
            customRules: module.customRules,
            customMitM: module.customMitM
        )
        return ModuleMetadataParser.stripWarningHeader(materialized)
    }

    func hasPreviewContent(for module: RelayModule) async -> Bool {
        if isClientMode {
            return (try? await previewContent(for: module)) != nil
        }
        return await fileStore.hasComponent(id: module.id)
    }

    func hasCombinedPreviewContent(platform: RelayPlatform) async -> Bool {
        if isClientMode {
            return (try? await combinedPreviewContent(platform: platform)) != nil
        }
        return await fileStore.hasCombined(platform: platform)
    }

    func moduleArgumentInfo(for module: RelayModule) async -> ModuleArgumentInfo {
        if isClientMode {
            guard let payload = try? await remoteClient().moduleArguments(moduleID: module.id) else {
                return ModuleArgumentInfo()
            }
            return ModuleArgumentInfo(
                definitions: payload.arguments.map {
                    ModuleArgumentDefinition(key: $0.key, defaultValue: $0.defaultValue)
                },
                helpText: payload.help
            )
        }
        guard let content = try? await fileStore.readConvertedComponent(id: module.id) else {
            return ModuleArgumentInfo()
        }
        return await processingWorker.argumentInfo(in: content)
    }

    func setModuleArgument(moduleID: UUID, key: String, value: String, defaultValue: String) {
        setModuleArguments(
            moduleID: moduleID,
            values: [key: value],
            defaultValues: [key: defaultValue]
        )
    }

    func setModuleArguments(
        moduleID: UUID,
        values: [String: String],
        defaultValues: [String: String]
    ) {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }) else { return }
        var nextOverrides = modules[index].argumentOverrides
        for (key, defaultValue) in defaultValues {
            guard let value = values[key] else { continue }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized == defaultValue {
                nextOverrides.removeValue(forKey: key)
            } else {
                nextOverrides[key] = normalized
            }
        }
        guard modules[index].argumentOverrides != nextOverrides else { return }
        modules[index].argumentOverrides = nextOverrides
        if isClientMode {
            Task {
                await performRemoteMutation { client in
                    try await client.setModuleArguments(id: moduleID, values: values)
                }
            }
            return
        }
        registerLocalChange()
        try? persistModules()
        statusMessage = "已更新 \(modules[index].name) 的模块参数"
        scheduleCombinedRebuild()
    }

    func resetModuleArguments(moduleID: UUID) {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }),
              !modules[index].argumentOverrides.isEmpty else { return }
        modules[index].argumentOverrides.removeAll()
        if isClientMode {
            Task {
                await performRemoteMutation { client in
                    try await client.resetModuleArguments(id: moduleID)
                }
            }
            return
        }
        registerLocalChange()
        try? persistModules()
        statusMessage = "已恢复 \(modules[index].name) 的默认参数"
        scheduleCombinedRebuild()
    }

    func updateModuleScriptOverrides(moduleID: UUID, overrides: [String: String]) {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }) else { return }
        registerLocalChange()
        modules[index].argumentOverrides = overrides
        try? persistModules()
        statusMessage = "已更新 \(modules[index].name) 的脚本参数覆盖"
        scheduleCombinedRebuild()
    }

    func setModulePolicyOverrides(moduleID: UUID, overrides: [String: String]) {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }) else { return }
        registerLocalChange()
        modules[index].policyOverrides = overrides
        try? persistModules()
        statusMessage = "已更新 \(modules[index].name) 的策略别名映射"
        scheduleCombinedRebuild()
    }

    func setModuleCustomOverrides(moduleID: UUID, rules: [String], mitm: [String]) {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }) else { return }
        registerLocalChange()
        modules[index].customRules = rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        modules[index].customMitM = mitm.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        try? persistModules()
        statusMessage = "已更新 \(modules[index].name) 的自定义规则与解密主机名"
        scheduleCombinedRebuild()
    }

    func combinedPreviewContent(platform: RelayPlatform) async throws -> String {
        if isClientMode {
            return try await remoteClient().combinedPreviewContent(platform: platform)
        }
        let data = try await fileStore.readCombined(platform: platform)
        guard let content = String(data: data, encoding: .utf8) else {
            throw RelayError.invalidOutput("最终模块缓存不是有效的 UTF-8 文本。")
        }
        let materialized = await processingWorker.materialize(content, overrides: [:])
        return ModuleMetadataParser.stripWarningHeader(materialized)
    }



    func setPlatformModuleEnabled(platform: RelayPlatform, moduleID: UUID, enabled: Bool) {
        if isClientMode {
            var currentPlatformSettings = settings.platformSettings[platform.rawValue] ?? PlatformSettings()
            if enabled {
                currentPlatformSettings.disabledModules.remove(moduleID)
            } else {
                currentPlatformSettings.disabledModules.insert(moduleID)
            }
            settings.platformSettings[platform.rawValue] = currentPlatformSettings
            Task {
                await performRemoteMutation { client in
                    try await client.setPlatformModuleEnabled(
                        platform: platform,
                        moduleID: moduleID,
                        enabled: enabled
                    )
                }
            }
            return
        }
        var currentPlatformSettings = settings.platformSettings[platform.rawValue] ?? PlatformSettings()
        if enabled {
            currentPlatformSettings.disabledModules.remove(moduleID)
        } else {
            currentPlatformSettings.disabledModules.insert(moduleID)
        }
        settings.platformSettings[platform.rawValue] = currentPlatformSettings
        saveSettings()
        
        statusMessage = enabled ? "已启用 \(platform.rawValue) 平台下的模块，即将重新合并" : "已停用 \(platform.rawValue) 平台下的模块，正在重新合并"
        scheduleCombinedRebuild()
    }

    func setAllPlatformModulesEnabled(platform: RelayPlatform, enabled: Bool) {
        var currentPlatformSettings = settings.platformSettings[platform.rawValue] ?? PlatformSettings()
        if enabled {
            currentPlatformSettings.disabledModules.removeAll()
        } else {
            currentPlatformSettings.disabledModules = Set(modules.map { $0.id })
        }
        settings.platformSettings[platform.rawValue] = currentPlatformSettings
        if isClientMode {
            Task {
                await performRemoteMutation { client in
                    try await client.setAllPlatformModulesEnabled(platform: platform, enabled: enabled)
                }
            }
            return
        }
        saveSettings()
        
        statusMessage = enabled ? "已启用所有平台模块，即将重新合并" : "已停用所有平台模块，正在重新合并"
        scheduleCombinedRebuild()
    }

    func setPlatformEnabled(platform: RelayPlatform, isEnabled: Bool) {
        let isNew = settings.platformSettings[platform.rawValue] == nil
        var currentSettings = settings.platformSettings[platform.rawValue] ?? PlatformSettings()
        currentSettings.isEnabled = isEnabled
        if isNew {
            currentSettings.disabledModules = Set(modules.map { $0.id })
        }
        settings.platformSettings[platform.rawValue] = currentSettings
        if !isEnabled, selectedModuleID == platform.selectionID {
            selectedModuleID = settings.enabledPlatforms.first?.selectionID ?? modules.first?.id
        }
        if isClientMode {
            saveSettings()
            return
        }
        saveSettings()
        
        Task {
            await rebuildCombinedFromCache()
        }
    }

    func savePreviewContent(_ content: String, for module: RelayModule) async throws {
        if isClientMode {
            try await remoteClient().savePreviewContent(moduleID: module.id, content: content)
            await refreshRemoteState()
            return
        }
        guard !isWorking else { throw RelayError.invalidOutput("当前正在更新，请稍后再写入。") }
        let namedContent = await processingWorker.applyingDisplayName(module.name, to: content)
        if let current = try? await fileStore.readComponent(id: module.id), current == namedContent {
            statusMessage = "内容没有变化"
            return
        }
        guard let workToken = beginWork() else { return }
        defer { endWork(workToken) }
        registerLocalChange()
        try await fileStore.writeComponentOverride(namedContent, id: module.id)
        if let index = modules.firstIndex(where: { $0.id == module.id }) {
            let original = (try? await fileStore.readConvertedComponent(id: module.id)) ?? ""
            let extracted = ModuleMetadataParser.extractOverrides(original: original, edited: namedContent)
            modules[index].argumentOverrides = extracted.argumentOverrides
            modules[index].policyOverrides = extracted.policyOverrides
            modules[index].customRules = extracted.customRules
            modules[index].customMitM = extracted.customMitM
            
            modules[index].overrideBaseHash = Data(original.utf8).sha256String
            modules[index].hasOverrideConflict = false
        }
        await rebuildCombinedFromCache()
        try persistModules()
        statusMessage = settings.automaticallyPublish ? "已写入 \(module.name)，等待合并发布" : "已写入 \(module.name)"
    }

    func restorePreviewContent(for module: RelayModule) async throws -> String {
        if isClientMode {
            let content = try await remoteClient().restorePreviewContent(moduleID: module.id)
            await refreshRemoteState()
            return content
        }
        guard !isWorking else { throw RelayError.invalidOutput("当前正在更新，请稍后再恢复。") }
        guard let workToken = beginWork() else {
            throw RelayError.invalidOutput("当前正在更新，请稍后再恢复。")
        }
        defer { endWork(workToken) }
        registerLocalChange()
        let content = try await fileStore.restoreComponent(id: module.id)
        if let index = modules.firstIndex(where: { $0.id == module.id }) {
            modules[index].overrideBaseHash = nil
            modules[index].hasOverrideConflict = false
            try? persistModules()
        }
        await rebuildCombinedFromCache()
        statusMessage = settings.automaticallyPublish
            ? "已恢复 \(module.name) 的转换结果，等待合并发布"
            : "已恢复 \(module.name) 的转换结果"
        let materialized = await processingWorker.materialize(
            content,
            overrides: module.argumentOverrides,
            policyOverrides: module.policyOverrides,
            customRules: module.customRules,
            customMitM: module.customMitM
        )
        return ModuleMetadataParser.stripWarningHeader(materialized)
    }

    func acceptOverrideConflict(moduleID: UUID) async {
        if isClientMode {
            await performRemoteMutation { client in
                try await client.acceptOverrideConflict(id: moduleID)
            }
            return
        }
        guard let index = modules.firstIndex(where: { $0.id == moduleID }),
              let converted = try? await fileStore.readConvertedComponent(id: moduleID) else { return }
        modules[index].overrideBaseHash = Data(converted.utf8).sha256String
        modules[index].hasOverrideConflict = false
        try? persistModules()
        statusMessage = "已保留 \(modules[index].name) 的本地编辑"
    }

    func convertedPreviewContent(for module: RelayModule) async throws -> String {
        let content = try await fileStore.readConvertedComponent(id: module.id)
        return await processingWorker.materialize(
            content,
            overrides: module.argumentOverrides,
            policyOverrides: module.policyOverrides,
            customRules: module.customRules,
            customMitM: module.customMitM
        )
    }

    func diagnosticsData() throws -> Data {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let report = DiagnosticReport(
            generatedAt: .now,
            appVersion: version,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            engineRevision: upstreamState.revision,
            storageMode: settings.storageMode == .gitHub ? "GitHub" : "Local",
            githubRepository: "\(settings.github.owner)/\(settings.github.repository)",
            webServerEnabled: settings.webServerEnabled,
            webServerPort: settings.webServerPort,
            modules: modules.map {
                DiagnosticModuleSnapshot(
                    id: $0.id,
                    name: $0.name,
                    sourceURL: redactedSourceURL($0.sourceURL),
                    enabled: $0.isEnabled,
                    state: $0.state.rawValue,
                    lastUpdatedAt: $0.lastUpdatedAt,
                    sourceCheckedAt: $0.sourceCheckedAt,
                    lastError: $0.lastError,
                    hasOverrideConflict: $0.hasOverrideConflict
                )
            },
            history: updateHistory
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    func clearUpdateHistory() {
        if isClientMode {
            updateHistory.removeAll()
            Task {
                await performRemoteMutation { client in
                    try await client.clearDiagnostics()
                }
            }
            return
        }
        updateHistory.removeAll()
        PersistenceStore.saveUpdateHistory([])
    }

    func openModule(_ id: UUID) {
        guard modules.contains(where: { $0.id == id }) else { return }
        selectedModuleID = id
        navigationRequest = .modules
    }

    private func replace(_ module: RelayModule) {
        guard let index = modules.firstIndex(where: { $0.id == module.id }) else { return }
        modules[index] = module
    }

    private func setState(id: UUID, state: ModuleUpdateState, error: String?) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[index].state = state
        modules[index].lastError = error
    }

    private func persistModules() throws {
        try PersistenceStore.saveModules(modules)
    }

    private func registerLocalChange() {
        localChangeGeneration &+= 1
        automaticPublishTask?.cancel()
    }

    private func recordHistory(_ entries: [UpdateHistoryEntry]) {
        guard !entries.isEmpty else { return }
        updateHistory = Array((entries.reversed() + updateHistory).prefix(200))
        PersistenceStore.saveUpdateHistory(updateHistory)
    }

    private func diagnosticDescription(for error: Error) -> String {
        if let relayError = error as? RelayError {
            return relayError.diagnosticDescription
        }
        return error.localizedDescription
    }

    private func redactedSourceURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return value }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? value
    }

    private func detectedFormat(for format: ModuleSourceFormat, source: String) -> ModuleSourceFormat? {
        guard format == .automatic, let url = URL(string: source) else { return nil }
        return format.resolvedFormat(for: url)
    }

    private func uniqueOutputFileName(for draft: ModuleDraft, source: String, excluding excludedID: UUID? = nil) -> String {
        let preferred = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? FilenameSanitizer.suggestedName(from: source)
            : draft.name
        let normalized = FilenameSanitizer.sgmoduleName(from: preferred)
        let unavailable = Set(modules.compactMap { module -> String? in
            module.id == excludedID ? nil : module.outputFileName.lowercased()
        } + [FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName).lowercased()])
        guard unavailable.contains(normalized.lowercased()) else { return normalized }

        let base = FilenameSanitizer.baseName(from: normalized)
        var suffix = 2
        while unavailable.contains("\(base)-\(suffix).sgmodule".lowercased()) { suffix += 1 }
        return "\(base)-\(suffix).sgmodule"
    }

    private static func normalizedModuleNaming(_ modules: [RelayModule], combinedFileName: String) -> [RelayModule] {
        var used = Set<String>()
        let combined = FilenameSanitizer.sgmoduleName(from: combinedFileName)
        return modules.map { value in
            var module = value
            let preferred = FilenameSanitizer.sgmoduleName(from: module.name)
            let base = FilenameSanitizer.baseName(from: preferred)
            var candidate = preferred
            var suffix = 2
            while used.contains(candidate.lowercased()) || candidate.caseInsensitiveCompare(combined) == .orderedSame {
                candidate = "\(base)-\(suffix).sgmodule"
                suffix += 1
            }
            used.insert(candidate.lowercased())
            module.outputFileName = candidate
            return module
        }
    }
}

struct IconSearchResult: Codable, Sendable {
    let name: String
    let url: String
    let source: String
}

extension AppModel {
    func updateModuleCustomIcon(id: UUID, customIconURL: String?, source: CustomIconSource = .manual) async throws {
        if isClientMode {
            try await remoteClient().updateModuleCustomIcon(id: id, url: customIconURL)
            await refreshRemoteState()
            return
        }
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        
        registerLocalChange()
        modules[index].customIconURL = customIconURL
        modules[index].customIconSource = customIconURL == nil ? .manual : source
        try persistModules()
        
        let effectiveURL = customIconURL ?? modules[index].iconURL
        if let effectiveURL, let url = URL(string: effectiveURL) {
            try? await iconStore.cacheIcon(from: url, for: id, force: true)
        } else {
            try? await iconStore.removeIcon(for: id)
        }
        
        scheduleCombinedRebuild()
        statusMessage = "已更新 \(modules[index].name) 的自定义图标"
    }
    
    func updatePlatformCustomIcon(platform: RelayPlatform, customIconURL: String?, source: CustomIconSource = .manual) async throws {
        throw RelayError.invalidOutput("汇总模块不支持自定义图标。")
    }
    
    nonisolated static func cleanSearchQuery(_ query: String) -> String {
        var cleaned = query
        cleaned = cleaned.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "去广告", with: "")
        cleaned = cleaned.replacingOccurrences(of: "净化", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func searchIcons(query: String, region: String? = nil) async -> [IconSearchResult] {
        let cleaned = AppModel.cleanSearchQuery(query)
        let searchRegion = region ?? settings.iconSearchRegion
        if isClientMode {
            return (try? await remoteClient().searchIcons(query: cleaned, region: searchRegion)) ?? []
        }

        var results: [IconSearchResult] = []
        if !cleaned.isEmpty, let encodedQuery = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let urlStr = "https://itunes.apple.com/search?term=\(encodedQuery)&entity=software&limit=15&country=\(searchRegion)"
            if let url = URL(string: urlStr),
               let (data, _) = try? await URLSession.shared.data(from: url) {
                 struct iTunesResponse: Codable {
                     struct iTunesResult: Codable {
                         let trackName: String
                         let artworkUrl100: String
                     }
                     let results: [iTunesResult]
                 }
                 if let response = try? JSONDecoder().decode(iTunesResponse.self, from: data) {
                     for app in response.results {
                         results.append(IconSearchResult(name: app.trackName, url: app.artworkUrl100, source: "App Store"))
                     }
                 }
            }
        }
        
        return results
    }
}
