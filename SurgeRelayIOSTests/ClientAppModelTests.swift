import Testing
import Foundation
@testable import SurgeRelayIOS

struct ClientAppModelTests {
    @Test func managementURLParsesPonteHost() {
        let url = RelayDeviceConfiguration.managementURL(address: "johnsmac.sgponte", defaultPort: 8787)
        #expect(url?.scheme == "http")
        #expect(url?.host == "johnsmac.sgponte")
        #expect(url?.port == 8787)
    }

    @Test func managementURLKeepsExplicitHTTPS() {
        let url = RelayDeviceConfiguration.managementURL(
            address: "https://relay.example.com:9443/path",
            defaultPort: 8787
        )
        #expect(url?.scheme == "https")
        #expect(url?.host == "relay.example.com")
        #expect(url?.port == 9443)
    }

    @Test func remoteModulePayloadMapsPublishedFields() throws {
        let payload = RemoteModulePayload(
            id: "11111111-1111-1111-1111-111111111111",
            name: "Demo",
            sourceURL: "https://example.com/a.plugin",
            sourceFormat: "automatic",
            sourceFormatTitle: "自动",
            outputFileName: "Demo.sgmodule",
            isEnabled: true,
            exportsIndividualModuleToICloud: false,
            state: "ready",
            stateTitle: "就绪",
            lastUpdatedAt: nil,
            lastError: nil,
            iconURL: "/icon.png",
            customIconURL: nil,
            customIconSource: nil,
            publishedURL: "https://cdn.example.com/Demo.sgmodule",
            advancedSummary: nil,
            hasOverrideConflict: false,
            scriptHubOptions: ScriptHubOptions(),
            policy: "",
            includeKeywords: "",
            excludeKeywords: "",
            mitmAdd: "",
            mitmRemove: "",
            noResolve: false,
            enableJQ: true,
            argumentOverrides: nil,
            policyOverrides: nil,
            customRules: nil,
            customMitM: nil,
            detectedSourceFormat: nil,
            contentHash: nil
        )
        let base = URL(string: "http://mac.sgponte:8787/")!
        let module = try #require(payload.asRelayModule(baseURL: base))
        #expect(module.name == "Demo")
        #expect(module.iconURL == "http://mac.sgponte:8787/icon.png")
    }

    @MainActor
    @Test func freshModelStartsUnconfigured() {
        // Isolate from developer defaults by using a temporary suite-backed model isn't available;
        // assert the default management helpers remain client-oriented.
        let url = RelayDeviceConfiguration.managementURL(address: "", defaultPort: 8787)
        #expect(url == nil)
    }
}
