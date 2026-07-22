import Foundation

enum SnapshotOutput {
    static func lines(for report: UsageReport, at date: Date = Date()) -> [String] {
        // Keep weekly usage at limit 0 for compatibility with existing snapshot consumers.
        var snapshots: [(index: Int, snapshot: UsageSnapshot)] = []
        if let weekly = report.weekly {
            snapshots.append((index: 0, snapshot: weekly))
        }
        if let fiveHour = report.fiveHour {
            snapshots.append((index: 1, snapshot: fiveHour))
        }

        return snapshots.flatMap { index, snapshot in
            let reading = snapshot.reading(at: date)
            return [
                "limit_\(index)_time_remaining=\(reading.timeRemainingPercent)",
                "limit_\(index)_usage_remaining=\(reading.usageRemainingPercent)",
                "limit_\(index)_resets_at=\(Int(snapshot.resetsAt.timeIntervalSince1970))",
            ]
        }
    }
}
