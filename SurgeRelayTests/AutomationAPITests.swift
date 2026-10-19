import XCTest
@testable import SurgeRelay

@MainActor
final class AutomationAPITests: XCTestCase {
    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                         token: String = String(repeating: "a", count: 64), loopback: Bool = true,
                         extraHeaders: [String: String] = [:]) throws -> WebHTTPRequest {
        WebHTTPRequest(method: method, path: "/api/v1/" + path, query: [:],
                       headers: ["host": "127.0.0.1:8787", "authorization": "Bearer " + token].merging(extraHeaders) { _, new in new },
                       body: try body.map(AutomationAPI.data) ?? Data(), isLoopback: loopback)
    }
    private func model() -> AppModel {
        let model = AppModel()
        model.deviceMode = .server
        model.modules = []; model.airportSubscriptions = []; model.surgeConfigurationTargets = []
        model.automationAccess = AutomationAccess(enabled: true, token: String(repeating: "a", count: 64))
        model.settings.storageMode = .gitHub
        model.settings.automaticallyPublish = false
        return model
    }
    func testAccessRejectsRemoteBrowserAndWrongTokens() throws {
        let access = AutomationAccess(enabled: true, token: String(repeating: "a", count: 64))
        XCTAssertTrue(access.authorizes(try request("capabilities")))
        XCTAssertFalse(access.authorizes(try request("capabilities", token: String(repeating: "b", count: 64))))
        XCTAssertFalse(access.authorizes(try request("capabilities", loopback: false)))
        XCTAssertFalse(access.authorizes(try request("capabilities", extraHeaders: ["origin": "https://example.com"])))
        XCTAssertFalse(access.authorizes(try request("capabilities", extraHeaders: ["host": "evil.example:8787"])))
        XCTAssertFalse(AutomationAccess().authorizes(try request("capabilities")))
    }
    func testCapabilitiesAndListsExcludeCredentials() async throws {
        let model = model()
        model.settings.githubToken = "private-github-token"
        model.airportSubscriptions = [AirportSubscription(name: "Test", sourceURL: "https://user:password@example.com/sub?token=private-sub-token")]
        let response = await model.automationAPI.response(for: try request("airports"), model: model)
        XCTAssertEqual(response.status, 200)
        let text = String(decoding: response.body, as: UTF8.self)
        XCTAssertFalse(text.contains("private-sub-token")); XCTAssertFalse(text.contains("password"))
        XCTAssertFalse(text.contains("private-github-token"))
    }
    func testPlanPreservesNestedFieldsAndRejectsStaleApply() async throws {
        let model = model()
        model.automationAccess.allowEdits = true
        let airport = AirportSubscription(name: "Airport", sourceURL: "https://example.com/sub")
        model.airportSubscriptions = [airport]
        let read = await model.automationAPI.response(for: try request("airports/\(airport.id)"), model: model)
        let object = try AutomationAPI.dictionary(read.body)
        let revision = try XCTUnwrap(object["revision"] as? String)
        let planResponse = await model.automationAPI.response(for: try request("plans", method: "POST", body: [
            "kind": "airport.settings", "id": airport.id.uuidString, "baseRevision": revision,
            "changes": ["nodeProcessing": ["includeKeywords": ["香港"]]]
        ]), model: model)
        XCTAssertEqual(planResponse.status, 200)
        XCTAssertTrue(model.airportSubscriptions[0].nodeProcessing.includeKeywords.isEmpty)
        let plan = try AutomationAPI.dictionary(planResponse.body)
        let after = try XCTUnwrap(plan["after"] as? [String: Any])
        let processing = try XCTUnwrap(after["nodeProcessing"] as? [String: Any])
        XCTAssertEqual(processing["filtersMetadataNodes"] as? Bool, true)
        XCTAssertEqual(processing["includeKeywords"] as? [String], ["香港"])
        model.airportSubscriptions[0].name = "Changed in App"
        let id = try XCTUnwrap(plan["planID"] as? String)
        let apply = await model.automationAPI.response(for: try request("plans/\(id)/apply", method: "POST"), model: model)
        XCTAssertEqual(apply.status, 409)
        XCTAssertEqual(model.airportSubscriptions[0].name, "Changed in App")
    }
    func testPermissionsUnknownFieldsAndRevocation() async throws {
        let model = model()
        let denied = await model.automationAPI.response(for: try request("jobs", method: "POST", body: ["action": "publish"]), model: model)
        XCTAssertEqual(denied.status, 403)
        XCTAssertThrowsError(try AutomationAPI.merge(["name": "test"], changes: ["sourceURL": "https://evil.example"]))
        model.automationAccess.resetToken()
        let revoked = await model.automationAPI.response(for: try request("capabilities"), model: model)
        XCTAssertEqual(revoked.status, 403)
    }
    func testAutomaticPublishRequiresPublishPermission() async throws {
        let model = model()
        model.automationAccess.allowRefresh = true
        model.settings.automaticallyPublish = true
        let denied = await model.automationAPI.response(for: try request("jobs", method: "POST", body: ["action": "refreshModules"]), model: model)
        XCTAssertEqual(denied.status, 403)
        model.settings.automaticallyPublish = false
        var module = RelayModule(name: "Individual", sourceURL: "https://example.com/a", outputFileName: "a")
        module.exportsIndividualModuleToICloud = true
        model.modules = [module]
        let exportDenied = await model.automationAPI.response(for: try request("jobs", method: "POST", body: ["action": "refreshModules"]), model: model)
        XCTAssertEqual(exportDenied.status, 403)
    }
    func testStrictPartialPatchValidation() throws {
        let module = RelayModule(name: "A", sourceURL: "https://example.com/a.sgmodule", outputFileName: "A")
        let fields = try AutomationAPI.moduleSettings(module)
        let patch = try AutomationAPI.merge(fields, changes: ["refreshIntervalMinutes": 15])
        let draft = try AutomationAPI.moduleDraft(patch, module: module)
        XCTAssertEqual(draft.sourceURL, module.sourceURL)
        XCTAssertEqual(draft.refreshIntervalMinutes, 15)
        XCTAssertThrowsError(try AutomationAPI.moduleDraft(AutomationAPI.merge(fields, changes: ["refreshIntervalMinutes": 20000]), module: module))
        XCTAssertThrowsError(try AutomationAPI.moduleDraft(AutomationAPI.merge(fields, changes: ["name": false]), module: module))
    }
    func testApplyPreservesOtherSettingsAndCannotReplay() async throws {
        let model = model()
        model.automationAccess.allowEdits = true
        var airport = AirportSubscription(name: "Test", sourceURL: "https://example.com/sub")
        airport.nodeProcessing.excludeKeywords = ["test"]
        model.airportSubscriptions = [airport]
        let read = await model.automationAPI.response(for: try request("airports/\(airport.id)"), model: model)
        let revision = try XCTUnwrap(AutomationAPI.dictionary(read.body)["revision"] as? String)
        let response = await model.automationAPI.response(for: try request("plans", method: "POST", body: [
            "kind": "airport.settings", "id": airport.id.uuidString, "baseRevision": revision,
            "changes": ["nodeProcessing": ["includeKeywords": ["香港"]]]
        ]), model: model)
        let planID = try XCTUnwrap(AutomationAPI.dictionary(response.body)["planID"] as? String)
        let applied = await model.automationAPI.response(for: try request("plans/\(planID)/apply", method: "POST"), model: model)
        XCTAssertEqual(applied.status, 200)
        XCTAssertEqual(model.airportSubscriptions[0].nodeProcessing.includeKeywords, ["香港"])
        XCTAssertEqual(model.airportSubscriptions[0].nodeProcessing.excludeKeywords, ["test"])
        let replay = await model.automationAPI.response(for: try request("plans/\(planID)/apply", method: "POST"), model: model)
        XCTAssertEqual(replay.status, 404)
    }

    func testAcceptedJobReportsFailureAndRejectsConcurrentJob() async throws {
        let model = model()
        model.automationAccess.allowPublish = true
        model.settings.github.publicBaseURL = ""
        let accepted = await model.automationAPI.response(for: try request("jobs", method: "POST", body: ["action": "publish"]), model: model)
        XCTAssertEqual(accepted.status, 202)
        let id = try XCTUnwrap(AutomationAPI.dictionary(accepted.body)["id"] as? String)
        let concurrent = await model.automationAPI.response(for: try request("jobs", method: "POST", body: ["action": "publish"]), model: model)
        XCTAssertEqual(concurrent.status, 409)
        for _ in 0..<30 { await Task.yield() }
        let result = await model.automationAPI.response(for: try request("jobs/\(id)"), model: model)
        let job = try AutomationAPI.dictionary(result.body)
        XCTAssertEqual(job["state"] as? String, "failed")
        XCTAssertFalse((job["message"] as? String ?? "").isEmpty)
    }

}
