import Foundation

@MainActor
enum WebManagementAPI {
    static func eventPayload(model: AppModel) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(statePayload(model: model)) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func response(for request: WebHTTPRequest, model: AppModel) async -> WebHTTPResponse {
        if !request.path.hasPrefix("/api/") {
            return assetResponse(for: request.path)
        }

        do {
            switch (request.method, request.path) {
            case ("GET", "/api/state"):
                return .json(statePayload(model: model))
            case ("GET", "/api/settings"):
                return .json(settingsPayload(model: model))
            case ("PUT", "/api/settings/general"):
                let mutation = try request.decodeBody(WebGeneralSettingsMutation.self)
                applyGeneralSettings(mutation, to: model)
                return .json(ActionPayload(ok: true, message: "通用设置已保存。"))
            case ("PUT", "/api/settings/web"):
                let mutation = try request.decodeBody(WebServerSettingsMutation.self)
                try applyWebSettings(mutation, to: model)
                return .json(ActionPayload(ok: true, message: "Web 管理设置已保存。"))
            case ("PUT", "/api/settings/script-hub"):
                let mutation = try request.decodeBody(WebScriptHubSettingsMutation.self)
                applyScriptHubSettings(mutation, to: model)
                return .json(ActionPayload(ok: true, message: "Script Hub 设置已保存。"))
            case ("POST", "/api/settings/script-hub/refresh"):
                Task { await model.refreshScriptHub(showProgress: false) }
                return .json(ActionPayload(ok: true, message: "已开始检查 Script Hub 更新。"), status: 202, reason: "Accepted")
            case ("PUT", "/api/settings/sync"):
                let mutation = try request.decodeBody(WebSyncSettingsMutation.self)
                try await applySyncSettings(mutation, to: model)
                return .json(ActionPayload(ok: true, message: "同步设置已保存。"))
            case ("POST", "/api/settings/sync/test"):
                let mutation = try request.decodeBody(WebSyncSettingsMutation.self)
                try await testSyncSettings(mutation, on: model)
                return .json(ActionPayload(ok: true, message: "GitHub 与 Cloudflare 验证成功。"))
            case ("POST", "/api/settings/diagnostics/clear"):
                model.clearUpdateHistory()
                return .json(ActionPayload(ok: true, message: "诊断历史已清除。"))
            case ("GET", "/api/appstore/search"):
                let query = request.query["q"] ?? ""
                let region = request.query["region"]
                let results = await model.searchIcons(query: query, region: region)
                return .json(results)
            case ("GET", "/api/settings/diagnostics/export"):
                return WebHTTPResponse(
                    contentType: "application/json; charset=utf-8",
                    headers: ["Content-Disposition": "attachment; filename=Surge-Relay-Diagnostics.json"],
                    body: try model.diagnosticsData()
                )
            case ("POST", "/api/update-all"):
                Task { await model.updateAll() }
                return .json(ActionPayload(ok: true, message: "已开始更新全部模块。"), status: 202, reason: "Accepted")
            case ("POST", "/api/modules"):
                let mutation = try request.decodeBody(WebModuleMutation.self)
                try await model.addModule(from: mutation.draft())
                return .json(ActionPayload(ok: true, message: model.statusMessage), status: 201, reason: "Created")
            case ("POST", "/api/modules/reorder"):
                let mutation = try request.decodeBody(WebReorderMutation.self)
                let ids = mutation.ids.compactMap(UUID.init(uuidString:))
                model.reorderModules(ids: ids)
                return .json(ActionPayload(ok: true, message: model.statusMessage))
            case ("POST", "/api/source/name"):
                let payload = try request.decodeBody(WebSourceNameRequest.self)
                guard let url = URL(string: payload.url),
                      ["http", "https"].contains(url.scheme?.lowercased()) else {
                    throw WebAPIError.invalidSourceURL
                }
                var sourceRequest = URLRequest(url: url)
                sourceRequest.setValue("Surge Relay", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: sourceRequest)
                let fallback = FilenameSanitizer.suggestedName(from: payload.url)
                    .replacingOccurrences(of: "-", with: " ")
                let name = String(data: data, encoding: .utf8)
                    .flatMap { ModuleMetadataParser.displayName(in: $0) } ?? fallback
                return .json(WebSourceNamePayload(name: name))
            case ("GET", "/api/combined/preview"):
                let platformStr = request.query["platform"] ?? ""
                let platform = RelayPlatform(rawValue: platformStr) ?? .ios
                return .text(try await model.combinedPreviewContent(platform: platform))
            case _ where request.path.hasPrefix("/api/combined/platforms/"):
                let pathComponents = request.path.split(separator: "/").map(String.init)
                if pathComponents.count == 7,
                   pathComponents[0] == "api",
                   pathComponents[1] == "combined",
                   pathComponents[2] == "platforms",
                   let platform = RelayPlatform(rawValue: pathComponents[3]),
                   pathComponents[4] == "modules",
                   let moduleID = UUID(uuidString: pathComponents[5]),
                   pathComponents[6] == "enabled",
                   request.method == "POST" {
                    let payload = try request.decodeBody(WebEnabledRequest.self)
                    model.setPlatformModuleEnabled(platform: platform, moduleID: moduleID, enabled: payload.enabled)
                    return .json(ActionPayload(ok: true, message: model.statusMessage))
                } else if pathComponents.count == 6,
                          pathComponents[0] == "api",
                          pathComponents[1] == "combined",
                          pathComponents[2] == "platforms",
                          let platform = RelayPlatform(rawValue: pathComponents[3]),
                          pathComponents[4] == "modules",
                          pathComponents[5] == "enabled",
                          request.method == "POST" {
                    let payload = try request.decodeBody(WebEnabledRequest.self)
                    model.setAllPlatformModulesEnabled(platform: platform, enabled: payload.enabled)
                    return .json(ActionPayload(ok: true, message: model.statusMessage))
                } else {
                    throw WebAPIError.moduleNotFound
                }
            default:
                return try await moduleResponse(for: request, model: model)
            }
        } catch let error as WebAPIError {
            return .error(status: error.status, message: error.localizedDescription)
        } catch let error as RelayError {
            let status = switch error {
            case .duplicateSourceURL: 409
            default: 400
            }
            return .error(status: status, message: error.localizedDescription)
        } catch {
            return .error(status: 400, message: error.localizedDescription)
        }
    }

