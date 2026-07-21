import Foundation

struct UsageReport: Equatable, Sendable {
    let snapshot: UsageSnapshot
}

struct UsageSnapshot: Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMinutes: Int
    let resetsAt: Date

    init?(usedPercent: Int, windowDurationMinutes: Int, resetsAt: Date) {
        guard
            (0...100).contains(usedPercent),
            windowDurationMinutes > 0,
            resetsAt.timeIntervalSinceReferenceDate.isFinite
        else {
            return nil
        }

        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    var usageRemainingPercent: Int {
        100 - usedPercent
    }

    func weekRemainingFraction(at date: Date = Date()) -> Double {
        let windowDuration = TimeInterval(windowDurationMinutes) * 60
        guard windowDuration > 0 else { return 0 }

        return (resetsAt.timeIntervalSince(date) / windowDuration)
            .clamped(to: 0...1)
    }

    func reading(at date: Date = Date()) -> UsageReading {
        let weekFraction = weekRemainingFraction(at: date)
        let weekPercent = Int((weekFraction * 100).rounded())
        let usagePercent = usageRemainingPercent

        let pace: UsagePace
        if usagePercent < 15 {
            pace = .critical
        } else if usagePercent >= weekPercent {
            pace = .onPace
        } else {
            pace = .behind
        }

        return UsageReading(
            weekRemainingFraction: weekFraction,
            weekRemainingPercent: weekPercent,
            usageRemainingPercent: usagePercent,
            pace: pace
        )
    }
}

struct UsageReading: Equatable, Sendable {
    let weekRemainingFraction: Double
    let weekRemainingPercent: Int
    let usageRemainingPercent: Int
    let pace: UsagePace

    var usageRemainingFraction: Double {
        Double(usageRemainingPercent) / 100
    }
}

enum UsagePace: Equatable, Sendable {
    case critical
    case onPace
    case behind
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
