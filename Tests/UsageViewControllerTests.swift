import AppKit
import Foundation

func usageViewControllerTests() -> [TestCase] {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func snapshot(windowMinutes: Int) -> UsageSnapshot {
        guard
            let snapshot = UsageSnapshot(
                usedPercent: 25,
                windowDurationMinutes: windowMinutes,
                resetsAt: now.addingTimeInterval(TimeInterval(windowMinutes * 30))
            )
        else {
            preconditionFailure("Invalid UsageSnapshot test fixture")
        }
        return snapshot
    }

    func report(
        weekly: UsageSnapshot?,
        fiveHour: UsageSnapshot?,
        models: [ModelUsage] = []
    ) -> UsageReport {
        guard let report = UsageReport(weekly: weekly, fiveHour: fiveHour, models: models) else {
            preconditionFailure("A UsageReport test fixture needs at least one window")
        }
        return report
    }

    @MainActor
    func visibleText(in view: NSView) -> [String] {
        let ownValue = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return ownValue
            + view.subviews
            .filter { !$0.isHidden }
            .flatMap(visibleText(in:))
    }

    @MainActor
    func comparisonBars(in view: NSView) -> [ComparisonBarView] {
        let own = (view as? ComparisonBarView).map { [$0] } ?? []
        return own + view.subviews.flatMap(comparisonBars(in:))
    }

    return [
        TestCase(name: "popover loads, expands, and collapses with optional five-hour usage") {
            try await MainActor.run {
                _ = NSApplication.shared
                let viewController = UsageViewController()

                var observedSizes: [NSSize] = []
                viewController.onContentSizeChange = { observedSizes.append($0) }

                viewController.show(
                    report: report(
                        weekly: snapshot(windowMinutes: 10_080),
                        fiveHour: snapshot(windowMinutes: 300)
                    ),
                    at: now
                )
                try expectEqual(
                    viewController.preferredContentSize,
                    AppConfiguration.expandedContentSize
                )

                viewController.show(
                    report: report(
                        weekly: snapshot(windowMinutes: 10_080),
                        fiveHour: nil
                    ),
                    at: now
                )
                try expectEqual(
                    viewController.preferredContentSize,
                    AppConfiguration.compactContentSize
                )
                try expect(
                    visibleText(in: viewController.view).contains("Weekly usage remaining"),
                    "expected the weekly window to remain visible"
                )
                try expect(
                    !visibleText(in: viewController.view).contains("5-hour usage remaining"),
                    "expected the unavailable five-hour window to be removed"
                )

                viewController.show(
                    report: report(
                        weekly: nil,
                        fiveHour: snapshot(windowMinutes: 300)
                    ),
                    at: now
                )
                try expectEqual(
                    viewController.preferredContentSize,
                    AppConfiguration.compactContentSize
                )
                let fiveHourText = visibleText(in: viewController.view)
                try expect(
                    fiveHourText.contains("CODEX USAGE"),
                    "expected the compact presentation to retain its header"
                )
                try expect(
                    fiveHourText.contains("5-hour usage remaining"),
                    "expected the five-hour window to be visible"
                )
                try expect(
                    !fiveHourText.contains("Weekly usage remaining"),
                    "expected the unavailable weekly window to be removed"
                )

                viewController.show(errorMessage: "An intentionally long diagnostic message")
                try expectEqual(
                    viewController.preferredContentSize,
                    AppConfiguration.errorContentSize
                )

                viewController.show(
                    report: report(
                        weekly: snapshot(windowMinutes: 10_080),
                        fiveHour: nil
                    ),
                    at: now
                )
                try expectEqual(
                    observedSizes,
                    [
                        AppConfiguration.expandedContentSize,
                        AppConfiguration.compactContentSize,
                        AppConfiguration.errorContentSize,
                        AppConfiguration.compactContentSize,
                    ]
                )
            }
        },
        TestCase(name: "popover adds a row per per-model bucket and collapses without them") {
            try await MainActor.run {
                _ = NSApplication.shared
                let viewController = UsageViewController()

                var observedSizes: [NSSize] = []
                viewController.onContentSizeChange = { observedSizes.append($0) }

                let spark = ModelUsage(
                    limitId: "codex_bengalfox",
                    displayName: "GPT-5.3-Codex-Spark",
                    snapshot: snapshot(windowMinutes: 10_080)
                )
                let lynx = ModelUsage(
                    limitId: "codex_lynx",
                    displayName: "GPT-5.3-Codex-Lynx",
                    snapshot: snapshot(windowMinutes: 300)
                )

                viewController.show(
                    report: report(
                        weekly: snapshot(windowMinutes: 10_080),
                        fiveHour: snapshot(windowMinutes: 300),
                        models: [spark, lynx]
                    ),
                    at: now
                )
                let twoModelSize = AppConfiguration.contentSize(
                    fiveHourAvailable: true,
                    weeklyAvailable: true,
                    modelCount: 2
                )
                try expect(
                    twoModelSize.height > AppConfiguration.expandedContentSize.height,
                    "expected model rows to grow the expanded presentation"
                )
                try expectEqual(viewController.preferredContentSize, twoModelSize)
                let expandedText = visibleText(in: viewController.view)
                try expect(
                    expandedText.contains("GPT-5.3-Codex-Spark"),
                    "expected the provider's model name verbatim"
                )
                try expect(
                    expandedText.contains("GPT-5.3-Codex-Lynx"),
                    "expected a row for every per-model bucket"
                )
                try expectEqual(
                    expandedText.filter { $0 == "Week remaining" }.count,
                    2
                )
                try expect(
                    expandedText.contains("Time remaining"),
                    "expected a sub-week model window to read time, not week"
                )

                viewController.show(
                    report: report(
                        weekly: snapshot(windowMinutes: 10_080),
                        fiveHour: nil,
                        models: [spark]
                    ),
                    at: now
                )
                let oneModelSize = AppConfiguration.contentSize(
                    fiveHourAvailable: false,
                    weeklyAvailable: true,
                    modelCount: 1
                )
                try expect(
                    oneModelSize.height > AppConfiguration.compactContentSize.height,
                    "expected a model row to grow the compact presentation"
                )
                try expectEqual(viewController.preferredContentSize, oneModelSize)

                viewController.show(
                    report: report(
                        weekly: snapshot(windowMinutes: 10_080),
                        fiveHour: nil
                    ),
                    at: now
                )
                try expectEqual(
                    viewController.preferredContentSize,
                    AppConfiguration.compactContentSize
                )
                try expect(
                    !visibleText(in: viewController.view).contains("GPT-5.3-Codex-Spark"),
                    "expected model rows to disappear with the report"
                )
                try expectEqual(
                    observedSizes,
                    [twoModelSize, oneModelSize, AppConfiguration.compactContentSize]
                )
            }
        },
        TestCase(name: "clock updates refresh cached model rows in place") {
            try await MainActor.run {
                _ = NSApplication.shared
                let viewController = UsageViewController()

                let spark = ModelUsage(
                    limitId: "codex_bengalfox",
                    displayName: "GPT-5.3-Codex-Spark",
                    snapshot: snapshot(windowMinutes: 300)
                )
                let sparkReport = report(
                    weekly: snapshot(windowMinutes: 10_080),
                    fiveHour: nil,
                    models: [spark]
                )

                viewController.show(report: sparkReport, at: now)
                let initialBars = comparisonBars(in: viewController.view)
                try expect(
                    !visibleText(in: viewController.view).contains("25%"),
                    "expected no quarter-window reading before the clock update"
                )

                viewController.updateClock(at: now.addingTimeInterval(4_500))
                try expect(
                    visibleText(in: viewController.view).contains("25%"),
                    "expected the clock update to refresh the model row's reading"
                )

                viewController.show(report: sparkReport, at: now)
                let reusedBars = comparisonBars(in: viewController.view)
                try expectEqual(initialBars.count, reusedBars.count)
                try expect(
                    zip(initialBars, reusedBars).allSatisfy { $0 === $1 },
                    "expected an identity-stable report to reuse the same model bars"
                )
            }
        },
        TestCase(name: "comparison bar tolerates a transient zero-width layout") {
            await MainActor.run {
                _ = NSApplication.shared
                let bar = ComparisonBarView(
                    timeLabel: "Time remaining",
                    usageLabel: "Usage remaining",
                    accessibilityLabel: "Test limit"
                )
                bar.frame = .zero
                bar.layoutSubtreeIfNeeded()
            }
        },
    ]
}
