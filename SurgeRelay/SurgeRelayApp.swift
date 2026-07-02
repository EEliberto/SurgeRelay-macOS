import AppKit
import Sparkle
import SwiftUI

enum SurgeRelayWindow {
    static let main = "main"
}

final class SurgeRelayAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        sender.setActivationPolicy(.regular)
        sender.activate(ignoringOtherApps: true)
        let window = sender.windows.first(where: { $0.canBecomeMain && $0.level == .normal })
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        return true
    }
}

@main
struct SurgeRelayApp: App {
    @NSApplicationDelegateAdaptor(SurgeRelayAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        Window("Surge Relay", id: SurgeRelayWindow.main) {
            RootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .task { await model.start() }
                .frame(minWidth: 700)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { model.presentsSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("更新全部模块") {
                    Task { await model.updateAll() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isWorking)
            }
        }

        MenuBarExtra("Surge Relay", systemImage: "repeat") {
            MenuBarContent(updater: updaterController.updater)
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .menuBarExtraStyle(.menu)
    }
}
