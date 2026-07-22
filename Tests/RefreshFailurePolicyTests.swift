import Foundation

func refreshFailurePolicyTests() -> [TestCase] {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func report(resetsAt: Date, models: [ModelUsage] = []) -> UsageReport {
        guard
            let snapshot = UsageSnapshot(
                usedPercent: 25,
                windowDurationMinutes: 10_080,
                resetsAt: resetsAt
            ),
            let report = UsageReport(weekly: snapshot, fiveHour: nil, models: models)
        else {
            preconditionFailure("Invalid refresh-policy test fixture")
        }
        return report
    }

    return [
        TestCase(name: "transient and schema failures preserve an explicitly stale report") {
            try expect(
                RefreshFailurePolicy.preservesLastReport(for: CodexClientError.timedOut),
                "expected timeout preservation"
            )
            try expect(
                RefreshFailurePolicy.preservesLastReport(
                    for: CodexClientError.launchFailed("exit 3")
                ),
                "expected launch-failure preservation"
            )
            try expect(
                RefreshFailurePolicy.preservesLastReport(
                    for: CodexClientError.connectionClosed(nil)
                ),
                "expected closed-connection preservation"
            )
            try expect(
                RefreshFailurePolicy.preservesLastReport(for: CodexClientError.invalidResponse),
                "expected schema-change preservation"
            )
        },
        TestCase(name: "missing installs and server rejections invalidate account data") {
            try expect(
                !RefreshFailurePolicy.preservesLastReport(for: CodexClientError.executableNotFound),
                "expected missing-executable invalidation"
            )
            try expect(
                !RefreshFailurePolicy.preservesLastReport(
                    for: CodexClientError.server("Sign in required")
                ),
                "expected server-rejection invalidation"
            )
            try expect(
                !RefreshFailurePolicy.preservesLastReport(for: CocoaError(.fileNoSuchFile)),
                "expected unfamiliar errors to invalidate"
            )
        },
        TestCase(name: "stale reports expire with their last usage window") {
            try expect(
                RefreshFailurePolicy.preservesLastReport(
                    for: CodexClientError.invalidResponse,
                    report: report(resetsAt: now.addingTimeInterval(1)),
                    at: now
                ),
                "expected an active stale window to remain visible"
            )
            try expect(
                !RefreshFailurePolicy.preservesLastReport(
                    for: CodexClientError.invalidResponse,
                    report: report(resetsAt: now),
                    at: now
                ),
                "expected an expired stale window to clear"
            )
        },
        TestCase(name: "an unexpired per-model window preserves a stale report") {
            guard
                let modelSnapshot = UsageSnapshot(
                    usedPercent: 25,
                    windowDurationMinutes: 10_080,
                    resetsAt: now.addingTimeInterval(60)
                )
            else {
                preconditionFailure("Invalid refresh-policy test fixture")
            }
            let model = ModelUsage(
                limitId: "codex_bengalfox",
                displayName: "GPT-5.3-Codex-Spark",
                snapshot: modelSnapshot
            )
            try expect(
                RefreshFailurePolicy.preservesLastReport(
                    for: CodexClientError.invalidResponse,
                    report: report(resetsAt: now, models: [model]),
                    at: now
                ),
                "expected the per-model window to preserve the stale report"
            )
        },
    ]
}
