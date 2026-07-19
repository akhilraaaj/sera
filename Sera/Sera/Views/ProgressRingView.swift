import SwiftUI

/// Concentric-dot progress field. Dots fill from the inside out, clockwise,
/// with the active count driven directly by `progress` (0…1).
struct ProgressRingView: View {
    var progress: Double
    var lineWidth: CGFloat = 6
    var showsLabel: Bool = true
    var compact: Bool = false
    var caption: String? = nil
    var daysElapsed: Int? = nil
    var daysRemaining: Int? = nil

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        Group {
            if compact {
                DotRingCanvas(progress: clampedProgress, ringCount: 5, style: .compact)
            } else {
                panelLayout
            }
        }
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(String(format: "%.1f percent", clampedProgress * 100)))
        .animation(.easeInOut(duration: 0.55), value: clampedProgress)
    }

    private var panelLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            DotRingCanvas(progress: clampedProgress, ringCount: 7, style: .panel)
                .frame(maxWidth: .infinity)
                .frame(height: 200)

            if showsLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f%%", clampedProgress * 100))
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    if let caption {
                        Text(caption)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let daysElapsed, let daysRemaining {
                ProgressMetricCards(
                    daysElapsed: daysElapsed,
                    daysRemaining: daysRemaining
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Style

private enum DotRingStyle {
    case compact
    case panel

    var edgeInsetFactor: CGFloat {
        switch self {
        case .compact: return 0.03
        case .panel: return 0.012
        }
    }

    var arcSpacingFactor: CGFloat {
        switch self {
        case .compact: return 0.76
        // Larger spacing along each ring so active dots don’t look packed.
        case .panel: return 0.92
        }
    }
}

// MARK: - Canvas

private struct DotRingCanvas: View, Animatable {
    var progress: Double
    var ringCount: Int
    var style: DotRingStyle

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        // Prefer width so the field fills the panel; center if taller.
        let side = min(size.width, size.height)
        guard side > 8 else { return }

        let origin = CGPoint(
            x: (size.width - side) * 0.5,
            y: (size.height - side) * 0.5
        )
        let drawSize = CGSize(width: side, height: side)

        let edgeInset = side * style.edgeInsetFactor
        let layout = DotLayout(
            size: drawSize,
            ringCount: ringCount,
            edgeInset: edgeInset,
            arcSpacingFactor: style.arcSpacingFactor
        )

        let total = layout.dots.count
        guard total > 0 else { return }

        let activeCount = Int((progress * Double(total)).rounded())
        let ringPitch = layout.ringPitch

        for (ordinal, dot) in layout.dots.enumerated() {
            let ringT = ringCount <= 1 ? 1.0 : Double(dot.ring) / Double(ringCount - 1)
            let sizeBoost = 1.0 + ringT * 0.10
            // Keep dots clearly smaller than pitch so rings and neighbors breathe.
            let baseInactive = ringPitch * 0.36 * sizeBoost
            let baseActive = ringPitch * 0.52 * sizeBoost
            let baseMarker = ringPitch * 0.64

            let isActive = ordinal < activeCount
            let showAsMarker = ordinal == activeCount && progress > 0 && progress < 1
            let point = CGPoint(x: origin.x + dot.point.x, y: origin.y + dot.point.y)

            if showAsMarker {
                let diameter = baseMarker
                let halo = baseMarker * 1.55
                let haloRect = CGRect(
                    x: point.x - halo * 0.5,
                    y: point.y - halo * 0.5,
                    width: halo,
                    height: halo
                )
                context.fill(Path(ellipseIn: haloRect), with: .color(SeraTheme.progressHalo))
                let rect = CGRect(
                    x: point.x - diameter * 0.5,
                    y: point.y - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(SeraTheme.progress))
            } else if isActive {
                let diameter = baseActive
                let rect = CGRect(
                    x: point.x - diameter * 0.5,
                    y: point.y - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(SeraTheme.progress))
            } else {
                let diameter = baseInactive
                let opacity = 0.20 + (1.0 - ringT) * 0.06
                let rect = CGRect(
                    x: point.x - diameter * 0.5,
                    y: point.y - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(opacity)))
            }
        }
    }
}

/// Concentric rings sized so the outer dots sit fully inside `edgeInset`.
private struct DotLayout {
    struct Dot {
        var ring: Int
        var index: Int
        var point: CGPoint
    }

    var dots: [Dot]
    var ringPitch: CGFloat

    init(size: CGSize, ringCount: Int, edgeInset: CGFloat, arcSpacingFactor: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let rings = CGFloat(max(ringCount, 1))
        // Reserve half an outer active dot past the outer ring center so edges don’t clip.
        let outerHalfDotFactor: CGFloat = 0.30
        let usable = min(size.width, size.height) * 0.5 - edgeInset
        let pitch = usable / (rings + outerHalfDotFactor)
        ringPitch = pitch
        let arcSpacing = pitch * arcSpacingFactor

        var built: [Dot] = []
        built.reserveCapacity(ringCount * 40)

        for ring in 0..<ringCount {
            let radius = pitch * CGFloat(ring + 1)
            let circumference = 2 * Double.pi * Double(radius)
            var count = max(8, Int((circumference / Double(arcSpacing)).rounded()))
            if count % 2 != 0 { count += 1 }

            for index in 0..<count {
                let angle = -Double.pi / 2 + (Double(index) / Double(count)) * 2 * Double.pi
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
                built.append(Dot(ring: ring, index: index, point: point))
            }
        }

        dots = built
    }
}