    private static func settingsPayload(model: AppModel) -> WebSettingsPayload {
        let webURL = model.webManagementURL?.absoluteString
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        var platformsDict: [String: Bool] = [:]
        for platform in RelayPlatform.allCases {
            platformsDict[platform.rawValue] = model.settings.platformSettings[platform.rawValue]?.isEnabled ?? false
        }
        return WebSettingsPayload(
            refreshIntervalMinutes: model.settings.refreshIntervalMinutes,
            launchAtLogin: model.settings.launchAtLogin,
            automaticallyPublish: model.settings.automaticallyPublish,
            iconSearchRegion: model.settings.iconSearchRegion,
            webServerEnabled: model.settings.webServerEnabled,
            webServerPort: model.settings.webServerPort,
            webServerState: webServerStateTitle(model.webServerState),
            webManagementURL: webURL,
            scriptHubModuleURL: model.settings.scriptHubModuleURL,
            automaticallyUpdateScriptHub: model.settings.automaticallyUpdateScriptHub,
            scriptHubRevision: model.upstreamState.revision,
            scriptHubLastCheckedAt: model.upstreamState.lastCheckedAt,
            scriptHubLastError: model.upstreamState.lastError,
            storageMode: model.settings.storageMode.rawValue,
            githubRepository: "https://github.com/\(model.settings.github.owner)/\(model.settings.github.repository)",
            githubTokenConfigured: !model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            githubPublicBaseURL: model.settings.github.publicBaseURL,
            githubRepositoryIsPrivate: model.settings.github.repositoryIsPrivate,
            updateHistory: Array(model.updateHistory.prefix(20)),
            appVersion: version,
            platforms: platformsDict
        )
    }

