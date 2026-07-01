import AppKit
import SwiftUI

/// Keeps the app resident in the menu bar by turning the main window's close
/// button into a hide action. This avoids replacing SwiftUI's window delegate.
struct MainWindowCloseBehavior: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.install(on: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.install(on: view.window) }
    }

    final class Coordinator: NSObject {
        private weak var window: NSWindow?

        func install(on candidate: NSWindow?) {
            guard let candidate, window !== candidate,
                  let closeButton = candidate.standardWindowButton(.closeButton) else { return }
            window = candidate
            closeButton.target = self
            closeButton.action = #selector(hideMainWindow)
        }

        @objc private func hideMainWindow() {
            window?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
