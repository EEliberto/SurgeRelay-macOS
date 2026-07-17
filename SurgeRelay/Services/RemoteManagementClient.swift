import Foundation

/// HTTP client used by client-mode Macs to drive the server's management API
/// through Surge Ponte, so the native UI can mirror the server app.
struct RemoteManagementClient: Sendable {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    /// Dedicated session for long-lived SSE; resource timeout must not kill the stream.
    static let streamingSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 86400
        configuration.timeoutIntervalForResource = 0
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    static let sseStallTimeout: TimeInterval = 60

    let baseURL: URL

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    func fetchState() async throws -> RemoteStatePayload {
        try await get("api/state")
    }

    func fetchActivity() async throws -> RemoteActivityPayload {
        try await get("api/activity")
    }

    func updateAll() async throws {
        _ = try await postAction("api/update-all")
    }

    func refreshScriptHub() async throws {
        _ = try await postAction("api/settings/script-hub/refresh")
    }

    func addModule(_ draft: ModuleDraft) async throws -> String {
        try await sendJSON(
            "api/modules",
            method: "POST",
            body: RemoteModuleMutation(draft: draft),
            expectingStatus: 201
        ).message
    }

    func updateModule(id: UUID, draft: ModuleDraft) async throws -> String {
        try await sendJSON(
            "api/modules/\(id.uuidString.lowercased())",
            method: "PUT",
            body: RemoteModuleMutation(draft: draft)
        ).message
    }

    func deleteModule(id: UUID) async throws {
        _ = try await send("api/modules/\(id.uuidString.lowercased())", method: "DELETE")
    }

    func setModuleEnabled(id: UUID, enabled: Bool) async throws {
        _ = try await sendJSON(
            "api/modules/\(id.uuidString.lowercased())/enabled",
            method: "POST",
            body: RemoteEnabledRequest(enabled: enabled)
        )
    }

    func setIndividualICloudExport(id: UUID, enabled: Bool) async throws {
        _ = try await sendJSON(
            "api/modules/\(id.uuidString.lowercased())/individual-icloud-export",
            method: "POST",
            body: RemoteEnabledRequest(enabled: enabled)
        )
    }

    func reorderModules(ids: [UUID]) async throws {
        _ = try await sendJSON(
            "api/modules/reorder",
            method: "POST",
            body: RemoteReorderRequest(ids: ids.map { $0.uuidString.lowercased() })
        )
    }

    func setPlatformModuleEnabled(platform: RelayPlatform, moduleID: UUID, enabled: Bool) async throws {
        _ = try await sendJSON(
            "api/combined/platforms/\(platform.rawValue)/modules/\(moduleID.uuidString.lowercased())/enabled",
            method: "POST",
            body: RemoteEnabledRequest(enabled: enabled)
        )
    }

    func setAllPlatformModulesEnabled(platform: RelayPlatform, enabled: Bool) async throws {
        _ = try await sendJSON(
            "api/combined/platforms/\(platform.rawValue)/modules/enabled",
            method: "POST",
            body: RemoteEnabledRequest(enabled: enabled)
        )
    }

    func setModuleArguments(id: UUID, values: [String: String]) async throws {
        _ = try await sendJSON(
            "api/modules/\(id.uuidString.lowercased())/arguments",
            method: "PUT",
            body: RemoteArgumentMutation(values: values)
        )
    }

    func resetModuleArguments(id: UUID) async throws {
        _ = try await send("api/modules/\(id.uuidString.lowercased())/arguments", method: "DELETE")
    }

    func updateModuleCustomIcon(id: UUID, url: String?) async throws {
        let path = "api/modules/\(id.uuidString.lowercased())/custom-icon"
        if let url {
            _ = try await sendJSON(path, method: "PUT", body: WebURLRequestPayload(url: url))
        } else {
            _ = try await send(path, method: "DELETE")
        }
    }

    func acceptOverrideConflict(id: UUID) async throws {
        _ = try await send("api/modules/\(id.uuidString.lowercased())/override-conflict", method: "POST")
    }

    func previewContent(moduleID: UUID) async throws -> String {
        try await getText("api/modules/\(moduleID.uuidString.lowercased())/preview")
    }

    func savePreviewContent(moduleID: UUID, content: String) async throws {
        _ = try await send(
            "api/modules/\(moduleID.uuidString.lowercased())/preview",
            method: "PUT",
            body: Data(content.utf8),
            contentType: "text/plain; charset=utf-8"
        )
    }

