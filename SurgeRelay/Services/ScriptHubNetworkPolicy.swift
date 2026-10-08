@preconcurrency import JavaScriptCore
import Darwin
import Foundation

enum ScriptHubNetworkPolicy {
    static func makeRequest(method: String, value: JSValue) throws -> URLRequest {
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
            let bodyValue = value.forProperty("body")
            if let bodyValue, !bodyValue.isUndefined, !bodyValue.isNull,
               let body = bodyValue.toString(), !body.isEmpty {
                request.httpBody = Data(body.utf8)
            }
        }
        request.setValue(request.value(forHTTPHeaderField: "User-Agent") ?? "SurgeRelay/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func validateNetworkRequest(_ request: URLRequest) throws {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host(percentEncoded: false)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            throw RelayError.invalidSourceURL
        }
        guard !isPrivateNetworkHost(host) else {
            throw RelayError.invalidOutput("Script-Hub HTTP bridge 已拦截本机或内网地址：\(host)")
        }
    }

    private static func isPrivateNetworkHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !normalized.isEmpty else { return true }
        if normalized == "localhost" || normalized.hasSuffix(".localhost") || normalized.hasSuffix(".local") {
            return true
        }
        if let ipv4 = parseIPv4(normalized) {
            return isPrivateIPv4(ipv4)
        }
        if let ipv6 = parseIPv6(normalized) {
            return isPrivateIPv6(ipv6)
        }
        return resolvesToPrivateAddress(normalized)
    }

    private static func parseIPv4(_ host: String) -> UInt32? {
        var address = in_addr()
        let result = host.withCString { inet_pton(AF_INET, $0, &address) }
        guard result == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        let result = host.withCString { inet_pton(AF_INET6, $0, &address) }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0.prefix(16)) }
    }

    private static func resolvesToPrivateAddress(_ host: String) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else {
            return false
        }
        defer { freeaddrinfo(result) }

        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let info = cursor?.pointee {
            if info.ai_family == AF_INET,
               let address = info.ai_addr?.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { $0.pointee.sin_addr }) {
                if isBlockedResolvedIPv4(UInt32(bigEndian: address.s_addr)) { return true }
            } else if info.ai_family == AF_INET6,
                      let address = info.ai_addr?.withMemoryRebound(to: sockaddr_in6.self, capacity: 1, { $0.pointee.sin6_addr }) {
                let bytes = withUnsafeBytes(of: address) { Array($0.prefix(16)) }
                if isPrivateIPv6(bytes) { return true }
            }
            cursor = info.ai_next
        }
        return false
    }

    static func isBlockedResolvedIPv4(_ value: UInt32) -> Bool {
        let first = Int((value >> 24) & 0xff)
        let second = Int((value >> 16) & 0xff)
        if first == 198 && (18...19).contains(second) {
            return false
        }
        return isPrivateIPv4(value)
    }

    private static func isPrivateIPv4(_ value: UInt32) -> Bool {
        let first = Int((value >> 24) & 0xff)
        let second = Int((value >> 16) & 0xff)
        let third = Int((value >> 8) & 0xff)

        if first == 0 || first == 10 || first == 127 || first >= 224 { return true }
        if first == 100 && (64...127).contains(second) { return true }
        if first == 169 && second == 254 { return true }
        if first == 172 && (16...31).contains(second) { return true }
        if first == 192 && second == 168 { return true }
        if first == 192 && second == 0 && third == 0 { return true }
        if first == 198 && (18...19).contains(second) { return true }
        if first == 203 && second == 0 && third == 113 { return true }
        return false
    }

    private static func isPrivateIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 16 else { return true }
        if bytes.allSatisfy({ $0 == 0 }) { return true }
        if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            let ipv4 = bytes.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return isPrivateIPv4(ipv4)
        }
        if bytes[0] & 0xfe == 0xfc { return true }
        if bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80 { return true }
        if bytes[0] == 0xff { return true }
        return false
    }

}
