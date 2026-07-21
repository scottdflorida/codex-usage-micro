import Foundation

enum CodexResponseParser {
    private static let weeklyWindowMinutes = 7 * 24 * 60
    private static let resetTolerance: TimeInterval = 5 * 60

    static func parseRateLimitsResponse(
        _ data: Data,
        now: Date = Date()
    ) throws -> UsageReport {
        let response: RateLimitsResponse
        do {
            response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        } catch {
            throw CodexResponseParsingError.invalidJSON
        }

        if let message = response.error?.message {
            throw CodexResponseParsingError.server(message)
        }

        guard let result = response.result else {
            throw CodexResponseParsingError.missingResult
        }

        let namedSnapshot = weeklySnapshot(
            from: result.rateLimitsByLimitId?["codex"],
            now: now
        )
        let legacySnapshot = weeklySnapshot(from: result.rateLimits, now: now)
        guard let snapshot = namedSnapshot ?? legacySnapshot else {
            throw CodexResponseParsingError.missingUsableWindow
        }

        return UsageReport(snapshot: snapshot)
    }

    private static func weeklySnapshot(
        from limits: RateLimitSnapshot?,
        now: Date
    ) -> UsageSnapshot? {
        guard let limits else { return nil }

        return [limits.primary, limits.secondary]
            .compactMap { makeSnapshot(from: $0, now: now) }
            .first { $0.windowDurationMinutes == weeklyWindowMinutes }
    }

    private static func makeSnapshot(
        from window: RateLimitWindow?,
        now: Date
    ) -> UsageSnapshot? {
        guard
            let window,
            let usedPercent = window.usedPercent,
            let windowDurationMinutes = window.windowDurationMinutes,
            windowDurationMinutes == weeklyWindowMinutes,
            let resetTimestamp = window.resetsAt
        else {
            return nil
        }

        let resetsAt = Date(timeIntervalSince1970: TimeInterval(resetTimestamp))
        let windowDuration = TimeInterval(windowDurationMinutes) * 60
        guard
            resetsAt >= now.addingTimeInterval(-resetTolerance),
            resetsAt <= now.addingTimeInterval(windowDuration + resetTolerance)
        else {
            return nil
        }

        return UsageSnapshot(
            usedPercent: usedPercent,
            windowDurationMinutes: windowDurationMinutes,
            resetsAt: resetsAt
        )
    }
}

enum CodexResponseParsingError: Error, Equatable {
    case invalidJSON
    case missingResult
    case missingUsableWindow
    case server(String)
}

private struct RateLimitsResponse: Decodable {
    let result: RateLimitsResult?
    let error: RPCErrorPayload?
}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

private struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Int?
    let windowDurationMinutes: Int?
    let resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMinutes = "windowDurationMins"
        case resetsAt
    }
}

struct RPCErrorPayload: Decodable, Equatable, Sendable {
    let message: String
}