    func restorePreviewContent(moduleID: UUID) async throws -> String {
        try await getText("api/modules/\(moduleID.uuidString.lowercased())/preview", method: "DELETE")
    }

    func combinedPreviewContent(platform: RelayPlatform) async throws -> String {
        try await getText("api/combined/preview?platform=\(platform.rawValue)")
    }

    func moduleArguments(moduleID: UUID) async throws -> RemoteArgumentsPayload {
        try await get("api/modules/\(moduleID.uuidString.lowercased())/arguments")
    }

    func pushGeneralSettings(
        refreshIntervalMinutes: Int,
        automaticallyPublish: Bool,
        iconSearchRegion: String,
        platforms: [String: Bool]
    ) async throws {
        _ = try await sendJSON(
            "api/settings/general",
            method: "PUT",
            body: RemoteGeneralSettingsMutation(
                refreshIntervalMinutes: refreshIntervalMinutes,
                launchAtLogin: nil,
                automaticallyPublish: automaticallyPublish,
                iconSearchRegion: iconSearchRegion,
                platforms: platforms
            )
        )
    }

    func pushScriptHubSettings(moduleURL: String, automaticallyUpdate: Bool) async throws {
        _ = try await sendJSON(
            "api/settings/script-hub",
            method: "PUT",
            body: RemoteScriptHubSettingsMutation(
                scriptHubModuleURL: moduleURL,
                automaticallyUpdateScriptHub: automaticallyUpdate
            )
        )
    }

    func pushSyncSettings(
        storageMode: String,
        githubRepository: String,
        githubToken: String?,
        githubPublicBaseURL: String
    ) async throws {
        _ = try await sendJSON(
            "api/settings/sync",
            method: "PUT",
            body: RemoteSyncSettingsMutation(
                storageMode: storageMode,
                githubRepository: githubRepository,
                githubToken: githubToken,
                githubPublicBaseURL: githubPublicBaseURL
            )
        )
    }

    func testSyncSettings(
        storageMode: String,
        githubRepository: String,
        githubToken: String?,
        githubPublicBaseURL: String
    ) async throws {
        _ = try await sendJSON(
            "api/settings/sync/test",
            method: "POST",
            body: RemoteSyncSettingsMutation(
                storageMode: storageMode,
                githubRepository: githubRepository,
                githubToken: githubToken,
                githubPublicBaseURL: githubPublicBaseURL
            )
        )
    }

    func clearDiagnostics() async throws {
        _ = try await send("api/settings/diagnostics/clear", method: "POST")
    }

