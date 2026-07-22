import AppKit
import Foundation

enum AppConfiguration {
    static let name = "Codex Usage Micro"
    static let version =
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
    static let popoverTitle = "CODEX USAGE"
    static let compactContentSize = NSSize(width: 320, height: 150)
    static let expandedContentSize = NSSize(width: 320, height: 238)
    static let errorContentSize = NSSize(width: 320, height: 110)

    static let automaticRefreshInterval = RefreshConfiguration.minutes * 60
    static let clockRefreshInterval: TimeInterval = 60
    static let requestTimeout: Duration = .seconds(12)

    static func contentSize(fiveHourAvailable: Bool, weeklyAvailable: Bool) -> NSSize {
        fiveHourAvailable && weeklyAvailable ? expandedContentSize : compactContentSize
    }
}
