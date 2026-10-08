@preconcurrency import JavaScriptCore
import Darwin
import Foundation

enum ScriptHubJavaScriptRuntime {
    private final class BoundedResponse: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let maximumSize: Int
        private let semaphore: DispatchSemaphore
        private var storedData = Data()
        private var storedResponse: URLResponse?
        private var storedError: Error?

        init(maximumSize: Int, semaphore: DispatchSemaphore) {
            self.maximumSize = maximumSize
            self.semaphore = semaphore
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            do { try ScriptHubNetworkPolicy.validateNetworkRequest(request); completionHandler(request) }
            catch {
                lock.withLock { storedError = error }
                completionHandler(nil)
                task.cancel()
            }
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            lock.lock()
            storedResponse = response
            let expectedLength = response.expectedContentLength
            if expectedLength > maximumSize {
                storedError = RelayError.invalidOutput("Script-Hub HTTP bridge 响应超过 20 MB 限制。")
                lock.unlock()
                completionHandler(.cancel)
            } else {
                lock.unlock()
                completionHandler(.allow)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            let exceedsLimit = data.count > maximumSize - storedData.count
            if exceedsLimit {
                storedError = RelayError.invalidOutput("Script-Hub HTTP bridge 响应超过 20 MB 限制。")
            } else {
                storedData.append(data)
            }
            lock.unlock()
            if exceedsLimit {
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            if storedError == nil {
                storedError = error
            }
            lock.unlock()
            semaphore.signal()
        }

        func get() -> (Data?, URLResponse?, Error?) {
            lock.lock()
            defer { lock.unlock() }
            return (storedData, storedResponse, storedError)
        }
    }

    private static let maximumHTTPBridgeResponseSize = 20 * 1024 * 1024

    static func execute(
        script: String,
        scriptConverterScript: String?,
        requestURL: URL
    ) throws -> String {
        guard let context = JSContext() else {
            throw RelayError.invalidOutput("无法创建 JavaScriptCore 运行环境。")
        }

        var output: String?
        var exceptionMessage: String?
        var sourceRetryAfter: SourceRetryAfterError?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString()
        }

        typealias HTTPBlock = @convention(block) (String, JSValue, JSValue) -> Void
        let httpBlock: HTTPBlock = { [weak context] method, requestValue, callback in
            if let sourceRetryAfter {
                context?.exception = JSValue(newErrorFromMessage: sourceRetryAfter.localizedDescription, in: context)
                return
            }
            do {
                let request = try ScriptHubNetworkPolicy.makeRequest(method: method, value: requestValue)
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
            } catch let error as SourceRetryAfterError {
                sourceRetryAfter = error
                context?.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
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
        while output == nil, exceptionMessage == nil, sourceRetryAfter == nil, Date() < deadline {
            context.evaluateScript("void 0")
            Thread.sleep(forTimeInterval: 0.001)
        }

        if let sourceRetryAfter { throw sourceRetryAfter }
        if let exceptionMessage {
            throw RelayError.invalidOutput("Script-Hub 执行异常：\(exceptionMessage)")
        }
        guard let output else {
            throw RelayError.invalidOutput("Script-Hub 内置引擎未在限定时间内返回结果。")
        }
        return output
    }

    private static func performSynchronously(_ request: URLRequest) throws -> (Data, URLResponse) {
        for attempt in 0..<3 {
            try Task.checkCancellation()
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
        try ScriptHubNetworkPolicy.validateNetworkRequest(request)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        let semaphore = DispatchSemaphore(value: 0)
        let result = BoundedResponse(maximumSize: maximumHTTPBridgeResponseSize, semaphore: semaphore)
        let started = ContinuousClock.now
        defer {
            let (data, response, error) = result.get()
            StageMetricsContext.current?.recordDownload(since: started, bytesRead: data.map { Int64($0.count) },
                                                         statusCode: (response as? HTTPURLResponse)?.statusCode, error: error)
        }
        let session = URLSession(configuration: configuration, delegate: result, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request)
        task.resume()
        let deadline = DispatchTime.now() + request.timeoutInterval + 2
        while semaphore.wait(timeout: .now() + .milliseconds(100)) != .success {
            if Task.isCancelled { task.cancel(); throw CancellationError() }
            if DispatchTime.now() >= deadline { task.cancel(); throw URLError(.timedOut) }
        }
        try Task.checkCancellation()
        let (data, response, error) = result.get()
        if let error { throw error }
        guard let data, let response else { throw URLError(.badServerResponse) }
        if let http = response as? HTTPURLResponse, let url = request.url,
           let retryAfter = SourceRetryAfterError.response(http, requestedURL: url) { throw retryAfter }
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
