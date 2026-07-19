import AppKit
import Foundation

enum DockEdge: Equatable, Sendable {
    case bottom
    case left
    case right
    case top
}

enum DockPosition {
    static func currentEdge(for screen: NSScreen = .main ?? NSScreen.screens[0]) -> DockEdge {
        if let orientation = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["orientation"] as? String {
            switch orientation {
            case "left": return .left
            case "right": return .right
            case "top": return .top
            default: break
            }
        }

        let full = screen.frame
        let visible = screen.visibleFrame
        let leftInset = visible.minX - full.minX
        let rightInset = full.maxX - visible.maxX
        let bottomInset = visible.minY - full.minY
        let topInset = full.maxY - visible.maxY

        let insets: [(DockEdge, CGFloat)] = [
            (.left, leftInset),
            (.right, rightInset),
            (.bottom, bottomInset),
            (.top, topInset)
        ]

        return insets.max(by: { $0.1 < $1.1 })?.0 ?? .bottom
    }

    /// Origin (bottom-left in AppKit coords) for a widget of `size` docked near the Dock.
    static func widgetOrigin(size: CGSize, padding: CGFloat = 12, screen: NSScreen = .main ?? NSScreen.screens[0]) -> CGPoint {
        let visible = screen.visibleFrame
        let edge = currentEdge(for: screen)

        switch edge {
        case .bottom:
            return CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + padding
            )
        case .top:
            return CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - padding
            )
        case .left:
            return CGPoint(
                x: visible.minX + padding,
                y: visible.minY + padding
            )
        case .right:
            return CGPoint(
                x: visible.maxX - size.width - padding,
                y: visible.minY + padding
            )
        }
    }
}
