import Foundation

enum ModuleUpdatePipeline {
    static let maximumConcurrency = 4

    @MainActor
    static func run<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maximumConcurrency: Int = maximumConcurrency,
        operation: @escaping @Sendable (Input) async -> Output,
        didComplete: @MainActor (Output) -> Void = { _ in }
    ) async -> [Output] {
        guard !inputs.isEmpty, !Task.isCancelled else { return [] }
        return await withTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            var outputs: [Int: Output] = [:]
            let limit = max(1, min(maximumConcurrency, inputs.count))
            for index in 0..<limit {
                let input = inputs[index]
                group.addTask { (index, await operation(input)) }
                next += 1
            }
            while let (index, output) = await group.next() {
                outputs[index] = output
                didComplete(output)
                if Task.isCancelled {
                    group.cancelAll()
                } else if next < inputs.count {
                    let index = next
                    let input = inputs[index]
                    group.addTask { (index, await operation(input)) }
                    next += 1
                }
            }
            return inputs.indices.compactMap { outputs[$0] }
        }
    }

    static func restoredState(for module: RelayModule) -> ModuleUpdateState {
        module.state == .updating ? (module.contentHash == nil ? .never : .current) : module.state
    }
}

struct ModuleUpdateOutcome: Sendable {
    var components: [(RelayModule, String)]
    var failures: Int
    var missingCache: [String]
    var missingCacheDetails: [String]
    var contentChanged: Bool
    var history: [UpdateHistoryEntry]
}
