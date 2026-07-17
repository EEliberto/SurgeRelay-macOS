import AppKit
import Sparkle
import SwiftUI

/// Contents of the menu bar extra: quick status plus a few common actions and
/// settings, without needing to bring the main window forward.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let updater: SPUUpdater

    var body: some View {
        Section("状态") {
            if model.deviceMode == .client {
                Text("客户端模式")
                if let url = model.remoteManagementURL {
                    Text(url.host ?? url.absoluteString)
                } else {
                    Text("尚未设置服务器 Ponte 地址")
                }
                if model.remoteConnectionState.isUnavailable {
                    Text("服务器无响应")
                } else if case .reconnecting = model.remoteConnectionState {
                    Text("正在重新连接服务器…")
                } else if !model.remoteConnectionState.isOperational, model.hasConfiguredRemoteServer {
                    Text("正在连接服务器…")
                }
            } else if model.settings.webServerEnabled {
                Text(webServerStatusText)
            }
            if model.isWorking {
                Text(workingText)
            }
            Text("最新更新：\(latestUpdateText)")
            Text("启用来源：\(model.modules.filter(\.isEnabled).count) / \(model.modules.count)")
        }

        Divider()

        Button("更新全部模块") {
            Task { await model.updateAll() }
        }
        .disabled(
            model.modules.isEmpty
                || model.isWorking
                || (model.deviceMode == .client && !model.isRemoteServerOperational)
        )

        if let url = model.combinedRawURL(for: .ios) {
            Button("拷贝总订阅地址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }

        Divider()

        if model.deviceMode == .server {
            Toggle("自动同步", isOn: Binding(
                get: { model.settings.automaticallyPublish },
                set: { model.settings.automaticallyPublish = $0; model.saveSettings() }
            ))
            Toggle("登录时启动", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Divider()
        }

        Button("打开 Surge Relay") {
            activateMainWindow()
        }
        CheckForUpdatesView(updater: updater)
        Button("设置…") {
            activateSettingsWindow()
        }
        Divider()
        Button("退出 Surge Relay") { NSApplication.shared.terminate(nil) }
    }

    private func activateSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: SurgeRelayWindow.settings)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var webServerStatusText: String {
        switch model.webServerState {
        case .running: "Web 管理：运行中"
        case .starting: "Web 管理：正在启动"
        case .restarting: "Web 管理：正在恢复"
        case .stopped: "Web 管理：已停止"
        case .failed: "Web 管理：失败"
        }
    }

    private var latestUpdateText: String {
        guard let date = model.modules.compactMap(\.lastUpdatedAt).max() else { return "尚未更新" }
        return date.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: Locale(identifier: "zh_CN")
        ))
    }

    private var workingText: String {
        if model.synchronizationTotalCount > 0 {
            return "正在更新 \(model.synchronizationCompletedCount) / \(model.synchronizationTotalCount)…"
        }
        return model.statusMessage
    }

    private func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: SurgeRelayWindow.main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            let window = NSApp.windows.first(where: {
                $0.canBecomeMain && $0.level == .normal && $0.title == "Surge Relay"
            }) ?? NSApp.windows.first(where: { $0.canBecomeMain && $0.level == .normal })
            window?.deminiaturize(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}
