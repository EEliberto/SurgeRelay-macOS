import Foundation

enum RemoteConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    /// Live sync dropped; UI keeps the last good projection while reconnecting.
    case reconnecting
    case unavailable(String)

    /// Client UI may show modules and accept mutations.
    var isOperational: Bool {
        switch self {
        case .connected, .reconnecting: true
        case .idle, .connecting, .unavailable: false
        }
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
        case .idle, .connecting, .reconnecting, .unavailable: true
        }
    }
}
