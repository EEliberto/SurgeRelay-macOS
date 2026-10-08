import Foundation

enum ModuleRefreshPlanner {
    static func shouldRefresh(_ module: RelayModule, globalInterval: Int, manual: Bool, now: Date = .now) -> Bool {
        if let deadline = module.serverRetryAfter, deadline > now { return false }
        if manual { return true }
        let interval = module.refreshIntervalMinutes ?? globalInterval
        guard interval > 0 else { return false }
        if let retry = module.nextRetryAt { return retry <= now }
        guard let last = module.lastRefreshAttemptAt ?? module.sourceCheckedAt ?? module.lastUpdatedAt else { return true }
        return last.addingTimeInterval(TimeInterval(interval) * 60) <= now
    }
    static func succeeded(_ module: inout RelayModule) {
        module.lastRefreshAttemptAt = .now
        module.consecutiveFailureCount = 0
        module.nextRetryAt = nil
        module.serverRetryAfter = nil
    }
    static func failed(_ module: inout RelayModule, error: Error) {
        module.lastRefreshAttemptAt = .now
        module.consecutiveFailureCount = min(module.consecutiveFailureCount + 1, 30)
        let delay = min(60 * pow(2, Double(min(module.consecutiveFailureCount - 1, 6))), 3600)
        module.serverRetryAfter = (error as? SourceRetryAfterError)?.retryAt
        module.nextRetryAt = max(Date.now.addingTimeInterval(delay), module.serverRetryAfter ?? .distantPast)
    }
}
