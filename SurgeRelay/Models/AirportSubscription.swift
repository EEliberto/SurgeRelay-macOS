import Foundation

struct AirportSubscription: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var sourceURL = ""
    var policyRegexFilter = ""
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
}

struct AirportSubscriptionDraft: Equatable {
    var name = ""
    var sourceURL = ""
    var policyRegexFilter = ""
    var iconURL = ""
    var isEnabled = true

    init() {}

    init(subscription: AirportSubscription) {
        name = subscription.name
        sourceURL = subscription.sourceURL
        policyRegexFilter = subscription.policyRegexFilter
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
