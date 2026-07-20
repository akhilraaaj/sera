import Foundation

/// Where Sera surfaces live on screen.
enum DisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Classic menu-bar status item + glass dropdown.
    case menuBar
    /// Dynamic Island–style notch widget (hover to expand).
    case notch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .notch: return "Notch"
        }
    }

    var showsMenuBar: Bool { self == .menuBar }
    var showsNotch: Bool { self == .notch }
}
