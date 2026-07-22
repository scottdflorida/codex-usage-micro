import Foundation

enum CodexResponseParser {
    private enum LimitWindow {
        case fiveHour
        case weekly

        var durationMinutes: Int {
            switch self {
            case .fiveHour: 5 * 60
            case .weekly: 7 * 24 * 60
            }
        }
    }

    private enum SourcePriority: CaseIterable {
        case exactCodex
        case codexDescriptor
        case legacy
        case unknown
    }

    private struct LimitSource {
        let priority: SourcePriority
        let identifiers: Set<String>
        let snapshot: RateLimitSnapshot
    }

    private struct ResolvedWindow {
        let snapshot: UsageSnapshot
        let sourceIdentifiers: Set<String>
    }

    private enum SnapshotResolution {
        case missing
        case value(UsageSnapshot)
        case ambiguous
    }

    private static let resetTolerance: TimeInterval = 5 * 60

    static func parseRateLimitsResponse(
        _ data: Data,
        now: Date = Date()
    ) throws -> UsageReport {
        let response: RateLimitsResponse
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            response = try decoder.decode(RateLimitsResponse.self, from: data)
        } catch {
            throw CodexResponseParsingError.invalidJSON
        }

        if let message = response.error?.message {
            throw CodexResponseParsingError.server(message)
        }

        guard let result = response.result else {
            throw CodexResponseParsingError.missingResult
        }

        let sources = limitSources(from: result)
        let weekly = preferredSnapshot(for: .weekly, from: sources, now: now)
        let fiveHour = preferredSnapshot(for: .fiveHour, from: sources, now: now)
        let mainPoolIdentifiers = (weekly?.sourceIdentifiers ?? [])
            .union(fiveHour?.sourceIdentifiers ?? [])

