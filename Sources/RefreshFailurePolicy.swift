import Foundation

enum RefreshFailurePolicy {
    static func preservesLastReport(
        for error: any Error,
        report: UsageReport,
        at date: Date = Date()
    ) -> Bool {
        report.hasUnexpiredUsage(at: date) && preservesLastReport(for: error)
    }

    static func preservesLastReport(for error: any Error) -> Bool {
        guard let error = error as? CodexClientError else { return false }

        switch error {
        case .executableNotFound, .server:
            return false
        case .launchFailed, .connectionClosed, .timedOut, .invalidResponse:
            return true
        }
    }
}
