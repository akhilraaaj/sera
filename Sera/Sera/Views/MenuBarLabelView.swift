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
                gaugeGlyph
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
        ZStack {
            GaugeArcShape()
                .stroke(Color.primary.opacity(0.30), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            GaugeArcShape(progress: clamped)
                .stroke(SeraTheme.progress, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
        .padding(.top, 2)
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

private struct GaugeArcShape: Shape {
    var progress: Double = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY - 0.5)
        let radius = min(rect.width, rect.height) * 0.52
        let start = Angle.degrees(180)
        let end = Angle.degrees(180 - 180 * min(1, max(0, progress)))
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        return path
    }
}
