import Foundation

struct MenuBarItemLayout: Equatable, Sendable {
    let statusItemWidth: Double
    let imageWidth: Double
    let brandSlotWidth: Double
    let gaugeOriginX: Double
    let gaugeWidth: Double

    static let standard = MenuBarItemLayout(
        statusItemWidth: 48,
        imageWidth: 44,
        brandSlotWidth: 44,
        gaugeOriginX: 0,
        gaugeWidth: 44
    )
}

enum MenuBarGaugeState: Equatable, Sendable {
    case loading
    case value(UsageReading)
    case unavailable

    var statusSymbol: String? {
        switch self {
        case .loading:
            "…"
        case .value:
            nil
        case .unavailable:
            "!"
        }
    }
}

enum MenuBarFreshness: Equatable, Sendable {
    case current
    case stale
}

enum UsageRowText {
    static func toolTip(name: String, snapshot: UsageSnapshot, at date: Date) -> String {
        let reading = snapshot.reading(at: date)
        return "\(name) · Usage left \(reading.usageRemainingPercent)% · "
            + "\(snapshot.spansWeek ? "Week" : "Time") left \(reading.timeRemainingPercent)%"
    }

    static func accessibility(name: String, snapshot: UsageSnapshot, at date: Date) -> String {
        let reading = snapshot.reading(at: date)
        return "\(name) usage remaining \(reading.usageRemainingPercent) percent, "
            + "\(snapshot.spansWeek ? "week" : "time") remaining \(reading.timeRemainingPercent) percent"
    }
}

struct MenuBarDisplayState: Equatable, Sendable {
    let brandName: String
    let gauge: MenuBarGaugeState
    let limitName: String?
    let freshness: MenuBarFreshness

    static let loading = MenuBarDisplayState(
        brandName: "Codex",
        gauge: .loading,
        limitName: nil,
        freshness: .current
    )

    static let unavailable = MenuBarDisplayState(
        brandName: "Codex",
        gauge: .unavailable,
        limitName: nil,
        freshness: .current
    )

    static func live(
        report: UsageReport,
        at date: Date = Date(),
        freshness: MenuBarFreshness = .current
    ) -> MenuBarDisplayState {
        let usesWeeklyLimit = report.weekly != nil
        guard let snapshot = report.weekly ?? report.fiveHour else {
            return unavailable
        }

        return MenuBarDisplayState(
            brandName: "Codex",
            gauge: .value(snapshot.reading(at: date)),
            limitName: usesWeeklyLimit ? "Weekly" : "5-hour",
            freshness: freshness
        )
    }
}
