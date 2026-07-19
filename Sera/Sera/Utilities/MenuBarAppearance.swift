import AppKit
import Combine
import SwiftUI

/// Appearance-only menu-bar tint — no screen capture / extra permissions.
/// Dark → black (matches typical opaque dark menu bar); light → light chrome.
@MainActor
final class MenuBarAppearance: ObservableObject {
    @Published private(set) var background: Color = .black
    @Published private(set) var colorScheme: ColorScheme = .dark

    private var observer: NSObjectProtocol?

    func start() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    func refresh() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            background = .black
            colorScheme = .dark
        } else {
            background = Color(red: 0.93, green: 0.93, blue: 0.94)
            colorScheme = .light
        }
    }
}
