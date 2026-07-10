import Foundation

actor ModuleFileStore {
    private final class CoordinationOutcome<Value>: @unchecked Sendable {
        var result: Result<Value, Error>?
    }

    private var componentDirectory: URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "Components", directoryHint: .isDirectory)
    }

    private var overrideDirectory: URL {
        PersistenceStore.configurationDirectoryURL.appending(path: "Overrides", directoryHint: .isDirectory)
    }

    private var assetDirectory: URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "Assets", directoryHint: .isDirectory)
    }

    private func combinedCacheURL(for platform: RelayPlatform) -> URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "Combined-\(platform.rawValue).cache")
    }

    private func combinedOverrideURL(for platform: RelayPlatform) -> URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "CombinedOverride-\(platform.rawValue).cache")
    }

    func prepareStorage() throws {
        for directory in [componentDirectory, overrideDirectory, assetDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func hasCombined() -> Bool {
        RelayPlatform.allCases.contains { platform in
            FileManager.default.fileExists(atPath: combinedOverrideURL(for: platform).path)
                || FileManager.default.fileExists(atPath: combinedCacheURL(for: platform).path)
        }
    }

    func hasCombined(platform: RelayPlatform) -> Bool {
        FileManager.default.fileExists(atPath: combinedOverrideURL(for: platform).path)
            || FileManager.default.fileExists(atPath: combinedCacheURL(for: platform).path)
    }

    func writeComponent(_ content: String, id: UUID) throws {
        try FileManager.default.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
        try Data(SurgeModuleSanitizer.sanitize(content).utf8).write(to: componentURL(for: id), options: .atomic)
    }

    func hasComponent(id: UUID) -> Bool {
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Surge Relay/Components/\(id.uuidString).sgmodule")
        return FileManager.default.fileExists(atPath: componentOverrideURL(for: id).path)
            || FileManager.default.fileExists(atPath: componentURL(for: id).path)
            || FileManager.default.fileExists(atPath: legacyURL.path)
    }

    func hasOverride(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: componentOverrideURL(for: id).path)
    }

    func readComponent(id: UUID) throws -> String {
        let overrideURL = componentOverrideURL(for: id)
        let legacyOverrideURL = PersistenceStore.cacheDirectoryURL
            .appending(path: "Overrides/\(id.uuidString).cache")
        if !FileManager.default.fileExists(atPath: overrideURL.path),
           FileManager.default.fileExists(atPath: legacyOverrideURL.path) {
            try FileManager.default.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: legacyOverrideURL, to: overrideURL)
        }
        if FileManager.default.fileExists(atPath: overrideURL.path) {
            return SurgeModuleSanitizer.sanitize(try decodeText(at: overrideURL))
        }
        return try readConvertedComponent(id: id)
    }

    func readConvertedComponent(id: UUID) throws -> String {
        let url = componentURL(for: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            let legacyURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Surge Relay/Components/\(id.uuidString).sgmodule")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try FileManager.default.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: legacyURL, to: url)
            }
        }
        return SurgeModuleSanitizer.sanitize(try decodeText(at: url))
    }

    func writeComponentOverride(_ content: String, id: UUID) throws {
        try FileManager.default.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
        try PersistenceStore.writeProtectedData(
            Data(SurgeModuleSanitizer.sanitize(content).utf8),
            to: componentOverrideURL(for: id)
        )
    }

    func restoreComponent(id: UUID) throws -> String {
        let url = componentOverrideURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        return try readConvertedComponent(id: id)
    }

    func removeComponent(id: UUID) throws {
        let url = componentURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let overrideURL = componentOverrideURL(for: id)
        if FileManager.default.fileExists(atPath: overrideURL.path) { try FileManager.default.removeItem(at: overrideURL) }
    }

    @discardableResult
    func writeCombined(_ content: String, platform: RelayPlatform) throws -> Bool {
        let cacheURL = combinedCacheURL(for: platform)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(content.utf8)
        if let existing = try? Data(contentsOf: cacheURL),
           existing.sha256String == data.sha256String {
            return false
        }
        try data.write(to: cacheURL, options: .atomic)
        return true
    }

    func readCombined(platform: RelayPlatform) throws -> Data {
        let overrideURL = combinedOverrideURL(for: platform)
        let cacheURL = combinedCacheURL(for: platform)
        let url = FileManager.default.fileExists(atPath: overrideURL.path) ? overrideURL : cacheURL
        return try Data(contentsOf: url)
    }

    /// Exports the merged module to a user-visible `.sgmodule` file in the given
    /// directory (used by local storage mode so Surge can load it directly).
    @discardableResult
    func exportCombined(_ content: String, toDirectory directoryPath: String, fileName: String) throws -> Bool {
        let base = FilenameSanitizer.baseName(from: AppSettings.fixedCombinedModuleFileName)
        let allowedNames = RelayPlatform.allCases.map { "\(base)-\($0.rawValue).sgmodule" } + [AppSettings.fixedCombinedModuleFileName]
        guard allowedNames.contains(fileName) else {
            throw RelayError.invalidOutput("汇总模块必须是预设的平台文件名之一。")
        }
        let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: fileName)
        let data = Data(content.utf8)
        let outcome = CoordinationOutcome<Bool>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            outcome.result = Result {
                let conflictVersions = try Self.validatedManagedConflictVersions(at: coordinatedURL)
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    let existing = try Data(contentsOf: coordinatedURL)
                    guard Self.isManagedCombinedModule(existing) else {
                        throw RelayError.invalidOutput(
                            "目标文件 \(fileName) 已存在且不属于 Surge Relay，已停止写入。"
                        )
                    }
                    if conflictVersions.isEmpty,
                       existing.sha256String == data.sha256String {
                        return false
                    }
                }

                // The configuration and component cache are the source of truth.
                // Conflicting iCloud versions are never merged into this derived file.
                try data.write(to: coordinatedURL, options: .atomic)
                try Self.resolve(conflictVersions, at: coordinatedURL)
                return true
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result = outcome.result else {
            throw RelayError.invalidOutput("iCloud 未能完成汇总模块写入协调。")
        }
        return try result.get()
    }

    func removeExportedCombined(fromDirectory directoryPath: String, fileName: String) throws {
        let base = FilenameSanitizer.baseName(from: AppSettings.fixedCombinedModuleFileName)
        let allowedNames = RelayPlatform.allCases.map { "\(base)-\($0.rawValue).sgmodule" } + [AppSettings.fixedCombinedModuleFileName]
        guard allowedNames.contains(fileName) else { return }
        let url = URL(filePath: directoryPath, directoryHint: .isDirectory)
            .appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let outcome = CoordinationOutcome<Void>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            outcome.result = Result {
                let existing = try Data(contentsOf: coordinatedURL)
                guard Self.isManagedCombinedModule(existing) else { return }
                let conflictVersions = try Self.validatedManagedConflictVersions(at: coordinatedURL)
                try Self.resolve(conflictVersions, at: coordinatedURL)
                try FileManager.default.removeItem(at: coordinatedURL)
            }
        }
        if let coordinationError { throw coordinationError }
        try outcome.result?.get()
    }

    /// Writes one user-selected component beside the combined module. The
    /// embedded module ID lets later updates and deletion prove ownership.
    @discardableResult
    func exportIndividual(
        _ content: String,
        moduleID: UUID,
        toDirectory directoryPath: String,
        fileName: String
    ) throws -> Bool {
        guard fileName != AppSettings.fixedCombinedModuleFileName else {
            throw RelayError.invalidOutput("独立模块不能使用汇总模块文件名。")
        }
        let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: FilenameSanitizer.sgmoduleName(from: fileName))
        let data = Self.managedIndividualData(content, moduleID: moduleID)
        let outcome = CoordinationOutcome<Bool>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            outcome.result = Result {
                let conflictVersions = try Self.validatedManagedIndividualConflictVersions(
                    at: coordinatedURL,
                    moduleID: moduleID
                )
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    let existing = try Data(contentsOf: coordinatedURL)
                    guard Self.isManagedIndividualModule(existing, moduleID: moduleID) else {
                        throw RelayError.invalidOutput(
                            "目标文件 \(coordinatedURL.lastPathComponent) 已存在且不属于该 Surge Relay 模块，已停止写入。"
                        )
                    }
                    if conflictVersions.isEmpty, existing.sha256String == data.sha256String {
                        return false
                    }
                }
                try data.write(to: coordinatedURL, options: .atomic)
                try Self.resolve(conflictVersions, at: coordinatedURL)
                return true
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result = outcome.result else {
            throw RelayError.invalidOutput("iCloud 未能完成独立模块写入协调。")
        }
        return try result.get()
    }

    func removeExportedIndividual(
        fromDirectory directoryPath: String,
        fileName: String,
        moduleID: UUID
    ) throws {
        let url = URL(filePath: directoryPath, directoryHint: .isDirectory)
            .appending(path: FilenameSanitizer.sgmoduleName(from: fileName))
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let outcome = CoordinationOutcome<Void>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            outcome.result = Result {
                let existing = try Data(contentsOf: coordinatedURL)
                guard Self.isManagedIndividualModule(existing, moduleID: moduleID) else { return }
                let conflictVersions = try Self.validatedManagedIndividualConflictVersions(
                    at: coordinatedURL,
                    moduleID: moduleID
                )
                try Self.resolve(conflictVersions, at: coordinatedURL)
                try FileManager.default.removeItem(at: coordinatedURL)
            }
        }
        if let coordinationError { throw coordinationError }
        try outcome.result?.get()
    }

    func hasExportedIndividual(
        inDirectory directoryPath: String,
        fileName: String,
        moduleID: UUID
    ) -> Bool {
        let url = URL(filePath: directoryPath, directoryHint: .isDirectory)
            .appending(path: FilenameSanitizer.sgmoduleName(from: fileName))
        guard let data = try? Data(contentsOf: url) else { return false }
        return Self.isManagedIndividualModule(data, moduleID: moduleID)
    }

    func writeCombinedOverride(_ content: String, platform: RelayPlatform) throws {
        let overrideURL = combinedOverrideURL(for: platform)
        try FileManager.default.createDirectory(at: overrideURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: overrideURL, options: .atomic)
    }

    func restoreCombined(platform: RelayPlatform) throws -> String {
        let overrideURL = combinedOverrideURL(for: platform)
        let cacheURL = combinedCacheURL(for: platform)
        if FileManager.default.fileExists(atPath: overrideURL.path) {
            try FileManager.default.removeItem(at: overrideURL)
        }
        return try decodeText(at: cacheURL)
    }

    func removeCombined(platform: RelayPlatform) throws {
        let cacheURL = combinedCacheURL(for: platform)
        let overrideURL = combinedOverrideURL(for: platform)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        if FileManager.default.fileExists(atPath: overrideURL.path) {
            try FileManager.default.removeItem(at: overrideURL)
        }
    }

    func removeCombined() throws {
        for platform in RelayPlatform.allCases {
            try removeCombined(platform: platform)
        }
    }

    func replaceAssets(_ assets: [GeneratedAsset], id: UUID) throws {
        let relativeRoot = "assets/\(id.uuidString.lowercased())"
        let root = assetDirectory.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        guard !assets.isEmpty else { return }

        for asset in assets {
            guard asset.relativePath.hasPrefix(relativeRoot + "/") else {
                throw RelayError.invalidOutput("生成脚本的保存路径无效。")
            }
            let fileName = String(asset.relativePath.dropFirst((relativeRoot + "/").count))
            let destination = root.appending(path: fileName)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try asset.data.write(to: destination, options: .atomic)
        }
    }

    func removeAssets(id: UUID) throws {
        let root = assetDirectory.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func generatedAssetFiles() throws -> [PublishFile] {
        guard FileManager.default.fileExists(atPath: assetDirectory.path),
              let enumerator = FileManager.default.enumerator(
                at: assetDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        var files: [PublishFile] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = fileURL.path.replacingOccurrences(of: assetDirectory.path + "/", with: "")
            files.append(PublishFile(name: "assets/\(relative)", data: try Data(contentsOf: fileURL)))
        }
        return files.sorted { $0.name < $1.name }
    }

    private func componentURL(for id: UUID) -> URL {
        componentDirectory.appending(path: "\(id.uuidString).cache")
    }

    private func componentOverrideURL(for id: UUID) -> URL {
        overrideDirectory.appending(path: "\(id.uuidString).module")
    }

    private func decodeText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw RelayError.invalidOutput("模块缓存不是有效的 UTF-8 文本。")
        }
        return content
    }

    private nonisolated static func isManagedCombinedModule(_ data: Data) -> Bool {
        guard let content = String(data: data, encoding: .utf8) else { return false }
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Combined exports include the target platform in the name, for
        // example "Surge Relay (iOS)". Keep the ownership check strict enough
        // to protect user files while accepting all Relay-generated platforms.
        let hasName = lines.contains {
            $0 == "#!name=Surge Relay" || $0.hasPrefix("#!name=Surge Relay (")
        }
        let hasCategory = lines.contains("#!category=Surge Relay")
        let hasAuthor = lines.contains {
            $0 == "#!author=Surge Relay" || $0.hasPrefix("#!author=Surge Relay · ")
        }
        return hasName && hasCategory && hasAuthor
    }

    private nonisolated static func individualMarker(moduleID: UUID) -> String {
        "#!surge-relay-module-id=\(moduleID.uuidString.lowercased())"
    }

    private nonisolated static func managedIndividualData(_ content: String, moduleID: UUID) -> Data {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let marker = individualMarker(moduleID: moduleID)
        let body = normalized.hasSuffix("\n") ? normalized : normalized + "\n"
        return Data((marker + "\n" + body).utf8)
    }

    private nonisolated static func isManagedIndividualModule(_ data: Data, moduleID: UUID) -> Bool {
        guard let content = String(data: data, encoding: .utf8) else { return false }
        let marker = individualMarker(moduleID: moduleID)
        return content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .contains { $0.trimmingCharacters(in: .whitespaces) == marker }
    }

    private nonisolated static func validatedManagedConflictVersions(at url: URL) throws -> [NSFileVersion] {
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        for version in versions {
            let data = try Data(contentsOf: version.url)
            guard isManagedCombinedModule(data) else {
                throw RelayError.invalidOutput("检测到不属于 Surge Relay 的 iCloud 冲突版本，已停止操作。")
            }
        }
        return versions
    }

    private nonisolated static func validatedManagedIndividualConflictVersions(
        at url: URL,
        moduleID: UUID
    ) throws -> [NSFileVersion] {
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        for version in versions {
            let data = try Data(contentsOf: version.url)
            guard isManagedIndividualModule(data, moduleID: moduleID) else {
                throw RelayError.invalidOutput("检测到不属于该 Surge Relay 模块的 iCloud 冲突版本，已停止操作。")
            }
        }
        return versions
    }

    private nonisolated static func resolve(_ versions: [NSFileVersion], at url: URL) throws {
        guard !versions.isEmpty else { return }
        for version in versions { version.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}
