import SwiftUI

@main
struct SeraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarScene(appState: appDelegate.appState)
    }
}

/// Isolated so `@ObservedObject` can react to `displayMode` and toggle the status item.
private struct MenuBarScene: Scene {
    @ObservedObject var appState: AppState

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarPanelView()
                .environmentObject(appState)
                .tint(SeraTheme.progress)
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { appState.displayMode.showsMenuBar },
            set: { show in
                appState.setDisplayMode(show ? .menuBar : .notch)
            }
        )
    }
}