    private static func webServerStateTitle(_ state: WebServerRuntimeState) -> String {
        switch state {
        case .stopped: "已停止"
        case .starting: "正在启动"
        case .restarting: "正在恢复"
        case .running: "运行中"
        case .failed(let message): "失败：\(message)"
        }
    }

    private static func applyGeneralSettings(_ mutation: WebGeneralSettingsMutation, to model: AppModel) {
        if let refreshIntervalMinutes = mutation.refreshIntervalMinutes {
            model.settings.refreshIntervalMinutes = max(0, refreshIntervalMinutes)
            model.restartScheduler()
        }
        if let automaticallyPublish = mutation.automaticallyPublish {
            model.settings.automaticallyPublish = automaticallyPublish
        }
        if let iconSearchRegion = mutation.iconSearchRegion {
            model.settings.iconSearchRegion = iconSearchRegion
        }
        if let platforms = mutation.platforms {
            for (platformRaw, isEnabled) in platforms {
                if let platform = RelayPlatform(rawValue: platformRaw) {
                    model.setPlatformEnabled(platform: platform, isEnabled: isEnabled)
                }
            }
        }
        if let launchAtLogin = mutation.launchAtLogin {
            model.setLaunchAtLogin(launchAtLogin)
        } else {
            model.saveSettings()
        }
    }

    private static func applyWebSettings(_ mutation: WebServerSettingsMutation, to model: AppModel) throws {
        if let webServerEnabled = mutation.webServerEnabled {
            model.settings.webServerEnabled = webServerEnabled
        }
        if let webServerPort = mutation.webServerPort {
            guard (1...65_535).contains(webServerPort) else { throw WebAPIError.invalidPort }
            model.settings.webServerPort = webServerPort
        }
        model.applyWebServerSettings()
    }

