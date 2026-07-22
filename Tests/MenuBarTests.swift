import Foundation

func menuBarTests() -> [TestCase] {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func snapshot(
        usedPercent: Double,
        windowMinutes: Int,
        resetOffset: TimeInterval
    ) -> UsageSnapshot {
        guard
            let snapshot = UsageSnapshot(
                usedPercent: usedPercent,
                windowDurationMinutes: windowMinutes,
                resetsAt: now.addingTimeInterval(resetOffset)
            )
        else {
            preconditionFailure("Invalid menu-bar snapshot fixture")
        }
        return snapshot
    }

    func report(weekly: UsageSnapshot?, fiveHour: UsageSnapshot?) -> UsageReport {
        guard let report = UsageReport(weekly: weekly, fiveHour: fiveHour) else {
            preconditionFailure("A menu-bar report fixture needs at least one window")
        }
        return report
    }

    return [
        TestCase(name: "menu-bar geometry permanently stacks the brand above the gauge") {
            let layout = MenuBarItemLayout.standard
            try expect(
                layout.statusItemWidth > layout.imageWidth,
                "status item must reserve button padding"
            )
            try expect(
                layout.brandSlotWidth == layout.imageWidth,
                "brand and gauge must share the same stacked width"
            )
            try expect(
                layout.gaugeOriginX + layout.gaugeWidth <= layout.imageWidth,
                "gauge must remain inside the image"
            )
        },
        TestCase(name: "menu-bar display always identifies Codex") {
            let weekly = snapshot(
                usedPercent: 21,
                windowMinutes: 10_080,
                resetOffset: 302_400
            )
            let usageReport = report(weekly: weekly, fiveHour: nil)

            let display = MenuBarDisplayState.live(
                report: usageReport,
                at: now
            )
            try expectEqual(display.brandName, "Codex")
        },
        TestCase(name: "menu-bar display prefers weekly and falls back to five-hour usage") {
            let weekly = snapshot(
                usedPercent: 21,
                windowMinutes: 10_080,
                resetOffset: 302_400
            )
            let fiveHour = snapshot(
                usedPercent: 62,
                windowMinutes: 300,
                resetOffset: 9_000
            )

            let weeklyDisplay = MenuBarDisplayState.live(
                report: report(weekly: weekly, fiveHour: fiveHour),
                at: now
            )
            try expectEqual(weeklyDisplay.limitName, "Weekly")
            guard case .value(let weeklyReading) = weeklyDisplay.gauge else {
                throw TestFailure(description: "expected a weekly gauge reading")
            }
            try expectEqual(weeklyReading.usageRemainingPercent, 79)

            let fiveHourDisplay = MenuBarDisplayState.live(
                report: report(weekly: nil, fiveHour: fiveHour),
                at: now
            )
            try expectEqual(fiveHourDisplay.limitName, "5-hour")
            guard case .value(let fiveHourReading) = fiveHourDisplay.gauge else {
                throw TestFailure(description: "expected a five-hour gauge reading")
            }
            try expectEqual(fiveHourReading.usageRemainingPercent, 38)
        },
        TestCase(name: "menu-bar display ignores per-model buckets") {
            let weekly = snapshot(
                usedPercent: 21,
                windowMinutes: 10_080,
                resetOffset: 302_400
            )
            let model = ModelUsage(
                limitId: "codex_bengalfox",
                displayName: "GPT-5.3-Codex-Spark",
                snapshot: snapshot(usedPercent: 80, windowMinutes: 10_080, resetOffset: 302_400)
            )
            guard let withModels = UsageReport(weekly: weekly, fiveHour: nil, models: [model]) else {
                throw TestFailure(description: "Invalid menu-bar report fixture")
            }

            try expectEqual(
                MenuBarDisplayState.live(report: withModels, at: now),
                MenuBarDisplayState.live(report: report(weekly: weekly, fiveHour: nil), at: now)
            )
        },
        TestCase(name: "tooltip and accessibility lines follow one compact convention") {
            let weekly = snapshot(usedPercent: 21, windowMinutes: 10_080, resetOffset: 302_400)
            let fiveHour = snapshot(usedPercent: 62, windowMinutes: 300, resetOffset: 9_000)

            try expectEqual(
                UsageRowText.toolTip(name: "Weekly", snapshot: weekly, at: now),
                "Weekly · Usage left 79% · Week left 50%"
            )
            try expectEqual(
                UsageRowText.toolTip(name: "GPT-5.3-Codex-Spark", snapshot: fiveHour, at: now),
                "GPT-5.3-Codex-Spark · Usage left 38% · Time left 50%"
            )
            try expectEqual(
                UsageRowText.accessibility(name: "weekly", snapshot: weekly, at: now),
                "weekly usage remaining 79 percent, week remaining 50 percent"
            )
            try expectEqual(
                UsageRowText.accessibility(name: "five-hour", snapshot: fiveHour, at: now),
                "five-hour usage remaining 38 percent, time remaining 50 percent"
            )
        },
        TestCase(name: "stale freshness keeps the gauge reading") {
            let weekly = snapshot(
                usedPercent: 21,
                windowMinutes: 10_080,
                resetOffset: 302_400
            )
            let usageReport = report(weekly: weekly, fiveHour: nil)

            let stale = MenuBarDisplayState.live(report: usageReport, at: now, freshness: .stale)
            try expectEqual(stale.freshness, .stale)
            guard case .value = stale.gauge else {
                throw TestFailure(description: "expected the stale gauge to keep its reading")
            }

            let live = MenuBarDisplayState.live(report: usageReport, at: now)
            try expectEqual(live.freshness, .current)
            try expectEqual(MenuBarDisplayState.loading.freshness, .current)
            try expectEqual(MenuBarDisplayState.unavailable.freshness, .current)
        },
        TestCase(name: "loading and unavailable menu-bar gauges use consistent symbols") {
            try expectEqual(MenuBarDisplayState.loading.brandName, "Codex")
            try expectEqual(MenuBarDisplayState.unavailable.brandName, "Codex")
            try expectEqual(MenuBarGaugeState.loading.statusSymbol, "…")
            try expectEqual(MenuBarGaugeState.unavailable.statusSymbol, "!")
        },
    ]
}
