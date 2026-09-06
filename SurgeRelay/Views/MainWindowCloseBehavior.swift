import AppKit
import SwiftUI

/// Applies the mode-specific lifecycle after SwiftUI closes the main window.
@MainActor
struct MainWindowCloseBehavior: NSViewRepresentable {
    let deviceMode: RelayDeviceMode

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.deviceMode = deviceMode
            context.coordinator.install(on: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.deviceMode = deviceMode
            context.coordinator.install(on: view.window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var closeObserver: NSObjectProtocol?
        var deviceMode: RelayDeviceMode = .server

        func install(on candidate: NSWindow?) {
            guard let candidate, window !== candidate else { return }
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            window = candidate
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: candidate,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.mainWindowWillClose()
                }
            }
        }

        private func mainWindowWillClose() {
            if deviceMode == .client {
                NSApp.terminate(nil)
                return
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