    private static func applyScriptHubSettings(_ mutation: WebScriptHubSettingsMutation, to model: AppModel) {
        if let scriptHubModuleURL = mutation.scriptHubModuleURL {
            model.settings.scriptHubModuleURL = scriptHubModuleURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let automaticallyUpdateScriptHub = mutation.automaticallyUpdateScriptHub {
            model.settings.automaticallyUpdateScriptHub = automaticallyUpdateScriptHub
        }
        model.saveSettings()
    }

    private static func testSyncSettings(_ mutation: WebSyncSettingsMutation, on model: AppModel) async throws {
        try applyGitHubDraft(mutation, to: model)
        model.presentedError = nil
        await model.testGitHub(showProgress: false)
        if let error = model.presentedError {
            model.presentedError = nil
            throw RelayError.invalidOutput(error)
        }
    }

    private static func applySyncSettings(_ mutation: WebSyncSettingsMutation, to model: AppModel) async throws {
        if mutation.storageMode == StorageMode.gitHub.rawValue || model.settings.storageMode == .gitHub {
            try applyGitHubDraft(mutation, to: model)
        }
        if let rawMode = mutation.storageMode {
            guard let mode = StorageMode(rawValue: rawMode) else { throw WebAPIError.invalidStorageMode }
            model.presentedError = nil
            let switched = await model.setStorageMode(mode)
            if !switched {
                let message = model.presentedError ?? "无法切换同步方式。"
                model.presentedError = nil
                throw RelayError.invalidOutput(message)
            }
        } else {
            model.saveSettings()
        }
    }

    private static func applyGitHubDraft(_ mutation: WebSyncSettingsMutation, to model: AppModel) throws {
        if let githubRepository = mutation.githubRepository {
            guard let parsed = parseGitHubRepository(githubRepository) else {
                throw RelayError.invalidOutput("请输入有效的 GitHub 仓库地址，例如 https://github.com/owner/repository。")
            }
            model.settings.github.owner = parsed.owner
            model.settings.github.repository = parsed.repository
        }
        if let githubPublicBaseURL = mutation.githubPublicBaseURL {
            model.settings.github.publicBaseURL = githubPublicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let githubToken = mutation.githubToken {
            model.githubToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
            model.settings.githubToken = model.githubToken
        }
        if model.settings.github.branch.isEmpty { model.settings.github.branch = "main" }
        if model.settings.github.directory.isEmpty { model.settings.github.directory = "modules" }
        model.saveSettings()
    }

    private static func parseGitHubRepository(_ value: String) -> (owner: String, repository: String)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let owner = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = parts[1]
            .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repository.isEmpty else { return nil }
        return (owner, repository)
    }

    private static func moduleResponse(for request: WebHTTPRequest, model: AppModel) async throws -> WebHTTPResponse {
        let components = request.path.split(separator: "/").map(String.init)
        guard components.count >= 3, components[0] == "api", components[1] == "modules",
              let id = UUID(uuidString: components[2]),
              let module = model.modules.first(where: { $0.id == id }) else {
            throw WebAPIError.moduleNotFound
        }

        if components.count == 3 {
            switch request.method {
            case "PUT":
                let mutation = try request.decodeBody(WebModuleMutation.self)
                try await model.updateModule(id: id, from: mutation.draft(existing: module))
                return .json(ActionPayload(ok: true, message: model.statusMessage))
            case "DELETE":
                await model.deleteModule(id: id)
                return .json(ActionPayload(ok: true, message: model.statusMessage))
            default:
                throw WebAPIError.methodNotAllowed
            }
        }

        switch (request.method, components[3]) {
        case ("POST", "enabled"):
            let payload = try request.decodeBody(WebEnabledRequest.self)
            model.setModuleEnabled(id: id, enabled: payload.enabled)
            return .json(ActionPayload(ok: true, message: model.statusMessage))
        case ("POST", "individual-icloud-export"):
            let payload = try request.decodeBody(WebEnabledRequest.self)
            await model.setModuleIndividualICloudExport(id: id, enabled: payload.enabled)
            return .json(ActionPayload(ok: true, message: model.statusMessage))
        case ("POST", "update"):
            Task { await model.update(moduleID: id) }
            return .json(ActionPayload(ok: true, message: "已开始更新 \(module.name)。"), status: 202, reason: "Accepted")
        case ("GET", "preview"):
            return .text(try await model.previewContent(for: module))
        case ("PUT", "preview"):
            guard let content = String(data: request.body, encoding: .utf8) else {
                throw WebAPIError.invalidBody
            }
            try await model.savePreviewContent(content, for: module)
            return .json(ActionPayload(ok: true, message: model.statusMessage))
        case ("DELETE", "preview"):
            let restored = try await model.restorePreviewContent(for: module)
            return .text(restored)
        case ("POST", "override-conflict"):
            await model.acceptOverrideConflict(moduleID: id)
            return .json(ActionPayload(ok: true, message: model.statusMessage))
        case ("PUT", "custom-icon"):
            let payload = try request.decodeBody(WebURLRequestPayload.self)
            try await model.updateModuleCustomIcon(id: id, customIconURL: payload.url)
            return .json(ActionPayload(ok: true, message: "自定义图标已应用"))
        case ("DELETE", "custom-icon"):
            try await model.updateModuleCustomIcon(id: id, customIconURL: nil)
            return .json(ActionPayload(ok: true, message: "自定义图标已重置"))
        case ("GET", "overrides"):
            let content = (try? await model.rawComponentContent(id: module.id)) ?? ""
            let discovered = ModuleMetadataParser.discoverScriptArguments(in: content)
            let policies = ModuleMetadataParser.extractUniquePolicies(in: content)
            let discoveredPayload = discovered.map { arg in
                WebOverridesPayload.DiscoveredArg(
                    name: arg.name,
                    defaultValue: arg.defaultValue,
                    value: module.argumentOverrides[arg.name] ?? ""
                )
            }
            let payload = WebOverridesPayload(
                discoveredArguments: discoveredPayload,
                extractedPolicies: policies,
                policyOverrides: module.policyOverrides,
                customRules: module.customRules,
                customMitM: module.customMitM
            )
            return .json(payload)
        case ("PUT", "overrides"):
            let mutation = try request.decodeBody(WebOverridesMutation.self)
            model.updateModuleScriptOverrides(moduleID: id, overrides: mutation.scriptArgs)
            model.setModulePolicyOverrides(moduleID: id, overrides: mutation.policyOverrides)
            model.setModuleCustomOverrides(moduleID: id, rules: mutation.customRules, mitm: mutation.customMitM)
            return .json(ActionPayload(ok: true, message: model.statusMessage))
        case ("GET", "arguments"):
            let info = await model.moduleArgumentInfo(for: module)
            let values = info.definitions.map { definition in
                WebArgumentPayload(
                    key: definition.key,
                    defaultValue: definition.defaultValue,
                    value: module.argumentOverrides[definition.key] ?? definition.defaultValue
                )
            }
            return .json(WebArgumentsPayload(arguments: values, help: info.helpText))
        case ("PUT", "arguments"):
            let payload = try request.decodeBody(WebArgumentMutation.self)
            let info = await model.moduleArgumentInfo(for: module)
            let defaults = Dictionary(uniqueKeysWithValues: info.definitions.map {
                ($0.key, $0.defaultValue)
            })
            if let values = payload.values {
                guard !values.keys.contains(where: { defaults[$0] == nil }) else {
                    throw WebAPIError.invalidArgument
                }
                model.setModuleArguments(
                    moduleID: id,
                    values: values,
                    defaultValues: defaults
                )
            } else {
                guard let key = payload.key,
                      let value = payload.value,
                      let defaultValue = defaults[key] else {
                    throw WebAPIError.invalidArgument
                }
                model.setModuleArgument(
                    moduleID: id,
                    key: key,
                    value: value,
                    defaultValue: defaultValue
                )
            }
            return .json(ActionPayload(ok: true, message: model.statusMessage))
        case ("DELETE", "arguments"):
            model.resetModuleArguments(moduleID: id)
            return .json(ActionPayload(ok: true, message: model.statusMessage))
        case ("GET", "icon"):
            return iconResponse(for: module)
        default:
            throw WebAPIError.methodNotAllowed
        }
    }

    private static func statePayload(model: AppModel) -> WebStatePayload {
        let newestUpdate = model.modules.compactMap(\.lastUpdatedAt).max()
        let progress: Double? = if model.synchronizationTotalCount > 0 {
            min(
                max(Double(model.synchronizationCompletedCount) / Double(model.synchronizationTotalCount), 0),
                1
            )
        } else {
            nil
        }
        let platforms = RelayPlatform.allCases.map { platform in
            let settings = model.settings.platformSettings[platform.rawValue] ?? PlatformSettings()
            let resolvedModules = model.settings.modules(for: platform, globalModules: model.modules)
            let enabledModules = resolvedModules.filter(\.isEnabled).map { $0.id.uuidString.lowercased() }
            return WebPlatformPayload(
                id: platform.rawValue,
                displayName: platform.summaryDisplayName,
                isEnabled: settings.isEnabled,
                fileName: model.platformFileName(for: platform),
                iconURL: settings.customIconURL ?? defaultPlatformIconURL(for: platform),
                customIconURL: nil,
                subscriptionURL: model.settings.storageMode == .gitHub
                    ? model.combinedRawURL(for: platform)?.absoluteString
                    : nil,
                enabledModules: enabledModules
            )
        }
        return WebStatePayload(
            storageMode: model.settings.storageMode.rawValue,
            settings: settingsPayload(model: model),
            combined: WebCombinedPayload(
                name: "Surge Relay 汇总 (\(RelayPlatform.ios.summaryDisplayName))",
                fileName: model.platformFileName(for: .ios),
                sourceCount: model.modules.count,
                enabledCount: model.settings.modules(for: .ios, globalModules: model.modules).filter(\.isEnabled).count,
                lastUpdatedAt: newestUpdate,
                subscriptionURL: model.settings.storageMode == .gitHub
                    ? model.combinedRawURL(for: .ios)?.absoluteString
                    : nil
            ),
            modules: model.modules.map { module in
                WebModulePayload(
                    id: module.id.uuidString.lowercased(),
                    name: module.name,
                    sourceURL: module.sourceURL,
                    sourceFormat: module.sourceFormat.rawValue,
                    sourceFormatTitle: module.sourceFormatDisplayTitle,
                    outputFileName: module.outputFileName,
                    isEnabled: module.isEnabled,
                    exportsIndividualModuleToICloud: module.exportsIndividualModuleToICloud,
                    state: module.state.rawValue,
                    stateTitle: module.state.title,
                    lastUpdatedAt: module.lastUpdatedAt,
                    lastError: module.lastError,
                    iconURL: iconURL(for: module),
                    customIconURL: module.customIconURL,
                    customIconSource: module.customIconSource.rawValue,
                    publishedURL: model.rawURL(for: module)?.absoluteString,
                    advancedSummary: module.scriptHubOptions.configuredSummary,
                    hasOverrideConflict: module.hasOverrideConflict,
                    scriptHubOptions: module.scriptHubOptions,
                    policy: module.scriptHubOptions.policy,
                    includeKeywords: module.scriptHubOptions.includeKeywords,
                    excludeKeywords: module.scriptHubOptions.excludeKeywords,
                    mitmAdd: module.scriptHubOptions.mitmAdd,
                    mitmRemove: module.scriptHubOptions.mitmRemove,
                    noResolve: module.scriptHubOptions.noResolve,
                    enableJQ: module.scriptHubOptions.enableJQ,
                    argumentOverrides: module.argumentOverrides,
                    policyOverrides: module.policyOverrides,
                    customRules: module.customRules,
                    customMitM: module.customMitM,
                    detectedSourceFormat: module.detectedSourceFormat?.rawValue,
                    contentHash: module.contentHash
                )
            },
            activity: WebActivityPayload(
                isWorking: model.isWorking,
                status: model.statusMessage,
                progress: progress,
                currentModuleID: model.synchronizingModuleID?.uuidString.lowercased(),
                error: model.presentedError
            ),
            platforms: platforms
        )
    }

    private static func defaultPlatformIconURL(for platform: RelayPlatform) -> String {
        switch platform {
        case .ios:
            return "/summary-ios.png?v=2"
        case .macos:
            return "/summary-macos.png?v=2"
        case .visionos:
            return "/summary-visionos.png?v=2"
        case .tvos:
            return "/summary-tvos.png?v=2"
        }
    }

    private static func iconURL(for module: RelayModule) -> String? {
        if FileManager.default.fileExists(atPath: ModuleIconStore.cachedURL(for: module.id).path) {
            return "/api/modules/\(module.id.uuidString.lowercased())/icon"
        }
        return module.customIconURL ?? module.iconURL
    }

    private static func iconResponse(for module: RelayModule) -> WebHTTPResponse {
        let url = ModuleIconStore.cachedURL(for: module.id)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .error(status: 404, message: "没有可用的模块图标。")
        }
        return WebHTTPResponse(
            contentType: imageContentType(data),
            headers: ["Cache-Control": "private, max-age=3600"],
            body: data
        )
    }

