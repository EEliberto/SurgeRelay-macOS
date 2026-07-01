import SwiftUI

/// The module list now lives directly in the sidebar of a two-column
/// NavigationSplitView (see `ModulesView`); settings moved to a toolbar button.
struct RootView: View {
    var body: some View {
        ModulesView()
            .background(MainWindowCloseBehavior())
    }
}
