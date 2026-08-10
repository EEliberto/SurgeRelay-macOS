import AppKit
import Sparkle
import SwiftUI

/// AppKit owns the status item so client launches never construct SwiftUI's
/// MenuBarExtra scene. The singleton also keeps the server item alive when all
/// SwiftUI windows are hidden.
@MainActor
final class MenuBarStatusController: NSObject, NSMenuDelegate {
    static let shared = MenuBarStatusController()

    private var statusItem: NSStatusItem?
    private weak var model: AppModel?
    private weak var updater: SPUUpdater?
    private var openMainWindowAction: (() -> Void)?
    private var openSettingsWindowAction: (() -> Void)?

    func configure(
        isEnabled: Bool,
        model: AppModel,
        updater: SPUUpdater,
        openMainWindow: @escaping () -> Void,
        openSettingsWindow: @escaping () -> Void
    ) {
        self.model = model
        self.updater = updater
        openMainWindowAction = openMainWindow
        openSettingsWindowAction = openSettingsWindow

        guard isEnabled else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let image = NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: "Surge Relay"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Surge Relay"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let model else { return }
        menu.removeAllItems()

        let status = NSMenuItem(title: webServerStatus(model), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(actionItem("更新全部模块", action: #selector(updateAll)))
        if model.combinedRawURL(for: .ios) != nil {
            menu.addItem(actionItem("拷贝总订阅地址", action: #selector(copyCombinedURL)))
        }
        menu.addItem(.separator())

        let automatic = actionItem("自动同步", action: #selector(toggleAutomaticSync))
        automatic.state = model.settings.automaticallyPublish ? .on : .off
        menu.addItem(automatic)

        let login = actionItem("登录时启动", action: #selector(toggleLaunchAtLogin))
        login.state = model.settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(actionItem("打开 Surge Relay", action: #selector(openMainWindow)))
        menu.addItem(actionItem("检查更新…", action: #selector(checkForUpdates)))
        menu.addItem(actionItem("设置…", action: #selector(openSettingsWindow)))
        menu.addItem(.separator())
        menu.addItem(actionItem("退出 Surge Relay", action: #selector(terminateCompletely)))
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func webServerStatus(_ model: AppModel) -> String {
        switch model.webServerState {
        case .running: "Web 管理：运行中"
        case .starting: "Web 管理：正在启动"
        case .restarting: "Web 管理：正在恢复"
        case .stopped: "Web 管理：已停止"
        case .failed: "Web 管理：失败"
        }
    }

    @objc private func updateAll() {
        guard let model else { return }
        Task { await model.updateAll() }
    }

    @objc private func copyCombinedURL() {
        guard let url = model?.combinedRawURL(for: .ios) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func toggleAutomaticSync() {
        guard let model else { return }
        model.settings.automaticallyPublish.toggle()
        model.saveSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        guard let model else { return }
        model.setLaunchAtLogin(!model.settings.launchAtLogin)
    }

    @objc private func openMainWindow() {
        openMainWindowAction?()
    }

    @objc private func openSettingsWindow() {
        openSettingsWindowAction?()
    }

    @objc private func checkForUpdates() {
        updater?.checkForUpdates()
    }

    @objc private func terminateCompletely() {
        SurgeRelayTerminationCoordinator.terminateCompletely()
    }
}

struct MenuBarStatusHost: View {
    @Environment(\.openWindow) private var openWindow
    let isEnabled: Bool
    let model: AppModel
    let updater: SPUUpdater

    var body: some View {
        MenuBarStatusInstaller(
            isEnabled: isEnabled,
            model: model,
            updater: updater,
            openMainWindow: { presentWindow(id: SurgeRelayWindow.main) },
            openSettingsWindow: { presentWindow(id: SurgeRelayWindow.settings) }
        )
    }

    private func presentWindow(id: String) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let normalWindows = NSApp.windows.filter { $0.level == .normal && $0.canBecomeMain }
            let window: NSWindow?
            if id == SurgeRelayWindow.settings {
                window = normalWindows.first(where: { $0.title == "设置" })
            } else {
                window = normalWindows.first(where: { $0.title != "设置" })
            }
            window?.deminiaturize(nil)
            window?.level = .normal
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }
}

private struct MenuBarStatusInstaller: NSViewRepresentable {
    let isEnabled: Bool
    let model: AppModel
    let updater: SPUUpdater
    let openMainWindow: () -> Void
    let openSettingsWindow: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        MenuBarStatusController.shared.configure(
            isEnabled: isEnabled,
            model: model,
            updater: updater,
            openMainWindow: openMainWindow,
            openSettingsWindow: openSettingsWindow
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        MenuBarStatusController.shared.configure(
            isEnabled: isEnabled,
            model: model,
            updater: updater,
            openMainWindow: openMainWindow,
            openSettingsWindow: openSettingsWindow
        )
    }
}
