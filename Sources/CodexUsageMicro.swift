import AppKit
import Darwin
import Foundation

@main
enum CodexUsageMicro {
    static func main() async {
        if CommandLine.arguments.contains("--snapshot") {
            await printSnapshot()
            return
        }

        await MainActor.run {
            let application = NSApplication.shared
            let delegate = AppDelegate()
            application.delegate = delegate
            application.run()
            withExtendedLifetime(delegate) {}
        }
    }

    private static func printSnapshot() async {
        do {
            let report = try await CodexClient().fetch()
            let reading = report.snapshot.reading()
            print("limit_0_time_remaining=\(reading.weekRemainingPercent)")
            print("limit_0_usage_remaining=\(reading.usageRemainingPercent)")
            print("limit_0_resets_at=\(Int(report.snapshot.resetsAt.timeIntervalSince1970))")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
