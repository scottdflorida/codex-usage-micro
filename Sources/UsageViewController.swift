import AppKit
import Foundation

@MainActor
final class UsageViewController: NSViewController {
    var onRefresh: (() -> Void)?
    var onContentSizeChange: ((NSSize) -> Void)?

    private let fiveHourBar = ComparisonBarView(
        timeLabel: "5-hour time remaining",
        usageLabel: "5-hour usage remaining",
        accessibilityLabel: "Five-hour limit"
    )
    private let weeklyBar = ComparisonBarView(
        timeLabel: "Week remaining",
        usageLabel: "Weekly usage remaining",
        accessibilityLabel: "Weekly limit"
    )
    private let contentStack = NSStackView()
    private let fiveHourSection = NSStackView()
    private let fiveHourResetRow = NSView()
    private let sectionDivider = SectionDividerView()
    private let fiveHourResetLabel = NSTextField(labelWithString: "5-hour reset: —")
    private let footerResetLabel = NSTextField(labelWithString: "Weekly reset: —")
    private let errorRow = NSView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private lazy var headerView = makeHeader()
    private lazy var footerView = makeFooter()

    private let fiveHourResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter
    }()
    private let weeklyResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Ejm")
        return formatter
    }()

    private struct ModelRow {
        let limitId: String
        let displayName: String
        let spansWeek: Bool
        let divider: SectionDividerView
        let bar: ComparisonBarView
    }

    private var report: UsageReport?
    private var modelRows: [ModelRow] = []
    private var rootHeightConstraint: NSLayoutConstraint?

    override func loadView() {
        let contentSize = AppConfiguration.compactContentSize
        let root = NSView(frame: NSRect(origin: .zero, size: contentSize))
        root.translatesAutoresizingMaskIntoConstraints = false

        configureResetLabels()
        configureButton(refreshButton, action: #selector(refreshPressed))
        configureButton(quitButton, action: #selector(quitPressed))

        configureResetRow(fiveHourResetRow, label: fiveHourResetLabel)
        configureErrorRow()
        fiveHourSection.orientation = .vertical
        fiveHourSection.alignment = .width
        fiveHourSection.spacing = 0
        fiveHourSection.detachesHiddenViews = true
        fiveHourSection.addArrangedSubview(fiveHourBar)
        fiveHourSection.addArrangedSubview(fiveHourResetRow)
        fiveHourSection.addArrangedSubview(sectionDivider)
        fiveHourSection.setCustomSpacing(3, after: fiveHourBar)
        fiveHourSection.setCustomSpacing(7, after: fiveHourResetRow)

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 7
        contentStack.detachesHiddenViews = true
        replaceArrangedSubviews(
            in: contentStack,
            with: [headerView, weeklyBar, footerView]
        )
        contentStack.setCustomSpacing(3, after: weeklyBar)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        let rootHeightConstraint = root.heightAnchor.constraint(equalToConstant: contentSize.height)
        self.rootHeightConstraint = rootHeightConstraint
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: contentSize.width),
            rootHeightConstraint,
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -3),
        ])

        preferredContentSize = contentSize
        view = root
    }

    func showLoading() {
        _ = view
        refreshButton.isEnabled = false
        setStatus("Updating…")
    }

    func show(
        report: UsageReport,
        at date: Date = Date(),
        status: UsagePresentationStatus = .live
    ) {
        _ = view
        self.report = report
        showUsagePresentation(
            fiveHourAvailable: report.fiveHour != nil,
            weeklyAvailable: report.weekly != nil,
            models: report.models
        )
        refreshButton.isEnabled = true
        setStatus(status.label, diagnostic: status.diagnostic)
        updateClock(at: date)
    }

    func show(errorMessage: String) {
        _ = view
        report = nil
        showErrorPresentation()
        refreshButton.isEnabled = true
        fiveHourBar.showUnavailable()
        weeklyBar.showUnavailable()

        fiveHourResetLabel.stringValue = "5-hour reset: —"
        footerResetLabel.stringValue = ""

        let diagnostic = DiagnosticText.sanitized(errorMessage)
        errorLabel.stringValue = diagnostic
        errorLabel.toolTip = diagnostic
        errorLabel.setAccessibilityValue(diagnostic)
        setStatus("Unavailable", diagnostic: diagnostic)
    }

    func updateClock(at date: Date = Date()) {
        guard let report else { return }

        if let fiveHour = report.fiveHour {
            let reading = fiveHour.reading(at: date)
            fiveHourBar.update(reading: reading, color: reading.pace.color)
            fiveHourResetLabel.stringValue =
                "5-hour reset: \(fiveHourResetFormatter.string(from: fiveHour.resetsAt))"
        } else {
            fiveHourBar.showUnavailable()
            fiveHourResetLabel.stringValue = "5-hour reset: —"
        }

        if let weekly = report.weekly {
            let reading = weekly.reading(at: date)
            weeklyBar.update(reading: reading, color: reading.pace.color)
            footerResetLabel.stringValue =
                "Weekly reset: \(weeklyResetFormatter.string(from: weekly.resetsAt))"
        } else {
            weeklyBar.showUnavailable()
            if let fiveHour = report.fiveHour {
                footerResetLabel.stringValue =
                    "5-hour reset: \(fiveHourResetFormatter.string(from: fiveHour.resetsAt))"
            } else {
                footerResetLabel.stringValue = ""
            }
        }

        for (row, model) in zip(modelRows, report.models) {
            let reading = model.snapshot.reading(at: date)
            row.bar.update(reading: reading, color: reading.pace.color)
        }
    }

    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: AppConfiguration.popoverTitle)
        title.font = .systemFont(ofSize: 12, weight: .bold)
        title.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        statusLabel.setAccessibilityLabel("Usage status")

        let header = NSView()
        for view in [header, title, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
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

    private func makeFooter() -> NSStackView {
        let footer = NSStackView(
            views: [footerResetLabel, NSView(), refreshButton, quitButton]
        )
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        return footer
    }

    private func configureResetLabels() {
        for label in [fiveHourResetLabel, footerResetLabel] {
            label.font = .systemFont(ofSize: 10.5, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .left
        }
    }

    private func configureResetRow(_ row: NSView, label: NSTextField) {
        row.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
        ])
    }

    private func configureErrorRow() {
        errorRow.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.setAccessibilityLabel("Usage error")
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorRow.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            errorRow.heightAnchor.constraint(equalToConstant: 14),
            errorLabel.leadingAnchor.constraint(equalTo: errorRow.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: errorRow.trailingAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorRow.centerYAnchor),
        ])
    }

    private func configureButton(_ button: NSButton, action: Selector) {
        button.bezelStyle = .inline
        button.controlSize = .small
        button.target = self
        button.action = action
    }

    private func showUsagePresentation(
        fiveHourAvailable: Bool,
        weeklyAvailable: Bool,
        models: [ModelUsage]
    ) {
        let showsBothWindows = fiveHourAvailable && weeklyAvailable
        footerResetLabel.isHidden = false

        rebuildModelRowsIfNeeded(for: models)
        let modelViews: [NSView] = modelRows.flatMap { [$0.divider, $0.bar] }

        replaceArrangedSubviews(in: contentStack, with: [])
        let lastMainBar: ComparisonBarView
        if showsBothWindows {
            replaceArrangedSubviews(
                in: fiveHourSection,
                with: [fiveHourBar, fiveHourResetRow, sectionDivider]
            )
            fiveHourSection.setCustomSpacing(3, after: fiveHourBar)
            fiveHourSection.setCustomSpacing(7, after: fiveHourResetRow)
            replaceArrangedSubviews(
                in: contentStack,
                with: [headerView, fiveHourSection, weeklyBar] + modelViews + [footerView]
            )
            contentStack.setCustomSpacing(8, after: fiveHourSection)
            lastMainBar = weeklyBar
        } else if fiveHourAvailable {
            replaceArrangedSubviews(in: fiveHourSection, with: [])
            replaceArrangedSubviews(
                in: contentStack,
                with: [headerView, fiveHourBar] + modelViews + [footerView]
            )
            lastMainBar = fiveHourBar
        } else {
            replaceArrangedSubviews(in: fiveHourSection, with: [])
            replaceArrangedSubviews(
                in: contentStack,
                with: [headerView, weeklyBar] + modelViews + [footerView]
            )
            lastMainBar = weeklyBar
        }

        // The tight footer gap follows the last bar; the reused main bar must not keep
        // it when model rows are appended after a presentation that had none.
        if let lastModelBar = modelRows.last?.bar {
            contentStack.setCustomSpacing(7, after: lastMainBar)
            contentStack.setCustomSpacing(3, after: lastModelBar)
        } else {
            contentStack.setCustomSpacing(3, after: lastMainBar)
        }

        let contentSize = AppConfiguration.contentSize(
            fiveHourAvailable: fiveHourAvailable,
            weeklyAvailable: weeklyAvailable,
            modelCount: models.count
        )
        setContentSize(contentSize)
    }

    private func rebuildModelRowsIfNeeded(for models: [ModelUsage]) {
        // A routine refresh reuses the existing rows so updateClock adjusts their readings
        // in place, matching the five-hour and weekly bars.
        let matchesExistingRows = modelRows.elementsEqual(models) { row, model in
            row.limitId == model.limitId
                && row.displayName == model.displayName
                && row.spansWeek == model.snapshot.spansWeek
        }
        guard !matchesExistingRows else { return }

        modelRows = models.map { model in
            ModelRow(
                limitId: model.limitId,
                displayName: model.displayName,
                spansWeek: model.snapshot.spansWeek,
                divider: SectionDividerView(),
                bar: ComparisonBarView(
                    timeLabel: model.snapshot.spansWeek ? "Week remaining" : "Time remaining",
                    usageLabel: model.displayName,
                    accessibilityLabel: "\(model.displayName) limit"
                )
            )
        }
    }

    private func showErrorPresentation() {
        footerResetLabel.isHidden = true
        modelRows = []
        replaceArrangedSubviews(in: contentStack, with: [])
        replaceArrangedSubviews(in: fiveHourSection, with: [])
        replaceArrangedSubviews(
            in: contentStack,
            with: [headerView, errorRow, footerView]
        )
        contentStack.setCustomSpacing(3, after: errorRow)
        setContentSize(AppConfiguration.errorContentSize)
    }

    private func replaceArrangedSubviews(
        in stack: NSStackView,
        with views: [NSView]
    ) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            stack.addArrangedSubview(view)
        }
    }

    private func setContentSize(_ contentSize: NSSize) {
        rootHeightConstraint?.constant = contentSize.height
        guard preferredContentSize != contentSize else { return }

        preferredContentSize = contentSize
        onContentSizeChange?(contentSize)
    }

    private func setStatus(_ value: String, diagnostic: String? = nil) {
        statusLabel.stringValue = value
        statusLabel.toolTip = diagnostic
        statusLabel.setAccessibilityValue(
            diagnostic.map { "\(value). \($0)" } ?? value
        )
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

enum UsagePresentationStatus: Equatable {
    case live
    case stale(String)

    var label: String {
        switch self {
        case .live: "Live"
        case .stale: "Stale"
        }
    }

    var diagnostic: String? {
        switch self {
        case .live: nil
        case .stale(let diagnostic): diagnostic
        }
    }
}