    private static func imageContentType(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "image/webp" }
        return "application/octet-stream"
    }

    nonisolated static func assetResponse(for path: String) -> WebHTTPResponse {
        let relativePath = path == "/" ? "index.html" : String(path.drop(while: { $0 == "/" }))
        guard !relativePath.contains(".."), let resourceRoot = Bundle.main.resourceURL else {
            return .error(status: 404, message: "页面不存在。")
        }
        let bundledRoot = resourceRoot.appending(path: "WebResources", directoryHint: .isDirectory)
        let requestedURL = bundledRoot.appending(path: relativePath)
        let legacyFlattenedURL = resourceRoot.appending(path: URL(filePath: relativePath).lastPathComponent)
        let bundledIndexURL = bundledRoot.appending(path: "index.html")
        let legacyIndexURL = resourceRoot.appending(path: "index.html")
        let fileURL: URL
        if FileManager.default.fileExists(atPath: requestedURL.path) {
            fileURL = requestedURL
        } else if FileManager.default.fileExists(atPath: legacyFlattenedURL.path) {
            // Older project files copied WebResources into the bundle root.
            fileURL = legacyFlattenedURL
        } else if FileManager.default.fileExists(atPath: bundledIndexURL.path) {
            fileURL = bundledIndexURL
        } else {
            fileURL = legacyIndexURL
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return .error(status: 404, message: "Web 页面资源尚未安装。")
        }
        let contentType = switch fileURL.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "ico": "image/x-icon"
        case "webmanifest": "application/manifest+json; charset=utf-8"
        default: "application/octet-stream"
        }
        return WebHTTPResponse(
            contentType: contentType,
            headers: [
                "Cache-Control": "no-cache, must-revalidate",
                "Content-Security-Policy": "default-src 'self'; img-src 'self' data: https:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
            ],
            body: data
        )
    }
}

