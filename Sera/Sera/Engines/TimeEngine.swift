import Foundation

struct TimeEngine: Sendable {
    var calendar: Calendar = .current

    func yearSnapshot(at date: Date = Date()) -> ProgressSnapshot {
        let (start, end) = DateMath.yearBounds(for: date, calendar: calendar)
        let total = end.timeIntervalSince(start)
        let elapsed = date.timeIntervalSince(start)
        let progress = DateMath.clampedProgress(elapsed: elapsed, total: total)

        let daysRemaining = DateMath.wholeDays(from: date, to: end, calendar: calendar)
        let daysElapsed = DateMath.wholeDays(from: start, to: date, calendar: calendar)
        let totalDays = max(1, DateMath.wholeDays(from: start, to: end, calendar: calendar))
        let weeksRemaining = Int(ceil(Double(daysRemaining) / 7.0))
        let monthsRemaining = max(0, calendar.dateComponents([.month], from: date, to: end).month ?? 0)
        let weekends = DateMath.weekendsRemaining(from: date, calendar: calendar)

        var snapshot = ProgressSnapshot(
            title: "\(calendar.component(.year, from: date))",
            progress: progress,
            daysRemaining: daysRemaining,
            weeksRemaining: weeksRemaining,
            monthsRemaining: monthsRemaining,
            daysElapsed: daysElapsed,
            totalDays: totalDays,
            insight: ""
        )
        snapshot.insight = InsightEngine.yearInsight(snapshot: snapshot, weekendsRemaining: weekends)
        return snapshot
    }

    func goalSnapshot(for goal: Goal, at date: Date = Date()) -> ProgressSnapshot {
        let progress: Double
        let daysRemaining: Int
        let daysElapsed: Int
        let totalDays: Int

        switch goal.progressKind {
        case .timeBased:
            let total = goal.endDate.timeIntervalSince(goal.startDate)
            let elapsed = date.timeIntervalSince(goal.startDate)
            progress = DateMath.clampedProgress(elapsed: elapsed, total: total)
            daysRemaining = DateMath.wholeDays(from: date, to: goal.endDate, calendar: calendar)
            daysElapsed = DateMath.wholeDays(from: goal.startDate, to: date, calendar: calendar)
            totalDays = max(1, DateMath.wholeDays(from: goal.startDate, to: goal.endDate, calendar: calendar))
        case .manual:
            let target = max(goal.targetValue ?? 1, 0.0001)
            let current = min(max(goal.currentValue ?? 0, 0), target)
            progress = current / target
            daysRemaining = DateMath.wholeDays(from: date, to: goal.endDate, calendar: calendar)
            daysElapsed = Int(current.rounded())
            totalDays = Int(target.rounded())
        }

        let weeksRemaining = Int(ceil(Double(max(0, daysRemaining)) / 7.0))
        let monthsRemaining = max(0, calendar.dateComponents([.month], from: date, to: goal.endDate).month ?? 0)

        return ProgressSnapshot(
            title: goal.title,
            progress: progress,
            daysRemaining: max(0, daysRemaining),
            weeksRemaining: weeksRemaining,
            monthsRemaining: monthsRemaining,
            daysElapsed: max(0, daysElapsed),
            totalDays: totalDays,
            insight: InsightEngine.goalInsight(title: goal.title, progress: progress, daysRemaining: max(0, daysRemaining))
        )
    }
}
