import Foundation

struct UsageReport: Equatable, Sendable {
    let weekly: UsageSnapshot?
    let fiveHour: UsageSnapshot?
    let models: [ModelUsage]

    init?(weekly: UsageSnapshot?, fiveHour: UsageSnapshot?, models: [ModelUsage] = []) {
        guard weekly != nil || fiveHour != nil else { return nil }
        self.weekly = weekly
        self.fiveHour = fiveHour
        self.models = models
    }

    func hasUnexpiredUsage(at date: Date = Date()) -> Bool {
        ([weekly, fiveHour].compactMap { $0 } + models.map(\.snapshot))
            .contains { $0.resetsAt > date }
    }
}

struct ModelUsage: Equatable, Sendable {
    let limitId: String
    let displayName: String
    let snapshot: UsageSnapshot
}

struct UsageSnapshot: Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date

    init?(usedPercent: Double, windowDurationMinutes: Int, resetsAt: Date) {
        guard
            usedPercent.isFinite,
            (0...100).contains(usedPercent),
            windowDurationMinutes > 0,
            // A year of headroom over any real limit window; also keeps resetsAt,
            // which is validated against this duration, far from Int overflow.
            windowDurationMinutes <= 366 * 24 * 60,
            resetsAt.timeIntervalSinceReferenceDate.isFinite
        else {
            return nil
        }

        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    var usageRemainingFraction: Double {
        (1 - usedPercent / 100).clamped(to: 0...1)
    }

    var usageRemainingPercent: Int {
        100 - Int(usedPercent.rounded())
    }

    var spansWeek: Bool {
        windowDurationMinutes == 7 * 24 * 60
    }

    func timeRemainingFraction(at date: Date = Date()) -> Double {
        let windowDuration = TimeInterval(windowDurationMinutes) * 60
        guard windowDuration > 0 else { return 0 }

        return (resetsAt.timeIntervalSince(date) / windowDuration)
            .clamped(to: 0...1)
    }

    func reading(at date: Date = Date()) -> UsageReading {
        let timeFraction = timeRemainingFraction(at: date)
        let usageFraction = usageRemainingFraction

        let pace: UsagePace
        if usageFraction < 0.15 {
            pace = .critical
        } else if usageFraction >= timeFraction {
            pace = .onPace
        } else {
            pace = .behind
        }

        return UsageReading(
            timeRemainingFraction: timeFraction,
            timeRemainingPercent: Int((timeFraction * 100).rounded()),
            usageRemainingFraction: usageFraction,
            usageRemainingPercent: usageRemainingPercent,
            pace: pace
        )
    }
}

struct UsageReading: Equatable, Sendable {
    let timeRemainingFraction: Double
    let timeRemainingPercent: Int
    let usageRemainingFraction: Double
    let usageRemainingPercent: Int
    let pace: UsagePace
}

enum UsagePace: Equatable, Sendable {
    case critical
    case onPace
    case behind
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
