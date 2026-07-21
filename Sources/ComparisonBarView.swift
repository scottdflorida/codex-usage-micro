import AppKit

@MainActor
final class ComparisonBarView: NSView {
    private enum Layout {
        static let rowHeight: CGFloat = 17
        static let trackHeight: CGFloat = 10
        static let labelGap: CGFloat = 2.5
        static let markerWidth: CGFloat = 3
    }

    private let weekName = NSTextField(labelWithString: "Week remaining")
    private let weekValue = NSTextField(labelWithString: "—")
    private let usageName = NSTextField(labelWithString: "Usage remaining")
    private let usageValue = NSTextField(labelWithString: "—")

    private var weekFraction = 0.0
    private var usageFraction = 0.0
    private var usageColor = NSColor.systemGray
    private var trackRect = NSRect.zero
    private var showsReading = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        weekName.font = .systemFont(ofSize: 12, weight: .medium)
        usageName.font = .systemFont(ofSize: 12, weight: .bold)
        [weekName, usageName].forEach { label in
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }

        [weekValue, usageValue].forEach { label in
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            label.alignment = .center
            addSubview(label)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Weekly usage comparison")
        setAccessibilityHelp("The colored bar shows usage remaining; the marker shows time remaining.")
        [weekName, weekValue, usageName, usageValue].forEach {
            $0.setAccessibilityElement(false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 62)
    }

    override func layout() {
        super.layout()

        trackRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - Layout.trackHeight / 2,
            width: bounds.width,
            height: Layout.trackHeight
        )

        layoutRow(
            name: usageName,
            value: usageValue,
            fraction: usageFraction,
            y: bounds.maxY - Layout.rowHeight
        )
        layoutRow(
            name: weekName,
            value: weekValue,
            fraction: weekFraction,
            y: bounds.minY
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard trackRect.width > 0 else { return }

        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.height / 2,
            yRadius: trackRect.height / 2
        )
        trackColor.setFill()
        trackPath.fill()
        guard showsReading else { return }

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        usageColor.setFill()
        NSBezierPath(
            rect: NSRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: trackRect.width * usageFraction,
                height: trackRect.height
            )
        ).fill()
        NSGraphicsContext.restoreGraphicsState()

        let rawMarkerX = trackRect.minX + trackRect.width * weekFraction
        let markerX = max(
            trackRect.minX,
            min(trackRect.maxX - Layout.markerWidth, rawMarkerX - Layout.markerWidth / 2)
        )

        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: markerX,
                y: trackRect.minY - 2,
                width: Layout.markerWidth,
                height: trackRect.height + 4
            ),
            xRadius: 1.5,
            yRadius: 1.5
        ).fill()
    }

    func update(reading: UsageReading, color: NSColor) {
        showsReading = true
        weekFraction = reading.weekRemainingFraction.clamped(to: 0...1)
        usageFraction = reading.usageRemainingFraction.clamped(to: 0...1)
        usageColor = color
        weekValue.stringValue = "\(reading.weekRemainingPercent)%"
        usageValue.stringValue = "\(reading.usageRemainingPercent)%"
        setAccessibilityValue(
            "Week remaining \(reading.weekRemainingPercent) percent, "
                + "usage remaining \(reading.usageRemainingPercent) percent"
        )
        needsLayout = true
        needsDisplay = true
    }

    func showUnavailable() {
        showsReading = false
        weekFraction = 0
        usageFraction = 0
        usageColor = .systemGray
        weekValue.stringValue = "—"
        usageValue.stringValue = "—"
        setAccessibilityValue("Usage unavailable")
        needsLayout = true
        needsDisplay = true
    }

    private func layoutRow(
        name: NSTextField,
        value: NSTextField,
        fraction: Double,
        y: CGFloat
    ) {
        name.sizeToFit()
        value.sizeToFit()

        let valueWidth = value.frame.width
        let markerCenter = bounds.minX + bounds.width * fraction
        let valueX = max(
            bounds.minX,
            min(bounds.maxX - valueWidth, markerCenter - valueWidth / 2)
        )
        value.frame = NSRect(x: valueX, y: y, width: valueWidth, height: Layout.rowHeight)

        let nameWidth = name.frame.width
        let nameX: CGFloat
        if fraction > 0.5 {
            name.alignment = .right
            nameX = max(bounds.minX, value.frame.minX - Layout.labelGap - nameWidth)
        } else {
            name.alignment = .left
            nameX = min(bounds.maxX - nameWidth, value.frame.maxX + Layout.labelGap)
        }
        name.frame = NSRect(x: nameX, y: y, width: nameWidth, height: Layout.rowHeight)
    }

    private var trackColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.24)
            : NSColor.black.withAlphaComponent(0.14)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
