import Foundation
import Testing
@testable import SurgeRelay

struct AirportSubscriptionParserTests {
    @Test func extractsOnlyProxySectionFromFullProfile() throws {
        let profile = """
        [General]
        loglevel = warning
        [Proxy]
        Hong Kong = trojan, example.com, 443, password=secret
        Japan = ss, example.net, 443, encrypt-method=aes-128-gcm, password=secret
        [Proxy Group]
        Select = select, Hong Kong, Japan
        """

        let entries = try AirportSubscriptionParser.proxyEntries(from: Data(profile.utf8))

        #expect(entries.map(\.originalName) == ["Hong Kong", "Japan"])
        #expect(entries[0].definition.hasPrefix("trojan,"))
    }

    @Test func decodesBase64PolicyList() throws {
        let list = "Node A = socks5, 127.0.0.1, 1080\nNode B = http, 127.0.0.1, 8080"
        let encoded = Data(list.utf8).base64EncodedString()

        let entries = try AirportSubscriptionParser.proxyEntries(from: Data(encoded.utf8))

        #expect(entries.map(\.originalName) == ["Node A", "Node B"])
    }

    @Test func filtersEnglishMetadataWithChineseAliases() {
        let pattern = #"^((?!(流量|重置|到期)).)*$"#

        #expect(!AirportSubscriptionParser.name("Traffic: 304 GB", matchesRegex: pattern))
        #expect(!AirportSubscriptionParser.name("Expire: 2027-02-26", matchesRegex: pattern))
        #expect(!AirportSubscriptionParser.name("Reset in 3 days", matchesRegex: pattern))
        #expect(AirportSubscriptionParser.name("🇭🇰 香港实验性 IPEL", matchesRegex: pattern))
    }

