import AppKit
import Foundation

@MainActor
final class UsageViewController: NSViewController {
    var onRefresh: (() -> Void)?

    private let comparisonBar = ComparisonBarView()
    private let resetLabel = NSTextField(labelWithString: "Checking \(AppConfiguration.name)…")
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    private var report: UsageReport?

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: AppConfiguration.contentSize))
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader()
        configureFooterControls()

        let footer = NSStackView(views: [resetLabel, NSView(), refreshButton, quitButton])
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY

        let stack = NSStackView(views: [header, comparisonBar, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: AppConfiguration.contentSize.width),
            root.heightAnchor.constraint(equalToConstant: AppConfiguration.contentSize.height),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -13),
        ])

        view = root
    }

    func showLoading() {
        refreshButton.isEnabled = false
        statusLabel.stringValue = "Updating…"
    }

    func show(report: UsageReport, at date: Date = Date()) {
        self.report = report
        refreshButton.isEnabled = true
        statusLabel.stringValue = "Live"
        updateClock(at: date)
    }

    func show(errorMessage: String) {
        report = nil
        refreshButton.isEnabled = true
        statusLabel.stringValue = "Unavailable"
        resetLabel.stringValue = DiagnosticText.sanitized(errorMessage)
        comparisonBar.showUnavailable()
    }

    func updateClock(at date: Date = Date()) {
        guard let snapshot = report?.snapshot else { return }

        let reading = snapshot.reading(at: date)
        comparisonBar.update(reading: reading, color: reading.pace.color)
        resetLabel.stringValue = "Resets \(resetDateFormatter.string(from: snapshot.resetsAt))"
    }

    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: AppConfiguration.popoverTitle)
        title.font = .systemFont(ofSize: 12, weight: .bold)
        title.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right

        let header = NSView()
        [header, title, statusLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        header.addSubview(title)
        header.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 16),
            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    private func configureFooterControls() {
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
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func quitPressed() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit \(AppConfiguration.name)?"
        alert.informativeText =
            "The menu-bar indicator will disappear until you open "
            + "\(AppConfiguration.name) again."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

private extension UsagePace {
    var color: NSColor {
        switch self {
        case .critical: .systemRed
        case .onPace: .systemGreen
        case .behind: .systemOrange
        }
    }
}
