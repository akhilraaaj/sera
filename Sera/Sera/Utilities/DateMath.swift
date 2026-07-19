import Foundation

enum DateMath {
    static func yearBounds(for date: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let year = calendar.component(.year, from: date)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        return (start, end)
    }

    static func clampedProgress(elapsed: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, elapsed / total))
    }

    static func wholeDays(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)
    }

    static func weekendsRemaining(from date: Date = Date(), calendar: Calendar = .current) -> Int {
        let (_, yearEnd) = yearBounds(for: date, calendar: calendar)
        var cursor = calendar.startOfDay(for: date)
        var count = 0

        while cursor < yearEnd {
            let weekday = calendar.component(.weekday, from: cursor)
            // 1 = Sunday, 7 = Saturday in Gregorian
            if weekday == 1 || weekday == 7 {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return count
    }
}
