import SwiftUI

@main
struct SurgeRelayIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ClientAppModel()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environment(model)
                .task {
                    model.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.start()
                    case .inactive, .background:
                        model.stopRemoteSession()
                    @unknown default:
                        model.stopRemoteSession()
                    }
                }
        }
    }
}
