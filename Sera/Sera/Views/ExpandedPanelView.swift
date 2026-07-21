import SwiftUI

struct ExpandedPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            switch appState.visualizationStyle {
            case .ring:
                ringHero
            case .grid:
                gridHero
            case .linear:
                linearHero
            case .gauge:
                gaugeHero
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Dot ring (minimal)

    private var ringHero: some View {
        ProgressRingView(
            progress: appState.snapshot.progress,
            showsLabel: true,
            compact: false,
            caption: ringCaption,
            daysElapsed: appState.snapshot.daysElapsed,
            daysRemaining: appState.snapshot.daysRemaining
        )
        .frame(maxWidth: .infinity)
    }

    private var ringCaption: String {
        if appState.selection == .year {
            return "of year completed"
        }
        return "of \(appState.displayTitle) completed"
    }

    // MARK: - Dot grid (same chrome as ring, square layout)

    private var gridHero: some View {
        GridProgressView(
            progress: appState.snapshot.progress,
            caption: ringCaption,
            showsLabel: true,
            columns: 12,
            daysElapsed: appState.snapshot.daysElapsed,
            daysRemaining: appState.snapshot.daysRemaining
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Linear (same chrome as ring / grid)

    private var linearHero: some View {
        LinearProgressBarView(
            progress: appState.snapshot.progress,
            caption: ringCaption,
            daysElapsed: appState.snapshot.daysElapsed,
            daysRemaining: appState.snapshot.daysRemaining
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Gauge (segmented semicircle)

    private var gaugeHero: some View {
        GaugeProgressView(
            progress: appState.snapshot.progress,
            caption: ringCaption,
            daysElapsed: appState.snapshot.daysElapsed,
            daysRemaining: appState.snapshot.daysRemaining,
            weeksRemaining: appState.snapshot.weeksRemaining
        )
        .frame(maxWidth: .infinity)
    }
}

struct GoalSelectorPanel: View {
    @EnvironmentObject private var appState: AppState
    /// Tighter chrome for the fixed-height notch shell.
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                standardBody
            }
        }
    }

    /// Notch: This Year / goals on the left, Style / Placement / Done on the right.
    private var compactBody: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Timelines")
                    .font(.system(size: 12, weight: .semibold))

                timelineList
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            settingsColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Timelines")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            timelineList
                .frame(maxHeight: .infinity, alignment: .top)

            Divider().opacity(0.3)

            settingsColumn
                .padding(14)
        }
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text("Style")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Picker(
                "Style",
                selection: Binding(
                    get: { appState.visualizationStyle },
                    set: { appState.setVisualizationStyle($0) }
                )
            ) {
                ForEach(VisualizationStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Placement")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, compact ? 2 : 4)

            Picker(
                "Placement",
                selection: Binding(
                    get: { appState.displayMode },
                    set: { appState.setDisplayMode($0) }
                )
            ) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !compact {
                Text(placementHint)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button("Done") {
                    appState.closeTimelines()
                }
                .buttonStyle(.borderedProminent)
                .tint(SeraTheme.progress)
                .controlSize(.small)
            }
        }
    }

    private var timelineList: some View {
        ScrollView {
            VStack(spacing: 4) {
                selectorRow(
                    title: YearTimeline.shared.title,
                    subtitle: appState.selection == .year ? appState.snapshot.percentDisplay : "Year countdown",
                    selected: appState.selection == .year
                ) {
                    appState.selectYear()
                }

                if appState.goalEngine.goals.isEmpty {
                    Text("No goals yet. Coming in future updates.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, compact ? 2 : 14)
                        .padding(.vertical, compact ? 6 : 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.goalEngine.goals) { goal in
                        let snap = appState.goalEngine.snapshot(for: goal)
                        selectorRow(
                            title: goal.title,
                            subtitle: snap.percentDisplay,
                            selected: appState.selection == .goal(goal.id)
                        ) {
                            appState.selectGoal(id: goal.id)
                        }
                    }
                }
            }
            .padding(.horizontal, compact ? 0 : 8)
        }
    }

    private var placementHint: String {
        switch appState.displayMode {
        case .menuBar:
            return "Click the menu bar item for the glass panel."
        case .notch:
            return "Hover the notch island to expand. Works best on notched MacBooks."
        }
    }

    private func selectorRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SeraTheme.progress)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? SeraTheme.progress.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