    func searchIcons(query: String, region: String?) async throws -> [IconSearchResult] {
        var path = "api/appstore/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let region, !region.isEmpty {
            path += "&region=\(region.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? region)"
        }
        return try await get(path)
    }

    /// Long-lived SSE consumer for `/api/events`. Calls `onState` whenever the
    /// server emits a state payload. Throws when the stream ends or stalls.
    func listenForStateEvents(onState: @escaping @MainActor (RemoteStatePayload) -> Void) async throws {
        guard let url = URL(string: "api/events", relativeTo: baseURL)?.absoluteURL else {
            throw RelayError.invalidOutput("无效的服务器地址。")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 86400

        let (bytes, response) = try await Self.streamingSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RelayError.invalidOutput("无法建立实时同步连接。")
        }

        let monitor = SSEStallMonitor()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var dataLines: [String] = []
                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        await monitor.touch()
                        if line.hasPrefix("data:") {
                            let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            dataLines.append(String(value))
                        } else if line.isEmpty, !dataLines.isEmpty {
                            let payload = dataLines.joined(separator: "\n")
                            dataLines.removeAll(keepingCapacity: true)
                            if let data = payload.data(using: .utf8),
                               let state = try? self.decoder.decode(RemoteStatePayload.self, from: data) {
                                await onState(state)
                            }
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    throw error
                }
                if Task.isCancelled { throw CancellationError() }
                throw RelayError.invalidOutput("与服务器的实时同步连接已断开。")
            }
            group.addTask {
                let stall = Duration.seconds(Self.sseStallTimeout)
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(5))
                    if await monitor.elapsed() > stall {
                        throw RelayError.invalidOutput("服务器连接已超时。")
                    }
                }
            }

            do {
                _ = try await group.next()
            } catch is CancellationError {
                group.cancelAll()
                throw CancellationError()
            } catch {
                group.cancelAll()
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
            group.cancelAll()
        }
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(path, method: "GET")
        return try decoder.decode(T.self, from: data)
    }

    private func getText(_ path: String, method: String = "GET") async throws -> String {
        let data = try await send(path, method: method)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RelayError.invalidOutput("服务器返回了无效的文本内容。")
        }
        return text
    }

    @discardableResult
    private func postAction(_ path: String) async throws -> RemoteActionPayload {
        let data = try await send(path, method: "POST")
        if data.isEmpty { return RemoteActionPayload(ok: true, message: "") }
        return try decoder.decode(RemoteActionPayload.self, from: data)
    }

    private func sendJSON<Body: Encodable>(
        _ path: String,
        method: String,
        body: Body?,
        expectingStatus: Int? = nil
    ) async throws -> RemoteActionPayload {
        let data: Data?
        if let body {
            data = try encoder.encode(body)
        } else {
            data = nil
        }
        let responseData = try await send(
            path,
            method: method,
            body: data,
            contentType: "application/json; charset=utf-8",
            expectingStatus: expectingStatus
        )
        if responseData.isEmpty {
            return RemoteActionPayload(ok: true, message: "")
        }
        return try decoder.decode(RemoteActionPayload.self, from: responseData)
    }

    @discardableResult
    private func send(
        _ path: String,
        method: String,
        body: Data? = nil,
        contentType: String? = nil,
        expectingStatus: Int? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RelayError.invalidOutput("无效的服务器地址。")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RelayError.invalidOutput("服务器没有返回有效响应。")
        }
        let accepted = expectingStatus.map { http.statusCode == $0 }
            ?? (200..<300).contains(http.statusCode)
        guard accepted else {
            if let payload = try? decoder.decode(RemoteErrorPayload.self, from: data),
               let message = payload.message, !message.isEmpty {
                throw RelayError.invalidOutput(message)
            }
            throw RelayError.invalidOutput("服务器返回错误（\(http.statusCode)）。")
        }
        return data
    }
}

private actor SSEStallMonitor {
    private var lastActivity = ContinuousClock.now

    func touch() {
        lastActivity = ContinuousClock.now
    }

    func elapsed() -> Duration {
        lastActivity.duration(to: ContinuousClock.now)
    }
}

// MARK: - Payloads

struct RemoteStatePayload: Codable, Sendable {
    var storageMode: String
    var settings: RemoteSettingsPayload
    var combined: RemoteCombinedPayload
    var modules: [RemoteModulePayload]
    var activity: RemoteActivityPayload
    var platforms: [RemotePlatformPayload]
}

struct RemoteSettingsPayload: Codable, Sendable {
    var refreshIntervalMinutes: Int
    var launchAtLogin: Bool
    var automaticallyPublish: Bool
    var iconSearchRegion: String
    var webServerEnabled: Bool
    var webServerPort: Int
    var webServerState: String
    var webManagementURL: String?
    var scriptHubModuleURL: String
    var automaticallyUpdateScriptHub: Bool
    var scriptHubRevision: String?
    var scriptHubLastCheckedAt: Date?
    var scriptHubLastError: String?
    var storageMode: String
    var githubRepository: String
    var githubTokenConfigured: Bool
    var githubPublicBaseURL: String
    var githubRepositoryIsPrivate: Bool?
    var updateHistory: [UpdateHistoryEntry]
    var appVersion: String
    var platforms: [String: Bool]
}

struct RemoteCombinedPayload: Codable, Sendable {
    var name: String
    var fileName: String
    var sourceCount: Int
    var enabledCount: Int
    var lastUpdatedAt: Date?
    var subscriptionURL: String?
}

struct RemotePlatformPayload: Codable, Sendable {
    var id: String
    var displayName: String
    var isEnabled: Bool
    var fileName: String
    var iconURL: String
    var customIconURL: String?
    var subscriptionURL: String?
    var enabledModules: [String]
}

