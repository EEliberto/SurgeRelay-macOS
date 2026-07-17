import Foundation

enum RemoteConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case unavailable(String)

    var isOperational: Bool {
        if case .connected = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var unavailableMessage: String? {
        if case let .unavailable(message) = self { return message }
        return nil
    }

    /// Menu bar uses a lighter template icon when the client is not live-synced.
    var shouldDimMenuBarIcon: Bool {
        switch self {
        case .connected: false
        case .idle, .connecting, .unavailable: true
        }
    }
}
