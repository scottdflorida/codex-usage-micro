import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client: any UsageFetching
    private let viewController = UsageViewController()
    private let popover = NSPopover()

    private var statusItem: NSStatusItem?
    private var report: UsageReport?
    private var refreshTask: Task<Void, Never>?
    private var usageTimer: Timer?
    private var clockTimer: Timer?

    init(client: any UsageFetching = CodexClient()) {
        self.client = client
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        scheduleTimers()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        usageTimer?.invalidate()
        clockTimer?.invalidate()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = AppConfiguration.contentSize
        popover.contentViewController = viewController
        viewController.onRefresh = { [weak self] in self?.refresh() }
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        guard let button = statusItem.button else { return }

        button.title = "\(AppConfiguration.menuTitlePrefix) —"
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "Codex weekly usage"
        button.setAccessibilityLabel("Codex weekly usage")
        button.setAccessibilityValue("Usage unavailable")
    }

    private func scheduleTimers() {
        usageTimer = Timer.scheduledTimer(
            timeInterval: AppConfiguration.automaticRefreshInterval,
            target: self,
            selector: #selector(automaticRefreshTimerFired),
            userInfo: nil,
            repeats: true
        )
        clockTimer = Timer.scheduledTimer(
            timeInterval: AppConfiguration.clockRefreshInterval,
            target: self,
            selector: #selector(clockTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            refresh()
        }
    }

    @objc private func automaticRefreshTimerFired() {
        refresh()
    }

    @objc private func clockTimerFired() {
        tick()
    }

    private func refresh() {
        guard refreshTask == nil else { return }

        viewController.showLoading()
        refreshTask = Task { [weak self, client] in
            do {
                let report = try await client.fetch()
                guard let self else { return }
                self.report = report
                self.viewController.show(report: report)
                self.updateStatusItem(with: report)
            } catch is CancellationError {
                // Application shutdown owns cancellation; no error state should flash on exit.
            } catch {
                guard let self else { return }
                let diagnostic = DiagnosticText.sanitized(error.localizedDescription)
                self.report = nil
                self.viewController.show(errorMessage: diagnostic)
                self.statusItem?.button?.title = "\(AppConfiguration.menuTitlePrefix) !"
                self.statusItem?.button?.toolTip = diagnostic
                self.statusItem?.button?.setAccessibilityValue("Usage unavailable")
            }
            self?.refreshTask = nil
        }
    }

    private func tick(at date: Date = Date()) {
        viewController.updateClock(at: date)
        if let report {
            updateStatusItem(with: report, at: date)
        }
    }

    private func updateStatusItem(with report: UsageReport, at date: Date = Date()) {
        let reading = report.snapshot.reading(at: date)
        statusItem?.button?.title = "\(AppConfiguration.menuTitlePrefix) \(reading.usageRemainingPercent)%"
        statusItem?.button?.toolTip =
            "Usage remaining: \(reading.usageRemainingPercent)% · "
            + "Week remaining: \(reading.weekRemainingPercent)%"
        statusItem?.button?.setAccessibilityValue(
            "Usage remaining \(reading.usageRemainingPercent) percent, "
                + "week remaining \(reading.weekRemainingPercent) percent"
        )
    }
}
