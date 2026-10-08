import Foundation
import Darwin

@main
struct ScriptHubWorkerMain {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        signal(SIGALRM, SIG_DFL)
        alarm(95)
        let directory = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let response: ScriptHubWorkerResponse
        let metrics = StageMetricsRecorder()
        var capturesMetrics = false
        do {
            let requestData = try ScriptHubWorkerFiles.read(directory.appending(path: ScriptHubWorkerFiles.requestName), maximumBytes: ScriptHubWorkerFiles.maximumMetadataBytes)
            let request = try JSONDecoder().decode(ScriptHubWorkerRequest.self, from: requestData)
            capturesMetrics = request.capturesMetrics == true
            let script = try ScriptHubWorkerFiles.read(directory.appending(path: ScriptHubWorkerFiles.scriptName), maximumBytes: ScriptHubWorkerFiles.maximumScriptBytes)
            let converter = request.hasConverter
                ? try ScriptHubWorkerFiles.read(directory.appending(path: ScriptHubWorkerFiles.converterName), maximumBytes: ScriptHubWorkerFiles.maximumScriptBytes - script.count) : nil
            let started = ContinuousClock.now
            let output: String
            do {
                output = try StageMetricsContext.$current.withValue(capturesMetrics ? metrics : nil) {
                    try ScriptHubJavaScriptRuntime.execute(
                        script: String(decoding: script, as: UTF8.self),
                        scriptConverterScript: converter.map { String(decoding: $0, as: UTF8.self) },
                        requestURL: request.requestURL
                    )
                }
                metrics.record(StageMetric(stage: .conversion, duration: max(0, StageMetricsRecorder.elapsed(since: started) - metrics.duration(for: .download)), bytesWritten: Int64(output.utf8.count)))
            } catch {
                metrics.record(StageMetric(stage: .conversion, duration: max(0, StageMetricsRecorder.elapsed(since: started) - metrics.duration(for: .download)), failedAttempts: 1, result: .failed))
                throw error
            }
            guard output.utf8.count <= ScriptHubWorkerFiles.maximumOutputBytes else {
                throw RelayError.invalidOutput("Script-Hub 转换输出超过 20 MB 限制。")
            }
            try Data(output.utf8).write(to: directory.appending(path: ScriptHubWorkerFiles.outputName), options: .atomic)
            response = ScriptHubWorkerResponse(succeeded: true, error: nil, stageMetrics: capturesMetrics ? metrics.snapshot : nil)
        } catch {
            let message: String
            if case let RelayError.invalidOutput(detail) = error { message = detail }
            else { message = error.localizedDescription }
            response = ScriptHubWorkerResponse(succeeded: false, error: String(message.prefix(4_000)), retryAfter: error as? SourceRetryAfterError, stageMetrics: capturesMetrics ? metrics.snapshot : nil)
        }
        do {
            try JSONEncoder().encode(response).write(to: directory.appending(path: ScriptHubWorkerFiles.responseName), options: .atomic)
        } catch { exit(74) }
    }
}
