import Foundation

actor ModuleFileStore {
    private var componentDirectory: URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "Components", directoryHint: .isDirectory)
    }

    private var overrideDirectory: URL {
        PersistenceStore.configurationDirectoryURL.appending(path: "Overrides", directoryHint: .isDirectory)
    }

    private var assetDirectory: URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "Assets", directoryHint: .isDirectory)
    }

    private var combinedCacheURL: URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "Combined.cache")
    }

    private var combinedOverrideURL: URL {
        PersistenceStore.cacheDirectoryURL.appending(path: "CombinedOverride.cache")
    }

    func prepareStorage() throws {
        for directory in [componentDirectory, overrideDirectory, assetDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func hasCombined() -> Bool {
        FileManager.default.fileExists(atPath: combinedOverrideURL.path)
            || FileManager.default.fileExists(atPath: combinedCacheURL.path)
    }

    func writeComponent(_ content: String, id: UUID) throws {
        try FileManager.default.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
        try Data(SurgeModuleSanitizer.sanitize(content).utf8).write(to: componentURL(for: id), options: .atomic)
    }

    func hasComponent(id: UUID) -> Bool {
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Surge Relay/Components/\(id.uuidString).sgmodule")
        return FileManager.default.fileExists(atPath: componentOverrideURL(for: id).path)
            || FileManager.default.fileExists(atPath: componentURL(for: id).path)
            || FileManager.default.fileExists(atPath: legacyURL.path)
    }

    func hasOverride(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: componentOverrideURL(for: id).path)
    }

    func readComponent(id: UUID) throws -> String {
        let overrideURL = componentOverrideURL(for: id)
        let legacyOverrideURL = PersistenceStore.cacheDirectoryURL
            .appending(path: "Overrides/\(id.uuidString).cache")
        if !FileManager.default.fileExists(atPath: overrideURL.path),
           FileManager.default.fileExists(atPath: legacyOverrideURL.path) {
            try FileManager.default.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: legacyOverrideURL, to: overrideURL)
        }
        if FileManager.default.fileExists(atPath: overrideURL.path) {
            return SurgeModuleSanitizer.sanitize(try decodeText(at: overrideURL))
        }
        return try readConvertedComponent(id: id)
    }

    func readConvertedComponent(id: UUID) throws -> String {
        let url = componentURL(for: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            let legacyURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Surge Relay/Components/\(id.uuidString).sgmodule")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try FileManager.default.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: legacyURL, to: url)
            }
        }
        return SurgeModuleSanitizer.sanitize(try decodeText(at: url))
    }

    func writeComponentOverride(_ content: String, id: UUID) throws {
        try FileManager.default.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
        try PersistenceStore.writeProtectedData(
            Data(SurgeModuleSanitizer.sanitize(content).utf8),
            to: componentOverrideURL(for: id)
        )
    }

    func restoreComponent(id: UUID) throws -> String {
        let url = componentOverrideURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        return try readConvertedComponent(id: id)
    }

    func removeComponent(id: UUID) throws {
        let url = componentURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let overrideURL = componentOverrideURL(for: id)
        if FileManager.default.fileExists(atPath: overrideURL.path) { try FileManager.default.removeItem(at: overrideURL) }
    }

    func writeCombined(_ content: String) throws {
        try FileManager.default.createDirectory(at: combinedCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: combinedCacheURL, options: .atomic)
    }

    func readCombined() throws -> Data {
        let url = FileManager.default.fileExists(atPath: combinedOverrideURL.path) ? combinedOverrideURL : combinedCacheURL
        return try Data(contentsOf: url)
    }

    /// Exports the merged module to a user-visible `.sgmodule` file in the given
    /// directory (used by local storage mode so Surge can load it directly).
    func exportCombined(_ content: String, toDirectory directoryPath: String, fileName: String) throws {
        let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: directory.appending(path: fileName), options: .atomic)
    }

    func writeCombinedOverride(_ content: String) throws {
        try FileManager.default.createDirectory(at: combinedOverrideURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: combinedOverrideURL, options: .atomic)
    }

    func restoreCombined() throws -> String {
        if FileManager.default.fileExists(atPath: combinedOverrideURL.path) {
            try FileManager.default.removeItem(at: combinedOverrideURL)
        }
        return try decodeText(at: combinedCacheURL)
    }

    func removeCombined() throws {
        if FileManager.default.fileExists(atPath: combinedCacheURL.path) {
            try FileManager.default.removeItem(at: combinedCacheURL)
        }
        if FileManager.default.fileExists(atPath: combinedOverrideURL.path) {
            try FileManager.default.removeItem(at: combinedOverrideURL)
        }
    }

    func replaceAssets(_ assets: [GeneratedAsset], id: UUID) throws {
        let relativeRoot = "assets/\(id.uuidString.lowercased())"
        let root = assetDirectory.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        guard !assets.isEmpty else { return }

        for asset in assets {
            guard asset.relativePath.hasPrefix(relativeRoot + "/") else {
                throw RelayError.invalidOutput("生成脚本的保存路径无效。")
            }
            let fileName = String(asset.relativePath.dropFirst((relativeRoot + "/").count))
            let destination = root.appending(path: fileName)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try asset.data.write(to: destination, options: .atomic)
        }
    }

    func removeAssets(id: UUID) throws {
        let root = assetDirectory.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func generatedAssetFiles() throws -> [PublishFile] {
        guard FileManager.default.fileExists(atPath: assetDirectory.path),
              let enumerator = FileManager.default.enumerator(
                at: assetDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        var files: [PublishFile] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = fileURL.path.replacingOccurrences(of: assetDirectory.path + "/", with: "")
            files.append(PublishFile(name: "assets/\(relative)", data: try Data(contentsOf: fileURL)))
        }
        return files.sorted { $0.name < $1.name }
    }

    func removeLegacyPublishedFiles(in directoryPath: String) throws {
        let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            if url.pathExtension.lowercased() == "sgmodule" || url.lastPathComponent == "assets" {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func componentURL(for id: UUID) -> URL {
        componentDirectory.appending(path: "\(id.uuidString).cache")
    }

    private func componentOverrideURL(for id: UUID) -> URL {
        overrideDirectory.appending(path: "\(id.uuidString).module")
    }

    private func decodeText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw RelayError.invalidOutput("模块缓存不是有效的 UTF-8 文本。")
        }
        return content
    }
}
