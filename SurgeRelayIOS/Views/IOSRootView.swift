import SwiftUI

struct IOSRootView: View {
    @Environment(ClientAppModel.self) private var model

    var body: some View {
        Group {
            if model.hasConfiguredServer {
                IOSMainShellView()
            } else {
                Color.clear
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !model.hasConfiguredServer },
            set: { _ in }
        )) {
            IOSWelcomeView()
                .interactiveDismissDisabled()
        }
    }
}

struct IOSMainShellView: View {
    @Environment(ClientAppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        TabView {
            Tab("模块", systemImage: "shippingbox") {
                if sizeClass == .regular {
                    IOSModulesSplitView()
                } else {
                    NavigationStack {
                        IOSModulesListView()
                    }
                }
            }

            Tab("设置", systemImage: "gearshape") {
                NavigationStack {
                    IOSSettingsView()
                }
            }
        }
        .alert("错误", isPresented: Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.dismissPresentedError() } }
        )) {
            Button("好", role: .cancel) { model.dismissPresentedError() }
        } message: {
            Text(model.presentedError ?? "")
        }
    }
}
