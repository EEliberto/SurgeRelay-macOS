@preconcurrency import JavaScriptCore
import Foundation

actor EmbeddedScriptHubEngine {
    private final class BlockingResponse: @unchecked Sendable {
        private let lock = NSLock()
        private var storedData: Data?
        private var storedResponse: URLResponse?
        private var storedError: Error?

        func set(data: Data?, response: URLResponse?, error: Error?) {
            lock.lock()
            storedData = data
            storedResponse = response
            storedError = error
            lock.unlock()
        }

        func get() -> (Data?, URLResponse?, Error?) {
            lock.lock()
            defer { lock.unlock() }
            return (storedData, storedResponse, storedError)
        }
    }

    func convert(script: String, scriptConverterScript: String? = nil, requestURL: URL) throws -> String {
        try Self.execute(
            script: script,
            scriptConverterScript: scriptConverterScript,
            requestURL: requestURL
        )
    }

    private static func execute(
        script: String,
        scriptConverterScript: String?,
        requestURL: URL
    ) throws -> String {
        guard let context = JSContext() else {
            throw RelayError.invalidOutput("无法创建 JavaScriptCore 运行环境。")
        }

        var output: String?
        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString()
        }

        typealias HTTPBlock = @convention(block) (String, JSValue, JSValue) -> Void
        let httpBlock: HTTPBlock = { method, requestValue, callback in
            do {
                let request = try Self.makeRequest(method: method, value: requestValue)
                if request.url?.host == "script.hub",
                   request.url?.path.contains("/convert/_start_/") == true,
                   let scriptConverterScript {
                    let body = try Self.execute(
                        script: scriptConverterScript,
                        scriptConverterScript: nil,
                        requestURL: request.url!
                    )
                    callback.call(withArguments: [
                        NSNull(),
                        ["status": 200, "statusCode": 200, "headers": [:]],
                        body
                    ])
                    return
                }
                let (data, response) = try Self.performSynchronously(request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                let headers = http?.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                    result[String(describing: entry.key)] = String(describing: entry.value)
                } ?? [:]
                let body = Self.decode(data)
                callback.call(withArguments: [NSNull(), ["status": status, "statusCode": status, "headers": headers], body])
            } catch {
                callback.call(withArguments: [String(reflecting: error), NSNull(), ""])
            }
        }
        context.setObject(httpBlock, forKeyedSubscript: "__relayHTTP" as NSString)

        typealias ReadBlock = @convention(block) (String) -> Any
        let readBlock: ReadBlock = { _ in NSNull() }
        context.setObject(readBlock, forKeyedSubscript: "__relayRead" as NSString)

        typealias WriteBlock = @convention(block) (String, String) -> Bool
        let writeBlock: WriteBlock = { _, _ in true }
        context.setObject(writeBlock, forKeyedSubscript: "__relayWrite" as NSString)

        typealias DoneBlock = @convention(block) (JSValue) -> Void
        let doneBlock: DoneBlock = { value in
            let response = value.forProperty("response")
            if let response, !response.isUndefined, !response.isNull {
                output = response.forProperty("body")?.toString()
            } else {
                output = value.forProperty("body")?.toString()
            }
        }
        context.setObject(doneBlock, forKeyedSubscript: "__relayDone" as NSString)

        let encodedURL = try Self.javascriptString(requestURL.absoluteString)
        context.evaluateScript(
            """
            var $environment = {"surge-version":"Surge Relay 0.1"};
            var $request = {url: \(encodedURL), method: "GET", headers: {"User-Agent":"SurgeRelay/0.1"}};
            var $httpClient = {
              get: function(request, callback) { __relayHTTP("GET", request, callback); },
              post: function(request, callback) { __relayHTTP("POST", request, callback); },
              put: function(request, callback) { __relayHTTP("PUT", request, callback); },
              delete: function(request, callback) { __relayHTTP("DELETE", request, callback); }
            };
            var $persistentStore = {
              read: function(key) { return __relayRead(key); },
              write: function(value, key) { return __relayWrite(value, key); }
            };
            var $notification = {post: function() {}};
            var $done = function(value) { __relayDone(value || {}); };
            var setTimeout = function() { return 0; };
            var clearTimeout = function() {};
            var console = {log: function(){}, warn: function(){}, error: function(){}};
            """
        )

        context.evaluateScript(script)
        let deadline = Date().addingTimeInterval(10)
        while output == nil, exceptionMessage == nil, Date() < deadline {
            context.evaluateScript("void 0")
            Thread.sleep(forTimeInterval: 0.001)
        }

        if let exceptionMessage {
            throw RelayError.invalidOutput("Script Hub 执行异常：\(exceptionMessage)")
        }
        guard let output else {
            throw RelayError.invalidOutput("Script Hub 内置引擎未在限定时间内返回结果。")
        }
        return output
    }

    private static func makeRequest(method: String, value: JSValue) throws -> URLRequest {
        let urlString: String
        if value.isString {
            urlString = value.toString()
        } else {
            urlString = value.forProperty("url")?.toString() ?? ""
        }
        guard let url = URL(string: urlString) else { throw RelayError.invalidSourceURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.httpMethod = method
        if !value.isString {
            if let headers = value.forProperty("headers")?.toDictionary() as? [String: Any] {
                for (key, value) in headers { request.setValue(String(describing: value), forHTTPHeaderField: key) }
            }
            if let body = value.forProperty("body")?.toString(), !body.isEmpty {
                request.httpBody = Data(body.utf8)
            }
        }
        request.setValue(request.value(forHTTPHeaderField: "User-Agent") ?? "SurgeRelay/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func performSynchronously(_ request: URLRequest) throws -> (Data, URLResponse) {
        for attempt in 0..<3 {
            do {
                return try performOnce(request)
            } catch {
                guard attempt < 2, isTransientNetworkError(error) else { throw error }
                Thread.sleep(forTimeInterval: [0.25, 0.75][attempt])
            }
        }
        throw URLError(.unknown)
    }

    private static func performOnce(_ request: URLRequest) throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        let session = URLSession(configuration: configuration)
        let result = BlockingResponse()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.downloadTask(with: request) { temporaryURL, response, error in
            do {
                let data = try temporaryURL.map { try Data(contentsOf: $0) }
                result.set(data: data, response: response, error: error)
            } catch {
                result.set(data: nil, response: response, error: error)
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + request.timeoutInterval + 2) == .success else {
            task.cancel()
            throw URLError(.timedOut)
        }
        let (data, response, error) = result.get()
        if let error { throw error }
        guard let data, let response else { throw URLError(.badServerResponse) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RelayError.httpFailure(status: http.statusCode, message: String(Self.decode(data).prefix(240)))
        }
        return (data, response)
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        let code = URLError.Code(rawValue: (error as NSError).code)
        return (error as NSError).domain == NSURLErrorDomain && [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .resourceUnavailable,
            .secureConnectionFailed
        ].contains(code)
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    private static func javascriptString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}
