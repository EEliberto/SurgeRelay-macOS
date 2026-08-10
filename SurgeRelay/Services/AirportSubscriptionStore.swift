import Foundation

enum AirportSubscriptionStore {
    private static var directoryURL: URL {
        let directory = PersistenceStore.cacheDirectoryURL
            .appending(path: "AirportSubscriptions", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func cacheURL(for id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString.lowercased()).txt")
    }

    static func save(_ data: Data, for id: UUID) throws {
        try data.write(to: cacheURL(for: id), options: .atomic)
    }

    static func data(for id: UUID) throws -> Data {
        try Data(contentsOf: cacheURL(for: id))
    }

    static func hasCache(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(for: id).path)
    }

    static func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: cacheURL(for: id))
    }
}
