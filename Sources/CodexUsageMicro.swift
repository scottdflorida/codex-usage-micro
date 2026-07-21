import AppKit
import Foundation

private enum ProviderConfig {
    struct RowLabels {
        let time: String
        let usage: String
    }

    static let appName = "Codex Usage Micro"
    static let title = "CODEX WEEKLY USAGE"
    static let menuPrefix = "Cx"
    static let toolTip = "Codex weekly usage"
    static let refreshInterval = RefreshConfiguration.minutes * 60
    static let contentSize = NSSize(width: 300, height: 150)
    static let statusLimitIndex = 0
    static let rows = [RowLabels(time: "Week remaining", usage: "Usage remaining")]
}

private struct UsageSnapshot: Sendable {
    let usedPercent: Int
    let windowDurationMinutes: Int
    let resetsAt: Date

    var usageRemainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }

    func weekRemaining(at date: Date = Date()) -> Double {
        let duration = Double(windowDurationMinutes) * 60
        guard duration > 0 else { return 0 }
        return max(0, min(1, resetsAt.timeIntervalSince(date) / duration))
    }
}

private struct UsageReport: Sendable {
    let limits: [UsageSnapshot]
}

private enum CodexClientError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case timedOut
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Codex is not installed"
        case .launchFailed(let message):
            return "Could not start Codex: \(message)"
        case .timedOut:
            return "Codex did not respond"
        case .invalidResponse:
            return "Codex returned an unfamiliar response"
        case .server(let message):
            return message
        }
    }
}

private final class RPCState: @unchecked Sendable {
    let lock = NSLock()
    let completed = DispatchSemaphore(value: 0)
    var buffer = Data()
    var response: [String: Any]?
    var error: Error?
    var sentReadRequest = false
}

private final class CodexClient: @unchecked Sendable {
    func fetch(completion: @escaping @Sendable (Result<UsageReport, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(self.fetchSynchronously())
        }
    }

    func fetchSynchronously() -> Result<UsageReport, Error> {
        guard let executable = Self.findCodexExecutable() else {
            return .failure(CodexClientError.executableNotFound)
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let state = RPCState()

        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            state.lock.lock()
            state.buffer.append(data)

            while let newline = state.buffer.firstIndex(of: 0x0A) {
                let line = state.buffer[..<newline]
                state.buffer.removeSubrange(...newline)

                guard
                    !line.isEmpty,
                    let object = try? JSONSerialization.jsonObject(with: Data(line)),
                    let message = object as? [String: Any]
                else { continue }

                let id = (message["id"] as? NSNumber)?.intValue

                if id == 1, !state.sentReadRequest {
                    state.sentReadRequest = true
                    do {
                        try Self.writeJSON(
                            ["id": 2, "method": "account/rateLimits/read", "params": NSNull()],
                            to: input.fileHandleForWriting
                        )
                    } catch {
                        state.error = error
                        state.completed.signal()
                    }
                } else if id == 2 {
                    state.response = message
                    state.completed.signal()
                }
            }
            state.lock.unlock()
        }

        do {
            try process.run()
            try Self.writeJSON(
                [
                    "id": 1,
                    "method": "initialize",
                    "params": [
                        "clientInfo": ["name": "codex-usage-micro", "version": "0.1.0"],
                        "capabilities": ["experimentalApi": true]
                    ]
                ],
                to: input.fileHandleForWriting
            )
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            return .failure(CodexClientError.launchFailed(error.localizedDescription))
        }

        let waitResult = state.completed.wait(timeout: .now() + 12)

        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()

        if waitResult == .timedOut {
            return .failure(CodexClientError.timedOut)
        }

        state.lock.lock()
        let response = state.response
        let stateError = state.error
        state.lock.unlock()

        if let stateError { return .failure(stateError) }
        guard let response else { return .failure(CodexClientError.invalidResponse) }

        if
            let error = response["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            return .failure(CodexClientError.server(message))
        }

        guard let snapshot = Self.parseSnapshot(response) else {
            return .failure(CodexClientError.invalidResponse)
        }
        return .success(UsageReport(limits: [snapshot]))
    }

