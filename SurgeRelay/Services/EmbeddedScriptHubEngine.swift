@preconcurrency import JavaScriptCore
import Darwin
import Foundation

actor EmbeddedScriptHubEngine {
    private let workerExecutableURL: URL?
    private let executionTimeout: Duration
    private let maximumConcurrentWorkers: Int
    private var activeWorkers = 0
    private var waiters: [(UUID, CheckedContinuation<Bool, Never>)] = []

    init(workerExecutableURL: URL? = nil, executionTimeout: Duration = .seconds(90), maximumConcurrentWorkers: Int = 4) {
        self.workerExecutableURL = workerExecutableURL
        self.executionTimeout = executionTimeout
        self.maximumConcurrentWorkers = max(1, min(maximumConcurrentWorkers, 4))
    }

    func convert(script: String, scriptConverterScript: String? = nil, requestURL: URL) async throws -> String {
        let metrics = StageMetricsContext.current
        let started = ContinuousClock.now
        var helperDownloads: TimeInterval = 0
        var receivedMetrics = false
        var launched = false
        var completed = false
        var outputBytes: Int64?
        defer {
            metrics?.record(StageMetric(stage: .conversion, duration: max(0, StageMetricsRecorder.elapsed(since: started) - helperDownloads),
                                        bytesWritten: outputBytes, failedAttempts: completed || Task.isCancelled ? 0 : 1,
                                        result: completed ? .completed : Task.isCancelled ? .cancelled : .failed,
                                        reason: "helper 执行与准备", isPartial: !receivedMetrics && launched,
                                        includesDownload: !receivedMetrics && launched))
        }
        try await acquireWorker()
        defer { releaseWorker() }
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: executionTimeout)
        let executable = workerExecutableURL ?? Self.bundledWorkerURL
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RelayError.invalidOutput("Script-Hub helper 缺失或不可执行，请重新安装完整的 Surge Relay 应用。")
        }
        guard script.utf8.count <= ScriptHubWorkerFiles.maximumScriptBytes,
              (scriptConverterScript?.utf8.count ?? 0) <= ScriptHubWorkerFiles.maximumScriptBytes - script.utf8.count else {
            throw RelayError.invalidOutput("Script-Hub 脚本合计超过 20 MB 限制。")
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "SurgeRelay-ScriptWorker-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = ScriptHubWorkerRequest(requestURL: requestURL, hasConverter: scriptConverterScript != nil, capturesMetrics: metrics != nil)
        let metadata = try JSONEncoder().encode(request)
        guard metadata.count <= ScriptHubWorkerFiles.maximumMetadataBytes else {
            throw RelayError.invalidOutput("Script-Hub 转换请求地址过长。")
        }
        try metadata.write(to: directory.appending(path: ScriptHubWorkerFiles.requestName), options: .atomic)
        try Data(script.utf8).write(to: directory.appending(path: ScriptHubWorkerFiles.scriptName), options: .atomic)
        if let scriptConverterScript {
            try Data(scriptConverterScript.utf8).write(to: directory.appending(path: ScriptHubWorkerFiles.converterName), options: .atomic)
        }
        let worker = ScriptHubWorkerProcess(executable: executable, directory: directory)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw RelayError.invalidOutput("Script-Hub 转换超过总执行时限，helper 已终止。")
                }
                try worker.start()
                launched = true
                while worker.isRunning {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else {
                        throw RelayError.invalidOutput("Script-Hub 转换超过总执行时限，helper 已终止。")
                    }
                    try await Task.sleep(for: .milliseconds(25))
                }
                try Task.checkCancellation()
                guard worker.exitStatus == 0 else {
                    throw RelayError.invalidOutput("Script-Hub helper 异常退出（\(worker.exitStatus)）。")
                }
                let responseData = try ScriptHubWorkerFiles.read(directory.appending(path: ScriptHubWorkerFiles.responseName), maximumBytes: ScriptHubWorkerFiles.maximumMetadataBytes)
                let response = try JSONDecoder().decode(ScriptHubWorkerResponse.self, from: responseData)
                if let stages = response.stageMetrics {
                    receivedMetrics = true
                    for stage in stages where stage.stage == .download {
                        helperDownloads += stage.duration
                        metrics?.record(stage)
                    }
                }
                if let retryAfter = response.retryAfter { throw retryAfter }
                guard response.succeeded else {
                    throw RelayError.invalidOutput(response.error ?? "Script-Hub helper 未返回有效结果。")
                }
                let output = try ScriptHubWorkerFiles.read(directory.appending(path: ScriptHubWorkerFiles.outputName), maximumBytes: ScriptHubWorkerFiles.maximumOutputBytes)
                guard let text = String(data: output, encoding: .utf8) else {
                    throw RelayError.invalidOutput("Script-Hub helper 返回的内容不是 UTF-8 文本。")
                }
                completed = true
                outputBytes = Int64(output.count)
                return text
            } catch {
                worker.stop()
                guard await worker.waitForExit() else {
                    throw RelayError.invalidOutput("Script-Hub helper 已收到强制终止信号，但尚未确认退出。")
                }
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        } onCancel: { worker.stop() }
    }

    static var bundledWorkerURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/SurgeRelayScriptWorker")
    }

    private func acquireWorker() async throws {
        try Task.checkCancellation()
        if activeWorkers < maximumConcurrentWorkers {
            activeWorkers += 1
            return
        }
        let identifier = UUID()
        let admitted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters.append((identifier, continuation)) }
            }
        } onCancel: { Task { await self.cancelWaiter(identifier) } }
        guard admitted, !Task.isCancelled else {
            if admitted { releaseWorker() }
            throw CancellationError()
        }
    }

    private func releaseWorker() {
        if waiters.isEmpty { activeWorkers -= 1 }
        else { waiters.removeFirst().1.resume(returning: true) }
    }

    private func cancelWaiter(_ identifier: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == identifier }) else { return }
        waiters.remove(at: index).1.resume(returning: false)
    }

    static func makeRequest(method: String, value: JSValue) throws -> URLRequest {
        try ScriptHubNetworkPolicy.makeRequest(method: method, value: value)
    }

    static func isBlockedResolvedIPv4(_ value: UInt32) -> Bool {
        ScriptHubNetworkPolicy.isBlockedResolvedIPv4(value)
    }
}

private final class ScriptHubWorkerProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var started = false
    private var stopping = false

    init(executable: URL, directory: URL) {
        process.executableURL = executable
        process.arguments = [directory.path]
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }

    var isRunning: Bool { process.isRunning }
    var exitStatus: Int32 { process.terminationStatus }

    func start() throws {
        try lock.withLock {
            guard !stopping else { throw CancellationError() }
            try process.run()
            started = true
        }
    }

    func stop() {
        lock.withLock {
            guard !stopping else { return }
            stopping = true
            guard started, process.isRunning else { return }
            process.terminate()
            let process = process
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(500)) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    func waitForExit() async -> Bool {
        guard let pid = lock.withLock({ started ? process.processIdentifier : nil }) else { return true }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while process.isRunning {
            if kill(pid, 0) == -1, errno == ESRCH { return true }
            guard ContinuousClock.now < deadline else { return false }
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(25)) {
                    continuation.resume()
                }
            }
        }
        return true
    }
}
