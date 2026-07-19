import SwiftUI

/// Content inside the system glass `MenuBarExtra` window.
struct MenuBarPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.isPanelOpen {
                GoalSelectorPanel()
            } else {
                ExpandedPanelView()

                Divider()

                HStack {
                    Button("Timelines") {
                        appState.openTimelines()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button("Quit Sera") {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 320)
        .onAppear {
            appState.setExpanded(true)
            appState.scheduleRefresh()
        }
        .onDisappear {
            appState.setExpanded(false)
        }
    }
}