        guard
            let report = UsageReport(
                weekly: weekly?.snapshot,
                fiveHour: fiveHour?.snapshot,
                models: modelUsages(from: result, excluding: mainPoolIdentifiers, now: now)
            )
        else {
            throw CodexResponseParsingError.missingUsableWindow
        }
        return report
    }

    private static func limitSources(from result: RateLimitsResult) -> [LimitSource] {
        let namedSources = (result.rateLimitsByLimitId ?? [:])
            .sorted { $0.key < $1.key }
            .filter { identifier, snapshot in
                !isPerModelBucket(identifier: identifier, snapshot: snapshot)
            }
            .map { identifier, snapshot in
                LimitSource(
                    priority: namedSourcePriority(identifier: identifier, snapshot: snapshot),
                    identifiers: Set([identifier, snapshot.limitId].compactMap { $0 }),
                    snapshot: snapshot
                )
            }
        let unknownSourceCount = namedSources.count { $0.priority == .unknown }
        var sources = namedSources.filter { $0.priority != .unknown || unknownSourceCount == 1 }

        // The named Codex bucket is authoritative. The legacy value remains the next-best
        // compatibility source, followed by an unrecognized named bucket only when its value is
        // unambiguous. This lets bucket identifiers evolve without guessing across conflicting
        // products or plans.
        if let legacy = result.rateLimits {
            sources.append(
                LimitSource(
                    priority: .legacy,
                    identifiers: Set([legacy.limitId].compactMap { $0 }),
                    snapshot: legacy
                )
            )
        }
        return sources
    }

    private static func namedSourcePriority(
        identifier: String,
        snapshot: RateLimitSnapshot
    ) -> SourcePriority {
        if isExactCodexIdentifier(identifier) || isExactCodexIdentifier(snapshot.limitId) {
            return .exactCodex
        }
        if isCodexDescriptor(identifier)
            || isCodexDescriptor(snapshot.limitId)
            || isCodexDescriptor(snapshot.limitName)
        {
            return .codexDescriptor
        }
        return .unknown
    }

    private static func preferredSnapshot(
        for limitWindow: LimitWindow,
        from sources: [LimitSource],
        now: Date
    ) -> ResolvedWindow? {
        for priority in SourcePriority.allCases {
            var uniqueCandidates: [ResolvedWindow] = []
            for source in sources where source.priority == priority {
                switch resolveSnapshot(
                    matchingDurationMinutes: limitWindow.durationMinutes,
                    from: source.snapshot,
                    now: now
                ) {
                case .missing:
                    continue
                case .value(let candidate):
                    if let index = uniqueCandidates.firstIndex(where: { $0.snapshot == candidate }) {
                        uniqueCandidates[index] = ResolvedWindow(
                            snapshot: candidate,
                            sourceIdentifiers: uniqueCandidates[index].sourceIdentifiers
                                .union(source.identifiers)
                        )
                    } else {
                        uniqueCandidates.append(
                            ResolvedWindow(snapshot: candidate, sourceIdentifiers: source.identifiers)
                        )
                    }
                case .ambiguous:
                    return nil
                }
            }

            if uniqueCandidates.count == 1 {
                return uniqueCandidates[0]
            }
            if uniqueCandidates.count > 1 {
                return nil
            }
        }
        return nil
    }

    private static func resolveSnapshot(
        matchingDurationMinutes expectedDurationMinutes: Int,
        from limits: RateLimitSnapshot,
        now: Date
    ) -> SnapshotResolution {
        let candidates = limits.windows.lazy
            .compactMap {
                makeSnapshot(
                    from: $0,
                    expectedDurationMinutes: expectedDurationMinutes,
                    now: now
                )
            }

        var uniqueCandidates: [UsageSnapshot] = []
        for candidate in candidates where !uniqueCandidates.contains(candidate) {
            uniqueCandidates.append(candidate)
        }
        switch uniqueCandidates.count {
        case 0: return .missing
        case 1: return .value(uniqueCandidates[0])
        default: return .ambiguous
        }
    }

    private static func makeSnapshot(
        from window: RateLimitWindow,
        expectedDurationMinutes: Int,
        now: Date
    ) -> UsageSnapshot? {
        guard
            let snapshot = makeSnapshot(from: window, now: now),
            snapshot.windowDurationMinutes == expectedDurationMinutes
        else {
            return nil
        }
        return snapshot
    }

    private static func makeSnapshot(from window: RateLimitWindow, now: Date) -> UsageSnapshot? {
        guard
            let usedPercent = window.usedPercent,
            let windowDurationMinutes = window.windowDurationMinutes,
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

    private static func modelUsages(
        from result: RateLimitsResult,
        excluding mainPoolIdentifiers: Set<String>,
        now: Date
    ) -> [ModelUsage] {
        // A per-model row carries the provider's label, sanitized for display, and must
        // never restate the bucket that already feeds the main pool.
        let candidates = (result.rateLimitsByLimitId ?? [:])
            .compactMap { identifier, bucket -> ModelUsage? in
                let limitId = bucket.limitId ?? identifier
                let displayName = DiagnosticText.sanitizedName(bucket.limitName ?? "")
                guard
                    !displayName.isEmpty,
                    isSnapshotSafeLimitId(limitId),
                    !mainPoolIdentifiers.contains(identifier),
                    !mainPoolIdentifiers.contains(limitId),
                    let primaryWindow = bucket.windows.first,
                    let snapshot = makeSnapshot(from: primaryWindow, now: now)
                else {
                    return nil
                }
                return ModelUsage(limitId: limitId, displayName: displayName, snapshot: snapshot)
            }

        // A duplicated limit id is ambiguous, so every claimant is dropped.
        let rowsPerLimitId = Dictionary(grouping: candidates, by: \.limitId).mapValues(\.count)
        return Array(
            candidates
                .filter { rowsPerLimitId[$0.limitId] == 1 }
                .sorted { $0.limitId < $1.limitId }
                .prefix(AppConfiguration.maximumModelRows)
        )
    }

    // A named bucket that is not the codex pool itself belongs to a single model; it must
    // never stand in for the account-wide weekly or five-hour gauge.
    private static func isPerModelBucket(identifier: String, snapshot: RateLimitSnapshot) -> Bool {
        guard let limitName = snapshot.limitName, !limitName.isEmpty else {
            return false
        }
        return !isExactCodexIdentifier(identifier) && !isExactCodexIdentifier(snapshot.limitId)
    }

    // A limit id becomes a model_<limitId> key in the line-oriented --snapshot contract;
    // anything outside that alphabet fails closed.
    private static func isSnapshotSafeLimitId(_ value: String) -> Bool {
        (1...64).contains(value.unicodeScalars.count)
            && value.unicodeScalars.allSatisfy { scalar in
                switch scalar {
                case "A"..."Z", "a"..."z", "0"..."9", "_", ".", "-": true
                default: false
                }
            }
    }

    private static func isExactCodexIdentifier(_ value: String?) -> Bool {
        value?.normalizedIdentifier == "codex"
    }

    private static func isCodexDescriptor(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.normalizedIdentifier.hasPrefix("codex")
            || value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .contains("codex")
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

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try? container.decodeIfPresent(RateLimitSnapshot.self, forKey: .rateLimits)

        guard
            container.contains(.rateLimitsByLimitId),
            let nestedDecoder = try? container.superDecoder(forKey: .rateLimitsByLimitId),
            let namedContainer = try? nestedDecoder.container(keyedBy: DynamicCodingKey.self)
        else {
            rateLimitsByLimitId = nil
            return
        }

        var namedLimits: [String: RateLimitSnapshot] = [:]
        for key in namedContainer.allKeys {
            if let snapshot = try? namedContainer.decode(RateLimitSnapshot.self, forKey: key) {
                namedLimits[key.stringValue] = snapshot
            }
        }
        rateLimitsByLimitId = namedLimits
    }
}

private struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let windows: [RateLimitWindow]

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([RateLimitWindow].self) {
            limitId = nil
            limitName = nil
            windows = array
            return
        }

        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        limitId = container.decodeString(forNormalizedKeys: ["limitid"])
        limitName = container.decodeString(forNormalizedKeys: ["limitname"])

        let orderedKeys = container.allKeys.sorted { left, right in
            let leftRank = Self.windowKeyRank(left.stringValue)
            let rightRank = Self.windowKeyRank(right.stringValue)
            return leftRank == rightRank
                ? left.stringValue < right.stringValue
                : leftRank < rightRank
        }

        var decodedWindows: [RateLimitWindow] = []
        if let directWindow = try? RateLimitWindow(from: decoder), directWindow.hasUsageValue {
            decodedWindows.append(directWindow)
        }
        for key in orderedKeys {
            if let window = try? container.decode(RateLimitWindow.self, forKey: key),
                window.hasUsageValue
            {
                decodedWindows.append(window)
                continue
            }
            if let nestedWindows = try? container.decode([RateLimitWindow].self, forKey: key) {
                decodedWindows.append(contentsOf: nestedWindows.filter(\.hasUsageValue))
            }
        }
        windows = decodedWindows
    }

    private static func windowKeyRank(_ value: String) -> Int {
        switch value.normalizedIdentifier {
        case "primary": 0
        case "secondary": 1
        default: 2
        }
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMinutes: Int?
    let resetsAt: Int64?

    var hasUsageValue: Bool {
        usedPercent != nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        // The protocol declares used_percent as f64; fractional values must survive decoding.
        usedPercent = container.decodeDouble(
            forNormalizedKeys: ["usedpercent", "usedpercentage"]
        )
        windowDurationMinutes = container.decodeInteger(
            Int.self,
            forNormalizedKeys: ["windowdurationmins", "windowdurationminutes"]
        )
        resetsAt = container.decodeInteger(
            Int64.self,
            forNormalizedKeys: ["resetsat", "resetat"]
        )
    }
}

struct RPCErrorPayload: Decodable, Equatable, Sendable {
    let message: String
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == DynamicCodingKey {
    fileprivate func decodeString(forNormalizedKeys normalizedKeys: [String]) -> String? {
        decodeValue(String.self, forNormalizedKeys: normalizedKeys)
    }

    fileprivate func decodeInteger<T: Decodable & LosslessStringConvertible>(
        _ type: T.Type,
        forNormalizedKeys normalizedKeys: [String]
    ) -> T? {
        for normalizedKey in normalizedKeys {
            guard let key = allKeys.first(where: { $0.stringValue.normalizedIdentifier == normalizedKey })
            else {
                continue
            }
            if let value = try? decode(type, forKey: key) {
                return value
            }
            if let string = try? decode(String.self, forKey: key), let value = T(string) {
                return value
            }
        }
        return nil
    }

    fileprivate func decodeDouble(forNormalizedKeys normalizedKeys: [String]) -> Double? {
        for normalizedKey in normalizedKeys {
            guard let key = allKeys.first(where: { $0.stringValue.normalizedIdentifier == normalizedKey })
            else {
                continue
            }
            if let value = try? decode(Double.self, forKey: key) {
                return value
            }
            if let string = try? decode(String.self, forKey: key), let value = Double(string) {
                return value
            }
        }
        return nil
    }

    private func decodeValue<T: Decodable>(
        _ type: T.Type,
        forNormalizedKeys normalizedKeys: [String]
    ) -> T? {
        for normalizedKey in normalizedKeys {
            guard let key = allKeys.first(where: { $0.stringValue.normalizedIdentifier == normalizedKey })
            else {
                continue
            }
            if let value = try? decodeIfPresent(type, forKey: key) {
                return value
            }
        }
        return nil
    }
}

extension String {
    fileprivate var normalizedIdentifier: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
