import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let combinedModuleSelectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var modules: [RelayModule]
    var settings: AppSettings
    var upstreamState: ScriptHubUpstreamState
    var selectedModuleID: UUID?
    var isWorking = false
    var statusMessage = "准备就绪"
    var presentedError: String?
    var githubToken: String
    var navigationRequest: SidebarDestination?
    /// Set to true to ask the main window to present the in-app settings sheet
    /// (used by the menu bar, the ⌘, command, and the toolbar gear button).
    var presentsSettings = false
    /// First-run setup presentation state.
    var presentsConfigurationWelcome = false
    var configurationWelcomeError: String?
    var configurationWelcomeLoadedExistingConfiguration = false
    var synchronizationCompletedCount = 0
    var synchronizationTotalCount = 0
    var synchronizingModuleID: UUID?
    var webServerState: WebServerRuntimeState = .stopped
    var updateHistory: [UpdateHistoryEntry]

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
    @ObservationIgnored private var combinedRebuildTask: Task<Void, Never>?
    @ObservationIgnored private var automaticUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var automaticPublishTask: Task<Void, Never>?
    @ObservationIgnored private var localChangeGeneration = 0
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var configurationExistedBeforeLaunch = false

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
        let loadedModules = Self.normalizedModuleNaming(
            PersistenceStore.loadModules(),
            combinedFileName: loadedSettings.combinedModuleFileName
        )
        modules = loadedModules
        settings = loadedSettings
        upstreamState = PersistenceStore.loadUpstreamState()
        updateHistory = PersistenceStore.loadUpdateHistory()
        githubToken = loadedSettings.githubToken
        selectedModuleID = Self.combinedModuleSelectionID
        PersistenceStore.saveSettings(loadedSettings)
        try? PersistenceStore.saveModules(loadedModules)
    }

    func start() async {
        guard !hasStarted else { return }
        if !PersistenceStore.hasCompletedInitialSetup {
            NSApp.activate(ignoringOtherApps: true)
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
            presentsConfigurationWelcome = true
            return
        }
        await startRuntime()
    }

    private func startRuntime() async {
        guard !hasStarted else { return }
        hasStarted = true
        applyWebServerSettings(persist: false)
        restartScheduler()
        if settings.storageMode == .gitHub {
            try? await fileStore.removeExportedCombined(
                fromDirectory: settings.localModuleDirectory,
                fileName: FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName)
            )
        }
        Task {
            do {
                try await fileStore.prepareStorage()
            } catch {
                presentedError = "无法初始化缓存目录：\(error.localizedDescription)"
            }
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
        settings.storageMode = storageMode
        saveSettings()
        PersistenceStore.markInitialSetupCompleted()
        presentsConfigurationWelcome = false
        await startRuntime()
        if storageMode == .local {
            await rebuildCombinedFromCache()
        } else {
            try? await fileStore.removeExportedCombined(
                fromDirectory: settings.localModuleDirectory,
                fileName: FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName)
            )
        }
        return true
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
        selectedModuleID = Self.combinedModuleSelectionID
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
        settings.githubToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settings.automaticallyPublish {
            automaticPublishTask?.cancel()
        }
        PersistenceStore.saveSettings(settings)
    }

    func saveGitHubToken() {
        githubToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.githubToken = githubToken
        PersistenceStore.saveSettings(settings)
        statusMessage = githubToken.isEmpty ? "GitHub Token 已从同步配置移除" : "GitHub Token 已保存到 iCloud 配置"
    }

    func applyWebServerSettings(persist: Bool = true) {
        guard (1...65_535).contains(settings.webServerPort),
              let port = UInt16(exactly: settings.webServerPort) else {
            webServerState = .failed("端口必须在 1–65535 之间。")
            return
        }
        if persist { saveSettings() }
        webServer.stop()
        guard settings.webServerEnabled else {
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
        } else {
            try? await fileStore.removeExportedCombined(
                fromDirectory: settings.localModuleDirectory,
                fileName: FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName)
            )
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
            saveSettings()
        } catch {
            settings.launchAtLogin = false
            presentedError = "无法更改登录启动设置：\(error.localizedDescription)"
        }
    }

    func restartScheduler() {
        schedulerTask?.cancel()
        guard settings.refreshIntervalMinutes > 0 else { return }
        let seconds = settings.refreshIntervalMinutes * 60
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.updateAll()
            }
        }
    }

    func addModule(from draft: ModuleDraft) throws {
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
        statusMessage = "已添加 \(module.name)，即将自动更新"
        scheduleAutomaticUpdate()
    }

    func updateModule(id: UUID, from draft: ModuleDraft) throws {
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
        _ = previousOutputFileName
        try persistModules()
        statusMessage = "已保存 \(modules[index].name)，即将自动更新"
        if modules[index].isEnabled {
            scheduleAutomaticUpdate()
        } else {
            scheduleCombinedRebuild()
        }
    }

    func setModuleEnabled(id: UUID, enabled: Bool) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        guard modules[index].isEnabled != enabled else { return }
        registerLocalChange()
        modules[index].isEnabled = enabled
        try? persistModules()
        statusMessage = enabled ? "已启用 \(modules[index].name)，即将自动更新" : "已停用 \(modules[index].name)，正在自动合并"
        if enabled {
            scheduleAutomaticUpdate()
        } else {
            scheduleCombinedRebuild()
        }
    }

    func moveModules(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let reordered = ModuleOrdering.moving(modules, fromOffsets: offsets, toOffset: destination)
        guard reordered != modules else { return }
        registerLocalChange()
        modules = reordered
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
        registerLocalChange()
        modules = reordered
        do {
            try persistModules()
            statusMessage = "已调整模块优先级，正在重新合并"
            scheduleCombinedRebuild()
        } catch {
            presentedError = "保存模块顺序失败：\(error.localizedDescription)"
        }
    }

    func deleteModule(id: UUID) async {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        registerLocalChange()
        let module = modules.remove(at: index)
        try? await fileStore.removeComponent(id: id)
        try? await fileStore.removeAssets(id: id)
        try? await iconStore.removeIcon(for: id)
        try? persistModules()
        selectedModuleID = modules.first?.id
        await rebuildCombinedFromCache()
        statusMessage = "已删除 \(module.name)，总模块已重新合并"
    }

    func updateAll() async {
        synchronizationTask?.cancel()
        combinedRebuildTask?.cancel()
        automaticPublishTask?.cancel()
        statusMessage = synchronizationInProgressMessage
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            while self.isWorking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            await self.performSynchronization()
        }
        synchronizationTask = task
        await task.value
    }

    private func performSynchronization() async {
        let enabledModules = modules.filter(\.isEnabled)
        guard !isWorking else { return }
        guard !enabledModules.isEmpty else {
            statusMessage = "已是最新。"
            return
        }
        automaticPublishTask?.cancel()
        let updateGeneration = localChangeGeneration
        isWorking = true
        synchronizationCompletedCount = 0
        synchronizationTotalCount = enabledModules.count
        synchronizingModuleID = nil
        defer {
            synchronizingModuleID = nil
            isWorking = false
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

        for moduleValue in enabledModules {
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
                                let materialized = await processingWorker.materialize(cached, overrides: module.argumentOverrides)
                                components.append((module, materialized))
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
                      modules[currentIndex].isEnabled else {
                    return
                }
                try await fileStore.replaceAssets(result.assets, id: module.id)
                try await fileStore.writeComponent(result.content, id: module.id)
                let effectiveContent = try await fileStore.readComponent(id: module.id)
                guard updateGeneration == localChangeGeneration, !Task.isCancelled,
                      let latestIndex = modules.firstIndex(where: { $0.id == module.id }),
                      modules[latestIndex].isEnabled else {
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
                if await fileStore.hasOverride(id: module.id),
                   let baseHash = module.overrideBaseHash {
                    module.hasOverrideConflict = baseHash != Data(convertedContent.utf8).sha256String
                } else {
                    module.hasOverrideConflict = false
                }
                let detectedIcon = await processingWorker.iconURL(
                    in: effectiveContent,
                    relativeTo: module.sourceURL
                )
                module.iconURL = detectedIcon?.absoluteString
                module.detectedSourceFormat = detectedFormat(for: module.sourceFormat, source: module.sourceURL)
                if let detectedIcon {
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
                components.append((module, materialized))
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
                    components.append((current, materialized))
                    newHistory.append(UpdateHistoryEntry(
                        moduleID: module.id,
                        moduleName: module.name,
                        outcome: .cachedAfterFailure,
                        duration: Date.now.timeIntervalSince(startedAt),
                        message: error.localizedDescription,
                        usedCache: true
                    ))
                } else {
                    missingCache.append(module.name)
                    newHistory.append(UpdateHistoryEntry(
                        moduleID: module.id,
                        moduleName: module.name,
                        outcome: .failed,
                        duration: Date.now.timeIntervalSince(startedAt),
                        message: error.localizedDescription
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
            try await writeCombinedModule(components)
            guard updateGeneration == localChangeGeneration, !Task.isCancelled else {
                return
            }
            if settings.storageMode == .gitHub {
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

    func update(moduleID _: UUID) async {
        // 单个来源改变也会影响同一份输出，因此始终安全地重建全部启用来源。
        await updateAll()
    }

    private func scheduleAutomaticUpdate() {
        automaticUpdateTask?.cancel()
        automaticUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            while self.isWorking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await self.updateAll()
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
            self.isWorking = true
            self.statusMessage = "正在同步到 Github…"
            defer { self.isWorking = false }
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
                self.presentedError = "GitHub 自动发布失败：\(error.localizedDescription)"
            }
        }
    }

    func refreshScriptHub(showProgress: Bool = true) async {
        guard !isWorking || !showProgress else { return }
        if showProgress { isWorking = true }
        await refreshScriptHubInternal(updatesStatus: true)
        if showProgress { isWorking = false }
    }

    private func refreshScriptHubInternal(updatesStatus: Bool) async {
        if updatesStatus { statusMessage = "正在更新 App 内置 Script-Hub 引擎…" }
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
                statusMessage = result.changed ? "内置 Script-Hub 引擎已更新至 \(result.revision)" : "内置 Script-Hub 引擎已是最新"
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
        guard !isWorking || !showProgress else { return }
        if showProgress { isWorking = true }
        defer { if showProgress { isWorking = false } }
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

    private func verifyCloudflarePublishedModule(expected: Data) async throws {
        let fileName = FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName)
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
        throw RelayError.invalidOutput("Cloudflare 尚未返回刚发布的汇总模块，本地文件已保留。")
    }

    func publishAll() async {
        guard !isWorking else { return }
        automaticPublishTask?.cancel()
        isWorking = true
        statusMessage = "正在同步到 Github…"
        defer { isWorking = false }
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
        let fileName = FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName)
        let data = try await fileStore.readCombined()
        var files = [PublishFile(name: fileName, data: data)]
        for module in modules {
            try Task.checkCancellation()
            guard let content = try? await fileStore.readComponent(id: module.id) else { continue }
            let materialized = await processingWorker.materialize(content, overrides: module.argumentOverrides)
            let namedContent = await processingWorker.applyingDisplayName(module.name, to: materialized)
            files.append(PublishFile(name: module.outputFileName, data: Data(namedContent.utf8)))
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
        try await verifyCloudflarePublishedModule(expected: data)
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
        let enabled = modules.filter(\.isEnabled)
        guard !enabled.isEmpty else {
            try? await fileStore.removeCombined()
            if settings.storageMode == .local {
                try? await fileStore.removeExportedCombined(
                    fromDirectory: settings.localModuleDirectory,
                    fileName: AppSettings.fixedCombinedModuleFileName
                )
            }
            return true
        }
        var components: [(RelayModule, String)] = []
        for module in enabled {
            guard let content = try? await fileStore.readComponent(id: module.id) else { return false }
            let materialized = await processingWorker.materialize(
                content,
                overrides: module.argumentOverrides
            )
            components.append((module, materialized))
        }
        do {
            try await writeCombinedModule(components)
            guard rebuildGeneration == localChangeGeneration else {
                return await rebuildCombinedFromCache()
            }
            scheduleAutomaticPublish()
            return true
        } catch {
            presentedError = "自动合并失败：\(error.localizedDescription)"
            setSynchronizationFailure(error.localizedDescription)
            return false
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
            if let detectedIcon {
                try? await iconStore.cacheIcon(from: detectedIcon, for: module.id, force: iconChanged)
            } else {
                try? await iconStore.removeIcon(for: module.id)
            }
        }
        if changed { try? persistModules() }
    }

    private func writeCombinedModule(_ components: [(RelayModule, String)]) async throws {
        let merged = try await processingWorker.merge(
            components,
            engineRevision: upstreamState.revision
        )
        try await fileStore.writeCombined(merged)
        if settings.storageMode == .local {
            try await fileStore.exportCombined(
                merged,
                toDirectory: settings.localModuleDirectory,
                fileName: FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName)
            )
        }
    }

    var combinedRawURL: URL? {
        settings.publishedURL(for: FilenameSanitizer.sgmoduleName(from: settings.combinedModuleFileName))
    }

    var combinedLocalFileURL: URL? {
        settings.localCombinedModuleURL
    }

    var webManagementURL: URL? {
        guard settings.webServerEnabled else { return nil }
        var host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if !host.contains(".") { host += ".local" }
        return URL(string: "http://\(host):\(settings.webServerPort)/")
    }

    func rawURL(for module: RelayModule) -> URL? {
        settings.publishedURL(for: module.outputFileName)
    }

    func previewContent(for module: RelayModule) async throws -> String {
        let content = try await fileStore.readComponent(id: module.id)
        return await processingWorker.materialize(content, overrides: module.argumentOverrides)
    }

    func hasPreviewContent(for module: RelayModule) async -> Bool {
        await fileStore.hasComponent(id: module.id)
    }

    func hasCombinedPreviewContent() async -> Bool {
        await fileStore.hasCombined()
    }

    func moduleArgumentInfo(for module: RelayModule) async -> ModuleArgumentInfo {
        guard let content = try? await fileStore.readConvertedComponent(id: module.id) else {
            return ModuleArgumentInfo()
        }
        return await processingWorker.argumentInfo(in: content)
    }

    func setModuleArgument(moduleID: UUID, key: String, value: String, defaultValue: String) {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }) else { return }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = modules[index].argumentOverrides[key]
        let nextStored: String? = normalized == defaultValue ? nil : normalized
        guard stored != nextStored else { return }
        registerLocalChange()
        if let nextStored {
            modules[index].argumentOverrides[key] = nextStored
        } else {
            modules[index].argumentOverrides.removeValue(forKey: key)
        }
        try? persistModules()
        statusMessage = "已更新 \(modules[index].name) 的模块参数"
        scheduleCombinedRebuild()
    }

    func resetModuleArguments(moduleID: UUID) {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }),
              !modules[index].argumentOverrides.isEmpty else { return }
        registerLocalChange()
        modules[index].argumentOverrides.removeAll()
        try? persistModules()
        statusMessage = "已恢复 \(modules[index].name) 的默认参数"
        scheduleCombinedRebuild()
    }

    func combinedPreviewContent() async throws -> String {
        let data = try await fileStore.readCombined()
        guard let content = String(data: data, encoding: .utf8) else {
            throw RelayError.invalidOutput("最终模块缓存不是有效的 UTF-8 文本。")
        }
        return await processingWorker.materialize(content, overrides: [:])
    }

    func savePreviewContent(_ content: String, for module: RelayModule) async throws {
        guard !isWorking else { throw RelayError.invalidOutput("当前正在更新，请稍后再写入。") }
        let namedContent = await processingWorker.applyingDisplayName(module.name, to: content)
        if let current = try? await fileStore.readComponent(id: module.id), current == namedContent {
            statusMessage = "内容没有变化"
            return
        }
        isWorking = true
        defer { isWorking = false }
        registerLocalChange()
        try await fileStore.writeComponentOverride(namedContent, id: module.id)
        if let index = modules.firstIndex(where: { $0.id == module.id }),
           let converted = try? await fileStore.readConvertedComponent(id: module.id) {
            modules[index].overrideBaseHash = Data(converted.utf8).sha256String
            modules[index].hasOverrideConflict = false
        }
        await rebuildCombinedFromCache()
        try persistModules()
        statusMessage = settings.automaticallyPublish ? "已写入 \(module.name)，等待合并发布" : "已写入 \(module.name)"
    }

    func restorePreviewContent(for module: RelayModule) async throws -> String {
        guard !isWorking else { throw RelayError.invalidOutput("当前正在更新，请稍后再恢复。") }
        isWorking = true
        defer { isWorking = false }
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
        return await processingWorker.materialize(content, overrides: module.argumentOverrides)
    }

    func acceptOverrideConflict(moduleID: UUID) async {
        guard let index = modules.firstIndex(where: { $0.id == moduleID }),
              let converted = try? await fileStore.readConvertedComponent(id: moduleID) else { return }
        modules[index].overrideBaseHash = Data(converted.utf8).sha256String
        modules[index].hasOverrideConflict = false
        try? persistModules()
        statusMessage = "已保留 \(modules[index].name) 的本地编辑"
    }

    func convertedPreviewContent(for module: RelayModule) async throws -> String {
        let content = try await fileStore.readConvertedComponent(id: module.id)
        return await processingWorker.materialize(content, overrides: module.argumentOverrides)
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
