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
            case ("POST", "/api/update-all"):
                Task { await model.updateAll() }
                return .json(ActionPayload(ok: true, message: "已开始更新全部模块。"), status: 202, reason: "Accepted")
            case ("POST", "/api/modules"):
                let mutation = try request.decodeBody(WebModuleMutation.self)
                try model.addModule(from: mutation.draft())
                return .json(ActionPayload(ok: true, message: model.statusMessage), status: 201, reason: "Created")
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
                return .text(try await model.combinedPreviewContent())
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
                try model.updateModule(id: id, from: mutation.draft(existing: module))
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
            guard let definition = info.definitions.first(where: { $0.key == payload.key }) else {
                throw WebAPIError.invalidArgument
            }
            model.setModuleArgument(
                moduleID: id,
                key: payload.key,
                value: payload.value,
                defaultValue: definition.defaultValue
            )
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
        return WebStatePayload(
            combined: WebCombinedPayload(
                name: "Surge Relay 汇总",
                fileName: FilenameSanitizer.sgmoduleName(from: model.settings.combinedModuleFileName),
                sourceCount: model.modules.count,
                enabledCount: model.modules.filter(\.isEnabled).count,
                lastUpdatedAt: newestUpdate,
                subscriptionURL: model.combinedRawURL?.absoluteString ?? model.combinedLocalFileURL?.absoluteString
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
                    state: module.state.rawValue,
                    stateTitle: module.state.title,
                    lastUpdatedAt: module.lastUpdatedAt,
                    lastError: module.lastError,
                    iconURL: iconURL(for: module),
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
                    enableJQ: module.scriptHubOptions.enableJQ
                )
            },
            activity: WebActivityPayload(
                isWorking: model.isWorking,
                status: model.statusMessage,
                progress: progress,
                currentModuleID: model.synchronizingModuleID?.uuidString.lowercased(),
                error: model.presentedError
            )
        )
    }

    private static func iconURL(for module: RelayModule) -> String? {
        if FileManager.default.fileExists(atPath: ModuleIconStore.cachedURL(for: module.id).path) {
            return "/api/modules/\(module.id.uuidString.lowercased())/icon"
        }
        return module.iconURL
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
    let combined: WebCombinedPayload
    let modules: [WebModulePayload]
    let activity: WebActivityPayload
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
    let state: String
    let stateTitle: String
    let lastUpdatedAt: Date?
    let lastError: String?
    let iconURL: String?
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
    let key: String
    let value: String
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
        }
    }
}
