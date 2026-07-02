import XCTest
@testable import SurgeRelay

final class SurgeRelayTests: XCTestCase {
    func testFilenameSanitizerCreatesSurgeModuleExtension() {
        XCTAssertEqual(FilenameSanitizer.sgmoduleName(from: "YouTube Ads.sgmodule"), "YouTube-Ads.sgmodule")
        XCTAssertEqual(FilenameSanitizer.sgmoduleName(from: "folder/bad:name"), "folder-bad-name.sgmodule")
        XCTAssertEqual(FilenameSanitizer.individualRelayName(from: "123.sgmodule"), "123-SurgeRelay.sgmodule")
        XCTAssertEqual(FilenameSanitizer.individualRelayName(from: "123-SurgeRelay.sgmodule"), "123-SurgeRelay.sgmodule")
    }

    func testAutomaticSourceFormat() throws {
        XCTAssertEqual(ModuleSourceFormat.automatic.scriptHubType(for: try XCTUnwrap(URL(string: "https://example.com/test.plugin"))), "loon-plugin")
        XCTAssertEqual(ModuleSourceFormat.automatic.scriptHubType(for: try XCTUnwrap(URL(string: "https://hub.kelee.one/Tool/Loon/Demo.lpx"))), "loon-plugin")
        XCTAssertEqual(ModuleSourceFormat.automatic.scriptHubType(for: try XCTUnwrap(URL(string: "https://example.com/test.sgmodule"))), "surge-module")
        XCTAssertEqual(ModuleSourceFormat.automatic.scriptHubType(for: try XCTUnwrap(URL(string: "https://example.com/rewrite.conf"))), "qx-rewrite")
        XCTAssertTrue(ModuleSourceFormat.automatic.isNativeSurgeModule(for: try XCTUnwrap(URL(string: "https://example.com/test.sgmodule?x=1"))))
        XCTAssertTrue(ModuleSourceFormat.surge.isNativeSurgeModule(for: try XCTUnwrap(URL(string: "https://example.com/no-extension"))))

        let detected = RelayModule(
            name: "Detected",
            sourceURL: "https://example.com/demo.lpx",
            outputFileName: "detected",
            detectedSourceFormat: .loon
        )
        XCTAssertEqual(detected.sourceFormatDisplayTitle, "自动识别（Loon）")
    }

    func testModuleSourceIdentityPreventsEquivalentDuplicates() {
        XCTAssertTrue(ModuleSourceIdentity.matches(
            " HTTPS://Example.com:443/path/module.sgmodule#preview ",
            "https://example.com/path/module.sgmodule"
        ))
        XCTAssertTrue(ModuleSourceIdentity.matches("http://example.com", "http://EXAMPLE.com:80/"))
        XCTAssertFalse(ModuleSourceIdentity.matches(
            "https://example.com/path/module.sgmodule?variant=one",
            "https://example.com/path/module.sgmodule?variant=two"
        ))
    }