    @Test func identifiesOnlyBuiltInDirectEntry() {
        #expect(AirportSubscriptionParser.isBuiltInDirect(
            AirportProxyEntry(originalName: "DIRECT", definition: "direct")
        ))
        #expect(!AirportSubscriptionParser.isBuiltInDirect(
            AirportProxyEntry(originalName: "Direct Server", definition: "socks5, 127.0.0.1, 1080")
        ))
    }

    @Test func appliesAirportNodeNameTemplate() {
        let renamed = AirportSubscriptionParser.renamedNode(
            "香港 01",
            airportName: "FlowerCloud",
            template: "{airport} - {name}"
        )

        #expect(renamed == "FlowerCloud - 香港 01")
        #expect(AirportSubscriptionParser.renamedNode(
            "香港 01",
            airportName: "FlowerCloud",
            template: ""
        ) == "香港 01")
    }

    @Test func optimizesCommonAirportNodeNames() {
        let optimization = AirportNodeNameOptimization()

        #expect(AirportSubscriptionParser.optimizedNodeName(
            "🇭🇰 香港实验性 IEPL 专线 1",
            using: optimization
        ) == "香港实验性 1")
        #expect(AirportSubscriptionParser.optimizedNodeName(
            "🇯🇵 日本 IPEL 8",
            using: optimization
        ) == "日本 8")
    }

    @Test func keepsNumbersAndHonorsCustomRemovalTerms() {
        let optimization = AirportNodeNameOptimization(
            removesEmoji: false,
            removalTerms: "高级, standard"
        )

        #expect(AirportSubscriptionParser.optimizedNodeName(
            "🇺🇸 美国高级 STANDARD 12",
            using: optimization
        ) == "🇺🇸 美国 12")
    }

    @Test func disabledOptimizationPreservesOriginalName() {
        let original = "🇭🇰 香港 IEPL 专线 1"
        let optimization = AirportNodeNameOptimization(isEnabled: false)

        #expect(AirportSubscriptionParser.optimizedNodeName(original, using: optimization) == original)
    }

    @Test func makesOptimizedDuplicateNamesUnique() {
        var usedNames = Set<String>()

        #expect(AirportSubscriptionParser.uniqueNodeName("香港", reserving: &usedNames) == "香港")
        #expect(AirportSubscriptionParser.uniqueNodeName("香港", reserving: &usedNames) == "香港 2")
        #expect(AirportSubscriptionParser.uniqueNodeName("香港 2", reserving: &usedNames) == "香港 2 2")
    }

    @Test func olderSavedAirportsReceiveSafeOptimizationDefaults() throws {
        let data = Data(#"{"name":"Example","sourceURL":"https://example.com/sub"}"#.utf8)

        let subscription = try JSONDecoder().decode(AirportSubscription.self, from: data)

        #expect(subscription.nodeNameOptimization.isEnabled)
        #expect(subscription.nodeNameOptimization.removesEmoji)
        #expect(subscription.nodeNameOptimization.removalTerms == "IEPL, IPEL, 专线")
        #expect(subscription.nodeProcessing.filtersMetadataNodes)
        #expect(subscription.nodeProcessing.sortOrder == .original)
        #expect(subscription.nodeProcessing.udpRelay == .inherit)
    }

    @Test func appliesStructuredIncludeExcludeAndMetadataFilters() {
        var subscription = AirportSubscription(name: "Example")
        subscription.nodeNameOptimization.isEnabled = false
        subscription.nodeProcessing.includeKeywords = ["香港", "日本"]
        subscription.nodeProcessing.excludeKeywords = ["日本"]
        let entries = [
            AirportProxyEntry(originalName: "Traffic: 20 GB", definition: "ss, info.example, 443"),
            AirportProxyEntry(originalName: "香港 1", definition: "ss, hk.example, 443"),
            AirportProxyEntry(originalName: "日本 1", definition: "ss, jp.example, 443"),
            AirportProxyEntry(originalName: "美国 1", definition: "ss, us.example, 443"),
        ]
        var usedNames = Set<String>()

        let result = AirportSubscriptionParser.process(entries, for: subscription, reserving: &usedNames)

        #expect(result.included.map(\.name) == ["香港 1"])
        #expect(result.records.first { $0.originalName.hasPrefix("Traffic") }?.status == "订阅信息")
        #expect(result.records.first { $0.originalName.hasPrefix("日本") }?.status == "命中排除规则")
        #expect(result.records.first { $0.originalName.hasPrefix("美国") }?.status == "不符合保留规则")
    }

    @Test func sortsByKeywordPriorityAndKeepsUnmatchedNodesStable() {
        var subscription = AirportSubscription(name: "Example")
        subscription.nodeNameOptimization.isEnabled = false
        subscription.nodeProcessing.sortOrder = .keywordPriority
        subscription.nodeProcessing.sortPriorityKeywords = ["日本", "香港"]
        let entries = [
            AirportProxyEntry(originalName: "美国 1", definition: "ss, us.example, 443"),
            AirportProxyEntry(originalName: "香港 1", definition: "ss, hk.example, 443"),
            AirportProxyEntry(originalName: "日本 1", definition: "ss, jp.example, 443"),
            AirportProxyEntry(originalName: "美国 2", definition: "ss, us2.example, 443"),
        ]
        var usedNames = Set<String>()

        let result = AirportSubscriptionParser.process(entries, for: subscription, reserving: &usedNames)

        #expect(result.included.map(\.name) == ["日本 1", "香港 1", "美国 1", "美国 2"])
    }

    @Test func appliesCompatibleProxyPropertyOverridesWithoutBreakingQuotedValues() {
        var subscription = AirportSubscription(name: "Example")
        subscription.nodeNameOptimization.isEnabled = false
        subscription.nodeProcessing.udpRelay = .enabled
        subscription.nodeProcessing.tcpFastOpen = .enabled
        subscription.nodeProcessing.skipCertificateVerification = .enabled
        let entries = [
            AirportProxyEntry(
                originalName: "SS",
                definition: "ss, server.example, 443, password=\"a,b\", udp-relay=false, fast-open=false"
            ),
            AirportProxyEntry(
                originalName: "Trojan",
                definition: "trojan, server.example, 443, password=secret, skip-cert-verify=false"
            ),
        ]
        var usedNames = Set<String>()

        let result = AirportSubscriptionParser.process(entries, for: subscription, reserving: &usedNames)

        #expect(result.included[0].definition.contains("password=\"a,b\""))
        #expect(result.included[0].definition.contains("udp-relay=true"))
        #expect(result.included[0].definition.contains("tfo=true"))
        #expect(!result.included[0].definition.contains("skip-cert-verify"))
        #expect(result.included[1].definition.contains("skip-cert-verify=true"))
    }
}
