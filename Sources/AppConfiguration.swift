import AppKit
import Foundation

enum AppConfiguration {
    static let name = "Codex Usage Micro"
    static let version =
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
    static let menuTitlePrefix = "Cx"
    static let popoverTitle = "CODEX WEEKLY USAGE"
    static let contentSize = NSSize(width: 300, height: 150)

    static let automaticRefreshInterval = RefreshConfiguration.minutes * 60
    static let clockRefreshInterval: TimeInterval = 60
    static let requestTimeout: Duration = .seconds(12)
}