    func testWebErrorPayloadIncludesUserFacingMessage() throws {
        let response = WebHTTPResponse.error(status: 409, message: "该模块已经添加，不能重复添加。")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: String])

        XCTAssertEqual(response.status, 409)
        XCTAssertEqual(payload["message"], "该模块已经添加，不能重复添加。")
    }

    func testRefreshPolicyDoesNotRefreshAgainBeforeInterval() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(RefreshPolicy.isDue(
            lastUpdatedAt: now.addingTimeInterval(-59 * 60),
            intervalMinutes: 60,
            now: now
        ))
        XCTAssertTrue(RefreshPolicy.isDue(
            lastUpdatedAt: now.addingTimeInterval(-60 * 60),
            intervalMinutes: 60,
            now: now
        ))
        XCTAssertFalse(RefreshPolicy.isDue(lastUpdatedAt: nil, intervalMinutes: 0, now: now))
    }

    func testScriptHubConversionURLPreservesOriginalAddress() async throws {
        let module = RelayModule(
            name: "Test",
            sourceURL: "https://example.com/path/plugin.conf?token=abc",
            sourceFormat: .loon,
            outputFileName: "my module"
        )
        let url = try await ScriptHubClient().conversionURL(module: module, baseURL: "http://script.hub/")
        XCTAssertTrue(url.absoluteString.contains("https://example.com/path/plugin.conf?token=abc/_end_/my-module.sgmodule"))
        XCTAssertTrue(url.absoluteString.contains("type=loon-plugin"))
        XCTAssertTrue(url.absoluteString.contains("target=surge-module"))
    }

    func testScriptHubAdvancedOptionsAreAddedToConversionURL() async throws {
        var options = ScriptHubOptions()
        options.policy = "Proxy Group"
        options.mitmAdd = "one.example.com,two.example.com"
        options.convertAllScripts = true
        options.compatibilityOnly = true
        let module = RelayModule(
            name: "Advanced",
            sourceURL: "https://example.com/plugin.conf",
            sourceFormat: .loon,
            outputFileName: "fallback",
            scriptHubOptions: options
        )

        let url = try await ScriptHubClient().conversionURL(module: module, baseURL: "http://script.hub")
        let value = url.absoluteString
        XCTAssertTrue(value.contains("/_end_/fallback.sgmodule"))
        XCTAssertTrue(value.contains("jsc=."))
        XCTAssertTrue(value.contains("compatibilityOnly=true"))
        XCTAssertTrue(value.contains("policy=Proxy%20Group"))
        XCTAssertTrue(value.contains("hnadd=one.example.com,two.example.com"))
        XCTAssertFalse(value.contains("&n="))
        XCTAssertFalse(value.contains("category="))
        XCTAssertFalse(value.contains("icon="))
    }

    func testGitHubRawURL() throws {
        var settings = GitHubSettings()
        settings.owner = "someone"
        settings.repository = "relay"
        settings.branch = "main"
        settings.directory = "modules"
        XCTAssertEqual(
            try XCTUnwrap(settings.rawURL(for: "YouTube.sgmodule")).absoluteString,
            "https://raw.githubusercontent.com/someone/relay/main/modules/YouTube.sgmodule"
        )
    }

    func testPublicRepositoryDoesNotExposePublishedURL() {
        var settings = GitHubSettings()
        settings.repositoryIsPrivate = false
        settings.publicBaseURL = "https://unused.example.workers.dev"
        XCTAssertNil(settings.publicURL(for: "Demo.sgmodule"))
    }

    func testPrivateRepositoryRequiresCloudflareAndUsesItWhenConfigured() throws {
        var settings = GitHubSettings()
        settings.repositoryIsPrivate = true
        XCTAssertNil(settings.publicURL(for: "Demo.sgmodule"))
        settings.publicBaseURL = "https://surge-relay.example.workers.dev/"
        XCTAssertEqual(
            try XCTUnwrap(settings.publicURL(for: "assets/demo/script.js")).absoluteString,
            "https://surge-relay.example.workers.dev/assets/demo/script.js"
        )
    }

    func testSettingsDecodeWithoutSyncedTokenOrRepositoryVisibility() throws {
        let data = Data(#"{"github":{"owner":"someone","repository":"relay","branch":"main","directory":"modules"}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.githubToken, "")
        XCTAssertNil(settings.github.repositoryIsPrivate)
    }

    func testLegacyCustomCombinedNameMigratesToFixedName() throws {
        let data = Data(#"{"combinedModuleFileName":"Custom.sgmodule"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.combinedModuleFileName, AppSettings.fixedCombinedModuleFileName)
    }

    func testStorageModeUsesFixedCombinedOutputName() throws {
        var settings = AppSettings()
        settings.localModuleDirectory = "/tmp/Surge Relay"
        settings.github.repositoryIsPrivate = true
        settings.github.publicBaseURL = "https://surge-relay.example.workers.dev"

        settings.storageMode = .local
        XCTAssertEqual(settings.combinedModuleFileName, "Surge-Relay.sgmodule")
        XCTAssertNil(settings.publishedURL(for: "Surge-Relay.sgmodule"))
        XCTAssertEqual(
            try XCTUnwrap(settings.localCombinedModuleURL).path,
            "/tmp/Surge Relay/Surge-Relay.sgmodule"
        )

        settings.storageMode = .gitHub
        XCTAssertNil(settings.localCombinedModuleURL)
        XCTAssertEqual(try XCTUnwrap(settings.publishedURL(for: "Surge-Relay.sgmodule")).host, "surge-relay.example.workers.dev")
    }

    func testSelectingSurgeFolderCreatesNestedConfigurationLayout() {
        let selected = URL(filePath: "/tmp/Surge", directoryHint: .isDirectory)
        let surgeDirectory = AppSettings.surgeDirectory(forSelectedDirectory: selected)
        XCTAssertEqual(surgeDirectory.path, "/tmp/Surge")
        XCTAssertEqual(
            AppSettings.configurationDirectory(forSurgeDirectory: surgeDirectory).path,
            "/tmp/Surge/Surge Relay"
        )

        let existingConfiguration = URL(filePath: "/tmp/Surge/Surge Relay", directoryHint: .isDirectory)
        XCTAssertEqual(
            AppSettings.surgeDirectory(forSelectedDirectory: existingConfiguration).path,
            "/tmp/Surge"
        )
    }

    func testConfigurationMigrationCopiesOverridesWithoutRemovingDestinationFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Source", directoryHint: .isDirectory)
        let destination = root.appending(path: "Destination", directoryHint: .isDirectory)
        let sourceOverride = source.appending(path: "Overrides/nested/module.cache")
        let existingOverride = destination.appending(path: "Overrides/keep.cache")
        try FileManager.default.createDirectory(
            at: sourceOverride.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: existingOverride.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("edited module".utf8).write(to: sourceOverride)
        try Data("keep me".utf8).write(to: existingOverride)

        try PersistenceStore.migrateOverrides(from: source, to: destination)

        XCTAssertEqual(
            try String(contentsOf: destination.appending(path: "Overrides/nested/module.cache"), encoding: .utf8),
            "edited module"
        )
        XCTAssertEqual(try String(contentsOf: existingOverride, encoding: .utf8), "keep me")
    }

    func testRelayModuleDecodesRegistryWithoutAdvancedOptions() throws {
        let original = RelayModule(
            name: "Legacy",
            sourceURL: "https://example.com/legacy.sgmodule",
            sourceFormat: .surge,
            outputFileName: "legacy"
        )
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "scriptHubOptions")
        object.removeValue(forKey: "argumentOverrides")
        object.removeValue(forKey: "iconURL")
        object.removeValue(forKey: "exportsIndividualModuleToICloud")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(RelayModule.self, from: legacyData)

        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertEqual(decoded.scriptHubOptions, ScriptHubOptions())
        XCTAssertTrue(decoded.argumentOverrides.isEmpty)
        XCTAssertNil(decoded.iconURL)
        XCTAssertFalse(decoded.exportsIndividualModuleToICloud)
        XCTAssertNil(decoded.sourceETag)
        XCTAssertNil(decoded.sourceContentHash)
        XCTAssertFalse(decoded.hasOverrideConflict)
    }

    func testUpdateHistoryRoundTrip() throws {
        let entry = UpdateHistoryEntry(
            moduleName: "Demo",
            outcome: .cachedAfterFailure,
            duration: 1.25,
            message: "Timeout",
            usedCache: true
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(UpdateHistoryEntry.self, from: data)
        XCTAssertEqual(decoded.moduleName, "Demo")
        XCTAssertEqual(decoded.outcome, .cachedAfterFailure)
        XCTAssertTrue(decoded.usedCache)
    }

    func testSourceRevisionServiceRecognizesUnchangedContent() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceRevisionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        SourceRevisionURLProtocol.response = (200, ["ETag": "demo-v1"], Data("same".utf8))
        let module = RelayModule(
            name: "Demo",
            sourceURL: "https://example.com/demo.sgmodule",
            outputFileName: "Demo",
            sourceContentHash: Data("same".utf8).sha256String
        )
        let result = try await SourceRevisionService(session: session).check(module)
        guard case let .unchanged(snapshot) = result else {
            return XCTFail("Expected unchanged source")
        }
        XCTAssertEqual(snapshot.etag, "demo-v1")
    }

    func testModuleMetadataParserFindsIconWithoutScrapingCatalog() throws {
        let content = """
        #!name=Demo
        #!icon = 'https://raw.githubusercontent.com/example/icons/main/demo.png'
        [General]
        """

        XCTAssertEqual(
            try XCTUnwrap(ModuleMetadataParser.iconURL(in: content)).absoluteString,
            "https://raw.githubusercontent.com/example/icons/main/demo.png"
        )
        XCTAssertNil(ModuleMetadataParser.iconURL(in: "#!name=No Icon\n[General]"))
        XCTAssertTrue(ModuleMetadataParser.applyingDisplayName("GUI Name", to: content).hasPrefix("#!name=GUI Name\n"))
    }

    func testGitBlobHashMatchesGitHubContentSHA() {
        XCTAssertEqual(Data("hello\n".utf8).gitBlobSHA1, "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    func testGitHubPublishSkipsCommitWhenRemoteHashesMatch() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubPublishURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let file = PublishFile(name: "Surge-Relay.sgmodule", data: Data("same".utf8))
        GitHubPublishURLProtocol.expectedBlobSHA = file.data.gitBlobSHA1

        var settings = GitHubSettings()
        settings.owner = "owner"
        settings.repository = "relay"
        settings.branch = "main"
        settings.directory = "modules"
        settings.publicBaseURL = "https://relay.example.workers.dev"

        let report = try await GitHubClient(session: session).publish(
            files: [file],
            settings: settings,
            token: "token"
        )
        XCTAssertTrue(report.publishedFiles.isEmpty)
        XCTAssertNil(report.commitSHA)
    }

    func testModuleArgumentsAreMaterializedAndMetadataIsRemoved() {
        let content = """
        #!name=Demo
        #!arguments=feature:true,mode:auto
        #!arguments-desc=feature toggle\\nmode selector
        [Script]
        %feature%disabled = type=cron, cronexp="0 0 * * *", script-path=https://example.com/a.js
        mode = %mode%
        // source note
        """
        let info = ModuleArgumentProcessor.info(in: content)
        XCTAssertEqual(info.definitions.map(\.key), ["feature", "mode"])
        XCTAssertEqual(info.helpText, "feature toggle\nmode selector")

        let result = ModuleArgumentProcessor.materialize(content, overrides: ["feature": "#", "mode": "show"])
        XCTAssertFalse(result.contains("#!arguments="))
        XCTAssertFalse(result.contains("disabled ="))
        XCTAssertFalse(result.contains("source note"))
        XCTAssertTrue(result.contains("mode = show"))
    }

    func testLegacyArgumentsWithSpacingAndQuotedDefaultsAreMaterialized() {
        let content = """
        #!name=Maps
        #!arguments = CountryCode:"CN",Dispatcher:"AutoNavi"
        #!arguments-desc = CountryCode help
        [Script]
        maps = type=http-request,argument=CountryCode="{{{CountryCode}}}"&Dispatcher="{{{Dispatcher}}}",script-path=https://example.com/maps.js
        """

        let info = ModuleArgumentProcessor.info(in: content)
        XCTAssertEqual(info.definitions.map(\.key), ["CountryCode", "Dispatcher"])
        XCTAssertEqual(info.definitions.map(\.defaultValue), ["CN", "AutoNavi"])
        let result = ModuleArgumentProcessor.materialize(content, overrides: [:])
        XCTAssertFalse(result.contains("#!arguments"))
        XCTAssertFalse(result.contains("{{{"))
        XCTAssertTrue(result.contains("CountryCode=\"CN\"&Dispatcher=\"AutoNavi\""))
    }

    func testAdvancedOptionsSummaryOnlyAppearsWhenConfigured() {
        XCTAssertNil(ScriptHubOptions().configuredSummary)
        var options = ScriptHubOptions()
        options.policy = "Proxy"
        options.convertAllScripts = true
        XCTAssertEqual(options.configuredSummary, "脚本转换：全部 · 策略：Proxy")
    }

    func testSurgeModuleSanitizerRemovesEmptyJQAndConvertsMisplacedLoonScript() {
        let content = """
        #!name=Demo
        [Body Rewrite]
        http-response-jq ^https:\\/\\/example\\.com\\/empty\\? ''
        http-response-jq ^https:\\/\\/example\\.com\\/valid\\? '.data=[]'
        [Map Local]
        ^https:\\/\\/example\\.com\\/api url script-response-header https://example.com/scripts/clean.js
        ^https:\\/\\/example\\.com\\/blank data-type=text data="{}" status-code=200
        """

        let sanitized = SurgeModuleSanitizer.sanitize(content)

        XCTAssertFalse(sanitized.contains("example\\.com\\/empty"))
        XCTAssertTrue(sanitized.contains("http-response-jq ^https:\\/\\/example\\.com\\/valid\\? '.data=[]'"))
        XCTAssertTrue(sanitized.contains("^https:\\/\\/example\\.com\\/blank data-type=text"))
        XCTAssertTrue(sanitized.contains("[Script]"))
        XCTAssertTrue(sanitized.contains(
            "clean = type=http-response, pattern=^https:\\/\\/example\\.com\\/api, requires-body=0, script-path=https://example.com/scripts/clean.js"
        ))
        XCTAssertFalse(sanitized.contains("url script-response-header"))
        XCTAssertEqual(SurgeModuleSanitizer.sanitize(sanitized), sanitized)
    }

    func testModuleOrderingMovesItemsInListOrder() {
        XCTAssertEqual(
            ModuleOrdering.moving(["A", "B", "C"], fromOffsets: IndexSet(integer: 2), toOffset: 0),
            ["C", "A", "B"]
        )
        XCTAssertEqual(
            ModuleOrdering.moving(["A", "B", "C"], fromOffsets: IndexSet(integer: 0), toOffset: 3),
            ["B", "C", "A"]
        )
    }

    func testWebRequestParserReadsJSONBodyAndQuery() throws {
        let body = #"{"enabled":true}"#
        let request = """
        POST /api/modules/demo/enabled?source=web HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        let parsed = try XCTUnwrap(WebManagementServer.parseRequest(Data(request.utf8), isLoopback: true))
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/api/modules/demo/enabled")
        XCTAssertEqual(parsed.query["source"], "web")
        XCTAssertEqual(String(data: parsed.body, encoding: .utf8), body)
        XCTAssertTrue(parsed.isLoopback)
    }

    func testAppSettingsDecodesWebManagementDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.webServerEnabled)
        XCTAssertEqual(settings.webServerPort, 8787)
    }

    func testMergerAddsSourceTogglesAndRemovesDeviceRestrictions() throws {
        let first = RelayModule(
            id: try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            name: "First",
            sourceURL: "https://example.com/first.sgmodule",
            sourceFormat: .surge,
            outputFileName: "first"
        )
        let second = RelayModule(
            id: try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            name: "Second",
            sourceURL: "https://example.com/second.sgmodule",
            sourceFormat: .surge,
            outputFileName: "second"
        )
        let firstContent = """
        #!name=First
        #!system=iOS
        #!requirement=CORE_VERSION>=20 && SYSTEM = 'iOS'
        [General]
        test-setting = first
        [MITM]
        hostname = %INSERT% one.example.com
        [Script]
        # source comment
        ## source heading
        // another source comment
        ; legacy source comment
        first = type=cron, cronexp="0 0 * * *", script-path=https://example.com/one.js
        """
        let secondContent = """
        #!name=Second
        #!system=mac
        [General]
        test-setting = second
        [MITM]
        hostname = %APPEND% two.example.com
        [Script]
        second = type=cron, cronexp="0 1 * * *", script-path=https://example.com/two.js
        """
        let merged = try ModuleMerger.merge([(first, firstContent), (second, secondContent)], engineRevision: "abcdef")
        XCTAssertTrue(merged.contains("#!desc=由 Surge Relay 整合 2 个模块"))
        XCTAssertFalse(merged.contains("Script-Hub abcdef"))
        XCTAssertFalse(merged.contains("#!system="))
        XCTAssertTrue(merged.contains("#!requirement=(CORE_VERSION>=20)"))
        XCTAssertFalse(merged.contains("Relay_First"))
        XCTAssertTrue(merged.contains("first = type=cron"))
        XCTAssertFalse(merged.contains("source comment"))
        XCTAssertFalse(merged.contains("source heading"))
        XCTAssertFalse(merged.contains("# --- [Relay_"))
        XCTAssertFalse(merged.contains("# 此文件由"))
        XCTAssertTrue(merged.contains("hostname = %INSERT% one.example.com, two.example.com"))
        let mitm = try XCTUnwrap(merged.range(of: "[MITM]")?.upperBound)
        let script = try XCTUnwrap(merged.range(of: "[Script]")?.lowerBound)
        XCTAssertFalse(merged[mitm..<script].contains("# --- [Relay_"))
        XCTAssertTrue(merged.contains("test-setting = first"))
        XCTAssertFalse(merged.contains("test-setting = second"))
        XCTAssertLessThan(
            try XCTUnwrap(merged.range(of: "first = type=cron")?.lowerBound),
            try XCTUnwrap(merged.range(of: "second = type=cron")?.lowerBound)
        )
    }

    func testCombinedExportPreservesEveryOtherModuleFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let personalModule = directory.appending(path: "Personal.sgmodule")
        let personalContent = "#!name=Personal\n[Rule]\nFINAL,DIRECT\n"
        try Data(personalContent.utf8).write(to: personalModule)

        let store = ModuleFileStore()
        let combined = "#!name=Surge Relay\n#!author=Surge Relay\n#!category=Surge Relay\n[Rule]\nFINAL,DIRECT\n"
        let firstWrite = try await store.exportCombined(
            combined,
            toDirectory: directory.path,
            fileName: "Surge-Relay.sgmodule"
        )
        let repeatedWrite = try await store.exportCombined(
            combined,
            toDirectory: directory.path,
            fileName: "Surge-Relay.sgmodule"
        )

        XCTAssertTrue(firstWrite)
        XCTAssertFalse(repeatedWrite)
        XCTAssertEqual(try String(contentsOf: personalModule, encoding: .utf8), personalContent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "Surge-Relay.sgmodule").path))
    }

    func testCombinedExportAndRemovalRefuseUnmanagedSameNameFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appending(path: "Surge-Relay.sgmodule")
        let personalContent = "#!name=Personal Relay\n[Rule]\nFINAL,DIRECT\n"
        try Data(personalContent.utf8).write(to: destination)

        let store = ModuleFileStore()
        let combined = "#!name=Surge Relay\n#!author=Surge Relay\n#!category=Surge Relay\n[Rule]\nFINAL,REJECT\n"
        do {
            try await store.exportCombined(
                combined,
                toDirectory: directory.path,
                fileName: destination.lastPathComponent
            )
            XCTFail("不应覆盖不属于 Surge Relay 的同名文件")
        } catch {
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), personalContent)
        }

        try await store.removeExportedCombined(
            fromDirectory: directory.path,
            fileName: destination.lastPathComponent
        )
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), personalContent)
    }
}

private final class SourceRevisionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (status: Int, headers: [String: String], data: Data) = (200, [:], Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let responseValue = Self.response
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseValue.status,
            httpVersion: "HTTP/1.1",
            headerFields: responseValue.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseValue.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class GitHubPublishURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var expectedBlobSHA = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let body: Data
        let status: Int
        if path == "/repos/owner/relay" {
            body = Data(#"{"private":true}"#.utf8)
            status = 200
        } else if path.contains("/repos/owner/relay/contents/modules/Surge-Relay.sgmodule") {
            body = Data("{\"sha\":\"\(Self.expectedBlobSHA)\"}".utf8)
            status = 200
        } else {
            body = Data(#"{"message":"unexpected request"}"#.utf8)
            status = 500
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
