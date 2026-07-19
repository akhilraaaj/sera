import Combine
import Foundation

/// Persists goals locally and computes progress via `TimeEngine`.
/// Phase 1: store + API ready; UI create/edit lands in Phase 3.
@MainActor
final class GoalEngine: ObservableObject {
    @Published private(set) var goals: [Goal] = []

    private let defaults: UserDefaults
    private let storageKey = "sera.goals"
    private let timeEngine: TimeEngine
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard, timeEngine: TimeEngine = TimeEngine()) {
        self.defaults = defaults
        self.timeEngine = timeEngine
        load()

        $goals
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] goals in
                self?.save(goals)
            }
            .store(in: &cancellables)
    }

    func add(_ goal: Goal) {
        goals.append(goal)
    }

    func update(_ goal: Goal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index] = goal
    }

    func delete(id: UUID) {
        goals.removeAll { $0.id == id }
    }

    func goal(id: UUID) -> Goal? {
        goals.first { $0.id == id }
    }

    func snapshot(for goal: Goal, at date: Date = Date()) -> ProgressSnapshot {
        timeEngine.goalSnapshot(for: goal, at: date)
    }

    func updateManualProgress(id: UUID, currentValue: Double) {
        guard var goal = goal(id: id), goal.progressKind == .manual else { return }
        goal.currentValue = currentValue
        update(goal)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            goals = try JSONDecoder().decode([Goal].self, from: data)
        } catch {
            goals = []
        }
    }

    private func save(_ goals: [Goal]) {
        do {
            let data = try JSONEncoder().encode(goals)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Ignore persistence failures in MVP; in-memory state remains usable.
        }
    }
}
