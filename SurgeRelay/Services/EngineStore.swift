import Foundation

actor EngineStore {
    private var directory: URL {
        PersistenceStore.cacheDirectoryURL
            .appending(path: "ScriptHubEngine", directoryHint: .isDirectory)
    }

    func save(scripts: [String: Data]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in scripts {
            try data.write(to: directory.appending(path: name), options: .atomic)
        }
    }

    func script(named name: String) throws -> String {
        let data = try Data(contentsOf: directory.appending(path: name))
        guard let script = String(data: data, encoding: .utf8), !script.isEmpty else {
            throw RelayError.invalidOutput("内置 Script Hub 引擎文件损坏。")
        }
        return script
    }

    func hasScript(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path)
    }
}
