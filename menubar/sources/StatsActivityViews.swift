import AppKit
import Foundation

// MARK: - YearHeatmapView
//
// Full-year GitHub-style contribution graph. 7 weekday rows × up to ~53 week
// columns. Month labels run across the top, weekday labels down the left, and
// a Less→More legend sits bottom-right. Cells are accent-tinted on a smooth
// log ramp (darker = more tokens). Today gets a hairline ring; the selected
// day a stronger one. Hover reports the day under the cursor; click selects it.
//
// No per-cell subviews — the whole grid is one custom-drawn layer, so even a
// 365-cell year renders and scrolls instantly.
final class YearHeatmapView: NSView {
    struct Day { let key: String; let date: Date; let tokens: UInt64 }

    /// newest-first (date "yyyy-MM-dd", tokens) — exactly snap.byDay.
    var values: [(date: String, tokens: UInt64)] = [] {
        didSet { rebuild() }
    }
    /// "yyyy-MM-dd" of the day drawn with the strong selection ring.
    var selectedKey: String? {
        didSet { if oldValue != selectedKey { needsDisplay = true } }
    }
    var onSelectDay: ((Day) -> Void)?
    var onHoverDay: ((Day?) -> Void)?

    private var days: [Day] = []        // newest-first, parsed
    private var grid: [[Day?]] = []     // grid[col][row]; col 0 = oldest week
    private var cols = 0
    private var hoveredKey: String? {
        didSet { if oldValue != hoveredKey { needsDisplay = true } }
    }

