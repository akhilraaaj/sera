import SwiftUI

/// Dynamic Island–style shell that sits over the Mac notch.
/// The idle state exposes only progress in the menu-bar band. Hovering morphs
/// the shell into the wide, bottom-rounded dashboard.
struct NotchWidgetView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var menuBarAppearance: MenuBarAppearance
    @State private var revealsExpandedContent = false

    private var expanded: Bool {
        appState.isNotchExpanded || appState.isPanelOpen
    }

    var body: some View {
        ZStack(alignment: .top) {
            menuBarAppearance.background

            if expanded {
                expandedContent
                    .opacity(revealsExpandedContent ? 1 : 0)
                    .offset(y: revealsExpandedContent ? 0 : -4)
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, menuBarAppearance.colorScheme)
        .clipShape(NotchIslandShape(expansion: expanded ? 1 : 0))
        .contentShape(NotchIslandShape(expansion: expanded ? 1 : 0))
        .animation(notchSpring, value: expanded)
        .animation(.easeInOut(duration: 0.25), value: menuBarAppearance.colorScheme)
        .animation(.easeOut(duration: 0.18), value: revealsExpandedContent)
        .onChange(of: expanded) { isExpanded in
            if isExpanded {
                revealsExpandedContent = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard expanded else { return }
                    revealsExpandedContent = true
                }
            } else {
                revealsExpandedContent = false
            }
        }
    }

    private var notchSpring: Animation {
        .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.42)
    }

    // MARK: - Collapsed

    /// Progress sits on the two visible shoulders beside the physical notch.
    private var collapsedContent: some View {
        HStack(spacing: 12) {
            CompactProgressBar(progress: appState.snapshot.progress)
                .frame(width: 42, height: 4)

            Spacer(minLength: 0)

            Text(appState.snapshot.percentWhole)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.78))
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 10)
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
                .frame(height: 43)

            if appState.isPanelOpen {
                GoalSelectorPanel()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                dashboard
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 26) {
                progressSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                NotchVisualization(
                    progress: appState.snapshot.progress,
                    style: appState.visualizationStyle
                )
                .frame(width: 150, height: 108)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity, alignment: .top)

            bottomBar
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
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

/// Collapsed: capsule over the notch.
/// Expanded: flat top flush with the menu bar (no top radius — avoids covering
/// neighboring menu-bar items) and soft rounded bottom corners.
private struct NotchIslandShape: Shape {
    var expansion: CGFloat

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let amount = min(1, max(0, expansion))
        let collapsedRadius = min(rect.height, rect.width) / 2
        // Drop top radius quickly so the open island never scoops into menu items.
        let topRadius = collapsedRadius * (1 - amount) * (1 - amount)
        let bottomRadius = collapsedRadius + (24 - collapsedRadius) * amount

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))

        if topRadius > 0.5 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius),
                radius: topRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        if topRadius > 0.5 {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
            path.addArc(
                center: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
                radius: topRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

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
                .frame(width: 96, height: 96)

            case .gauge:
                compactGauge
                    .frame(width: 148, height: 88)

            case .linear:
                compactLinear
                    .frame(width: 136, height: 38)

            case .grid:
                compactGrid
                    .frame(width: 126, height: 76)
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
                segmentCount: 11
            )
            .frame(width: 148, height: 88)

            Text(String(format: "%.0f%%", clamped * 100))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.9))
                .offset(y: 18)
        }
        .frame(width: 148, height: 88, alignment: .top)
    }

    private var compactLinear: some View {
        HStack(spacing: 5) {
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        Double(index) < clamped * 8
                            ? SeraTheme.progress
                            : Color.primary.opacity(0.14)
                    )
            }
        }
    }

    private var compactGrid: some View {
        let columns = 8
        let rows = 4
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
