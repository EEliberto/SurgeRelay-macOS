import Foundation

struct SourceRetryAfterError: Error, LocalizedError, Codable, Equatable, Sendable {
    let statusCode: Int
    let sourceURL: String
    let responseURL: String?
    let retryAt: Date

    var errorDescription: String? {
        "来源返回 HTTP \(statusCode)，服务器要求在 \(retryAt.formatted(date: .abbreviated, time: .standard)) 后再试（Retry-After）。"
    }

    static func response(_ response: HTTPURLResponse, requestedURL: URL, now: Date = .now) -> Self? {
        guard [429, 503].contains(response.statusCode),
              let value = response.value(forHTTPHeaderField: "Retry-After"),
              let retryAt = deadline(value, now: now) else { return nil }
        return Self(statusCode: response.statusCode, sourceURL: requestedURL.absoluteString,
                    responseURL: response.url?.absoluteString, retryAt: retryAt)
    }

    static func deadline(_ value: String, now: Date = .now) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let seconds = UInt64(value) {
            return now.addingTimeInterval(TimeInterval(seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE',' dd MMM yyyy HH':'mm':'ss zzz", "EEEE',' dd-MMM-yy HH':'mm':'ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
