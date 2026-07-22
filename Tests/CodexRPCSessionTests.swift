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
            try expectEqual(report.weekly?.usedPercent, 25)
            try expectEqual(report.weekly?.windowDurationMinutes, 10_080)
            try expectEqual(report.fiveHour?.usedPercent, 40)
            try expectEqual(report.fiveHour?.windowDurationMinutes, 300)
        },
        TestCase(name: "RPC session remains stable across repeated live-style fetches") {
            for _ in 0..<20 {
                let session = CodexRPCSession(
                    executableURL: fixtureURL(named: "fake-codex-success.zsh"),
                    timeout: .seconds(2)
                )
                let response = try await session.readRateLimits()
                let report = try CodexResponseParser.parseRateLimitsResponse(
                    response,
                    now: Date(timeIntervalSince1970: 1_785_500_000)
                )
                try expectEqual(report.weekly?.usedPercent, 25)
            }
        },
        TestCase(name: "RPC session correlates responses and tolerates string request IDs") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-noisy-success.zsh"),
                timeout: .seconds(2)
            )

            let response = try await session.readRateLimits()
            let report = try CodexResponseParser.parseRateLimitsResponse(
                response,
                now: Date(timeIntervalSince1970: 1_785_500_000)
            )
            try expectEqual(report.weekly?.usedPercent, 25)
        },
        TestCase(name: "RPC session ignores server-initiated requests with colliding IDs") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-server-request-collision.zsh"),
                timeout: .seconds(2)
            )

            let response = try await session.readRateLimits()
            let report = try CodexResponseParser.parseRateLimitsResponse(
                response,
                now: Date(timeIntervalSince1970: 1_785_500_000)
            )
            try expectEqual(report.weekly?.usedPercent, 25)
        },
        TestCase(name: "RPC session surfaces launch failures") {
            let session = CodexRPCSession(
                executableURL: URL(fileURLWithPath: "/nonexistent-codex-\(UUID().uuidString)"),
                timeout: .seconds(2)
            )

            do {
                _ = try await session.readRateLimits()
                throw TestFailure(description: "expected launchFailed, but the request succeeded")
            } catch CodexClientError.launchFailed {
                // Expected.
            }
        },
        TestCase(name: "RPC session rejects a stdout flood past the output cap") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-flood.zsh"),
                timeout: .seconds(5)
            )

            try await expectAsyncThrows(CodexClientError.invalidResponse) {
                _ = try await session.readRateLimits()
            }
        },
        TestCase(name: "RPC session maps a dead stdin to a closed connection") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-stdin-closed.zsh"),
                timeout: .seconds(2)
            )

            do {
                _ = try await session.readRateLimits()
                throw TestFailure(description: "expected connectionClosed, but the request succeeded")
            } catch CodexClientError.connectionClosed {
                // Expected.
            }
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
            try expectEqual(report.weekly?.usedPercent, 25)
        },
        TestCase(name: "RPC session drains diagnostics before process failure") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-stderr-exit.zsh"),
                timeout: .seconds(2)
            )

            try await expectAsyncThrows(
                CodexClientError.connectionClosed("fatal startup failure")
            ) {
                _ = try await session.readRateLimits()
            }
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
        TestCase(name: "RPC session cancelled at start still surfaces CancellationError") {
            let session = CodexRPCSession(
                executableURL: fixtureURL(named: "fake-codex-hang.zsh"),
                timeout: .seconds(30)
            )
            let request = Task {
                try await session.readRateLimits()
            }
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
