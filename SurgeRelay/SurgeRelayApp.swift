import AppKit
import CoreServices
import Sparkle
import SwiftUI

enum SurgeRelayWindow {
    static let main = "main"
    static let settings = "settings"
}

extension Notification.Name {
    static let showSurgeRelayAbout = Notification.Name("showSurgeRelayAbout")
}

@MainActor
enum SurgeRelaySettingsNavigation {
    private static var hasPendingAboutRequest = false

    static func requestAbout() {
        hasPendingAboutRequest = true
        NotificationCenter.default.post(name: .showSurgeRelayAbout, object: nil)
    }

    static func consumeAboutRequest() -> Bool {
        defer { hasPendingAboutRequest = false }
        return hasPendingAboutRequest
    }
}

@MainActor
private struct SurgeRelayAppInfoCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 Surge Relay") {
                NSApp.setActivationPolicy(.regular)
                SurgeRelaySettingsNavigation.requestAbout()
                openWindow(id: SurgeRelayWindow.settings)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

private struct SurgeRelaySettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                openWindow(id: SurgeRelayWindow.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

final class SurgeRelayAppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAsLoginItem = Self.currentLaunchIsLoginItem
        NSApp.setActivationPolicy(launchedAsLoginItem ? .accessory : .regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAsLoginItem = launchedAsLoginItem || Self.currentLaunchIsLoginItem
        guard launchedAsLoginItem else {
            NSApp.setActivationPolicy(.regular)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.level == .normal }
                .forEach { $0.orderOut(nil) }
        }
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

    private static var currentLaunchIsLoginItem: Bool {
        NSAppleEventManager.shared()
            .currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}

/// Starts AppModel runtime at process scope so menu-bar-only mode keeps serving clients.
private struct SurgeRelayRuntimeHost<Content: View>: View {
    let model: AppModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task {
                await model.start()
            }
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

    private var menuBarIconOpacity: Double {
        guard model.deviceMode == .client else { return 1 }
        return model.remoteConnectionState.shouldDimMenuBarIcon ? 0.35 : 1
    }

    private static let menuBarIcon: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let image = NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: "Surge Relay"
        )?.withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        Window("Surge Relay", id: SurgeRelayWindow.main) {
            SurgeRelayRuntimeHost(model: model) {
                RootView()
                    .environment(model)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
            .frame(minWidth: 920, minHeight: 640)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 760)
        .commands {
            SurgeRelayAppInfoCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            SurgeRelaySettingsCommands()
            CommandGroup(after: .newItem) {
                Button("更新全部模块") {
                    Task { await model.updateAll() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isWorking || model.deviceMode == .client)
            }
        }

        Window("设置", id: SurgeRelayWindow.settings) {
            SettingsView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 620)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            SurgeRelayRuntimeHost(model: model) {
                MenuBarContent(updater: updaterController.updater)
                    .environment(model)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        } label: {
            Image(nsImage: Self.menuBarIcon)
                // Template menu-bar icons can't use semantic colors reliably;
                // opacity is the system-native way to show a lighter disconnected state.
                .opacity(menuBarIconOpacity)
                .accessibilityLabel("Surge Relay")
        }
        .menuBarExtraStyle(.menu)
    }
}
