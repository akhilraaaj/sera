import AppKit
import SwiftUI

/// Menu bar status label.
///
/// `MenuBarExtra` clips / ignores most custom SwiftUI views in the label.
/// A `Label` with an `NSImage` icon (fixed 18pt) + `Text` title is the
/// reliable pattern — no overlap, correct retina sizing.
struct MenuBarLabelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text(appState.snapshot.percentWhole)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        } icon: {
            if let glyph = makeGlyphImage() {
                Image(nsImage: glyph)
            } else {
                Image(systemName: fallbackSymbol)
            }
        }
        .labelStyle(.titleAndIcon)
        .help("\(appState.displayTitle) — \(appState.snapshot.percentDisplay)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appState.displayTitle)
        .accessibilityValue(appState.snapshot.percentDisplay)
    }

    private var fallbackSymbol: String {
        switch appState.visualizationStyle {
        case .ring: return "circle.circle"
        case .gauge: return "gauge.with.needle"
        case .linear: return "chart.bar.fill"
        case .grid: return "circle.grid.3x3.fill"
        }
    }

    @MainActor
    private func makeGlyphImage() -> NSImage? {
        MenuBarGlyphImage.make(
            progress: appState.snapshot.progress,
            style: appState.visualizationStyle,
            colorScheme: colorScheme
        )
    }
}

// MARK: - 18×18 glyph NSImage

enum MenuBarGlyphImage {
    /// Menu-bar icon slot size in points.
    static let side: CGFloat = 18

    @MainActor
    static func make(
        progress: Double,
        style: VisualizationStyle,
        colorScheme: ColorScheme
    ) -> NSImage? {
        let artwork = MenuBarGlyphArtwork(progress: progress, style: style)
            .frame(width: side, height: side)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: artwork)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: side, height: side)

        guard let image = renderer.nsImage else { return nil }

        // Critical for MenuBarExtra: point size must be the on-screen size.
        image.size = NSSize(width: side, height: side)
        image.isTemplate = false
        return image
    }
}

// MARK: - Glyph artwork

private struct MenuBarGlyphArtwork: View {
    var progress: Double
    var style: VisualizationStyle

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        ZStack {
            switch style {
            case .ring:
                ringGlyph
            case .gauge:
                // Less padding so the semicircle can match ring/grid weight.
                gaugeGlyph
                    .padding(-1)
            case .linear:
                linearGlyph
            case .grid:
                gridGlyph
            }
        }
        .padding(2)
    }

    private var ringGlyph: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                let t = Double(ring)
                let ringStart = t / 3
                let ringEnd = (t + 1) / 3
                let local = min(1, max(0, (clamped - ringStart) / (ringEnd - ringStart)))
                let inset = CGFloat(ring) * 2.4

                Circle()
                    .stroke(Color.primary.opacity(0.30), lineWidth: 1.5)
                    .padding(inset)

                Circle()
                    .trim(from: 0, to: local)
                    .stroke(
                        SeraTheme.progress,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
    }

    private var gaugeGlyph: some View {
        // Segmented semicircle sized to fill the 18pt slot like ring/grid,
        // with its visual center aligned to the adjacent percent text.
        Canvas { context, size in
            let count = 7
            let filled = Int((clamped * Double(count)).rounded())

            let side = min(size.width, size.height)
            let blockLength = side * 0.34
            let margin: CGFloat = 0.35

            // Use nearly the full icon width for diameter.
            let outerExtent = min(size.width * 0.5 - margin, size.height - margin)
            let radius = max(5, outerExtent - blockLength * 0.5)

            // Center the semicircle’s bounding box in the icon.
            let visualTop = -(radius + blockLength * 0.5)
            let visualBottom = blockLength * 0.35
            let visualMid = (visualTop + visualBottom) * 0.5
            let center = CGPoint(
                x: size.width * 0.5,
                y: size.height * 0.5 - visualMid
            )

            let startAngle = Double.pi
            let span = Double.pi
            let slotWidth = CGFloat(span / Double(count)) * radius
            let blockWidth = max(1.6, slotWidth * 0.82)
            let corner = blockWidth * 0.35

            for index in 0..<count {
                let t = (Double(index) + 0.5) / Double(count)
                let angle = startAngle - t * span
                let mid = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y - CGFloat(sin(angle)) * radius
                )
                let rotation = Double.pi / 2 - angle
                let active = index < filled
                let rect = CGRect(
                    x: -blockWidth * 0.5,
                    y: -blockLength * 0.5,
                    width: blockWidth,
                    height: blockLength
                )
                let path = Path(roundedRect: rect, cornerRadius: corner)

                context.drawLayer { layer in
                    layer.translateBy(x: mid.x, y: mid.y)
                    layer.rotate(by: .radians(rotation))
                    layer.fill(
                        path,
                        with: .color(active ? SeraTheme.progress : Color.primary.opacity(0.30))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var linearGlyph: some View {
        let count = 5
        let filled = Int((clamped * Double(count)).rounded())
        return HStack(spacing: 1.6) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(index < filled ? SeraTheme.progress : Color.primary.opacity(0.30))
            }
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var gridGlyph: some View {
        let cols = 3
        let filled = Int((clamped * 9).rounded())
        return VStack(spacing: 1.6) {
            ForEach(0..<cols, id: \.self) { row in
                HStack(spacing: 1.6) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        Circle()
                            .fill(index < filled ? SeraTheme.progress : Color.primary.opacity(0.30))
                    }
                }
            }
        }
    }
}