    private static func parseSnapshot(_ response: [String: Any]) -> UsageSnapshot? {
        guard let result = response["result"] as? [String: Any] else { return nil }

        let preferred: [String: Any]?
        if
            let byID = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = byID["codex"] as? [String: Any]
        {
            preferred = codex
        } else {
            preferred = result["rateLimits"] as? [String: Any]
        }

        guard
            let limits = preferred,
            let primary = limits["primary"] as? [String: Any],
            let used = (primary["usedPercent"] as? NSNumber)?.intValue,
            let duration = (primary["windowDurationMins"] as? NSNumber)?.intValue,
            let resetTimestamp = (primary["resetsAt"] as? NSNumber)?.doubleValue
        else { return nil }

        return UsageSnapshot(
            usedPercent: used,
            windowDurationMinutes: duration,
            resetsAt: Date(timeIntervalSince1970: resetTimestamp)
        )
    }

    private static func writeJSON(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func findCodexExecutable() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        for directory in pathEntries {
            let path = URL(fileURLWithPath: directory)
                .appendingPathComponent("codex")
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}


private final class ComparisonBarView: NSView {
    private let weekName = NSTextField(labelWithString: "Week remaining")
    private let weekValue = NSTextField(labelWithString: "—")
    private let usageName = NSTextField(labelWithString: "Usage remaining")
    private let usageValue = NSTextField(labelWithString: "—")

    private var weekFraction = 0.0
    private var usageFraction = 0.0
    private var usageColor = NSColor.systemGray
    private var trackRect: NSRect = .zero

    init(timeLabel: String, usageLabel: String) {
        super.init(frame: .zero)
        weekName.stringValue = timeLabel
        usageName.stringValue = usageLabel
        translatesAutoresizingMaskIntoConstraints = false

        weekName.font = .systemFont(ofSize: 12, weight: .medium)
        usageName.font = .systemFont(ofSize: 12, weight: .bold)
        for label in [weekName, usageName] {
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }

        for label in [weekValue, usageValue] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            label.alignment = .center
            addSubview(label)
        }

        setAccessibilityElement(true)
        setAccessibilityLabel("Weekly usage comparison")
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 62)
    }

    override func layout() {
        super.layout()

        let rowHeight: CGFloat = 17
        let trackHeight: CGFloat = 10
        trackRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - trackHeight / 2,
            width: bounds.width,
            height: trackHeight
        )

        layoutRow(
            name: usageName,
            value: usageValue,
            fraction: usageFraction,
            y: bounds.maxY - rowHeight,
            rowHeight: rowHeight
        )
        layoutRow(
            name: weekName,
            value: weekValue,
            fraction: weekFraction,
            y: bounds.minY,
            rowHeight: rowHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard trackRect.width > 0 else { return }

        let radius = trackRect.height / 2
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let trackColor = isDark
            ? NSColor.white.withAlphaComponent(0.24)
            : NSColor.black.withAlphaComponent(0.14)
        trackColor.setFill()
        trackPath.fill()

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        let fillWidth = trackRect.width * max(0, min(1, usageFraction))
        usageColor.setFill()
        NSBezierPath(rect: NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: fillWidth,
            height: trackRect.height
        )).fill()
        NSGraphicsContext.restoreGraphicsState()

