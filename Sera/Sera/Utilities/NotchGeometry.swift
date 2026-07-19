import AppKit
import Foundation

/// Screen geometry for a BoringNotch-style island over the Mac notch / top center.
enum NotchGeometry {
    struct Info: Equatable {
        var screen: NSScreen
        /// Physical (or synthetic) notch rect in AppKit screen coordinates.
        var notchFrame: NSRect
        var menubarHeight: CGFloat
        var hasHardwareNotch: Bool
    }

    /// Fallback island size when the display has no hardware notch.
    private static let syntheticWidth: CGFloat = 172
    private static let syntheticHeight: CGFloat = 32

    static func info(for screen: NSScreen? = NSScreen.main) -> Info? {
        guard let screen else { return nil }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let menubarHeight = max(24, frame.maxY - visible.maxY)

        if let notch = hardwareNotchFrame(on: screen, menubarHeight: menubarHeight) {
            return Info(
                screen: screen,
                notchFrame: notch,
                menubarHeight: menubarHeight,
                hasHardwareNotch: true
            )
        }

        let width = syntheticWidth
        let height = min(syntheticHeight, menubarHeight)
        let rect = NSRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
        return Info(
            screen: screen,
            notchFrame: rect,
            menubarHeight: menubarHeight,
            hasHardwareNotch: false
        )
    }

    /// Collapsed panel frame — matches notch width, sits flush with the top edge.
    static func collapsedFrame(info: Info, horizontalPadding: CGFloat = 0) -> NSRect {
        var frame = info.notchFrame
        frame.origin.x -= horizontalPadding
        frame.size.width += horizontalPadding * 2
        // Slightly taller than the physical cutout so the black shell reads as an island.
        let height = max(info.notchFrame.height, 34)
        frame.origin.y = info.screen.frame.maxY - height
        frame.size.height = height
        return frame
    }

    /// Expanded panel frame — drops below the menu bar and can bias its
    /// content to either side while staying physically attached to the notch.
    static func expandedFrame(
        info: Info,
        size: CGSize,
        horizontalOffset: CGFloat = 0
    ) -> NSRect {
        let top = info.screen.frame.maxY
        let idealX = info.notchFrame.midX - size.width / 2 + horizontalOffset
        let sideMargin: CGFloat = 12
        let x = min(
            info.screen.frame.maxX - size.width - sideMargin,
            max(info.screen.frame.minX + sideMargin, idealX)
        )
        return NSRect(
            x: x,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Hardware notch

    private static func hardwareNotchFrame(on screen: NSScreen, menubarHeight: CGFloat) -> NSRect? {
        if #available(macOS 12.0, *) {
            let left = screen.auxiliaryTopLeftArea
            let right = screen.auxiliaryTopRightArea
            if let left, let right, right.minX > left.maxX + 40 {
                let width = right.minX - left.maxX
                let height = max(menubarHeight, max(left.height, right.height))
                return NSRect(
                    x: left.maxX,
                    y: screen.frame.maxY - height,
                    width: width,
                    height: height
                )
            }
        }

        // Older path: top safe-area inset implies a notch, width estimated from typical M-series.
        if #available(macOS 12.0, *) {
            let inset = screen.safeAreaInsets.top
            if inset > 0 {
                let width = syntheticWidth + 20
                return NSRect(
                    x: screen.frame.midX - width / 2,
                    y: screen.frame.maxY - inset,
                    width: width,
                    height: inset
                )
            }
        }

        return nil
    }
}
