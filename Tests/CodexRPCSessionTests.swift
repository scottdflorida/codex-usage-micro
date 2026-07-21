import Foundation

func codexRPCSessionTests() -> [TestCase] {
    [
        TestCase(name: "RPC session completes the required handshake in order") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-success.zsh"),
                timeout: .seconds(2)
            )

            let response = try await session.readRateLimits()
            let report = try CodexResponseParser.parseRateLimitsResponse(
                response,
                now: Date(timeIntervalSince1970: 1_785_500_000)
            )
            try expectEqual(report.snapshot.usedPercent, 25)
            try expectEqual(report.snapshot.windowDurationMinutes, 10_080)
        },
        TestCase(name: "RPC session surfaces and sanitizes initialize errors") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-initialize-error.zsh"),
                timeout: .seconds(2)
            )

            try await expectAsyncThrows(CodexClientError.server("Sign in required")) {
                _ = try await session.readRateLimits()
            }
        },
        TestCase(name: "RPC session drains a final response before process exit") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-exit-after-response.zsh"),
                timeout: .seconds(2)
            )

            let response = try await session.readRateLimits()
            let report = try CodexResponseParser.parseRateLimitsResponse(
                response,
                now: Date(timeIntervalSince1970: 1_785_500_000)
            )
            try expectEqual(report.snapshot.usedPercent, 25)
        },
        TestCase(name: "RPC session times out deterministically") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-hang.zsh"),
                timeout: .milliseconds(75)
            )

            try await expectAsyncThrows(CodexClientError.timedOut) {
                _ = try await session.readRateLimits()
            }
        },
        TestCase(name: "RPC session honors task cancellation") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-hang.zsh"),
                timeout: .seconds(30)
            )
            let request = Task {
                try await session.readRateLimits()
            }

            try await Task.sleep(for: .milliseconds(75))
            request.cancel()

            do {
                _ = try await request.value
                throw TestFailure(description: "expected cancellation, but the request succeeded")
            } catch is CancellationError {
                // Expected.
            }
        },
    ]
}

private func fixtureURL(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent(name, isDirectory: false)
}
