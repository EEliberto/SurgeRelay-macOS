import Foundation

enum RefreshPolicy {
    static func isDue(lastUpdatedAt: Date?, intervalMinutes: Int, now: Date = .now) -> Bool {
        guard intervalMinutes > 0 else { return false }
        guard let lastUpdatedAt else { return true }
        return now.timeIntervalSince(lastUpdatedAt) >= Double(intervalMinutes * 60)
    }
}

struct GitHubSettings: Codable, Equatable, Sendable {
    var owner = "EEliberto"
    var repository = "Surge-Relay"
    var branch = "main"
    var directory = "modules"
    var publicBaseURL = ""
    var repositoryIsPrivate: Bool?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? "EEliberto"
        repository = try container.decodeIfPresent(String.self, forKey: .repository) ?? "Surge-Relay"
        branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? "main"
        directory = try container.decodeIfPresent(String.self, forKey: .directory) ?? "modules"
        publicBaseURL = try container.decodeIfPresent(String.self, forKey: .publicBaseURL) ?? ""
        repositoryIsPrivate = try container.decodeIfPresent(Bool.self, forKey: .repositoryIsPrivate)
    }

    var isConfigured: Bool {
        !owner.isEmpty && !repository.isEmpty && !branch.isEmpty
    }

    var hasValidCloudflarePublicBaseURL: Bool {
        let value = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return false
        }
        return true
    }

    func rawURL(for fileName: String) -> URL? {
        guard isConfigured else { return nil }
        let components = [owner, repository, branch, directory, fileName]
            .filter { !$0.isEmpty }
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
        return URL(string: "https://raw.githubusercontent.com/\(components.joined(separator: "/"))")
    }

    func publicURL(for fileName: String) -> URL? {
        guard repositoryIsPrivate == true, hasValidCloudflarePublicBaseURL else { return nil }
        let base = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = fileName.split(separator: "/").map { component in
            String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
        }.joined(separator: "/")
        return URL(string: "\(base)/\(path)")
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    static let fixedCombinedModuleFileName = "Surge-Relay.sgmodule"

    // Retained only so settings written by early builds continue to decode.
    // Surge Relay no longer scans or cleans this directory.
    var outputDirectory: String = AppSettings.defaultOutputDirectory
    var scriptHubModuleURL = "https://raw.githubusercontent.com/Script-Hub-Org/Script-Hub/main/modules/script-hub.surge.sgmodule"
    private(set) var combinedModuleFileName = Self.fixedCombinedModuleFileName
    // Retained so existing settings decode cleanly during migration.
    var scriptHubBaseURL = "http://script.hub"
    var managedEngineFileName = "Script-Hub-Relay.sgmodule"
    var automaticallyUpdateScriptHub = true
    var refreshIntervalMinutes = 60
    var automaticallyPublish = true
    var launchAtLogin = false
    var github = GitHubSettings()
    var githubToken = ""
    var storageMode: StorageMode = .gitHub
    var localModuleDirectory: String = AppSettings.defaultSurgeDirectory
    var webServerEnabled = false
    var webServerPort = 8787

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputDirectory = try container.decodeIfPresent(String.self, forKey: .outputDirectory) ?? Self.defaultOutputDirectory
        scriptHubModuleURL = try container.decodeIfPresent(String.self, forKey: .scriptHubModuleURL)
            ?? "https://raw.githubusercontent.com/Script-Hub-Org/Script-Hub/main/modules/script-hub.surge.sgmodule"
        combinedModuleFileName = Self.fixedCombinedModuleFileName
        scriptHubBaseURL = try container.decodeIfPresent(String.self, forKey: .scriptHubBaseURL) ?? "http://script.hub"
        managedEngineFileName = try container.decodeIfPresent(String.self, forKey: .managedEngineFileName) ?? "Script-Hub-Relay.sgmodule"
        automaticallyUpdateScriptHub = try container.decodeIfPresent(Bool.self, forKey: .automaticallyUpdateScriptHub) ?? true
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 60
        automaticallyPublish = try container.decodeIfPresent(Bool.self, forKey: .automaticallyPublish) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        github = try container.decodeIfPresent(GitHubSettings.self, forKey: .github) ?? GitHubSettings()
        githubToken = try container.decodeIfPresent(String.self, forKey: .githubToken) ?? ""
        storageMode = try container.decodeIfPresent(StorageMode.self, forKey: .storageMode) ?? .gitHub
        localModuleDirectory = try container.decodeIfPresent(String.self, forKey: .localModuleDirectory) ?? Self.defaultSurgeDirectory
        webServerEnabled = try container.decodeIfPresent(Bool.self, forKey: .webServerEnabled) ?? false
        webServerPort = try container.decodeIfPresent(Int.self, forKey: .webServerPort) ?? 8787
    }

    static var defaultOutputDirectory: String {
        defaultConfigurationDirectory
    }

    static var defaultSurgeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/iCloud~com~nssurge~inc/Documents", directoryHint: .isDirectory)
            .path
    }

    static var defaultConfigurationDirectory: String {
        URL(filePath: defaultSurgeDirectory, directoryHint: .isDirectory)
            .appending(path: "Surge Relay", directoryHint: .isDirectory)
            .path
    }

    static func surgeDirectory(forSelectedDirectory selectedDirectory: URL) -> URL {
        let selectedDirectory = selectedDirectory.standardizedFileURL
        if selectedDirectory.lastPathComponent.caseInsensitiveCompare("Surge Relay") == .orderedSame {
            return selectedDirectory.deletingLastPathComponent()
        }
        return selectedDirectory
    }

    static func configurationDirectory(forSurgeDirectory surgeDirectory: URL) -> URL {
        surgeDirectory.standardizedFileURL
            .appending(path: "Surge Relay", directoryHint: .isDirectory)
    }

    func publishedURL(for fileName: String) -> URL? {
        guard storageMode == .gitHub else { return nil }
        return github.publicURL(for: fileName)
    }

    var localCombinedModuleURL: URL? {
        guard storageMode == .local else { return nil }
        let directory = localModuleDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else { return nil }
        return URL(filePath: directory, directoryHint: .isDirectory)
            .appending(path: FilenameSanitizer.sgmoduleName(from: combinedModuleFileName))
    }
}

enum StorageMode: String, Codable, Sendable {
    case local
    case gitHub
}

struct ScriptHubUpstreamState: Codable, Equatable, Sendable {
    var revision: String?
    var lastCheckedAt: Date?
    var lastUpdatedAt: Date?
    var lastError: String?
}

enum SidebarDestination: String, CaseIterable, Hashable, Identifiable {
    case modules
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modules: "模块"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .modules: "shippingbox"
        case .settings: "gear"
        }
    }
}
