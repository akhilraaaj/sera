import Combine
import CoreGraphics
import Foundation

/// Idle island size inside the always-expanded notch window.
/// The panel stays top-pinned; SwiftUI morphs the clip between this size and
/// the full window so hover-expand never opens a gap under the menu bar.
@MainActor
final class NotchLayout: ObservableObject {
    @Published var idleSize: CGSize = CGSize(width: 300, height: 37)
}
