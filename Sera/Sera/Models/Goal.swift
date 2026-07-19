import Foundation

enum GoalProgressKind: String, Codable, Sendable {
    case timeBased
    case manual
}

struct Goal: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var progressKind: GoalProgressKind
    /// Used when `progressKind == .manual`. Target units (e.g. days, currency units).
    var targetValue: Double?
    /// Used when `progressKind == .manual`. Current completion toward `targetValue`.
    var currentValue: Double?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        progressKind: GoalProgressKind = .timeBased,
        targetValue: Double? = nil,
        currentValue: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.progressKind = progressKind
        self.targetValue = targetValue
        self.currentValue = currentValue
    }
}

/// Year countdown presented as a selectable timeline alongside goals.
struct YearTimeline: Identifiable, Equatable, Sendable {
    static let shared = YearTimeline()
    let id = "year-timeline"
    let title = "This Year"
}
