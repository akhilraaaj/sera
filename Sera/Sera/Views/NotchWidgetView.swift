import SwiftUI

/// Dynamic Island–style shell that sits over the Mac notch.
/// The idle state exposes only progress in the menu-bar band. Hovering morphs
/// the shell into the wide, bottom-rounded dashboard.
struct NotchWidgetView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notchLayout: NotchLayout
    @State private var revealsExpandedContent = false

    private var expanded: Bool {
        appState.isNotchExpanded || appState.isPanelOpen
    }

    private var islandShape: NotchIslandShape {
        NotchIslandShape(
            expansion: expanded ? 1 : 0,
            idleSize: notchLayout.idleSize
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Match the hardware notch — always opaque black.
            Color.black

            if expanded {
                expandedContent
                    .opacity(revealsExpandedContent ? 1 : 0)
                    .offset(y: revealsExpandedContent ? 0 : -4)
            } else {
                collapsedContent
                    .frame(width: notchLayout.idleSize.width, height: notchLayout.idleSize.height)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(islandShape)
        .contentShape(islandShape)
        .animation(notchSpring, value: expanded)
        .animation(.easeOut(duration: 0.18), value: revealsExpandedContent)
        .onChange(of: expanded) { isExpanded in
            if isExpanded {
                revealsExpandedContent = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    guard expanded else { return }
                    revealsExpandedContent = true
                }
            } else {
                revealsExpandedContent = false
            }
        }
    }

    private var notchSpring: Animation {
        .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.55)
    }

    // MARK: - Collapsed

    /// Progress sits on the two visible shoulders beside the physical notch,
    /// inset enough to clear the concave ears and soft bottom corners.
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            CompactProgressBar(progress: appState.snapshot.progress)
                .frame(width: 44, height: 4)

            Spacer(minLength: 12)

            Text(appState.snapshot.percentWhole)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.78))
                .frame(width: 40, alignment: .trailing)
        }
        // Clears idle ear inset (~6) + a little breathing room inside the curve.
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appState.displayTitle) progress")
        .accessibilityValue(appState.snapshot.percentDisplay)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Keeps content below the camera/notch while the panel remains
            // physically attached to the top edge of the display.
            Color.clear
                .frame(height: 38)

            Group {
                if appState.isPanelOpen {
                    GoalSelectorPanel(compact: true)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 14)
                } else {
                    dashboard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 32) {
                progressSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                NotchVisualization(
                    progress: appState.snapshot.progress,
                    style: appState.visualizationStyle
                )
                .frame(width: 190, height: 112)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 36)
            .frame(maxHeight: .infinity, alignment: .center)

            bottomBar
                .padding(.horizontal, 36)
                .padding(.bottom, 14)
        }
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(appState.displayTitle.lowercased())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(appState.snapshot.percentWhole)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .tracking(-1.5)

            Text(progressCaption)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)

            if !appState.snapshot.insight.isEmpty {
                Text(appState.snapshot.insight)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            CompactProgressBar(progress: appState.snapshot.progress)
                .frame(width: 56, height: 5)

            Text(appState.snapshot.percentWhole)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                appState.openTimelines()
            } label: {
                Label("Timelines", systemImage: "scope")
            }

            Button {
                appState.cycleVisualizationStyle()
            } label: {
                Image(systemName: styleSymbol)
            }
            .help("Change visualization style")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Sera")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary.opacity(0.82))
        .buttonStyle(NotchToolbarButtonStyle())
    }

    private var progressCaption: String {
        appState.selection == .year
            ? "of the year completed"
            : "of this timeline completed"
    }

    private var styleSymbol: String {
        switch appState.visualizationStyle {
        case .ring: return "circle.circle"
        case .gauge: return "gauge.with.needle"
        case .linear: return "chart.bar.fill"
        case .grid: return "circle.grid.3x3.fill"
        }
    }
}

// MARK: - Shared components

private struct CompactProgressBar: View {
    var progress: Double

    private var clamped: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))

                Capsule()
                    .fill(SeraTheme.progress)
                    .frame(width: max(4, proxy.size.width * clamped))
            }
        }
    }
}