struct RemoteModulePayload: Codable, Sendable {
    var id: String
    var name: String
    var sourceURL: String
    var sourceFormat: String
    var sourceFormatTitle: String
    var outputFileName: String
    var isEnabled: Bool
    var exportsIndividualModuleToICloud: Bool
    var state: String
    var stateTitle: String
    var lastUpdatedAt: Date?
    var lastError: String?
    var iconURL: String?
    var customIconURL: String?
    var customIconSource: String?
    var publishedURL: String?
    var advancedSummary: String?
    var hasOverrideConflict: Bool
    var scriptHubOptions: ScriptHubOptions
    var policy: String
    var includeKeywords: String
    var excludeKeywords: String
    var mitmAdd: String
    var mitmRemove: String
    var noResolve: Bool
    var enableJQ: Bool
    var argumentOverrides: [String: String]?
    var policyOverrides: [String: String]?
    var customRules: [String]?
    var customMitM: [String]?
    var detectedSourceFormat: String?
    var contentHash: String?
}

struct RemoteActivityPayload: Codable, Sendable {
    var isWorking: Bool
    var status: String
    var progress: Double?
    /// Optional for compatibility with servers from before activity polling.
    var completedCount: Int?
    var totalCount: Int?
    var currentModuleID: String?
    var error: String?
}

struct RemoteActionPayload: Codable, Sendable {
    var ok: Bool
    var message: String
}

struct RemoteErrorPayload: Codable, Sendable {
    var message: String?
}

struct RemoteEnabledRequest: Codable, Sendable {
    var enabled: Bool
}

struct RemoteReorderRequest: Codable, Sendable {
    var ids: [String]
}

struct RemoteArgumentMutation: Codable, Sendable {
    var values: [String: String]
}

struct RemoteArgumentsPayload: Codable, Sendable {
    var arguments: [RemoteArgumentPayload]
    var help: String?
}

struct RemoteArgumentPayload: Codable, Sendable {
    var key: String
    var defaultValue: String
    var value: String
}

struct RemoteGeneralSettingsMutation: Codable, Sendable {
    var refreshIntervalMinutes: Int?
    var launchAtLogin: Bool?
    var automaticallyPublish: Bool?
    var iconSearchRegion: String?
    var platforms: [String: Bool]?
}

struct RemoteScriptHubSettingsMutation: Codable, Sendable {
    var scriptHubModuleURL: String?
    var automaticallyUpdateScriptHub: Bool?
}

struct RemoteSyncSettingsMutation: Codable, Sendable {
    var storageMode: String?
    var githubRepository: String?
    var githubToken: String?
    var githubPublicBaseURL: String?
}

struct RemoteModuleMutation: Codable, Sendable {
    var name: String
    var sourceURL: String
    var sourceFormat: String
    var isEnabled: Bool
    var scriptHubOptions: ScriptHubOptions

    init(draft: ModuleDraft) {
        name = draft.name
        sourceURL = draft.sourceURL
        sourceFormat = draft.sourceFormat.rawValue
        isEnabled = draft.isEnabled
        scriptHubOptions = draft.scriptHubOptions
    }
}

extension RemoteModulePayload {
    func asRelayModule(baseURL: URL) -> RelayModule? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let format = ModuleSourceFormat(rawValue: sourceFormat) ?? .automatic
        let detected = detectedSourceFormat.flatMap(ModuleSourceFormat.init(rawValue:))
        let stateValue = ModuleUpdateState(rawValue: state) ?? .never
        let iconSource = customIconSource.flatMap(CustomIconSource.init(rawValue:)) ?? .manual

        return RelayModule(
            id: uuid,
            name: name,
            sourceURL: sourceURL,
            sourceFormat: format,
            outputFileName: outputFileName,
            isEnabled: isEnabled,
            exportsIndividualModuleToICloud: exportsIndividualModuleToICloud,
            scriptHubOptions: scriptHubOptions,
            argumentOverrides: argumentOverrides ?? [:],
            policyOverrides: policyOverrides ?? [:],
            customRules: customRules ?? [],
            customMitM: customMitM ?? [],
            iconURL: Self.absoluteURLString(iconURL, baseURL: baseURL),
            customIconURL: Self.absoluteURLString(customIconURL, baseURL: baseURL),
            customIconSource: iconSource,
            detectedSourceFormat: detected,
            lastUpdatedAt: lastUpdatedAt,
            contentHash: contentHash,
            hasOverrideConflict: hasOverrideConflict,
            state: stateValue,
            lastError: lastError
        )
    }

    private static func absoluteURLString(_ value: String?, baseURL: URL) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString
    }
}
