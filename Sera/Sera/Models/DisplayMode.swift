import Foundation

/// Where Sera surfaces live on screen.
enum DisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Classic menu-bar status item + glass dropdown.
    case menuBar
    /// Dynamic Island–style notch widget (hover to expand).
    case notch
    /// Menu bar item and notch widget together.
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .notch: return "Notch"
        case .both: return "Both"
        }
    }

    var showsMenuBar: Bool {
        switch self {
        case .menuBar, .both: return true
        case .notch: return false
        }
    }

    var showsNotch: Bool {
        switch self {
        case .notch, .both: return true
        case .menuBar: return false
        }
    }
}
