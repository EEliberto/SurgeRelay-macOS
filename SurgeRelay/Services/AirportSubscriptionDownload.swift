import Foundation

/// Subscription control-plane requests must not inherit the system proxy/PAC settings.
/// Surge enhanced mode is handled separately by AirportSubscriptionDirectRules.
enum AirportSubscriptionDownload {
    static func session(delegate: AirportSubscriptionRedirectDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0,
        ]
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

final class AirportSubscriptionRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let registerHost: @Sendable (String) async -> Bool

    init(registerHost: @escaping @Sendable (String) async -> Bool) {
        self.registerHost = registerHost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host,
              await registerHost(host) else { return nil }
        return request
    }
}
