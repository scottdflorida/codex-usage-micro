import Foundation

func refreshThrottleTests() -> [TestCase] {
    [
        TestCase(name: "popover refresh throttle skips fresh data and honors the maximum age") {
            let throttle = RefreshThrottle(maximumAge: 15 * 60)
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            try expect(
                throttle.shouldRefresh(lastSuccessfulRefreshAt: nil, now: now),
                "expected a never-fetched state to refresh"
            )
            try expect(
                !throttle.shouldRefresh(
                    lastSuccessfulRefreshAt: now.addingTimeInterval(-(15 * 60) + 1),
                    now: now
                ),
                "expected fresh data to skip the refresh"
            )
            try expect(
                throttle.shouldRefresh(
                    lastSuccessfulRefreshAt: now.addingTimeInterval(-(15 * 60)),
                    now: now
                ),
                "expected data at the maximum age to refresh"
            )
            try expect(
                throttle.shouldRefresh(
                    lastSuccessfulRefreshAt: now.addingTimeInterval(1),
                    now: now
                ),
                "expected a future timestamp to refresh"
            )
        }
    ]
}
