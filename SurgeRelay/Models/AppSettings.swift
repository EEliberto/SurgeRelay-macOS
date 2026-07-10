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

enum RelayPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case ios = "iOS"
    case macos = "macOS"
    case tvos = "tvOS"
    case visionos = "visionOS"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var summaryIconAssetName: String {
        switch self {
        case .ios: return "SummaryIOSIcon"
        case .macos: return "SummaryMacOSIcon"
        case .tvos: return "SummaryTVOSIcon"
        case .visionos: return "SummaryVisionOSIcon"
        }
    }

    var selectionID: UUID {
        switch self {
        case .ios: return UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        case .macos: return UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        case .tvos: return UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        case .visionos: return UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        }
    }

    static func from(selectionID: UUID) -> RelayPlatform? {
        for platform in allCases {
            if platform.selectionID == selectionID {
                return platform
            }
        }
        return nil
    }
}

struct PlatformSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool = false
    var moduleOrder: [UUID] = []
    var disabledModules: Set<UUID> = []
    var customIconURL: String?
    var customIconSource: CustomIconSource = .manual

    private enum CodingKeys: String, CodingKey {
        case isEnabled, moduleOrder, disabledModules, customIconURL, customIconSource
    }

    init() {}

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        moduleOrder = try container.decodeIfPresent([UUID].self, forKey: .moduleOrder) ?? []
        disabledModules = try container.decodeIfPresent(Set<UUID>.self, forKey: .disabledModules) ?? []
        customIconURL = try container.decodeIfPresent(String.self, forKey: .customIconURL)
        customIconSource = try container.decodeIfPresent(CustomIconSource.self, forKey: .customIconSource) ?? .manual
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
    var platformSettings: [String: PlatformSettings] = [
        RelayPlatform.ios.rawValue: PlatformSettings(isEnabled: true),
        RelayPlatform.macos.rawValue: PlatformSettings(isEnabled: true),
        RelayPlatform.tvos.rawValue: PlatformSettings(isEnabled: false),
        RelayPlatform.visionos.rawValue: PlatformSettings(isEnabled: false)
    ]
    var iconSearchRegion: String = "cn"

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
        platformSettings = try container.decodeIfPresent([String: PlatformSettings].self, forKey: .platformSettings) ?? [
            RelayPlatform.ios.rawValue: PlatformSettings(isEnabled: true),
            RelayPlatform.macos.rawValue: PlatformSettings(isEnabled: true),
            RelayPlatform.tvos.rawValue: PlatformSettings(isEnabled: false),
            RelayPlatform.visionos.rawValue: PlatformSettings(isEnabled: false)
        ]
        iconSearchRegion = try container.decodeIfPresent(String.self, forKey: .iconSearchRegion) ?? "cn"
    }

    var enabledPlatforms: [RelayPlatform] {
        RelayPlatform.allCases.filter { platform in
            platformSettings[platform.rawValue]?.isEnabled ?? false
        }
    }

    func modules(for platform: RelayPlatform, globalModules: [RelayModule]) -> [RelayModule] {
        let settings = platformSettings[platform.rawValue] ?? PlatformSettings()
        let globalLookup = Dictionary(uniqueKeysWithValues: globalModules.map { ($0.id, $0) })
        
        var orderedIds = settings.moduleOrder
        // Filter out any IDs that no longer exist globally
        orderedIds = orderedIds.filter { globalLookup[$0] != nil }
        
        // Append any global modules that are not in the ordered list
        let orderedSet = Set(orderedIds)
        for module in globalModules {
            if !orderedSet.contains(module.id) {
                orderedIds.append(module.id)
            }
        }
        
        // Map to RelayModule and apply platform-specific enabled state
        return orderedIds.compactMap { id -> RelayModule? in
            guard var module = globalLookup[id] else { return nil }
            module.isEnabled = module.isEnabled && !settings.disabledModules.contains(id)
            return module
        }
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

    func localCombinedModuleURL(for platform: RelayPlatform) -> URL? {
        guard storageMode == .local else { return nil }
        let directory = localModuleDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else { return nil }
        let platFileName: String
        if platform == .ios {
            platFileName = FilenameSanitizer.sgmoduleName(from: combinedModuleFileName)
        } else {
            let base = FilenameSanitizer.baseName(from: combinedModuleFileName)
            platFileName = "\(base)-\(platform.rawValue).sgmodule"
        }
        return URL(filePath: directory, directoryHint: .isDirectory)
            .appending(path: platFileName)
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
