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

        let limitLines = snapshots.flatMap { index, snapshot in
            let reading = snapshot.reading(at: date)
            return [
                "limit_\(index)_time_remaining=\(reading.timeRemainingPercent)",
                "limit_\(index)_usage_remaining=\(reading.usageRemainingPercent)",
                "limit_\(index)_resets_at=\(epochSeconds(snapshot.resetsAt))",
            ]
        }
        let modelLines = report.models.flatMap { model in
            let reading = model.snapshot.reading(at: date)
            return [
                "model_\(model.limitId)_time_remaining=\(reading.timeRemainingPercent)",
                "model_\(model.limitId)_usage_remaining=\(reading.usageRemainingPercent)",
                "model_\(model.limitId)_resets_at=\(epochSeconds(model.snapshot.resetsAt))",
            ]
        }
        return limitLines + modelLines
    }

    // Int(Double) traps on overflow; saturate so no reset timestamp can crash output.
    private static func epochSeconds(_ date: Date) -> Int {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return 0 }
        if seconds >= Double(Int.max) { return .max }
        if seconds <= Double(Int.min) { return .min }
        return Int(seconds)
    }
}
