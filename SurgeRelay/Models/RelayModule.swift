import Foundation

enum ModuleSourceIdentity {
    static func canonicalValue(for source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return trimmed }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        if (components.scheme == "https" && components.port == 443) ||
            (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }

        return components.string ?? trimmed
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        canonicalValue(for: lhs) == canonicalValue(for: rhs)
    }
}

enum ModuleSourceFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case quantumultX
    case loon
    case surge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "自动识别"
        case .quantumultX: "Quantumult X 重写"
        case .loon: "Loon 插件"
        case .surge: "Surge 模块"
        }
    }

    var shortTitle: String {
        switch self {
        case .automatic: "自动"
        case .quantumultX: "Quantumult X"
        case .loon: "Loon"
        case .surge: "Surge"
        }
    }

    func resolvedFormat(for sourceURL: URL) -> ModuleSourceFormat {
        guard self == .automatic else { return self }
        let path = sourceURL.path.lowercased()
        switch sourceURL.pathExtension.lowercased() {
        case "sgmodule": return .surge
        case "plugin", "lpx": return .loon
        default: break
        }
        if path.contains("/loon/") { return .loon }
        if path.contains("/quantumultx/") || path.contains("/quantumult-x/") || path.contains("/qx/") {
            return .quantumultX
        }
        return .quantumultX
    }

    func scriptHubType(for sourceURL: URL) -> String {
        switch resolvedFormat(for: sourceURL) {
        case .quantumultX: "qx-rewrite"
        case .loon: "loon-plugin"
        case .surge: "surge-module"
        case .automatic: "qx-rewrite"
        }
    }

    func isNativeSurgeModule(for sourceURL: URL) -> Bool {
        resolvedFormat(for: sourceURL) == .surge
    }
}

enum ModuleUpdateState: String, Codable, Sendable {
    case never
    case updating
    case current
    case failed

    var title: String {
        switch self {
        case .never: "尚未更新"
        case .updating: "正在更新"
        case .current: "已是最新"
        case .failed: "更新失败"
        }
    }
}

enum CustomIconSource: String, Codable, Sendable {
    case manual
    case appStore
}