    // Gutters reserved around the cell grid for labels + legend.
    private let topGutter: CGFloat = 16
    private let leftGutter: CGFloat = 30
    private let bottomGutter: CGFloat = 22
    private let gap: CGFloat = 3

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 150) }

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L10n.text("Yearly activity heatmap", "Yıllık aktivite ısı haritası"))
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout model

    private func rebuild() {
        let f = Self.isoFmt
        days = values.compactMap { v in
            guard let d = f.date(from: v.date) else { return nil }
            return Day(key: v.date, date: d, tokens: v.tokens)
        }
        guard let newest = days.first else { grid = []; cols = 0; needsDisplay = true; return }
        let newestWeekday = (Self.cal.component(.weekday, from: newest.date) + 5) % 7 // Mon=0..Sun=6
        cols = 1 + ((days.count - 1) + (6 - newestWeekday)) / 7
        var g = Array(repeating: [Day?](repeating: nil, count: 7), count: cols)
        // Newest day sits in the last column, in its true weekday row; older
        // days walk one weekday up per step, wrapping into earlier columns.
        for (i, day) in days.enumerated() {
            let row = ((newestWeekday - i) % 7 + 7) % 7
            let col = cols - 1 - ((i + (6 - newestWeekday)) / 7)
            if col >= 0, col < cols { g[col][row] = day }
        }
        grid = g
        needsDisplay = true
        updateA11y()
    }

    private func updateA11y() {
        let active = days.filter { $0.tokens > 0 }.count
        setAccessibilityValue(L10n.text(
            "\(active) active days in the last year",
            "Son bir yılda \(active) aktif gün"
        ))
    }

    /// (cellSize, originX, originY) for the current bounds, or nil if too small.
    private func metrics() -> (cell: CGFloat, ox: CGFloat, oy: CGFloat)? {
        guard cols > 0 else { return nil }
        let gridW = bounds.width - leftGutter
        let gridH = bounds.height - topGutter - bottomGutter
        let cell = min(
            (gridW - gap * CGFloat(cols - 1)) / CGFloat(cols),
            (gridH - gap * 6) / 7
        )
        guard cell > 2 else { return nil }
        // Center the grid vertically inside the band between the gutters.
        let usedH = cell * 7 + gap * 6
        let oy = topGutter + max(0, (gridH - usedH) / 2)
        return (cell, leftGutter, oy)
    }

    private func cellRect(col: Int, row: Int, _ m: (cell: CGFloat, ox: CGFloat, oy: CGFloat)) -> NSRect {
        NSRect(
            x: m.ox + CGFloat(col) * (m.cell + gap),
            y: m.oy + CGFloat(row) * (m.cell + gap),
            width: m.cell, height: m.cell
        )
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        guard !grid.isEmpty, let m = metrics() else { return }
        let accent = ThemeStore.current.accent
        let maxTok = max(days.map(\.tokens).max() ?? 1, 1)
        let radius = max(2, min(7, m.cell * 0.3))
        let todayKey = days.first?.key

        // Cells.
        for col in 0..<cols {
            for row in 0..<7 {
                guard let day = grid[col][row] else { continue }
                let rect = cellRect(col: col, row: row, m)
                let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                if day.tokens == 0 {
                    NSColor.separatorColor.withAlphaComponent(0.18).setFill()
                    path.fill()
                } else {
                    let norm = log(Double(day.tokens) + 1) / log(Double(maxTok) + 1)
                    accent.withAlphaComponent(0.18 + CGFloat(norm) * 0.72).setFill()
                    path.fill()
                }
                // Hover hint — faint inset before commit.
                if day.key == hoveredKey, day.key != selectedKey {
                    accent.withAlphaComponent(0.9).setStroke()
                    let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: radius + 1, yRadius: radius + 1)
                    ring.lineWidth = 1
                    ring.stroke()
                }
                // Today — hairline outline so the "now" cell always reads.
                if day.key == todayKey, day.key != selectedKey {
                    NSColor.labelColor.withAlphaComponent(0.45).setStroke()
                    let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
                    ring.lineWidth = 1
                    ring.stroke()
                }
                // Selected — strong accent ring.
                if day.key == selectedKey {
                    accent.setStroke()
                    let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), xRadius: radius + 1.5, yRadius: radius + 1.5)
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
            }
        }

        drawWeekdayLabels(m)
        drawMonthLabels(m)
        drawLegend(accent: accent, maxBottom: bounds.height)
    }

    private func labelAttrs(_ alpha: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(alpha),
        ]
    }

    private func drawWeekdayLabels(_ m: (cell: CGFloat, ox: CGFloat, oy: CGFloat)) {
        let names = L10n.lang == .tr
            ? ["Pzt", "", "Çar", "", "Cum", "", ""]
            : ["Mon", "", "Wed", "", "Fri", "", ""]
        for row in [0, 2, 4] {
            let s = NSAttributedString(string: names[row], attributes: labelAttrs())
            let r = cellRect(col: 0, row: row, m)
            let size = s.size()
            s.draw(at: NSPoint(x: max(0, m.ox - size.width - 6), y: r.midY - size.height / 2))
        }
    }

    private func drawMonthLabels(_ m: (cell: CGFloat, ox: CGFloat, oy: CGFloat)) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        fmt.dateFormat = "MMM"
        var lastMonth = -1
        for col in 0..<cols {
            // Representative date = topmost present cell in the column.
            guard let rep = grid[col].compactMap({ $0 }).first else { continue }
            let month = Self.cal.component(.month, from: rep.date)
            if month != lastMonth {
                lastMonth = month
                let s = NSAttributedString(string: fmt.string(from: rep.date), attributes: labelAttrs())
                let x = m.ox + CGFloat(col) * (m.cell + gap)
                s.draw(at: NSPoint(x: x, y: max(0, m.oy - 14)))
            }
        }
    }

    private func drawLegend(accent: NSColor, maxBottom: CGFloat) {
        let sw: CGFloat = 9, sgap: CGFloat = 3
        let levels: [CGFloat] = [0.18, 0.36, 0.54, 0.72, 0.9]
        let y = bounds.height - bottomGutter + 4
        let less = NSAttributedString(string: L10n.text("Less", "Az"), attributes: labelAttrs())
        let more = NSAttributedString(string: L10n.text("More", "Çok"), attributes: labelAttrs())
        let swatchesW = CGFloat(levels.count) * sw + CGFloat(levels.count - 1) * sgap
        let totalW = less.size().width + 6 + swatchesW + 6 + more.size().width
        var x = bounds.width - totalW
        let lsize = less.size()
        less.draw(at: NSPoint(x: x, y: y + (sw - lsize.height) / 2))
        x += lsize.width + 6
        for lvl in levels {
            let rect = NSRect(x: x, y: y, width: sw, height: sw)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
            accent.withAlphaComponent(lvl).setFill()
            path.fill()
            x += sw + sgap
        }
        x += 6
        more.draw(at: NSPoint(x: x, y: y + (sw - more.size().height) / 2))
    }

    // MARK: Hit testing + hover

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    private func day(at p: NSPoint) -> Day? {
        guard let m = metrics() else { return nil }
        for col in 0..<cols {
            for row in 0..<7 {
                guard let day = grid[col][row] else { continue }
                if cellRect(col: col, row: row, m).insetBy(dx: -gap / 2, dy: -gap / 2).contains(p) {
                    return day
                }
            }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let d = day(at: convert(event.locationInWindow, from: nil))
        hoveredKey = d?.key
        onHoverDay?(d)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredKey = nil
        onHoverDay?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        if let d = day(at: convert(event.locationInWindow, from: nil)) {
            onSelectDay?(d)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - ProjectBreakdownView
//
// Horizontal "which project ate what" bars for a selected day or range.
// Each row: project name (left) · accent bar (share of the visible total) ·
// tokens + cost (right). Custom-drawn, no per-row subviews.
final class ProjectBreakdownView: NSView {
    struct Row {
        let name: String
        let tokens: UInt64
        let cost: Double
        let share: Double // 0…1 of the largest row
    }

    var rows: [Row] = [] {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    private let rowH: CGFloat = 38
    private let barH: CGFloat = 6

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(1, CGFloat(rows.count) * rowH))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }
        let accent = ThemeStore.current.accent
        let w = bounds.width

        for (i, row) in rows.enumerated() {
            let y = CGFloat(i) * rowH

            let value = "\(ContextSnapshot.formatTokens(row.tokens)) · \(ContextSnapshot.formatUSD(row.cost))"
            let valAttr = NSAttributedString(string: value, attributes: [
                .font: Typography.bodyMono(11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let valSize = valAttr.size()
            valAttr.draw(at: NSPoint(x: w - valSize.width, y: y + 3))

            let nameAttr = NSAttributedString(string: row.name, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])
            let nameMax = w - valSize.width - 12
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingMiddle
            let nameTrunc = NSAttributedString(string: row.name, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ])
            nameTrunc.draw(in: NSRect(x: 0, y: y + 2, width: max(20, nameMax), height: 16))
            _ = nameAttr

            // Bar track + accent fill.
            let by = y + 22
            let track = NSBezierPath(roundedRect: NSRect(x: 0, y: by, width: w, height: barH), xRadius: barH / 2, yRadius: barH / 2)
            NSColor.separatorColor.withAlphaComponent(0.22).setFill()
            track.fill()

            let fillW = max(barH, w * CGFloat(min(1, max(0, row.share))))
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: by, width: fillW, height: barH), xRadius: barH / 2, yRadius: barH / 2)
            accent.withAlphaComponent(0.9).setFill()
            fill.fill()
        }
    }
}

