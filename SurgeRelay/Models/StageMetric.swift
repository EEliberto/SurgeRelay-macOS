import Foundation

enum WorkStage: String, Codable, CaseIterable, Hashable, Sendable {
    case download, conversion, cache, publish

    var title: String {
        switch self {
        case .download: "下载"
        case .conversion: "转换"
        case .cache: "缓存"
        case .publish: "发布"
        }
    }
}

enum StageMetricResult: String, Codable, Hashable, Sendable {
    case completed, failed, skipped, cancelled
}

struct StageMetric: Codable, Hashable, Sendable {
    var stage: WorkStage
    var duration: TimeInterval
    var bytesRead: Int64? = nil
    var bytesWritten: Int64? = nil
    var attempts = 1
    var failedAttempts = 0
    var result: StageMetricResult = .completed
    var reason: String? = nil
    var isPartial = false
    var includesDownload = false
}

struct WorkStageProgress: Codable, Equatable, Identifiable, Sendable {
    var moduleID: UUID
    var moduleName: String
    var stage: WorkStage
    var startedAt: Date
    var detail: String? = nil
    var id: UUID { moduleID }
}

enum StageMetricsContext {
    @TaskLocal static var current: StageMetricsRecorder?
}

final class StageMetricsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [WorkStage: StageMetric] = [:]

    var snapshot: [StageMetric] { lock.withLock { WorkStage.allCases.compactMap { values[$0] } } }

    func duration(for stage: WorkStage) -> TimeInterval { lock.withLock { values[stage]?.duration ?? 0 } }

    func record(_ metric: StageMetric) {
        lock.withLock {
            guard var current = values[metric.stage] else { values[metric.stage] = metric; return }
            current.duration += metric.duration
            current.bytesRead = Self.sum(current.bytesRead, metric.bytesRead)
            current.bytesWritten = Self.sum(current.bytesWritten, metric.bytesWritten)
            current.attempts += metric.attempts
            current.failedAttempts += metric.failedAttempts
            current.result = metric.result
            if let reason = metric.reason, !(current.reason?.contains(reason) ?? false) {
                current.reason = String(([current.reason, reason].compactMap { $0 }.joined(separator: "；")).prefix(320))
            }
            current.isPartial = current.isPartial || metric.isPartial
            current.includesDownload = current.includesDownload || metric.includesDownload
            values[metric.stage] = current
        }
    }

    func measure<Value>(
        _ stage: WorkStage, reason: String? = nil,
        bytes: (Value) -> (read: Int64?, written: Int64?) = { _ in (nil, nil) },
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> Value
    ) async rethrows -> Value {
        let started = ContinuousClock.now
        do {
            let value = try await operation()
            let counts = bytes(value)
            record(StageMetric(stage: stage, duration: Self.elapsed(since: started), bytesRead: counts.read, bytesWritten: counts.written, reason: reason))
            return value
        } catch {
            let cancelled = Self.isCancellation(error)
            record(StageMetric(stage: stage, duration: Self.elapsed(since: started), failedAttempts: cancelled ? 0 : 1,
                               result: cancelled ? .cancelled : .failed, reason: reason, isPartial: true))
            throw error
        }
    }

    func recordDownload(since started: ContinuousClock.Instant, bytesRead: Int64?, statusCode: Int?, error: (any Error)? = nil) {
        let cancelled = Self.isCancellation(error)
        let failed = !cancelled && (error != nil || (statusCode ?? 200) >= 400)
        record(StageMetric(stage: .download, duration: Self.elapsed(since: started), bytesRead: bytesRead,
                           failedAttempts: failed ? 1 : 0,
                           result: cancelled ? .cancelled : failed ? .failed : .completed,
                           reason: statusCode.map { "HTTP \($0)" }, isPartial: error != nil))
    }

    private static func isCancellation(_ error: (any Error)?) -> Bool {
        Task.isCancelled || (error.map { $0 is CancellationError || ($0 as? URLError)?.code == .cancelled } ?? false)
    }

    static func elapsed(since started: ContinuousClock.Instant) -> TimeInterval {
        let value = started.duration(to: .now).components
        return max(0, Double(value.seconds) + Double(value.attoseconds) / 1e18)
    }

    private static func sum(_ lhs: Int64?, _ rhs: Int64?) -> Int64? {
        guard lhs != nil || rhs != nil else { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
    }
}