        let markerWidth: CGFloat = 3
        let rawMarkerX = trackRect.minX + trackRect.width * max(0, min(1, weekFraction))
        let markerX = max(trackRect.minX, min(trackRect.maxX - markerWidth, rawMarkerX - markerWidth / 2))
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: NSRect(
            x: markerX,
            y: trackRect.minY - 2,
            width: markerWidth,
            height: trackRect.height + 4
        ), xRadius: 1.5, yRadius: 1.5).fill()
    }

    func update(
        weekPercent: Int,
        weekFraction: Double,
        usagePercent: Int,
        usageFraction: Double,
        color: NSColor
    ) {
        self.weekFraction = max(0, min(1, weekFraction))
        self.usageFraction = max(0, min(1, usageFraction))
        usageColor = color
        weekValue.stringValue = "\(weekPercent)%"
        usageValue.stringValue = "\(usagePercent)%"
        setAccessibilityValue("Week remaining \(weekPercent) percent, usage remaining \(usagePercent) percent")
        needsLayout = true
        needsDisplay = true
    }

    private func layoutRow(
        name: NSTextField,
        value: NSTextField,
        fraction: Double,
        y: CGFloat,
        rowHeight: CGFloat
    ) {
        name.sizeToFit()
        value.sizeToFit()
        let valueWidth = value.frame.width
        let markerCenter = bounds.minX + bounds.width * max(0, min(1, fraction))
        let valueX = max(bounds.minX, min(bounds.maxX - valueWidth, markerCenter - valueWidth / 2))

        value.frame = NSRect(x: valueX, y: y, width: valueWidth, height: rowHeight)

        let nameWidth = name.frame.width
        let gap: CGFloat = 2.5
        let placeNameOnLeft = fraction > 0.5
        let nameX: CGFloat
        if placeNameOnLeft {
            name.alignment = .right
            nameX = max(bounds.minX, value.frame.minX - gap - nameWidth)
        } else {
            name.alignment = .left
            nameX = min(bounds.maxX - nameWidth, value.frame.maxX + gap)
        }
        name.frame = NSRect(x: nameX, y: y, width: nameWidth, height: rowHeight)
    }
}

private final class SectionDividerView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 9)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.12)
        color.setFill()
        NSBezierPath(rect: NSRect(
            x: bounds.minX,
            y: floor(bounds.midY),
            width: bounds.width,
            height: 1
        )).fill()
    }
}

private final class UsageViewController: NSViewController {
    private let comparisonBars = ProviderConfig.rows.map {
        ComparisonBarView(timeLabel: $0.time, usageLabel: $0.usage)
    }
    private let resetLabel = NSTextField(labelWithString: "Checking \(ProviderConfig.appName)…")
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private var report: UsageReport?

