import Foundation

func snapshotOutputTests() -> [TestCase] {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func snapshot(usedPercent: Double, windowMinutes: Int, resetOffset: TimeInterval) -> UsageSnapshot {
        guard
            let snapshot = UsageSnapshot(
                usedPercent: usedPercent,
                windowDurationMinutes: windowMinutes,
                resetsAt: now.addingTimeInterval(resetOffset)
            )
        else {
            preconditionFailure("Invalid UsageSnapshot test fixture")
        }
        return snapshot
    }

    let weekly = snapshot(usedPercent: 25, windowMinutes: 10_080, resetOffset: 302_400)
    let fiveHour = snapshot(usedPercent: 40, windowMinutes: 300, resetOffset: 9_000)

    func report(weekly: UsageSnapshot?, fiveHour: UsageSnapshot?) -> UsageReport {
        guard let report = UsageReport(weekly: weekly, fiveHour: fiveHour) else {
            preconditionFailure("A UsageReport test fixture needs at least one window")
        }
        return report
    }

    return [
        TestCase(name: "snapshot output keeps weekly usage at limit zero") {
            let lines = SnapshotOutput.lines(
                for: report(weekly: weekly, fiveHour: fiveHour),
                at: now
            )
            try expectEqual(
                lines,
                [
                    "limit_0_time_remaining=50",
                    "limit_0_usage_remaining=75",
                    "limit_0_resets_at=1700302400",
                    "limit_1_time_remaining=50",
                    "limit_1_usage_remaining=60",
                    "limit_1_resets_at=1700009000",
                ]
            )
        },
        TestCase(name: "snapshot output omits an unavailable five-hour window") {
            let lines = SnapshotOutput.lines(
                for: report(weekly: weekly, fiveHour: nil),
                at: now
            )
            try expectEqual(lines.count, 3)
            try expect(lines.allSatisfy { $0.hasPrefix("limit_0_") }, "expected only limit zero")
        },
        TestCase(name: "snapshot output keeps five-hour-only usage at limit one") {
            let lines = SnapshotOutput.lines(
                for: report(weekly: nil, fiveHour: fiveHour),
                at: now
            )
            try expectEqual(
                lines,
                [
                    "limit_1_time_remaining=50",
                    "limit_1_usage_remaining=60",
                    "limit_1_resets_at=1700009000",
                ]
            )
        },
    ]
}
