import Foundation

func usageModelTests() -> [TestCase] {
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    func snapshot(
        usedPercent: Double,
        resetOffset: TimeInterval = 3_600,
        windowMinutes: Int = 60
    ) -> UsageSnapshot {
        guard
            let snapshot = UsageSnapshot(
                usedPercent: usedPercent,
                windowDurationMinutes: windowMinutes,
                resetsAt: referenceDate.addingTimeInterval(resetOffset)
            )
        else {
            preconditionFailure("Invalid UsageSnapshot test fixture")
        }
        return snapshot
    }

    return [
        TestCase(name: "usage remaining is calculated at percentage boundaries") {
            try expectEqual(snapshot(usedPercent: 0).usageRemainingPercent, 100)
            try expectEqual(snapshot(usedPercent: 35).usageRemainingPercent, 65)
            try expectEqual(snapshot(usedPercent: 100).usageRemainingPercent, 0)
        },
        TestCase(name: "fractional usage rounds for display") {
            try expectEqual(snapshot(usedPercent: 33.5).usageRemainingPercent, 66)
            try expectEqual(snapshot(usedPercent: 33.4).usageRemainingPercent, 67)
            try expectEqual(snapshot(usedPercent: 0.4).usageRemainingPercent, 100)
            try expectEqual(snapshot(usedPercent: 99.6).usageRemainingPercent, 0)
        },
        TestCase(name: "snapshot rejects malformed provider values") {
            let resetDate = Date(timeIntervalSince1970: 1_700_000_000)
            try expectEqual(
                UsageSnapshot(usedPercent: -1, windowDurationMinutes: 60, resetsAt: resetDate),
                nil
            )
            try expectEqual(
                UsageSnapshot(usedPercent: 101, windowDurationMinutes: 60, resetsAt: resetDate),
                nil
            )
            try expectEqual(
                UsageSnapshot(usedPercent: 50, windowDurationMinutes: 0, resetsAt: resetDate),
                nil
            )
        },
        TestCase(name: "usage report requires at least one available window") {
            try expectEqual(UsageReport(weekly: nil, fiveHour: nil), nil)
            try expect(
                UsageReport(weekly: snapshot(usedPercent: 25), fiveHour: nil) != nil,
                "expected a weekly-only report to be valid"
            )
            try expect(
                UsageReport(weekly: nil, fiveHour: snapshot(usedPercent: 25)) != nil,
                "expected a five-hour-only report to be valid"
            )
        },
        TestCase(name: "time remaining uses the configured window") {
            let value = snapshot(
                usedPercent: 25,
                resetOffset: 3_600,
                windowMinutes: 120
            ).timeRemainingFraction(at: referenceDate)
            try expect(abs(value - 0.5) < 0.000_001, "expected 0.5, got \(value)")
        },
        TestCase(name: "time remaining is clamped at window boundaries") {
            let expired = snapshot(usedPercent: 25, resetOffset: -60)
            let beyondWindow = snapshot(usedPercent: 25, resetOffset: 20_000, windowMinutes: 60)
            try expectEqual(expired.timeRemainingFraction(at: referenceDate), 0)
            try expectEqual(beyondWindow.timeRemainingFraction(at: referenceDate), 1)
        },
        TestCase(name: "matching usage and time is on pace") {
            let value = snapshot(
                usedPercent: 50,
                resetOffset: 3_600,
                windowMinutes: 120
            ).reading(at: referenceDate)
            try expectEqual(value.pace, .onPace)
        },
        TestCase(name: "usage trailing time is behind") {
            let value = snapshot(
                usedPercent: 60,
                resetOffset: 3_600,
                windowMinutes: 120
            ).reading(at: referenceDate)
            try expectEqual(value.pace, .behind)
        },
        TestCase(name: "pacing uses exact time before rounding for display") {
            let value = snapshot(
                usedPercent: 50,
                resetOffset: 3_628.8,
                windowMinutes: 120
            ).reading(at: referenceDate)
            try expectEqual(value.timeRemainingPercent, 50)
            try expectEqual(value.pace, .behind)
        },
        TestCase(name: "critical threshold takes priority over pacing") {
            let critical = snapshot(usedPercent: 86, resetOffset: 60, windowMinutes: 120)
            let boundary = snapshot(usedPercent: 85, resetOffset: 60, windowMinutes: 120)
            try expectEqual(critical.reading(at: referenceDate).pace, .critical)
            try expectEqual(boundary.reading(at: referenceDate).pace, .onPace)
        },
    ]
}
