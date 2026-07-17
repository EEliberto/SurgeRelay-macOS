import AppKit
import Foundation

extension AppModel {
    func beginNetworkRecoveryMonitoring() {
        guard networkPathMonitor == nil else { return }

        let monitor = NetworkPathMonitor()
        monitor.onBecameReachable = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleNetworkRecovery()
            }
        }
        monitor.start()
        networkPathMonitor = monitor

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleNetworkRecovery()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleNetworkRecovery()
            }
        }
    }

    func handleNetworkRecovery() {
        if deviceMode == .server, webServerShouldRun {
            switch webServerState {
            case .failed, .stopped:
                scheduleWebServerRestart(immediate: true)
            default:
                break
            }
        }
        if isClientMode, hasConfiguredRemoteServer, !remoteConnectionState.isOperational {
            startRemoteSessionIfNeeded()
        }
    }

    func handleWebServerStateChange(_ state: WebServerRuntimeState) {
        let previous = webServerState
        webServerState = state
        switch state {
        case .running:
            beginWebServerActivity()
        case .failed:
            endWebServerActivity()
            if webServerShouldRun {
                scheduleWebServerRestart()
            }
        case .stopped:
            endWebServerActivity()
            if webServerShouldRun, case .running = previous {
                scheduleWebServerRestart()
            }
        case .starting, .restarting:
            break
        }
    }

    func startWebServerListener(port: UInt16) {
        webServer.stop()
        let configuration = WebServerConfiguration(port: port)
        do {
            try webServer.start(
                configuration: configuration,
                stateHandler: { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.handleWebServerStateChange(state)
                    }
                },
                eventHandler: { [weak self] in
                    guard let self else { return "{}" }
                    return await WebManagementAPI.eventPayload(model: self)
                },
                requestHandler: { [weak self] request in
                    if !request.path.hasPrefix("/api/") {
                        return WebManagementAPI.assetResponse(for: request.path)
                    }
                    guard let self else {
                        return .error(status: 500, message: "Surge Relay 已停止。")
                    }
                    return await WebManagementAPI.response(for: request, model: self)
                }
            )
        } catch {
            webServerState = .failed(error.localizedDescription)
            if webServerShouldRun {
                scheduleWebServerRestart()
            }
        }
    }

    func scheduleWebServerRestart(immediate: Bool = false) {
        webServerRestartTask?.cancel()
        webServerRestartTask = Task { [weak self] in
            var delay = immediate ? 0.0 : 1.0
            let maxDelay = 30.0
            while !Task.isCancelled {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled, let self, self.webServerShouldRun else { return }
                guard (1...65_535).contains(self.settings.webServerPort),
                      let port = UInt16(exactly: self.settings.webServerPort) else { return }

                self.webServerState = .restarting
                self.startWebServerListener(port: port)
                if case .running = self.webServerState { return }
                delay = min(maxDelay, max(1, delay * 2))
            }
        }
    }

    func beginWebServerActivity() {
        guard webServerActivityToken == nil else { return }
        webServerActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Surge Relay Web management"
        )
    }

    func endWebServerActivity() {
        if let token = webServerActivityToken {
            ProcessInfo.processInfo.endActivity(token)
            webServerActivityToken = nil
        }
    }
}