    var onRefresh: (() -> Void)?

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: ProviderConfig.contentSize))
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: ProviderConfig.title)
        title.font = .systemFont(ofSize: 12, weight: .bold)
        title.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        header.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 16),
            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        resetLabel.font = .systemFont(ofSize: 11)
        resetLabel.textColor = .secondaryLabelColor

        refreshButton.bezelStyle = .inline
        refreshButton.controlSize = .small
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)

        quitButton.bezelStyle = .inline
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(quitPressed)

        let spacer = NSView()
        let footer = NSStackView(views: [resetLabel, spacer, refreshButton, quitButton])
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY

        let stackViews: [NSView] = [header] + comparisonBars + [footer]
        let stack = NSStackView(views: stackViews)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let bottomInset: CGFloat = 13
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: ProviderConfig.contentSize.width),
            root.heightAnchor.constraint(equalToConstant: ProviderConfig.contentSize.height),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -bottomInset)
        ])

        view = root
    }

    func showLoading() {
        refreshButton.isEnabled = false
        statusLabel.stringValue = "Updating…"
    }

    func show(report: UsageReport) {
        self.report = report
        refreshButton.isEnabled = true
        statusLabel.stringValue = "Live"
        updateClock()
    }

    func show(error: Error) {
        report = nil
        refreshButton.isEnabled = true
        statusLabel.stringValue = "Unavailable"
        resetLabel.stringValue = error.localizedDescription
        for bar in comparisonBars {
            bar.update(
                weekPercent: 0,
                weekFraction: 0,
                usagePercent: 0,
                usageFraction: 0,
                color: .systemGray
            )
        }
    }

    func updateClock(at date: Date = Date()) {
        guard let report else { return }

        for (bar, snapshot) in zip(comparisonBars, report.limits) {
            let timeFraction = snapshot.weekRemaining(at: date)
            let timePercent = Int((timeFraction * 100).rounded())
            let usagePercent = snapshot.usageRemainingPercent
            let usageFraction = Double(usagePercent) / 100

            let usageColor: NSColor
            if usagePercent < 15 {
                usageColor = .systemRed
            } else if usagePercent >= timePercent {
                usageColor = .systemGreen
            } else {
                usageColor = .systemOrange
            }
            bar.update(
                weekPercent: timePercent,
                weekFraction: timeFraction,
                usagePercent: usagePercent,
                usageFraction: usageFraction,
                color: usageColor
            )
        }

        if let snapshot = report.limits.first {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE h:mm a"
            resetLabel.stringValue = "Resets \(formatter.string(from: snapshot.resetsAt))"
        }
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func quitPressed() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit \(ProviderConfig.appName)?"
        alert.informativeText = "The menu-bar indicator will disappear until you open \(ProviderConfig.appName) again."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, @unchecked Sendable {
    private let client = CodexClient()
    private let viewController = UsageViewController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var report: UsageReport?
    private var usageTimer: Timer?
    private var clockTimer: Timer?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = ProviderConfig.contentSize
        popover.contentViewController = viewController

        viewController.onRefresh = { [weak self] in self?.refresh() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "\(ProviderConfig.menuPrefix) —"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = ProviderConfig.toolTip
        }

        refresh()
        usageTimer = Timer.scheduledTimer(withTimeInterval: ProviderConfig.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startClickOutsideMonitors()
            refresh()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopClickOutsideMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopClickOutsideMonitors()
    }

    private func refresh() {
        viewController.showLoading()
        client.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let report):
                    self.report = report
                    self.viewController.show(report: report)
                    self.updateStatusItem(report: report)
                case .failure(let error):
                    self.report = nil
                    self.viewController.show(error: error)
                    self.statusItem.button?.title = "\(ProviderConfig.menuPrefix) !"
                    self.statusItem.button?.toolTip = error.localizedDescription
                }
            }
        }
    }

    private func tick() {
        viewController.updateClock()
        if let report { updateStatusItem(report: report) }
    }

    private func updateStatusItem(report: UsageReport) {
        guard report.limits.indices.contains(ProviderConfig.statusLimitIndex) else { return }
        let snapshot = report.limits[ProviderConfig.statusLimitIndex]
        let week = Int((snapshot.weekRemaining() * 100).rounded())
        let usage = snapshot.usageRemainingPercent
        statusItem.button?.title = "\(ProviderConfig.menuPrefix) \(usage)%"
        statusItem.button?.toolTip = "Week remaining: \(week)% · Usage remaining: \(usage)%"
    }

    private func startClickOutsideMonitors() {
        guard localClickMonitor == nil, globalClickMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem.button?.window
            if event.window !== popoverWindow && event.window !== statusWindow {
                self.popover.performClose(nil)
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopClickOutsideMonitors() {
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}

@main
private enum UsageMicroMain {
    static func main() {
        if CommandLine.arguments.contains("--snapshot") {
            let result: Result<UsageReport, Error>
            result = CodexClient().fetchSynchronously()
            switch result {
            case .success(let report):
                for (index, snapshot) in report.limits.enumerated() {
                    let time = Int((snapshot.weekRemaining() * 100).rounded())
                    print("limit_\(index)_time_remaining=\(time)")
                    print("limit_\(index)_usage_remaining=\(snapshot.usageRemainingPercent)")
                    print("limit_\(index)_resets_at=\(Int(snapshot.resetsAt.timeIntervalSince1970))")
                }
                exit(EXIT_SUCCESS)
            case .failure(let error):
                fputs("\(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
