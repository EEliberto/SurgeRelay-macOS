import Foundation
import Network

final class NetworkPathMonitor: @unchecked Sendable {
    var onBecameReachable: (@Sendable () -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.allenmiao.SurgeRelay.network-monitor", qos: .utility)
    private var lastStatus: NWPath.Status?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let becameReachable = path.status == .satisfied
                && self.lastStatus != .satisfied
            self.lastStatus = path.status
            if becameReachable {
                self.onBecameReachable?()
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