// MARK: - TokenCompositionView
//
// One continuous rounded bar split by token category (Input · Output ·
// Cache-read), with a colored-dot legend below. Answers "where do the
// tokens actually go" at a glance — cache-read usually dwarfs the rest.
final class TokenCompositionView: NSView {
    struct Segment { let label: String; let value: UInt64; let color: NSColor }
    var segments: [Segment] = [] {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    private let barH: CGFloat = 12
    private let legendTop: CGFloat = 22
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 42) }

    override func draw(_ dirtyRect: NSRect) {
        let total = segments.reduce(0.0) { $0 + Double($1.value) }
        let w = bounds.width
        let barRect = NSRect(x: 0, y: 0, width: w, height: barH)
        let clip = NSBezierPath(roundedRect: barRect, xRadius: barH / 2, yRadius: barH / 2)

        // Track (empty state too).
        NSColor.separatorColor.withAlphaComponent(0.22).setFill()
        clip.fill()

        if total > 0 {
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            var x: CGFloat = 0
            for seg in segments where seg.value > 0 {
                let segW = w * CGFloat(Double(seg.value) / total)
                seg.color.setFill()
                NSBezierPath(rect: NSRect(x: x, y: 0, width: segW + 0.5, height: barH)).fill()
                x += segW
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // Legend.
        var lx: CGFloat = 0
        let ly = legendTop
        let dot: CGFloat = 7
        for seg in segments {
            let pct = total > 0 ? Int((Double(seg.value) / total * 100).rounded()) : 0
            let circle = NSBezierPath(ovalIn: NSRect(x: lx, y: ly + 2, width: dot, height: dot))
            seg.color.setFill()
            circle.fill()
            lx += dot + 5
            let text = "\(seg.label)  \(pct)%"
            let attr = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            attr.draw(at: NSPoint(x: lx, y: ly))
            lx += attr.size().width + 16
        }
    }
}

// MARK: - SessionListView
//
// The individual sessions behind a selected day/range: start time + duration
// on the left, model · project beneath, tokens · cost on the right. Hairline
// between rows. Custom-drawn, no per-row subviews.
final class SessionListView: NSView {
    struct Row {
        let time: String
        let duration: String
        let detail: String // model · project
        let tokens: UInt64
        let cost: Double
    }

    var rows: [Row] = [] {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    private let rowH: CGFloat = 42
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(1, CGFloat(rows.count) * rowH))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }
        let w = bounds.width
        for (i, row) in rows.enumerated() {
            let y = CGFloat(i) * rowH
            if i > 0 {
                NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 0, y: y))
                line.line(to: NSPoint(x: w, y: y))
                line.lineWidth = 0.5
                line.stroke()
            }

            let value = "\(ContextSnapshot.formatTokens(row.tokens)) · \(ContextSnapshot.formatUSD(row.cost))"
            let valAttr = NSAttributedString(string: value, attributes: [
                .font: Typography.bodyMono(11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let vs = valAttr.size()
            valAttr.draw(at: NSPoint(x: w - vs.width, y: y + 8))

            let head = NSMutableAttributedString(string: row.time, attributes: [
                .font: Typography.bodyMono(12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ])
            if !row.duration.isEmpty {
                head.append(NSAttributedString(string: "  \(row.duration)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            }
            head.draw(at: NSPoint(x: 0, y: y + 6))

            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            let det = NSAttributedString(string: row.detail, attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: para,
            ])
            det.draw(in: NSRect(x: 0, y: y + 23, width: max(20, w - vs.width - 12), height: 14))
        }
    }
}

// MARK: - InsightCardView
//
// One narrative insight: a tinted SF-Symbol chip + a headline (the metric,
// with the number emphasised) + a plain-language detail line.
final class InsightCardView: NSView {
    init(symbol: String, tint: NSColor, headline: NSAttributedString, detail: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.cornerCurve = .continuous
        chip.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = tint
        icon.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(icon)

        let head = NSTextField(labelWithAttributedString: headline)
        head.lineBreakMode = .byWordWrapping
        head.maximumNumberOfLines = 0
        head.translatesAutoresizingMaskIntoConstraints = false

        let det = NSTextField(wrappingLabelWithString: detail)
        det.font = NSFont.systemFont(ofSize: 11)
        det.textColor = .secondaryLabelColor
        det.maximumNumberOfLines = 0
        det.translatesAutoresizingMaskIntoConstraints = false

        let textCol = NSStackView(views: [head, det])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        textCol.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chip)
        addSubview(textCol)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: leadingAnchor),
            chip.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            chip.widthAnchor.constraint(equalToConstant: 30),
            chip.heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            textCol.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 10),
            textCol.trailingAnchor.constraint(equalTo: trailingAnchor),
            textCol.topAnchor.constraint(equalTo: topAnchor),
            textCol.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(headline.string)
    }
    required init?(coder: NSCoder) { fatalError() }
}