private struct NotchToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0))
            )
            .contentShape(Rectangle())
    }
}

/// Mac-notch silhouette morphing inside a fixed, top-pinned window.
///
/// `expansion == 0` draws the idle island (centered, menu-bar height).
/// `expansion == 1` fills the window with the hover dashboard silhouette.
/// Soft bottom corners and concave top ears stay for the whole morph.
private struct NotchIslandShape: Shape {
    var expansion: CGFloat
    var idleSize: CGSize

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let amount = min(1, max(0, expansion))
        let idleWidth = min(idleSize.width, rect.width)
        let idleHeight = min(idleSize.height, rect.height)
        let width = idleWidth + (rect.width - idleWidth) * amount
        let height = idleHeight + (rect.height - idleHeight) * amount
        let island = CGRect(
            x: rect.midX - width / 2,
            y: rect.minY,
            width: width,
            height: height
        )

        let idealTop = 6 + (10 - 6) * amount
        let idealBottom = 12 + (24 - 12) * amount
        let topCornerRadius = min(idealTop, max(0, island.height * 0.28))
        let bottomCornerRadius = min(
            max(idealBottom, min(12, island.height * 0.36)),
            max(0, island.height - topCornerRadius - 1)
        )

        var path = Path()

        path.move(to: CGPoint(x: island.minX, y: island.minY))
        path.addQuadCurve(
            to: CGPoint(x: island.minX + topCornerRadius, y: island.minY + topCornerRadius),
            control: CGPoint(x: island.minX + topCornerRadius, y: island.minY)
        )

        path.addLine(to: CGPoint(x: island.minX + topCornerRadius, y: island.maxY - bottomCornerRadius))

        path.addQuadCurve(
            to: CGPoint(
                x: island.minX + topCornerRadius + bottomCornerRadius,
                y: island.maxY
            ),
            control: CGPoint(x: island.minX + topCornerRadius, y: island.maxY)
        )

        path.addLine(
            to: CGPoint(
                x: island.maxX - topCornerRadius - bottomCornerRadius,
                y: island.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: island.maxX - topCornerRadius,
                y: island.maxY - bottomCornerRadius
            ),
            control: CGPoint(x: island.maxX - topCornerRadius, y: island.maxY)
        )

        path.addLine(to: CGPoint(x: island.maxX - topCornerRadius, y: island.minY + topCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: island.maxX, y: island.minY),
            control: CGPoint(x: island.maxX - topCornerRadius, y: island.minY)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Right-side visualization

private struct NotchVisualization: View {
    var progress: Double
    var style: VisualizationStyle

    private var clamped: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        Group {
            switch style {
            case .ring:
                ProgressRingView(
                    progress: clamped,
                    showsLabel: false,
                    compact: true
                )
                .frame(width: 124, height: 124)

            case .gauge:
                compactGauge
                    .frame(width: 196, height: 114)

            case .linear:
                compactLinear
                    .frame(width: 180, height: 48)

            case .grid:
                compactGrid
                    .frame(width: 168, height: 100)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35), value: clamped)
        .accessibilityLabel("Progress visualization")
        .accessibilityValue(Text(String(format: "%.1f percent", clamped * 100)))
    }

    private var compactGauge: some View {
        ZStack {
            SegmentedSemicircleGauge(
                progress: clamped,
                segmentCount: 13
            )
            .frame(width: 196, height: 114)

            Text(String(format: "%.0f%%", clamped * 100))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.9))
                .offset(y: 22)
        }
        .frame(width: 196, height: 114, alignment: .top)
    }

    private var compactLinear: some View {
        HStack(spacing: 6) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(
                        Double(index) < clamped * 9
                            ? SeraTheme.progress
                            : Color.primary.opacity(0.14)
                    )
            }
        }
    }

    private var compactGrid: some View {
        let columns = 9
        let rows = 5
        let filled = Int((clamped * Double(columns * rows)).rounded())

        return VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        Circle()
                            .fill(
                                index < filled
                                    ? SeraTheme.progress
                                    : Color.primary.opacity(0.14)
                            )
                    }
                }
            }
        }
    }
}
