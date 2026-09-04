import Foundation

struct AirportNodeNameOptimization: Codable, Equatable, Sendable {
    static let defaultRemovalTerms = "IEPL, IPEL, 专线"

    var isEnabled: Bool
    var removesEmoji: Bool
    var removalTerms: String

    init(
        isEnabled: Bool = true,
        removesEmoji: Bool = true,
        removalTerms: String = defaultRemovalTerms
    ) {
        self.isEnabled = isEnabled
        self.removesEmoji = removesEmoji
        self.removalTerms = removalTerms
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, removesEmoji, removalTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        removesEmoji = try container.decodeIfPresent(Bool.self, forKey: .removesEmoji) ?? true
        removalTerms = try container.decodeIfPresent(String.self, forKey: .removalTerms)
            ?? Self.defaultRemovalTerms
    }
}

enum AirportNodeSortOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case nameAscending
    case nameDescending
    case keywordPriority

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: "订阅原始顺序"
        case .nameAscending: "名称升序"
        case .nameDescending: "名称降序"
        case .keywordPriority: "关键词优先级"
        }
    }
}

enum AirportProxyOptionOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case enabled
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inherit: "跟随订阅"
        case .enabled: "开启"
        case .disabled: "关闭"
        }
    }

    var boolValue: Bool? {
        switch self {
        case .inherit: nil
        case .enabled: true
        case .disabled: false
        }
    }
}

struct AirportNodeProcessingOptions: Codable, Equatable, Sendable {
    var filtersMetadataNodes: Bool
    var includeKeywords: [String]
    var excludeKeywords: [String]
    var sortOrder: AirportNodeSortOrder
    var sortPriorityKeywords: [String]
    var udpRelay: AirportProxyOptionOverride
    var tcpFastOpen: AirportProxyOptionOverride
    var skipCertificateVerification: AirportProxyOptionOverride

    init(
        filtersMetadataNodes: Bool = true,
        includeKeywords: [String] = [],
        excludeKeywords: [String] = [],
        sortOrder: AirportNodeSortOrder = .original,
        sortPriorityKeywords: [String] = [],
        udpRelay: AirportProxyOptionOverride = .inherit,
        tcpFastOpen: AirportProxyOptionOverride = .inherit,
        skipCertificateVerification: AirportProxyOptionOverride = .inherit
    ) {
        self.filtersMetadataNodes = filtersMetadataNodes
        self.includeKeywords = includeKeywords
        self.excludeKeywords = excludeKeywords
        self.sortOrder = sortOrder
        self.sortPriorityKeywords = sortPriorityKeywords
        self.udpRelay = udpRelay
        self.tcpFastOpen = tcpFastOpen
        self.skipCertificateVerification = skipCertificateVerification
    }

    private enum CodingKeys: String, CodingKey {
        case filtersMetadataNodes, includeKeywords, excludeKeywords, sortOrder, sortPriorityKeywords
        case udpRelay, tcpFastOpen, skipCertificateVerification
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filtersMetadataNodes = try container.decodeIfPresent(Bool.self, forKey: .filtersMetadataNodes) ?? true
        includeKeywords = try container.decodeIfPresent([String].self, forKey: .includeKeywords) ?? []
        excludeKeywords = try container.decodeIfPresent([String].self, forKey: .excludeKeywords) ?? []
        sortOrder = try container.decodeIfPresent(AirportNodeSortOrder.self, forKey: .sortOrder) ?? .original
        sortPriorityKeywords = try container.decodeIfPresent([String].self, forKey: .sortPriorityKeywords) ?? []
        udpRelay = try container.decodeIfPresent(AirportProxyOptionOverride.self, forKey: .udpRelay) ?? .inherit
        tcpFastOpen = try container.decodeIfPresent(AirportProxyOptionOverride.self, forKey: .tcpFastOpen) ?? .inherit
        skipCertificateVerification = try container.decodeIfPresent(
            AirportProxyOptionOverride.self,
            forKey: .skipCertificateVerification
        ) ?? .inherit
    }
}

struct AirportSubscription: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var sourceURL = ""
    var policyRegexFilter = ""
    var nodeNameTemplate = ""
    var nodeNameOptimization = AirportNodeNameOptimization()
    var nodeProcessing = AirportNodeProcessingOptions()
    var iconURL = ""
    var isEnabled = true
    var lastUpdatedAt: Date?
    var lastError: String?

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        guard !trimmedName.isEmpty,
              let url = URL(string: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        sourceURL: String = "",
        policyRegexFilter: String = "",
        nodeNameTemplate: String = "",
        nodeNameOptimization: AirportNodeNameOptimization = AirportNodeNameOptimization(),
        nodeProcessing: AirportNodeProcessingOptions = AirportNodeProcessingOptions(),
        iconURL: String = "",
        isEnabled: Bool = true,
        lastUpdatedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.policyRegexFilter = policyRegexFilter
        self.nodeNameTemplate = nodeNameTemplate
        self.nodeNameOptimization = nodeNameOptimization
        self.nodeProcessing = nodeProcessing
        self.iconURL = iconURL
        self.isEnabled = isEnabled
        self.lastUpdatedAt = lastUpdatedAt
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sourceURL, policyRegexFilter, nodeNameTemplate, nodeNameOptimization, nodeProcessing, iconURL
        case isEnabled, lastUpdatedAt, lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        policyRegexFilter = try container.decodeIfPresent(String.self, forKey: .policyRegexFilter) ?? ""
        nodeNameTemplate = try container.decodeIfPresent(String.self, forKey: .nodeNameTemplate) ?? ""
        nodeNameOptimization = try container.decodeIfPresent(
            AirportNodeNameOptimization.self,
            forKey: .nodeNameOptimization
        ) ?? AirportNodeNameOptimization()
        nodeProcessing = try container.decodeIfPresent(
            AirportNodeProcessingOptions.self,
            forKey: .nodeProcessing
        ) ?? AirportNodeProcessingOptions()
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct AirportSubscriptionDraft: Equatable {
    var name = ""
    var sourceURL = ""
    var policyRegexFilter = ""
    var nodeNameTemplate = ""
    var nodeNameOptimization = AirportNodeNameOptimization()
    var nodeProcessing = AirportNodeProcessingOptions()
    var iconURL = ""
    var isEnabled = true

    init() {}

    init(subscription: AirportSubscription) {
        name = subscription.name
        sourceURL = subscription.sourceURL
        policyRegexFilter = subscription.policyRegexFilter
        nodeNameTemplate = subscription.nodeNameTemplate
        nodeNameOptimization = subscription.nodeNameOptimization
        nodeProcessing = subscription.nodeProcessing
        iconURL = subscription.iconURL
        isEnabled = subscription.isEnabled
    }
}

enum AirportSubscriptionSummary {
    static let selectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
}

struct SurgeConfigurationTarget: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var path: String
    var isEnabled = true
    var lastWrittenAt: Date?

    var url: URL { URL(filePath: path) }
}
