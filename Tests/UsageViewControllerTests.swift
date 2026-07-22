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

    func report(weekly: UsageSnapshot?, fiveHour: UsageSnapshot?) -> UsageReport {
        guard let report = UsageReport(weekly: weekly, fiveHour: fiveHour) else {
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