private struct WebStatePayload: Encodable {
    let storageMode: String
    let settings: WebSettingsPayload
    let combined: WebCombinedPayload
    let modules: [WebModulePayload]
    let activity: WebActivityPayload
    let platforms: [WebPlatformPayload]
}

private struct WebOverridesPayload: Encodable {
    struct DiscoveredArg: Encodable {
        let name: String
        let defaultValue: String
        let value: String
    }
    let discoveredArguments: [DiscoveredArg]
    let extractedPolicies: [String]
    let policyOverrides: [String: String]
    let customRules: [String]
    let customMitM: [String]
}

private struct WebOverridesMutation: Decodable {
    let scriptArgs: [String: String]
    let policyOverrides: [String: String]
    let customRules: [String]
    let customMitM: [String]
}

private struct WebPlatformPayload: Encodable {
    let id: String
    let displayName: String
    let isEnabled: Bool
    let fileName: String
    let iconURL: String
    let customIconURL: String?
    let subscriptionURL: String?
    let enabledModules: [String]
}

private struct WebCombinedPayload: Encodable {
    let name: String
    let fileName: String
    let sourceCount: Int
    let enabledCount: Int
    let lastUpdatedAt: Date?
    let subscriptionURL: String?
}

private struct WebModulePayload: Encodable {
    let id: String
    let name: String
    let sourceURL: String
    let sourceFormat: String
    let sourceFormatTitle: String
    let outputFileName: String
    let isEnabled: Bool
    let exportsIndividualModuleToICloud: Bool
    let state: String
    let stateTitle: String
    let lastUpdatedAt: Date?
    let lastError: String?
    let iconURL: String?
    let customIconURL: String?
    let customIconSource: String
    let publishedURL: String?
    let advancedSummary: String?
    let hasOverrideConflict: Bool
    let scriptHubOptions: ScriptHubOptions
    let policy: String
    let includeKeywords: String
    let excludeKeywords: String
    let mitmAdd: String
    let mitmRemove: String
    let noResolve: Bool
    let enableJQ: Bool
    let argumentOverrides: [String: String]
    let policyOverrides: [String: String]
    let customRules: [String]
    let customMitM: [String]
    let detectedSourceFormat: String?
    let contentHash: String?
}

