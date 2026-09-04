import Foundation

extension AppModel {
    func addAirportSubscription(from draft: AirportSubscriptionDraft) throws {
        var subscription = AirportSubscription()
        apply(draft, to: &subscription)
        try validateAirportSubscription(subscription)
        airportSubscriptions.append(subscription)
        invalidateAirportConfigurationPreview()
        try persistAirportSubscriptions()
        statusMessage = "已添加 \(subscription.name)"
    }

    func updateAirportSubscription(id: UUID, from draft: AirportSubscriptionDraft) throws {
        guard let index = airportSubscriptions.firstIndex(where: { $0.id == id }) else { return }
        var updated = airportSubscriptions[index]
        let sourceChanged = updated.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
            != draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        apply(draft, to: &updated)
        try validateAirportSubscription(updated, excluding: id)
        if sourceChanged {
            updated.lastUpdatedAt = nil
            AirportSubscriptionStore.remove(for: id)
        }
        updated.lastError = nil
        airportSubscriptions[index] = updated
        invalidateAirportConfigurationPreview()
        try persistAirportSubscriptions()
        statusMessage = sourceChanged
            ? "已更新 \(updated.name) 的订阅链接"
            : "已更新 \(updated.name) 的过滤与显示设置"
    }

    func removeAirportSubscription(id: UUID) {
        airportSubscriptions.removeAll { $0.id == id }
        invalidateAirportConfigurationPreview()
        AirportSubscriptionStore.remove(for: id)
        try? persistAirportSubscriptions()
        statusMessage = "机场订阅已移除"
    }

    func setAirportSubscriptionEnabled(id: UUID, enabled: Bool) {
        guard let index = airportSubscriptions.firstIndex(where: { $0.id == id }) else { return }
        airportSubscriptions[index].isEnabled = enabled
        invalidateAirportConfigurationPreview()
        try? persistAirportSubscriptions()
    }

