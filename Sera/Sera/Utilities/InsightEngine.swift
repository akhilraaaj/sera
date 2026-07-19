import Foundation

enum InsightEngine {
    static func yearInsight(snapshot: ProgressSnapshot, weekendsRemaining: Int) -> String {
        if snapshot.daysRemaining <= 0 {
            return "A new year begins."
        }
        if snapshot.progress >= 0.9 {
            return "Only \(snapshot.daysRemaining) days left in the year"
        }
        if snapshot.progress >= 0.7 {
            return "\(snapshot.percentWhole) of the year is gone"
        }
        if weekendsRemaining > 0 && weekendsRemaining <= 20 {
            return "Only \(weekendsRemaining) weekends remaining this year"
        }
        if snapshot.weeksRemaining > 0 {
            return "You have \(snapshot.weeksRemaining) weeks left"
        }
        return "You have \(snapshot.daysRemaining) days left"
    }

    static func goalInsight(title: String, progress: Double, daysRemaining: Int) -> String {
        if daysRemaining <= 0 {
            return "“\(title)” timeline has ended"
        }
        if progress >= 0.7 {
            return "\(Int(progress * 100))% of your goal time is gone"
        }
        return "You have \(daysRemaining) days left on “\(title)”"
    }
}