private struct WebReorderMutation: Decodable {
    let ids: [String]
}

private struct WebSettingsPayload: Encodable {
    let refreshIntervalMinutes: Int
    let launchAtLogin: Bool
    let automaticallyPublish: Bool
    let iconSearchRegion: String
    let webServerEnabled: Bool
    let webServerPort: Int
    let webServerState: String
    let webManagementURL: String?
    let scriptHubModuleURL: String
    let automaticallyUpdateScriptHub: Bool
    let scriptHubRevision: String?
    let scriptHubLastCheckedAt: Date?
    let scriptHubLastError: String?
    let storageMode: String
    let githubRepository: String
    let githubTokenConfigured: Bool
    let githubPublicBaseURL: String
    let githubRepositoryIsPrivate: Bool?
    let updateHistory: [UpdateHistoryEntry]
    let appVersion: String
    let platforms: [String: Bool]
}

private struct WebGeneralSettingsMutation: Decodable {
    let refreshIntervalMinutes: Int?
    let launchAtLogin: Bool?
    let automaticallyPublish: Bool?
    let iconSearchRegion: String?
    let platforms: [String: Bool]?
}

private struct WebServerSettingsMutation: Decodable {
    let webServerEnabled: Bool?
    let webServerPort: Int?
}

private struct WebScriptHubSettingsMutation: Decodable {
    let scriptHubModuleURL: String?
    let automaticallyUpdateScriptHub: Bool?
}

