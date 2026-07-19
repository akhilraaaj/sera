import SwiftUI

/// Square dot matrix with the same chrome as the ring: viz → percent → caption.
struct GridProgressView: View {
    var progress: Double
    var caption: String? = nil
    var showsLabel: Bool = true
    /// Side length of the square grid.
    var columns: Int = 16
    var daysElapsed: Int? = nil
    var daysRemaining: Int? = nil

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    private var cellCount: Int { columns * columns }

    private var filledCount: Int {
        Int((clampedProgress * Double(cellCount)).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DotGridCanvas(
                progress: clampedProgress,
                columns: columns
            )
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
        .accessibilityLabel("Progress grid")
        .accessibilityValue(Text("\(filledCount) of \(cellCount) cells, \(String(format: "%.0f percent", clampedProgress * 100))"))
        .animation(.easeInOut(duration: 0.45), value: clampedProgress)
    }
}

// MARK: - Canvas

private struct DotGridCanvas: View, Animatable {
    var progress: Double
    var columns: Int

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
        let cols = max(columns, 1)
        let rows = cols
        let total = cols * rows
        let filled = Int((progress * Double(total)).rounded())

        // Leave clear gaps between cells so the filled field doesn’t look congested.
        let inset = min(size.width, size.height) * 0.015
        let field = min(size.width, size.height) - inset * 2
        let pitch = field / CGFloat(cols)
        let inactiveDiameter = pitch * 0.52
        let activeDiameter = pitch * 0.64
        let markerDiameter = pitch * 0.76

        let originX = (size.width - field) * 0.5
        let originY = (size.height - field) * 0.5

        for index in 0..<total {
            let row = index / cols
            let col = index % cols
            let center = CGPoint(
                x: originX + (CGFloat(col) + 0.5) * pitch,
                y: originY + (CGFloat(row) + 0.5) * pitch
            )

            let isActive = index < filled
            let showAsMarker = index == filled && progress > 0 && progress < 1

            let rowT = rows <= 1 ? 0.0 : Double(row) / Double(rows - 1)

            if showAsMarker {
                let diameter = markerDiameter
                let halo = markerDiameter * 1.65
                let haloRect = CGRect(
                    x: center.x - halo * 0.5,
                    y: center.y - halo * 0.5,
                    width: halo,
                    height: halo
                )
                context.fill(Path(ellipseIn: haloRect), with: .color(SeraTheme.progressHalo))
                let rect = CGRect(
                    x: center.x - diameter * 0.5,
                    y: center.y - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(SeraTheme.progress))
            } else if isActive {
                let diameter = activeDiameter
                let rect = CGRect(
                    x: center.x - diameter * 0.5,
                    y: center.y - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(SeraTheme.progress))
            } else {
                let diameter = inactiveDiameter
                let opacity = 0.22 + (1.0 - rowT) * 0.05
                let rect = CGRect(
                    x: center.x - diameter * 0.5,
                    y: center.y - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(opacity)))
            }
        }
    }
}