    func refreshAirportSubscription(id: UUID) async throws {
        guard let index = airportSubscriptions.firstIndex(where: { $0.id == id }),
              let url = URL(string: airportSubscriptions[index].sourceURL) else {
            throw RelayError.invalidOutput("机场订阅地址无效。")
        }
        do {
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 30
            )
            request.timeoutInterval = 30
            request.setValue("Surge Relay", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw RelayError.invalidOutput("机场订阅返回 HTTP \(http.statusCode)。")
            }
            guard !data.isEmpty else { throw RelayError.invalidOutput("机场订阅内容为空。") }
            _ = try AirportSubscriptionParser.proxyEntries(from: data)
            try AirportSubscriptionStore.save(data, for: id)
            invalidateAirportConfigurationPreview()
            guard let currentIndex = airportSubscriptions.firstIndex(where: { $0.id == id }) else { return }
            airportSubscriptions[currentIndex].lastUpdatedAt = .now
            airportSubscriptions[currentIndex].lastError = nil
            try persistAirportSubscriptions()
            statusMessage = "已刷新 \(airportSubscriptions[currentIndex].name) 的预览"
        } catch {
            if let currentIndex = airportSubscriptions.firstIndex(where: { $0.id == id }) {
                airportSubscriptions[currentIndex].lastError = error.localizedDescription
                try? persistAirportSubscriptions()
            }
            throw error
        }
    }

    func cachedAirportSubscriptionContent(id: UUID) throws -> String {
        let data = try AirportSubscriptionStore.data(for: id)
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw RelayError.invalidOutput("缓存内容不是可预览的文本。")
    }

    func hasCachedAirportSubscription(id: UUID) -> Bool {
        if isClientMode { return remoteAirportCacheIDs.contains(id) }
        return AirportSubscriptionStore.hasCache(for: id)
    }

    func saveAirportSubscriptionForCurrentMode(id: UUID?, draft: AirportSubscriptionDraft) async throws {
        guard isClientMode else {
            if let id {
                try updateAirportSubscription(id: id, from: draft)
            } else {
                try addAirportSubscription(from: draft)
            }
            return
        }
        let client = try operationalRemoteClient()
        if let id {
            try await client.updateAirportSubscription(id: id, draft: draft)
        } else {
            try await client.addAirportSubscription(draft)
        }
        try await synchronizeRemoteAirportState(using: client)
    }

    func removeAirportSubscriptionForCurrentMode(id: UUID) async throws {
        guard isClientMode else {
            removeAirportSubscription(id: id)
            return
        }
        let client = try operationalRemoteClient()
        try await client.deleteAirportSubscription(id: id)
        try await synchronizeRemoteAirportState(using: client)
    }

    func setAirportSubscriptionEnabledForCurrentMode(id: UUID, enabled: Bool) async throws {
        guard isClientMode else {
            setAirportSubscriptionEnabled(id: id, enabled: enabled)
            return
        }
        let client = try operationalRemoteClient()
        try await client.setAirportSubscriptionEnabled(id: id, enabled: enabled)
        try await synchronizeRemoteAirportState(using: client)
    }

    func refreshAirportSubscriptionForCurrentMode(id: UUID) async throws {
        guard isClientMode else {
            try await refreshAirportSubscription(id: id)
            return
        }
        let client = try operationalRemoteClient()
        try await client.refreshAirportSubscription(id: id)
        try await synchronizeRemoteAirportState(using: client)
    }

    func airportSubscriptionPreviewForCurrentMode(id: UUID, refresh: Bool) async throws -> String {
        guard isClientMode else {
            if refresh { try await refreshAirportSubscription(id: id) }
            return try cachedAirportSubscriptionContent(id: id)
        }
        let client = try operationalRemoteClient()
        if refresh {
            try await client.refreshAirportSubscription(id: id)
            try await synchronizeRemoteAirportState(using: client)
        }
        return try await client.airportSubscriptionPreview(id: id)
    }

    func saveSurgeConfigurationTargetForCurrentMode(id: UUID?, path: String) async throws {
        guard isClientMode else {
            if let id {
                try updateSurgeConfigurationTarget(id: id, path: path)
            } else {
                try addSurgeConfigurationTarget(path: path)
            }
            return
        }
        let client = try operationalRemoteClient()
        if let id {
            try await client.updateSurgeConfigurationTarget(id: id, path: path)
        } else {
            try await client.addSurgeConfigurationTarget(path: path)
        }
        try await synchronizeRemoteAirportState(using: client)
    }

    func removeSurgeConfigurationTargetForCurrentMode(id: UUID) async throws {
        guard isClientMode else {
            removeSurgeConfigurationTarget(id: id)
            return
        }
        let client = try operationalRemoteClient()
        try await client.deleteSurgeConfigurationTarget(id: id)
        try await synchronizeRemoteAirportState(using: client)
    }

    func setSurgeConfigurationTargetEnabledForCurrentMode(id: UUID, enabled: Bool) async throws {
        guard isClientMode else {
            setSurgeConfigurationTargetEnabled(id: id, enabled: enabled)
            return
        }
        let client = try operationalRemoteClient()
        try await client.setSurgeConfigurationTargetEnabled(id: id, enabled: enabled)
        try await synchronizeRemoteAirportState(using: client)
    }

    func writeAirportSubscriptionsForCurrentMode() async throws {
        guard isClientMode else {
            _ = try writeAirportSubscriptionsToEnabledConfigurations()
            return
        }
        let client = try operationalRemoteClient()
        try await client.writeAirportSubscriptions()
        try await synchronizeRemoteAirportState(using: client)
    }

    private func operationalRemoteClient() throws -> RemoteManagementClient {
        guard remoteConnectionState.isOperational else {
            throw RelayError.invalidOutput("服务器无响应，无法执行此操作。")
        }
        return try remoteClient()
    }

    private func synchronizeRemoteAirportState(using client: RemoteManagementClient) async throws {
        let state = try await client.fetchState()
        applyRemoteState(state, baseURL: client.baseURL)
        remoteConnectionState = .connected
    }

    func addSurgeConfigurationTargets(_ urls: [URL]) {
        let existingPaths = Set(surgeConfigurationTargets.map { $0.url.standardizedFileURL.path })
        let additions = urls
            .map(\.standardizedFileURL)
            .filter { !existingPaths.contains($0.path) }
            .map { SurgeConfigurationTarget(path: $0.path) }
        surgeConfigurationTargets.append(contentsOf: additions)
        try? persistSurgeConfigurationTargets()
    }

    func addSurgeConfigurationTarget(path: String) throws {
        let url = try validatedSurgeConfigurationURL(path: path)
        guard !surgeConfigurationTargets.contains(where: { $0.url.standardizedFileURL == url }) else {
            throw RelayError.invalidOutput("该配置文件已在列表中。")
        }
        surgeConfigurationTargets.append(SurgeConfigurationTarget(path: url.path))
        try persistSurgeConfigurationTargets()
        statusMessage = "已添加 \(url.lastPathComponent)"
    }

    func updateSurgeConfigurationTarget(id: UUID, path: String) throws {
        let url = try validatedSurgeConfigurationURL(path: path)
        guard !surgeConfigurationTargets.contains(where: { $0.id != id && $0.url.standardizedFileURL == url }) else {
            throw RelayError.invalidOutput("该配置文件已在列表中。")
        }
        guard let index = surgeConfigurationTargets.firstIndex(where: { $0.id == id }) else { return }
        surgeConfigurationTargets[index].path = url.path
        try persistSurgeConfigurationTargets()
        statusMessage = "已更新 \(url.lastPathComponent)"
    }

    func setSurgeConfigurationTargetEnabled(id: UUID, enabled: Bool) {
        guard let index = surgeConfigurationTargets.firstIndex(where: { $0.id == id }) else { return }
        surgeConfigurationTargets[index].isEnabled = enabled
        try? persistSurgeConfigurationTargets()
    }

    func removeSurgeConfigurationTarget(id: UUID) {
        surgeConfigurationTargets.removeAll { $0.id == id }
        try? persistSurgeConfigurationTargets()
    }

    func writeAirportSubscriptionsToEnabledConfigurations() throws -> Int {
        let targets = surgeConfigurationTargets.filter(\.isEnabled)
        guard !targets.isEmpty else { throw RelayError.invalidOutput("没有已启用的 Surge 配置文件。") }
        for target in targets {
            try writeAirportSubscriptions(to: target.url)
            if let index = surgeConfigurationTargets.firstIndex(where: { $0.id == target.id }) {
                surgeConfigurationTargets[index].lastWrittenAt = .now
            }
        }
        try persistSurgeConfigurationTargets()
        statusMessage = "已写入 \(targets.count) 个 Surge 配置"
        return targets.count
    }

    var airportConfigurationPreview: String {
        _ = airportConfigurationPreviewRevision
        if let airportConfigurationPreviewCache { return airportConfigurationPreviewCache }
        let preview = (try? generatedAirportConfiguration().preview)
            ?? "请先刷新所有已启用机场，以生成 [Proxy] 与 [Proxy Group] 预览。"
        airportConfigurationPreviewCache = preview
        return preview
    }

    func invalidateAirportConfigurationPreview() {
        airportConfigurationPreviewCache = nil
        airportConfigurationPreviewRevision &+= 1
    }

    func writeAirportSubscriptions(to configurationURL: URL) throws {
        let original = try String(contentsOf: configurationURL, encoding: .utf8)
        let generated = try generatedAirportConfiguration()
        var updated = try replacingManagedBlock(
            in: original,
            section: "Proxy",
            block: generated.proxyBlock,
            startMarker: "# >>> Surge Relay 机场代理",
            endMarker: "# <<< Surge Relay 机场代理"
        )
        updated = try replacingManagedBlock(
            in: updated,
            section: "Proxy Group",
            block: generated.groupBlock,
            startMarker: "# >>> Surge Relay 机场分组",
            endMarker: "# <<< Surge Relay 机场分组",
            legacyHeader: "# 机场订阅汇总"
        )

        let backupURL = configurationURL.appendingPathExtension("surge-relay-backup")
        try Data(original.utf8).write(to: backupURL, options: .atomic)
        try Data(updated.utf8).write(to: configurationURL, options: .atomic)
        statusMessage = "已写入 \(configurationURL.lastPathComponent)"
    }

    private func apply(_ draft: AirportSubscriptionDraft, to subscription: inout AirportSubscription) {
        subscription.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        subscription.sourceURL = draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        subscription.policyRegexFilter = draft.policyRegexFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        subscription.nodeNameTemplate = draft.nodeNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        subscription.nodeNameOptimization = draft.nodeNameOptimization
        subscription.nodeProcessing = draft.nodeProcessing
        subscription.iconURL = draft.iconURL.trimmingCharacters(in: .whitespacesAndNewlines)
        subscription.isEnabled = draft.isEnabled
    }

    private func validateAirportSubscription(_ subscription: AirportSubscription, excluding id: UUID? = nil) throws {
        guard subscription.isConfigured else {
            throw RelayError.invalidOutput("请输入机场名称和有效的 http(s) 订阅地址。")
        }
        guard !subscription.trimmedName.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "=" || $0 == "," }) else {
            throw RelayError.invalidOutput("机场名称不能包含逗号、等号或换行。")
        }
        guard !airportSubscriptions.contains(where: {
            $0.id != id && $0.trimmedName.caseInsensitiveCompare(subscription.trimmedName) == .orderedSame
        }) else {
            throw RelayError.invalidOutput("已存在同名机场。")
        }
        let regex = subscription.policyRegexFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !regex.isEmpty {
            do {
                _ = try NSRegularExpression(pattern: regex)
            } catch {
                throw RelayError.invalidOutput("节点过滤正则无效。")
            }
        }
        let template = subscription.nodeNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !template.isEmpty {
            guard template.contains("{name}") else {
                throw RelayError.invalidOutput("节点名称模板必须包含 {name}。")
            }
            guard !template.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "=" || $0 == "," }) else {
                throw RelayError.invalidOutput("节点名称模板不能包含逗号、等号或换行。")
            }
        }
    }

    private func persistAirportSubscriptions() throws {
        try PersistenceStore.saveAirportSubscriptions(airportSubscriptions)
    }

    private func persistSurgeConfigurationTargets() throws {
        try PersistenceStore.saveSurgeConfigurationTargets(surgeConfigurationTargets)
    }

    private func validatedSurgeConfigurationURL(path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            throw RelayError.invalidOutput("请输入服务器上的完整配置文件路径。")
        }
        let url = URL(filePath: trimmed).standardizedFileURL
        guard url.pathExtension.caseInsensitiveCompare("conf") == .orderedSame else {
            throw RelayError.invalidOutput("请选择 .conf 配置文件。")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw RelayError.invalidOutput("找不到这个配置文件。")
        }
        return url
    }

    private func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func generatedAirportConfiguration() throws -> (proxyBlock: String, groupBlock: String, preview: String) {
        let subscriptions = airportSubscriptions.filter { $0.isEnabled && $0.isConfigured }
        guard !subscriptions.isEmpty else { throw RelayError.invalidOutput("没有已启用的机场。") }
        var proxyLines = ["# >>> Surge Relay 机场代理"]
        var groupLines = ["# >>> Surge Relay 机场分组"]
        var usedProxyNames = Set<String>()

        for subscription in subscriptions {
            let entries = try AirportSubscriptionParser.proxyEntries(
                from: AirportSubscriptionStore.data(for: subscription.id)
            )
            let processingResult = AirportSubscriptionParser.process(
                entries,
                for: subscription,
                reserving: &usedProxyNames
            )
            guard !processingResult.included.isEmpty else {
                throw RelayError.invalidOutput("\(subscription.name) 的节点在过滤后为空。")
            }
            let names = processingResult.included.map { entry -> String in
                let name = entry.name
                proxyLines.append("\(name) = \(entry.definition)")
                return quoted(name)
            }
            var groupMembers = names
            let icon = subscription.iconURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !icon.isEmpty { groupMembers.append("icon-url=\(icon)") }
            groupLines.append("\(subscription.trimmedName) = select, \(groupMembers.joined(separator: ", "))")
        }
        proxyLines.append("# <<< Surge Relay 机场代理")
        groupLines.append("# <<< Surge Relay 机场分组")
        let proxyBlock = proxyLines.joined(separator: "\n")
        let groupBlock = groupLines.joined(separator: "\n")
        return (proxyBlock, groupBlock, "[Proxy]\n\(proxyBlock)\n\n[Proxy Group]\n\(groupBlock)")
    }

    private func replacingManagedBlock(
        in content: String,
        section: String,
        block: String,
        startMarker: String,
        endMarker: String,
        legacyHeader: String? = nil
    ) throws -> String {
        guard let sectionHeader = content.range(of: "[\(section)]") else {
            if section == "Proxy", let proxyGroup = content.range(of: "[Proxy Group]") {
                return content.replacingCharacters(
                    in: proxyGroup.lowerBound..<proxyGroup.lowerBound,
                    with: "[Proxy]\n\(block)\n\n"
                )
            }
            throw RelayError.invalidOutput("没有找到 [\(section)] 配置段。")
        }
        let nextSection = content.range(of: "\n[", range: sectionHeader.upperBound..<content.endIndex)?.lowerBound
            ?? content.endIndex
        let sectionRange = sectionHeader.upperBound..<nextSection

        if let start = content.range(of: startMarker, range: sectionRange),
           let end = content.range(of: endMarker, range: start.upperBound..<nextSection) {
            return content.replacingCharacters(in: start.lowerBound..<end.upperBound, with: block)
        }
        if let legacyHeader,
           let legacy = content.range(of: legacyHeader, range: sectionRange) {
            let remainder = legacy.upperBound..<nextSection
            let nextComment = content.range(of: "\n# ", range: remainder)?.lowerBound ?? nextSection
            return content.replacingCharacters(in: legacy.lowerBound..<nextComment, with: block)
        }
        let insertion = content[sectionHeader.upperBound...].firstIndex(of: "\n") ?? sectionHeader.upperBound
        return content.replacingCharacters(in: insertion..<insertion, with: "\n\(block)")
    }
}