private struct WebSyncSettingsMutation: Decodable {
    let storageMode: String?
    let githubRepository: String?
    let githubToken: String?
    let githubPublicBaseURL: String?
}

private struct WebActivityPayload: Encodable {
    let isWorking: Bool
    let status: String
    let progress: Double?
    let currentModuleID: String?
    let error: String?
}

private struct ActionPayload: Encodable {
    let ok: Bool
    let message: String
}

private struct WebEnabledRequest: Decodable {
    let enabled: Bool
}

private struct WebSourceNameRequest: Decodable {
    let url: String
}

private struct WebSourceNamePayload: Encodable {
    let name: String
}

private struct WebArgumentMutation: Decodable {
    let key: String?
    let value: String?
    let values: [String: String]?
}

private struct WebArgumentPayload: Encodable {
    let key: String
    let defaultValue: String
    let value: String
}

private struct WebArgumentsPayload: Encodable {
    let arguments: [WebArgumentPayload]
    let help: String?
}

private struct WebModuleMutation: Decodable {
    let name: String
    let sourceURL: String
    let sourceFormat: String?
    let isEnabled: Bool?
    let policy: String?
    let includeKeywords: String?
    let excludeKeywords: String?
    let mitmAdd: String?
    let mitmRemove: String?
    let noResolve: Bool?
    let enableJQ: Bool?
    let scriptHubOptions: ScriptHubOptions?

    func draft(existing: RelayModule? = nil) throws -> ModuleDraft {
        var draft = existing.map(ModuleDraft.init(module:)) ?? ModuleDraft()
        draft.name = name
        draft.sourceURL = sourceURL
        if let sourceFormat {
            guard let format = ModuleSourceFormat(rawValue: sourceFormat) else {
                throw WebAPIError.invalidFormat
            }
            draft.sourceFormat = format
        }
        if let isEnabled { draft.isEnabled = isEnabled }
        if let scriptHubOptions { draft.scriptHubOptions = scriptHubOptions }
        if let policy { draft.scriptHubOptions.policy = policy }
        if let includeKeywords { draft.scriptHubOptions.includeKeywords = includeKeywords }
        if let excludeKeywords { draft.scriptHubOptions.excludeKeywords = excludeKeywords }
        if let mitmAdd { draft.scriptHubOptions.mitmAdd = mitmAdd }
        if let mitmRemove { draft.scriptHubOptions.mitmRemove = mitmRemove }
        if let noResolve { draft.scriptHubOptions.noResolve = noResolve }
        if let enableJQ { draft.scriptHubOptions.enableJQ = enableJQ }
        return draft
    }
}

private enum WebAPIError: LocalizedError {
    case invalidModule
    case moduleNotFound
    case methodNotAllowed
    case invalidBody
    case invalidArgument
    case invalidFormat
    case invalidSourceURL
    case invalidPort
    case invalidStorageMode

    var status: Int {
        switch self {
        case .moduleNotFound: 404
        case .methodNotAllowed: 405
        default: 400
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidModule: "模块标识无效。"
        case .moduleNotFound: "找不到这个模块。"
        case .methodNotAllowed: "此处不支持该操作。"
        case .invalidBody: "请求内容不是有效的 UTF-8 文本。"
        case .invalidArgument: "找不到这个模块参数。"
        case .invalidFormat: "来源格式无效。"
        case .invalidSourceURL: "来源地址无效。"
        case .invalidPort: "端口必须在 1–65535 之间。"
        case .invalidStorageMode: "同步方式无效。"
        }
    }
}
