import Foundation

struct ProgressSnapshot: Equatable, Sendable {
    var title: String
    var progress: Double
    var daysRemaining: Int
    var weeksRemaining: Int
    var monthsRemaining: Int
    var daysElapsed: Int
    var totalDays: Int
    var insight: String

    var percentDisplay: String {
        String(format: "%.1f%%", progress * 100)
    }

    var percentWhole: String {
        String(format: "%.0f%%", progress * 100)
    }

    static let empty = ProgressSnapshot(
        title: "Year",
        progress: 0,
        daysRemaining: 0,
        weeksRemaining: 0,
        monthsRemaining: 0,
        daysElapsed: 0,
        totalDays: 365,
        insight: ""
    )
}
