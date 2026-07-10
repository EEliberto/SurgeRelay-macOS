import Foundation

enum PersistenceStore {
    private static let configurationDirectoryKey = "SurgeRelay.configurationDirectory.v1"
    private static let initialSetupCompletedKey = "SurgeRelay.initialSetupCompleted.v1"
    private static let initialSetupLoadedExistingKey = "SurgeRelay.initialSetupLoadedExisting.v1"
    private static let legacySettingsKey = "SurgeRelay.settings.v1"
    private static let legacyUpstreamKey = "SurgeRelay.upstream.v1"

    static var hasSelectedConfigurationDirectory: Bool {
        UserDefaults.standard.string(forKey: configurationDirectoryKey) != nil
    }

    static var hasCompletedInitialSetup: Bool {
        if UserDefaults.standard.object(forKey: initialSetupCompletedKey) != nil {
            return UserDefaults.standard.bool(forKey: initialSetupCompletedKey)
        }
        // Existing installations already completed the older directory prompt.
        return hasSelectedConfigurationDirectory
    }

    static func markInitialSetupPending() {
        UserDefaults.standard.set(false, forKey: initialSetupCompletedKey)
    }

    static func markInitialSetupCompleted() {
        UserDefaults.standard.set(true, forKey: initialSetupCompletedKey)
    }

    static var initialSetupLoadedExistingConfiguration: Bool {
        UserDefaults.standard.bool(forKey: initialSetupLoadedExistingKey)
    }

    static func setInitialSetupLoadedExistingConfiguration(_ loadedExisting: Bool) {
        UserDefaults.standard.set(loadedExisting, forKey: initialSetupLoadedExistingKey)
    }

    static var configurationDirectoryURL: URL {
        let path = UserDefaults.standard.string(forKey: configurationDirectoryKey)
            ?? AppSettings.defaultConfigurationDirectory
        let directory = URL(filePath: path, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var cacheDirectoryURL: URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Surge Relay/Cache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var registryURL: URL {
        configurationDirectoryURL.appending(path: "modules.json")
    }

    static var settingsURL: URL {
        configurationDirectoryURL.appending(path: "settings.json")
    }

    static var settingsBackupURL: URL {
        configurationDirectoryURL.appending(path: "settings.json.bak")
    }

    static var upstreamStateURL: URL {
        configurationDirectoryURL.appending(path: "script-hub-state.json")
    }

    static var updateHistoryURL: URL {
        configurationDirectoryURL.appending(path: "update-history.json")
    }

    static func loadModules() -> [RelayModule] {
        if let modules: [RelayModule] = decodeFile(at: registryURL) {
            return modules
        }
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Surge Relay/modules.json")
        guard let modules: [RelayModule] = decodeFile(at: legacyURL) else { return [] }
        try? saveModules(modules)
        return modules
    }

    static func saveModules(_ modules: [RelayModule]) throws {
        try write(modules, to: registryURL)
    }

    static func loadSettings() -> AppSettings {
        if let settings: AppSettings = decodeFile(at: settingsURL) {
            return settings
        }
        if let settings: AppSettings = decodeFile(at: settingsBackupURL) {
            saveSettings(settings)
            return settings
        }
        if let data = UserDefaults.standard.data(forKey: legacySettingsKey),
           let settings = try? decoder.decode(AppSettings.self, from: data) {
            saveSettings(settings)
            return settings
        }
        let settings = AppSettings()
        return settings
    }

    static func saveSettings(_ settings: AppSettings) {
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            try? FileManager.default.removeItem(at: settingsBackupURL)
            try? FileManager.default.copyItem(at: settingsURL, to: settingsBackupURL)
        }
        try? write(settings, to: settingsURL)
    }

    static func loadUpstreamState() -> ScriptHubUpstreamState {
        if let state: ScriptHubUpstreamState = decodeFile(at: upstreamStateURL) {
            return state
        }
        if let data = UserDefaults.standard.data(forKey: legacyUpstreamKey),
           let state = try? decoder.decode(ScriptHubUpstreamState.self, from: data) {
            saveUpstreamState(state)
            return state
        }
        return ScriptHubUpstreamState()
    }

    static func saveUpstreamState(_ state: ScriptHubUpstreamState) {
        try? write(state, to: upstreamStateURL)
    }

    static func loadUpdateHistory() -> [UpdateHistoryEntry] {
        decodeFile(at: updateHistoryURL) ?? []
    }

    static func saveUpdateHistory(_ entries: [UpdateHistoryEntry]) {
        try? write(Array(entries.prefix(200)), to: updateHistoryURL)
    }

    static func useConfigurationDirectory(_ path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let sourceDirectory = configurationDirectoryURL
        let directory = URL(filePath: trimmed, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try migrateOverrides(from: sourceDirectory, to: directory)
        UserDefaults.standard.set(directory.path, forKey: configurationDirectoryKey)
    }

    /// Selects a configuration directory on a new Mac without migrating the
    /// temporary/default configuration over an existing iCloud copy.
    static func selectConfigurationDirectory(_ path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let directory = URL(filePath: trimmed, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        UserDefaults.standard.set(directory.path, forKey: configurationDirectoryKey)
    }

    static func migrateOverrides(from sourceDirectory: URL, to destinationDirectory: URL) throws {
        let sourceDirectory = sourceDirectory.standardizedFileURL
        let destinationDirectory = destinationDirectory.standardizedFileURL
        guard sourceDirectory != destinationDirectory else { return }

        let fileManager = FileManager.default
        let sourceRoot = sourceDirectory.appending(path: "Overrides", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: sourceRoot.path) else { return }

        let destinationRoot = destinationDirectory.appending(path: "Overrides", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        for relativePath in try fileManager.subpathsOfDirectory(atPath: sourceRoot.path) {
            let sourceURL = sourceRoot.appending(path: relativePath)
            let destinationURL = destinationRoot.appending(path: relativePath)
            let isDirectory = try sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
            }
        }
    }

    private static func decodeFile<Value: Decodable>(at url: URL) -> Value? {
        if let data = try? Data(contentsOf: url),
           let value = try? decoder.decode(Value.self, from: data) {
            return value
        }
        for backup in backupFiles(for: url) {
            guard let data = try? Data(contentsOf: backup),
                  let value = try? decoder.decode(Value.self, from: data) else { continue }
            preserveCorruptFile(at: url)
            try? data.write(to: url, options: .atomic)
            return value
        }
        return nil
    }

    private static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try writeProtectedData(encoder.encode(value), to: url)
    }

    static func writeProtectedData(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: url) {
            guard existing != data else { return }
            try createBackup(of: url, data: existing)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func createBackup(of url: URL, data: Data) throws {
        let directory = configurationDirectoryURL
            .appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: url.lastPathComponent, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let destination = directory.appending(path: "\(stamp)-\(UUID().uuidString.prefix(6)).backup")
        try data.write(to: destination, options: .atomic)
        let files = backupFiles(for: url)
        for expired in files.dropFirst(20) {
            try? FileManager.default.removeItem(at: expired)
        }
    }

    private static func backupFiles(for url: URL) -> [URL] {
        let directory = configurationDirectoryURL
            .appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: url.lastPathComponent, directoryHint: .isDirectory)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted {
            let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    private static func preserveCorruptFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let destination = url.deletingLastPathComponent()
            .appending(path: "\(url.lastPathComponent).corrupt-\(Int(Date.now.timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
