import SwiftUI

/// Shared Sera palette. Progress fill uses the brand accent throughout.
enum SeraTheme {
    /// Active / completed progress — `#f54e00`.
    static let progress = Color(red: 245 / 255, green: 78 / 255, blue: 0)
    /// Soft tip halo behind the leading marker.
    static let progressHalo = progress.opacity(0.18)
    /// Unfilled track / inactive dots.
    static let track = Color.primary.opacity(0.12)
}