struct RelayModule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sourceURL: String
    var sourceFormat: ModuleSourceFormat
    var outputFileName: String
    var isEnabled: Bool
    var exportsIndividualModuleToICloud: Bool
    var scriptHubOptions: ScriptHubOptions
    var argumentOverrides: [String: String]
    var policyOverrides: [String: String]
    var customRules: [String]
    var customMitM: [String]
    var iconURL: String?
    var customIconURL: String?
    var customIconSource: CustomIconSource
    var detectedSourceFormat: ModuleSourceFormat?
    var createdAt: Date
    var lastUpdatedAt: Date?
    var contentHash: String?
    var sourceETag: String?
    var sourceLastModified: String?
    var sourceContentHash: String?
    var sourceCheckedAt: Date?
    var conversionEngineRevision: String?
    var overrideBaseHash: String?
    var hasOverrideConflict: Bool
    var state: ModuleUpdateState
    var lastError: String?

    init(
        id: UUID = UUID(),
        name: String,
        sourceURL: String,
        sourceFormat: ModuleSourceFormat = .automatic,
        outputFileName: String,
        isEnabled: Bool = true,
        exportsIndividualModuleToICloud: Bool = false,
        scriptHubOptions: ScriptHubOptions = ScriptHubOptions(),
        argumentOverrides: [String: String] = [:],
        policyOverrides: [String: String] = [:],
        customRules: [String] = [],
        customMitM: [String] = [],
        iconURL: String? = nil,
        customIconURL: String? = nil,
        customIconSource: CustomIconSource = .manual,
        detectedSourceFormat: ModuleSourceFormat? = nil,
        createdAt: Date = .now,
        lastUpdatedAt: Date? = nil,
        contentHash: String? = nil,
        sourceETag: String? = nil,
        sourceLastModified: String? = nil,
        sourceContentHash: String? = nil,
        sourceCheckedAt: Date? = nil,
        conversionEngineRevision: String? = nil,
        overrideBaseHash: String? = nil,
        hasOverrideConflict: Bool = false,
        state: ModuleUpdateState = .never,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.sourceFormat = sourceFormat
        self.outputFileName = FilenameSanitizer.sgmoduleName(from: outputFileName)
        self.isEnabled = isEnabled
        self.exportsIndividualModuleToICloud = exportsIndividualModuleToICloud
        self.scriptHubOptions = scriptHubOptions
        self.argumentOverrides = argumentOverrides
        self.policyOverrides = policyOverrides
        self.customRules = customRules
        self.customMitM = customMitM
        self.iconURL = iconURL
        self.customIconURL = customIconURL
        self.customIconSource = customIconSource
        self.detectedSourceFormat = detectedSourceFormat
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.contentHash = contentHash
        self.sourceETag = sourceETag
        self.sourceLastModified = sourceLastModified
        self.sourceContentHash = sourceContentHash
        self.sourceCheckedAt = sourceCheckedAt
        self.conversionEngineRevision = conversionEngineRevision
        self.overrideBaseHash = overrideBaseHash
        self.hasOverrideConflict = hasOverrideConflict
        self.state = state
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sourceURL, sourceFormat, outputFileName, isEnabled, exportsIndividualModuleToICloud, scriptHubOptions, argumentOverrides, policyOverrides, customRules, customMitM, iconURL, customIconURL, customIconSource, detectedSourceFormat
        case createdAt, lastUpdatedAt, contentHash, sourceETag, sourceLastModified, sourceContentHash, sourceCheckedAt
        case conversionEngineRevision, overrideBaseHash, hasOverrideConflict, state, lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        sourceFormat = try container.decodeIfPresent(ModuleSourceFormat.self, forKey: .sourceFormat) ?? .automatic
        outputFileName = try container.decodeIfPresent(String.self, forKey: .outputFileName)
            ?? FilenameSanitizer.suggestedName(from: sourceURL)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        exportsIndividualModuleToICloud = try container.decodeIfPresent(
            Bool.self,
            forKey: .exportsIndividualModuleToICloud
        ) ?? false
        scriptHubOptions = try container.decodeIfPresent(ScriptHubOptions.self, forKey: .scriptHubOptions) ?? ScriptHubOptions()
        argumentOverrides = try container.decodeIfPresent([String: String].self, forKey: .argumentOverrides) ?? [:]
        policyOverrides = try container.decodeIfPresent([String: String].self, forKey: .policyOverrides) ?? [:]
        customRules = try container.decodeIfPresent([String].self, forKey: .customRules) ?? []
        customMitM = try container.decodeIfPresent([String].self, forKey: .customMitM) ?? []
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        customIconURL = try container.decodeIfPresent(String.self, forKey: .customIconURL)
        customIconSource = try container.decodeIfPresent(CustomIconSource.self, forKey: .customIconSource) ?? .manual
        detectedSourceFormat = try container.decodeIfPresent(ModuleSourceFormat.self, forKey: .detectedSourceFormat)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        sourceETag = try container.decodeIfPresent(String.self, forKey: .sourceETag)
        sourceLastModified = try container.decodeIfPresent(String.self, forKey: .sourceLastModified)
        sourceContentHash = try container.decodeIfPresent(String.self, forKey: .sourceContentHash)
        sourceCheckedAt = try container.decodeIfPresent(Date.self, forKey: .sourceCheckedAt)
        conversionEngineRevision = try container.decodeIfPresent(String.self, forKey: .conversionEngineRevision)
        overrideBaseHash = try container.decodeIfPresent(String.self, forKey: .overrideBaseHash)
        hasOverrideConflict = try container.decodeIfPresent(Bool.self, forKey: .hasOverrideConflict) ?? false
        state = try container.decodeIfPresent(ModuleUpdateState.self, forKey: .state) ?? .never
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    var sourceFormatDisplayTitle: String {
        guard sourceFormat == .automatic else { return sourceFormat.title }
        let resolved = detectedSourceFormat ?? URL(string: sourceURL).map { sourceFormat.resolvedFormat(for: $0) }
        guard let resolved else { return sourceFormat.title }
        return "自动识别（\(resolved.shortTitle)）"
    }
}

struct ModuleDraft: Sendable {
    var name = ""
    var sourceURL = ""
    var sourceFormat: ModuleSourceFormat = .automatic
    var outputFileName = ""
    var isEnabled = true
    var scriptHubOptions = ScriptHubOptions()

    init() {}

    init(module: RelayModule) {
        name = module.name
        sourceURL = module.sourceURL
        sourceFormat = module.sourceFormat
        outputFileName = module.outputFileName
        isEnabled = module.isEnabled
        scriptHubOptions = module.scriptHubOptions
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入模块名称。" }
        guard let url = URL(string: sourceURL), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return "请输入有效的 HTTP 或 HTTPS 来源地址。"
        }
        return nil
    }
}
