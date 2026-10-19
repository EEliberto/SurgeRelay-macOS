import Foundation

/// Device-local access settings are deliberately excluded from Web/Ponte settings payloads.
struct AutomationAccess: Codable, Equatable {
    var enabled = false
    var token = ""
    var allowEdits = false
    var allowRefresh = false
    var allowPublish = false

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "automationAccess"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "automationAccess") }
    }

    mutating func ensureToken() { if token.isEmpty { resetToken() } }
    mutating func resetToken() { token = UUID().uuidString + UUID().uuidString }

    func authorizes(_ request: WebHTTPRequest) -> Bool {
        guard enabled, token.count >= 32, request.isLoopback,
              request.headers["origin"] == nil,
              let host = request.headers["host"],
              let components = URLComponents(string: "http://" + host),
              ["127.0.0.1", "localhost", "[::1]", "::1"].contains(components.host?.lowercased() ?? ""),
              let authorization = request.headers["authorization"],
              authorization.hasPrefix("Bearer ") else { return false }
        let supplied = Array(authorization.dropFirst(7).utf8), expected = Array(token.utf8)
        guard supplied.count == expected.count else { return false }
        return zip(supplied, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

struct AutomationFailure: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

struct AutomationJob: Encodable {
    let id: UUID
    let action: String
    let createdAt: Date
    var state = "running"
    var finishedAt: Date?
    var message: String?
}

@MainActor
final class AutomationAPI {
    private struct Plan {
        let id: UUID
        let kind: String
        let targetID: UUID
        let revision: String
        let payload: Data
        let expiresAt: Date
    }
    private var plans: [UUID: Plan] = [:]
    private var jobs: [AutomationJob] = []
    private var mutationInFlight = false

    func invalidatePlans() { plans.removeAll() }

    func response(for request: WebHTTPRequest, model: AppModel) async -> WebHTTPResponse {
        guard !model.isClientMode, model.automationAccess.authorizes(request) else {
            return .error(status: 403, message: "自动化访问未启用、令牌无效或请求不是本机调用。")
        }
        do {
            let response = try await route(request, model: model)
            return WebHTTPResponse(status: response.status, reason: response.reason,
                                   headers: response.headers.merging(["Cache-Control": "no-store"]) { _, new in new }, body: response.body)
        } catch let error as AutomationFailure {
            return .error(status: error.status, message: error.message)
        } catch {
            return .error(status: 400, message: Self.redact(error.localizedDescription))
        }
    }

    private func route(_ request: WebHTTPRequest, model: AppModel) async throws -> WebHTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        let resource = parts.count > 2 ? parts[2] : "capabilities"
        let id = parts.count > 3 ? UUID(uuidString: parts[3]) : nil
        if request.method == "GET" {
            switch resource {
            case "capabilities" where parts.count <= 3:
                return try Self.json([
                    "apiVersion": "1", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                    "permissions": ["read": true, "edit": model.automationAccess.allowEdits,
                                    "refresh": model.automationAccess.allowRefresh, "publish": model.automationAccess.allowPublish],
                    "resources": ["modules", "airports", "configuration", "search", "diagnostics", "jobs"],
                    "planKinds": ["module.content", "module.settings", "airport.settings"],
                    "jobActions": ["refreshModules", "refreshAirport", "publish", "writeAirports"],
                    "automaticPublishing": model.settings.automaticallyPublish,
                    "documentation": "https://github.com/EEliberto/SurgeRelay-macOS/blob/main/docs/Automation.md"
                ])
            case "modules" where parts.count == 3:
                return try Self.json(model.modules.map { module in
                    ["id": module.id.uuidString, "name": module.name, "sourceURL": Self.safeURL(module.sourceURL),
                     "state": module.state.rawValue, "lastError": Self.redact(module.lastError ?? ""),
                     "hasOverrideConflict": module.hasOverrideConflict] as [String: Any]
                })
            case "modules" where parts.count == 4 || (parts.count == 5 && parts[4] == "content"):
                let module = try module(id, in: model)
                if parts.count == 5 {
                    let content = try await model.previewContent(for: module)
                    // Content is returned verbatim for round-trip editing; callers explicitly request it.
                    return try Self.json(["id": module.id.uuidString, "revision": Self.hash(content), "content": content])
                }
                return try Self.json(["revision": try revision(module), "settings": try Self.moduleSettings(module)])
            case "airports" where parts.count == 3:
                return try Self.json(model.airportSubscriptions.map {
                    ["id": $0.id.uuidString, "name": $0.name, "sourceURL": Self.safeURL($0.sourceURL),
                     "lastError": Self.redact($0.lastError ?? ""), "hasCache": model.hasCachedAirportSubscription(id: $0.id)] as [String: Any]
                })
            case "airports" where parts.count == 4 || (parts.count == 5 && parts[4] == "nodes"):
                let airport = try airport(id, in: model)
                if parts.count == 5 {
                    let entries = try AirportSubscriptionParser.proxyEntries(from: AirportSubscriptionStore.data(for: airport.id))
                    var names = Set<String>()
                    let processed = AirportSubscriptionParser.process(entries, for: airport, reserving: &names)
                    return .json(processed.records)
                }
                return try Self.json(["revision": try revision(airport), "settings": try Self.airportSettings(airport)])
            case "configuration" where parts.count == 3:
                let names = AirportPolicyFileStore.fileNames(for: model.airportSubscriptions.filter { $0.isEnabled && $0.isConfigured })
                let targets: [[String: Any]] = model.surgeConfigurationTargets.map { target in
                    ["name": target.url.lastPathComponent, "enabled": target.isEnabled,
                     "exists": FileManager.default.fileExists(atPath: target.path),
                     "policyFiles": names.values.sorted().map { name in
                         ["name": name, "exists": FileManager.default.fileExists(atPath: target.url.deletingLastPathComponent().appending(path: name).path)] as [String: Any]
                     }]
                }
                return try Self.json(["preview": model.airportConfigurationPreview, "targets": targets])
            case "search" where parts.count == 3:
                let query = request.query["q", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty, query.count <= 256 else { throw failure(400, "q 须为 1–256 个字符。") }
                var hits: [[String: Any]] = [], unavailable: [[String: String]] = []
                let limit = min(max(Int(request.query["limit"] ?? "100") ?? 100, 1), 500)
                for module in model.modules {
                    do {
                        let content = try await model.previewContent(for: module)
                        var section = ""
                        for (offset, line) in content.components(separatedBy: "\n").enumerated() {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") { section = trimmed }
                            if line.localizedCaseInsensitiveContains(query) {
                                if hits.count == limit { return try Self.json(["matches": hits, "unavailable": unavailable, "truncated": true]) }
                                hits.append(["moduleID": module.id.uuidString, "module": module.name,
                                             "sourceURL": Self.safeURL(module.sourceURL), "section": section,
                                             "line": offset + 1, "text": Self.redact(line)])
                            }
                        }
                    } catch { unavailable.append(["moduleID": module.id.uuidString, "error": Self.redact(error.localizedDescription)]) }
                }
                return try Self.json(["matches": hits, "unavailable": unavailable, "truncated": false])
            case "diagnostics" where parts.count == 3:
                return try Self.json(["isWorking": model.isWorking,
                                      "message": Self.redact(model.statusMessage),
                                      "error": Self.redact(model.presentedError ?? ""),
                                      "failedModules": model.modules.filter { $0.state == .failed }.map {
                                          ["id": $0.id.uuidString, "name": $0.name, "error": Self.redact($0.lastError ?? "")]
                                      }, "publishIssues": try Self.object(model.publishLintIssues)])
            case "jobs" where parts.count == 3: return .json(jobs)
            case "jobs" where parts.count == 4:
                guard let job = jobs.first(where: { $0.id == id }) else { throw failure(404, "任务不存在或已过期。") }
                return .json(job)
            default: throw failure(404, "接口不存在。")
            }
        }
        guard request.method == "POST" else { throw failure(405, "不支持此方法。") }
        if resource == "plans", parts.count == 3 {
            try require(model.automationAccess.allowEdits, "未允许编辑。")
            guard !mutationInFlight, !model.isWorking else { throw failure(409, "正在处理其他任务。") }
            return try await makePlan(request, model: model)
        }
        if resource == "plans", parts.count == 5, parts[4] == "apply", let id {
            try require(model.automationAccess.allowEdits, "未允许编辑。")
            try requirePublishingIfAutomatic(model)
            guard !mutationInFlight, !model.isWorking else { throw failure(409, "正在处理其他任务。") }
            plans = plans.filter { $0.value.expiresAt > .now }
            guard let plan = plans[id] else { throw failure(404, "计划不存在或已过期，请重新预览。") }
            if plan.kind == "module.settings" {
                try require(model.automationAccess.allowRefresh, "模块设置变更会触发刷新，请同时允许刷新。")
            }
            mutationInFlight = true
            defer { mutationInFlight = false }
            try await apply(plan, model: model)
            plans.removeValue(forKey: id)
            return try Self.json(["applied": true, "planID": id.uuidString])
        }
        if resource == "jobs", parts.count == 3 { return try startJob(request, model: model) }
        throw failure(404, "接口不存在。")
    }

    private func makePlan(_ request: WebHTTPRequest, model: AppModel) async throws -> WebHTTPResponse {
        let body = try Self.dictionary(request.body)
        guard let kind = body["kind"] as? String, let rawID = body["id"] as? String,
              let id = UUID(uuidString: rawID), let base = body["baseRevision"] as? String else {
            throw failure(400, "需要 kind、id 和 baseRevision。")
        }
        let before: Any, after: Any, payload: Data, current: String
        switch kind {
        case "module.content":
            let module = try module(id, in: model)
            let content = try await model.previewContent(for: module)
            guard let replacement = body["content"] as? String, !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw failure(400, "content 不能为空。")
            }
            before = content; after = replacement; payload = Data(replacement.utf8); current = Self.hash(content)
        case "module.settings":
            let module = try module(id, in: model)
            let settings = try Self.moduleSettings(module)
            let changes = try Self.changes(body)
            let merged = try Self.merge(settings, changes: changes)
            _ = try Self.moduleDraft(merged, module: module)
            before = settings; after = merged; payload = try Self.data(merged); current = try revision(module)
        case "airport.settings":
            let airport = try airport(id, in: model)
            let settings = try Self.airportSettings(airport)
            let merged = try Self.merge(settings, changes: Self.changes(body))
            _ = try Self.airportDraft(merged, airport: airport)
            before = settings; after = merged; payload = try Self.data(merged); current = try revision(airport)
        default: throw failure(400, "未知的计划类型。")
        }
        guard base == current else { throw failure(409, "内容已变化，请重新读取后生成计划。") }
        guard try Self.data(before) != Self.data(after) else { throw failure(400, "没有需要应用的修改。") }
        plans = plans.filter { $0.value.expiresAt > .now }
        guard plans.count < 20, plans.values.reduce(0, { $0 + $1.payload.count }) + payload.count <= 16 * 1024 * 1024 else { throw failure(409, "待处理计划过多，请稍后重试。") }
        let plan = Plan(id: UUID(), kind: kind, targetID: id, revision: current, payload: payload, expiresAt: .now.addingTimeInterval(600))
        plans[plan.id] = plan
        return try Self.json(["planID": plan.id.uuidString, "kind": kind, "baseRevision": current,
                              "expiresAt": ISO8601DateFormatter().string(from: plan.expiresAt), "before": before, "after": after,
                              "automaticPublishing": model.settings.automaticallyPublish])
    }

    private func apply(_ plan: Plan, model: AppModel) async throws {
        switch plan.kind {
        case "module.content":
            let module = try module(plan.targetID, in: model)
            let content = try await model.previewContent(for: module)
            guard Self.hash(content) == plan.revision else { throw failure(409, "内容已变化，请重新预览。") }
            _ = try await model.savePreviewContent(String(decoding: plan.payload, as: UTF8.self), for: module,
                                                  expectedETag: "\"" + plan.revision + "\"")
        case "module.settings":
            let module = try module(plan.targetID, in: model)
            guard try revision(module) == plan.revision else { throw failure(409, "模块已变化，请重新预览。") }
            try await model.updateModule(id: module.id, from: Self.moduleDraft(Self.dictionary(plan.payload), module: module))
        case "airport.settings":
            let airport = try airport(plan.targetID, in: model)
            guard try revision(airport) == plan.revision else { throw failure(409, "机场已变化，请重新预览。") }
            try model.updateAirportSubscription(id: airport.id, from: Self.airportDraft(Self.dictionary(plan.payload), airport: airport))
        default: throw failure(400, "未知的计划类型。")
        }
    }

    private func startJob(_ request: WebHTTPRequest, model: AppModel) throws -> WebHTTPResponse {
        let body = try Self.dictionary(request.body)
        guard let action = body["action"] as? String else { throw failure(400, "缺少 action。") }
        let target = (body["id"] as? String).flatMap(UUID.init(uuidString:))
        switch action {
        case "refreshModules":
            try require(model.automationAccess.allowRefresh, "未允许刷新。")
            try requirePublishingIfAutomatic(model)
            if body["id"] != nil { _ = try module(target, in: model) }
        case "refreshAirport":
            try require(model.automationAccess.allowRefresh, "未允许刷新。")
            _ = try airport(target, in: model)
        case "publish", "writeAirports":
            try require(model.automationAccess.allowPublish, "未允许发布。")
        default: throw failure(400, "未知的任务类型。")
        }
        guard !mutationInFlight, !model.isWorking else { throw failure(409, "正在处理其他任务。") }
        mutationInFlight = true
        let job = AutomationJob(id: UUID(), action: action, createdAt: .now)
        jobs.append(job)
        if jobs.count > 100 { jobs.removeFirst(jobs.count - 100) }
        Task { @MainActor [self, model] in
            defer { mutationInFlight = false }
            do {
                switch action {
                case "refreshModules":
                    let ids = target.map { [$0] } ?? model.modules.filter { $0.isEnabled || (model.settings.storageMode == .local && $0.exportsIndividualModuleToICloud) }.map(\.id)
                    guard !ids.isEmpty else { throw failure(400, "没有可刷新的模块。") }
                    let before = Dictionary(uniqueKeysWithValues: model.modules.filter { ids.contains($0.id) }.map { ($0.id, $0.lastRefreshAttemptAt) })
                    await model.updateModules(ids: ids)
                    let remaining = model.modules.filter { ids.contains($0.id) }
                    guard remaining.count == ids.count else { throw failure(409, "刷新期间模块已被删除。") }
                    let skipped = remaining.filter { $0.lastRefreshAttemptAt == before[$0.id] ?? nil }
                    if !skipped.isEmpty { throw failure(409, "部分模块未执行刷新（可能被取消、未启用或受来源重试间隔限制）：" + skipped.map(\.name).joined(separator: "、")) }
                    let failed = model.modules.filter { ids.contains($0.id) && $0.state == .failed }
                    if !failed.isEmpty { throw failure(400, failed.map { "\($0.name): \($0.lastError ?? "刷新失败")" }.joined(separator: "\n")) }
                    if let error = model.presentedError { throw failure(400, error) }
                case "refreshAirport":
                    if let target {
                        let original = try airport(target, in: model)
                        try await model.refreshAirportSubscription(id: target)
                        let current = try airport(target, in: model)
                        guard current.sourceURL == original.sourceURL, current.lastUpdatedAt != original.lastUpdatedAt else {
                            throw failure(409, "刷新期间订阅已变化，请重试。")
                        }
                    }
                case "publish": try await model.publishForAutomation()
                case "writeAirports": try await model.writeAirportSubscriptionsForCurrentMode()
                default: break
                }
                finish(job.id, state: "succeeded", message: action == "refreshModules" ? "刷新已完成；自动发布按 App 设置执行，可单独启动 publish 任务确认发布结果。" : "已完成。")
            } catch { finish(job.id, state: "failed", message: Self.redact(error.localizedDescription)) }
        }
        return .json(job, status: 202, reason: "Accepted")
    }

    private func finish(_ id: UUID, state: String, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state; jobs[index].message = message; jobs[index].finishedAt = .now
    }

    private func requirePublishingIfAutomatic(_ model: AppModel) throws {
        if model.settings.automaticallyPublish || model.settings.storageMode == .local || model.modules.contains(where: { $0.exportsIndividualModuleToICloud }) {
            try require(model.automationAccess.allowPublish, "当前设置会自动同步生成文件，请同时允许发布。")
        }
    }

    private func module(_ id: UUID?, in model: AppModel) throws -> RelayModule {
        guard let value = model.modules.first(where: { $0.id == id }) else { throw failure(404, "模块不存在。") }
        return value
    }
    private func airport(_ id: UUID?, in model: AppModel) throws -> AirportSubscription {
        guard let value = model.airportSubscriptions.first(where: { $0.id == id }) else { throw failure(404, "机场不存在。") }
        return value
    }
    private func revision<T: Encodable>(_ value: T) throws -> String { try Self.data(Self.object(value)).sha256String }
    private func require(_ allowed: Bool, _ message: String) throws { if !allowed { throw failure(403, message) } }
    private func failure(_ status: Int, _ message: String) -> AutomationFailure { AutomationFailure(status: status, message: message) }
    static func hash(_ content: String) -> String { Data(content.utf8).sha256String }
    static func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) }
    static func object<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }
    static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationFailure(status: 400, message: "需要 JSON 对象。")
        }
        return value
    }
    static func json(_ value: Any) throws -> WebHTTPResponse { WebHTTPResponse(body: try data(value)) }
    static func changes(_ body: [String: Any]) throws -> [String: Any] {
        guard let changes = body["changes"] as? [String: Any], !changes.isEmpty else {
            throw AutomationFailure(status: 400, message: "changes 不能为空。")
        }
        return changes
    }
    /// Reject unknown fields and recursively preserve unspecified options.
    static func merge(_ original: [String: Any], changes: [String: Any]) throws -> [String: Any] {
        var result = original
        for (key, value) in changes {
            guard original.keys.contains(key) else { throw AutomationFailure(status: 400, message: "不支持的字段：\(key)") }
            if let nested = original[key] as? [String: Any], let patch = value as? [String: Any] {
                result[key] = try merge(nested, changes: patch)
            } else { result[key] = value }
        }
        return result
    }
    static func moduleSettings(_ module: RelayModule) throws -> [String: Any] {
        ["name": module.name, "sourceFormat": module.sourceFormat.rawValue,
         "refreshIntervalMinutes": module.refreshIntervalMinutes as Any? ?? NSNull(),
         "scriptHubOptions": try object(module.scriptHubOptions)]
    }
    static func airportSettings(_ airport: AirportSubscription) throws -> [String: Any] {
        ["name": airport.name, "policyRegexFilter": airport.policyRegexFilter,
         "nodeNameTemplate": airport.nodeNameTemplate, "nodeNameOptimization": try object(airport.nodeNameOptimization),
         "nodeProcessing": try object(airport.nodeProcessing)]
    }
    private struct ModulePatch: Decodable {
        let name: String
        let sourceFormat: ModuleSourceFormat
        let refreshIntervalMinutes: Int?
        let scriptHubOptions: ScriptHubOptions
    }
    static func moduleDraft(_ object: [String: Any], module: RelayModule) throws -> ModuleDraft {
        let patch = try JSONDecoder().decode(ModulePatch.self, from: data(object))
        var draft = ModuleDraft(module: module)
        draft.name = patch.name; draft.sourceFormat = patch.sourceFormat
        draft.refreshIntervalMinutes = patch.refreshIntervalMinutes; draft.scriptHubOptions = patch.scriptHubOptions
        if let message = draft.validationMessage { throw AutomationFailure(status: 400, message: message) }
        return draft
    }
    private struct AirportPatch: Decodable {
        let name: String
        let policyRegexFilter: String
        let nodeNameTemplate: String
        let nodeNameOptimization: AirportNodeNameOptimization
        let nodeProcessing: AirportNodeProcessingOptions
    }
    static func airportDraft(_ object: [String: Any], airport: AirportSubscription) throws -> AirportSubscriptionDraft {
        let patch = try JSONDecoder().decode(AirportPatch.self, from: data(object))
        guard !patch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AutomationFailure(status: 400, message: "名称不能为空。")
        }
        if !patch.policyRegexFilter.isEmpty { _ = try NSRegularExpression(pattern: patch.policyRegexFilter) }
        var draft = AirportSubscriptionDraft(subscription: airport)
        draft.name = patch.name; draft.policyRegexFilter = patch.policyRegexFilter; draft.nodeNameTemplate = patch.nodeNameTemplate
        draft.nodeNameOptimization = patch.nodeNameOptimization; draft.nodeProcessing = patch.nodeProcessing
        return draft
    }
    static func safeURL(_ value: String) -> String {
        guard var url = URLComponents(string: value), url.host != nil else { return "" }
        url.user = nil; url.password = nil; url.query = nil; url.fragment = nil
        return url.string ?? ""
    }
    static func redact(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s\"<>]+"#) else { return value }
        var result = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: safeURL(String(result[range])))
        }
        return result
    }
}
