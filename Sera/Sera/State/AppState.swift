import Combine
import Foundation

enum TimelineSelection: Equatable, Hashable {
    case year
    case goal(UUID)
}

@MainActor
final class AppState: ObservableObject {
    @Published var selection: TimelineSelection = .year
    @Published var visualizationStyle: VisualizationStyle = .ring
    @Published var displayMode: DisplayMode = .menuBar
    @Published var isExpanded: Bool = false
    @Published var isNotchExpanded: Bool = false
    @Published var isPanelOpen: Bool = false
    /// Composer drawn inside the notch island. The island becomes key while this is true.
    @Published private(set) var isAddGoalPresented: Bool = false
    /// Hover-leave and focus-loss collapse are ignored until this instant after an action.
    private(set) var suppressNotchCollapseUntil: Date = .distantPast
    @Published private(set) var snapshot: ProgressSnapshot = .empty
    @Published private(set) var now: Date = Date()

    let goalEngine: GoalEngine
    private let timeEngine: TimeEngine
    private var cancellables = Set<AnyCancellable>()

    private let styleKey = "sera.visualizationStyle"
    private let selectionKey = "sera.selection"
    private let displayModeKey = "sera.displayMode"

    init(goalEngine: GoalEngine? = nil, timeEngine: TimeEngine = TimeEngine()) {
        self.goalEngine = goalEngine ?? GoalEngine()
        self.timeEngine = timeEngine
        restorePreferences()
        refresh()
        startTicker()

        self.goalEngine.$goals
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)
    }

    var selectedGoal: Goal? {
        guard case .goal(let id) = selection else { return nil }
        return goalEngine.goal(id: id)
    }

    var displayTitle: String {
        switch selection {
        case .year:
            return snapshot.title
        case .goal:
            return selectedGoal?.title ?? snapshot.title
        }
    }

    func setVisualizationStyle(_ style: VisualizationStyle) {
        guard style != visualizationStyle else { return }
        Task { @MainActor in
            visualizationStyle = style
            UserDefaults.standard.set(style.rawValue, forKey: styleKey)
        }
    }

    func cycleVisualizationStyle() {
        let styles = VisualizationStyle.allCases
        guard let index = styles.firstIndex(of: visualizationStyle) else {
            setVisualizationStyle(.ring)
            return
        }
        setVisualizationStyle(styles[(index + 1) % styles.count])
    }

    func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else { return }
        Task { @MainActor in
            // Close Timelines before swapping shells so the notch does not
            // spawn mid-panel and animate expand on first frame (glitchy).
            isPanelOpen = false
            if mode.showsNotch {
                isNotchExpanded = false
            }

            displayMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: displayModeKey)

            // Match prior notch → menu bar handoff: tear down first, then clear.
            if !mode.showsNotch {
                isNotchExpanded = false
            }
        }
    }

    func setNotchExpanded(_ expanded: Bool) {
        Task { @MainActor in
            guard isNotchExpanded != expanded else { return }
            isNotchExpanded = expanded
            if !expanded {
                isPanelOpen = false
                isAddGoalPresented = false
            }
        }
    }

    /// Idle island. Clears Timelines and the calendar as well as the hover shell.
    func collapseNotch() {
        Task { @MainActor in
            guard Date() >= suppressNotchCollapseUntil else { return }
            isNotchExpanded = false
            isPanelOpen = false
            isAddGoalPresented = false
        }
    }

    /// Keeps the island expanded across the focus change that follows an action.
    func noteNotchAction() {
        isNotchExpanded = true
        suppressNotchCollapseUntil = Date().addingTimeInterval(0.85)
    }

    func refresh(at date: Date = Date()) {
        now = date
        switch selection {
        case .year:
            snapshot = timeEngine.yearSnapshot(at: date)
        case .goal(let id):
            if let goal = goalEngine.goal(id: id) {
                snapshot = timeEngine.goalSnapshot(for: goal, at: date)
            } else {
                // Defer nested publish so we don't mutate selection mid-refresh.
                snapshot = timeEngine.yearSnapshot(at: date)
                Task { @MainActor in
                    self.selection = .year
                    self.persistSelection(.year)
                }
            }
        }
    }

    func scheduleRefresh(at date: Date = Date()) {
        Task { @MainActor in
            refresh(at: date)
        }
    }

    func cycleSelection(forward: Bool = true) {
        var items: [TimelineSelection] = [.year]
        items.append(contentsOf: goalEngine.goals.map { .goal($0.id) })
        guard let currentIndex = items.firstIndex(of: selection) else {
            applySelection(.year)
            return
        }
        let delta = forward ? 1 : -1
        let next = (currentIndex + delta + items.count) % items.count
        applySelection(items[next])
    }

    func selectYear() {
        Task { @MainActor in
            applySelection(.year)
            isPanelOpen = false
            noteNotchAction()
        }
    }

    func selectGoal(id: UUID) {
        Task { @MainActor in
            applySelection(.goal(id))
            isPanelOpen = false
            noteNotchAction()
        }
    }

    func deleteGoal(id: UUID) {
        Task { @MainActor in
            if case .goal(let selected) = selection, selected == id {
                applySelection(.year)
            }
            goalEngine.delete(id: id)
            noteNotchAction()
        }
    }

    func openTimelines() {
        Task { @MainActor in
            isPanelOpen = true
        }
    }

    func presentAddGoal() {
        Task { @MainActor in
            isNotchExpanded = true
            // Keep Timelines underneath. Closing it here flashes the home
            // dashboard for the first frames of the calendar open.
            isAddGoalPresented = true
        }
    }

    func cancelAddGoal() {
        Task { @MainActor in
            isAddGoalPresented = false
            isNotchExpanded = true
            isPanelOpen = true
            noteNotchAction()
        }
    }

    func dismissAddGoal() {
        Task { @MainActor in
            isAddGoalPresented = false
            noteNotchAction()
        }
    }

    func closeTimelines() {
        Task { @MainActor in
            isPanelOpen = false
            noteNotchAction()
        }
    }

    func setExpanded(_ expanded: Bool) {
        Task { @MainActor in
            isExpanded = expanded
            if !expanded {
                isPanelOpen = false
            }
        }
    }

    private func applySelection(_ newSelection: TimelineSelection) {
        selection = newSelection
        persistSelection(newSelection)
        refresh()
    }

    private func startTicker() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.scheduleRefresh(at: date)
            }
            .store(in: &cancellables)

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .prefix(2)
            .sink { [weak self] date in
                self?.scheduleRefresh(at: date)
            }
            .store(in: &cancellables)
    }

    private func restorePreferences() {
        if let raw = UserDefaults.standard.string(forKey: styleKey),
           let style = VisualizationStyle(rawValue: raw) {
            visualizationStyle = style
        }

        if let raw = UserDefaults.standard.string(forKey: displayModeKey) {
            if raw == "both" {
                // Former combined mode — prefer notch.
                displayMode = .notch
                UserDefaults.standard.set(DisplayMode.notch.rawValue, forKey: displayModeKey)
            } else if let mode = DisplayMode(rawValue: raw) {
                displayMode = mode
            }
        }

        if let raw = UserDefaults.standard.string(forKey: selectionKey) {
            if raw == "year" {
                selection = .year
            } else if let id = UUID(uuidString: raw) {
                selection = .goal(id)
            }
        }
    }

    private func persistSelection(_ selection: TimelineSelection) {
        switch selection {
        case .year:
            UserDefaults.standard.set("year", forKey: selectionKey)
        case .goal(let id):
            UserDefaults.standard.set(id.uuidString, forKey: selectionKey)
        }
    }
}
