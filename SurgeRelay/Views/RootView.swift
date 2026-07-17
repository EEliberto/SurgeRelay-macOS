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
}
