import AppKit
import SwiftUI

/// The module list lives directly in the sidebar of a two-column
/// NavigationSplitView (see `ModulesView`); settings are opened from the app menu.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        Group {
            if model.deviceMode == .client, !model.hasConfiguredRemoteServer {
                ContentUnavailableView {
                    Label("尚未设置服务器", systemImage: "network.slash")
                } description: {
                    Text("请完成欢迎向导，输入服务器 Mac 的 Ponte 地址，例如 johnsmac.sgponte。")
                } actions: {
                    Button("打开欢迎向导") {
                        model.presentWelcomeWizard(allowDismiss: true)
                    }
                    .buttonStyle(.glassProminent)
                }
            } else if model.deviceMode == .client, model.remoteConnectionState.isUnavailable {
                ContentUnavailableView {
                    Label("服务器无响应", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(unavailableDescription)
                } actions: {
                    Button("重新连接") {
                        model.startRemoteSessionIfNeeded()
                    }
                    .buttonStyle(.glassProminent)
                    Button("设置") {
                        openWindow(id: SurgeRelayWindow.settings)
                    }
                }
            } else if model.deviceMode == .client, !model.remoteConnectionState.isOperational {
                ContentUnavailableView {
                    Label("正在连接服务器", systemImage: "network")
                } description: {
                    Text("正在通过 Surge Ponte 连接服务器 Mac…")
                } actions: {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Button("设置") {
                            openWindow(id: SurgeRelayWindow.settings)
                        }
                    }
                }
            } else {
                ModulesView()
            }
        }
        .background(MainWindowCloseBehavior())
        .sheet(isPresented: $model.presentsConfigurationWelcome) {
            WelcomeWizardView()
                .environment(model)
        }
    }

    private var unavailableDescription: String {
        if let message = model.remoteConnectionState.unavailableMessage, !message.isEmpty {
            return "\(message)\n\n请确认服务器 Mac 上的 Surge Relay 正在运行，且已在设置中启用 Web 管理。"
        }
        return "无法连接 Ponte 服务器。请确认服务器 Mac 上的 Surge Relay 正在运行，且已在设置中启用 Web 管理。"
    }
}
