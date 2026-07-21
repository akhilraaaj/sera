import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var notchEngine: NotchWindowEngine?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        appState.$displayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.syncNotch(for: mode)
            }
            .store(in: &cancellables)

        syncNotch(for: appState.displayMode)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func syncNotch(for mode: DisplayMode) {
        if mode.showsNotch {
            guard notchEngine == nil else { return }
            // Let MenuBarExtra finish removing before the island appears —
            // same quiet handoff as notch → menu bar (destroy, then show).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.appState.displayMode.showsNotch, self.notchEngine == nil else { return }
                self.notchEngine = NotchWindowEngine(appState: self.appState)
            }
        } else {
            notchEngine?.destroy()
            notchEngine = nil
        }
    }
}
