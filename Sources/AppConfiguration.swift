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
    // One divider plus one comparison bar, including the surrounding stack spacing.
    static let modelSectionHeight: CGFloat = 85
    // The popover has no scroll view, so rows beyond this cap would grow past the screen.
    static let maximumModelRows = 4

    static let automaticRefreshInterval = RefreshConfiguration.minutes * 60
    static let clockRefreshInterval: TimeInterval = 60
    static let requestTimeout: Duration = .seconds(12)

    static func contentSize(
        fiveHourAvailable: Bool,
        weeklyAvailable: Bool,
        modelCount: Int
    ) -> NSSize {
        let base = fiveHourAvailable && weeklyAvailable ? expandedContentSize : compactContentSize
        return NSSize(
            width: base.width,
            height: base.height + CGFloat(modelCount) * modelSectionHeight
        )
    }
}
