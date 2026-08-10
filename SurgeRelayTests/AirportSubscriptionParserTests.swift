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
}
