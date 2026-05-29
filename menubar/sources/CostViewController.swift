import AppKit
import Foundation

/// Cost pane — replicates `better-ccusage daily --instances`: per (day ×
/// project) token + estimated-cost breakdown, read from the same
/// ~/.context-bar/context.json the other panes use.
///
/// Costs are ESTIMATES. Subscription users aren't billed per token; these show
/// what the metered API would charge, priced per turn from the LiteLLM rate
/// table (the same source ccusage uses) and summed. Fields consumed from each
/// `claude` / `codex` AgentBlock written by src/usage_signal.py:
///   - by_day_project: [{date, project, models, input, output,
///                       cache_creation, cache_read, tokens, cost, sessions}]
///   - cost_today / cost_7d / total_cost_30d
///   - total_input_30d / total_output_30d
///   - pricing_source / pricing_is_estimate (snapshot-level)
final class CostViewController: PreferencePaneViewController {
    enum Range: Int { case last7 = 0, last30 = 1 }
    enum Provider: Int { case claude = 0, codex = 1 }
    private var range: Range = .last30
    private var provider: Provider = .claude

    private let providerControl = NSSegmentedControl()
    private let rangeControl = NSSegmentedControl()
    private let tilesStack = NSStackView()
    private let projectionLabel = NSTextField(labelWithString: "")
    private let savingsLabel = NSTextField(labelWithString: "")
    private let sparkHost = NSView()
    private let instancesStack = NSStackView()
    private let footnote = NSTextField(labelWithString: "")

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reload()
    }

    private func buildUI() {
        providerControl.segmentStyle = .texturedRounded
        providerControl.segmentCount = 2
        providerControl.setLabel("Claude", forSegment: 0)
        providerControl.setLabel("Codex", forSegment: 1)
        providerControl.selectedSegment = 0
        providerControl.target = self
        providerControl.action = #selector(providerChanged(_:))
        providerControl.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Provider", "Sağlayıcı"),
            subtitle: L10n.text(
                "Cost source. Each provider is priced from its own transcripts.",
                "Maliyet kaynağı. Her sağlayıcı kendi transkriptlerinden fiyatlanır."
            ),
            body: providerControl
        )

        rangeControl.segmentStyle = .texturedRounded
        rangeControl.segmentCount = 2
        rangeControl.setLabel(L10n.text("Last 7 days", "Son 7 gün"), forSegment: 0)
        rangeControl.setLabel(L10n.text("Last 30 days", "Son 30 gün"), forSegment: 1)
        rangeControl.selectedSegment = 1
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged(_:))
        rangeControl.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Range", "Aralık"),
            subtitle: nil,
            body: rangeControl
        )

        tilesStack.orientation = .vertical
        tilesStack.alignment = .leading
        tilesStack.spacing = 10
        tilesStack.translatesAutoresizingMaskIntoConstraints = false

        // Projection line — the headline for a subscription user weighing a
        // forced move to the metered API. Bold run-rate + plain-language sub.
        projectionLabel.maximumNumberOfLines = 0
        projectionLabel.translatesAutoresizingMaskIntoConstraints = false

        savingsLabel.font = NSFont.systemFont(ofSize: 11)
        savingsLabel.textColor = .secondaryLabelColor
        savingsLabel.maximumNumberOfLines = 0
        savingsLabel.translatesAutoresizingMaskIntoConstraints = false

        let costStack = NSStackView(views: [tilesStack, projectionLabel, savingsLabel])
        costStack.orientation = .vertical
        costStack.alignment = .leading
        costStack.spacing = 10
        costStack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Estimated cost", "Tahmini maliyet"),
            subtitle: L10n.text(
                "What this usage would cost on the metered API. You're on a subscription — these are estimates, not charges.",
                "Bu kullanımın ölçümlü API'de tutacağı tahmini maliyet. Abonelik kullandığınız için bunlar tahmindir, fatura değildir."
            ),
            body: costStack
        )
        tilesStack.widthAnchor.constraint(equalTo: costStack.widthAnchor).isActive = true
        projectionLabel.widthAnchor.constraint(equalTo: costStack.widthAnchor).isActive = true
        savingsLabel.widthAnchor.constraint(equalTo: costStack.widthAnchor).isActive = true

        sparkHost.translatesAutoresizingMaskIntoConstraints = false
        sparkHost.heightAnchor.constraint(equalToConstant: 150).isActive = true
        addSection(
            title: L10n.text("Cost trend (30 days)", "Maliyet trendi (30 gün)"),
            subtitle: L10n.text(
                "Estimated daily cost. Hover any day for its date, cost, and tokens.",
                "Tahmini günlük maliyet. Tarih, maliyet ve token için bir günün üzerine gelin."
            ),
            body: sparkHost
        )

        instancesStack.orientation = .vertical
        instancesStack.alignment = .leading
        instancesStack.spacing = 8
        instancesStack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Daily cost by project", "Projeye göre günlük maliyet"),
            subtitle: L10n.text(
                "One row per project per day — like `better-ccusage daily --instances`.",
                "Gün başına proje başına bir satır — `better-ccusage daily --instances` gibi."
            ),
            body: instancesStack
        )

        footnote.font = NSFont.systemFont(ofSize: 10)
        footnote.textColor = .tertiaryLabelColor
        footnote.maximumNumberOfLines = 0
        footnote.translatesAutoresizingMaskIntoConstraints = false
        addSection(title: L10n.text("Source", "Kaynak"), subtitle: nil, body: footnote)
    }

    @objc private func providerChanged(_ sender: NSSegmentedControl) {
        provider = Provider(rawValue: sender.selectedSegment) ?? .claude
        reload()
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        range = Range(rawValue: sender.selectedSegment) ?? .last30
        reload()
    }

    // MARK: - Data

    private struct Instance {
        let date: String
        let project: String
        let models: [String]
        let input: UInt64
        let output: UInt64
        let cacheCreate: UInt64
        let cacheRead: UInt64
        let tokens: UInt64
        let cost: Double
    }

    private struct DailyPoint { let date: String; let cost: Double; let tokens: UInt64 }
    private struct CostData {
        var instances: [Instance] = []
        var dailyPoints: [DailyPoint] = []   // last 30 days, oldest → newest
        var costToday: Double = 0
        var cost7d: Double = 0
        var cost30d: Double = 0
        var input30d: UInt64 = 0
        var output30d: UInt64 = 0
        var cacheSavings30d: Double = 0
        var pricingSource: String?
        var isEstimate: Bool = true
        var planType: String?              // "pro", "max", "free"
        var planTier: String?              // raw rate_limit_tier (max_20x …)
    }

    private func loadData() -> CostData {
        let path = ContextSnapshot.resolveSnapshotPath()
        let key: String = (provider == .codex) ? "codex" : "claude"
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let c = root[key] as? [String: Any]
        else {
            return CostData()
        }
        func u64(_ any: Any?) -> UInt64 {
            if let n = any as? UInt64 { return n }
            if let n = any as? Int, n >= 0 { return UInt64(n) }
            if let d = any as? Double, d.isFinite, d >= 0 { return UInt64(d) }
            if let n = any as? NSNumber { return n.uint64Value }
            return 0
        }
        func dbl(_ any: Any?) -> Double {
            if let d = any as? Double { return d }
            if let n = any as? NSNumber { return n.doubleValue }
            return 0
        }
        var out = CostData()
        out.costToday = dbl(c["cost_today"])
        out.cost7d = dbl(c["cost_7d"])
        out.cost30d = dbl(c["total_cost_30d"])
        out.input30d = u64(c["total_input_30d"])
        out.output30d = u64(c["total_output_30d"])
        out.cacheSavings30d = dbl(c["cache_savings_30d"])
        out.pricingSource = root["pricing_source"] as? String
        out.isEstimate = (root["pricing_is_estimate"] as? Bool) ?? true
        out.instances = ((c["by_day_project"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let date = o["date"] as? String, let project = o["project"] as? String else { return nil }
            let models = (o["models"] as? [String]) ?? []
            return Instance(
                date: date,
                project: project,
                models: models,
                input: u64(o["input"]),
                output: u64(o["output"]),
                cacheCreate: u64(o["cache_creation"]),
                cacheRead: u64(o["cache_read"]),
                tokens: u64(o["tokens"]),
                cost: dbl(o["cost"])
            )
        }
        // by_day arrives newest-first (padded to the history window). Take the
        // last 30 calendar days and flip to oldest→newest for the trend chart.
        let byDay = (c["by_day"] as? [[String: Any]]) ?? []
        out.dailyPoints = byDay.prefix(30).reversed().map {
            DailyPoint(date: ($0["date"] as? String) ?? "", cost: dbl($0["cost"]), tokens: u64($0["tokens"]))
        }

        // Active subscription (for the API-vs-plan projection). Accounts live at
        // the snapshot root; prefer the active one, else the first.
        let accounts = (root["accounts"] as? [[String: Any]]) ?? []
        let active = accounts.first(where: { ($0["is_active"] as? Bool) ?? false }) ?? accounts.first
        out.planType = active?["subscription_type"] as? String
        out.planTier = active?["rate_limit_tier"] as? String
        return out
    }

    // MARK: - Render

    func reload() {
        guard isViewLoaded else { return }
        let data = loadData()
        tilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        instancesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Clear EVERY trend-host subview (chart, caption, empty label) so
        // repeated reloads don't stack overlapping views/text.
        sparkHost.subviews.forEach { $0.removeFromSuperview() }

        // The 7-day cost_7d is a precise rolling-window value from the engine;
        // for the 7-day range we also scope the instance list to the last 7
        // calendar days. cost_today/cost_30d are always shown for context.
        let rangeDays = (range == .last7) ? 7 : 30
        let cutoff = cutoffDate(daysAgo: rangeDays)
        let visible = data.instances.filter { dateFromKey($0.date).map { $0 >= cutoff } ?? true }
        let rangeCost = visible.reduce(0.0) { $0 + $1.cost }

        let tiles: [NSView] = [
            StatTileView(
                caption: L10n.text("today", "bugün"),
                value: formatUSD(data.costToday), mono: true
            ),
            StatTileView(
                caption: L10n.text("last 7 days", "son 7 gün"),
                value: formatUSD(data.cost7d), mono: true
            ),
            StatTileView(
                caption: range == .last7
                    ? L10n.text("range total", "aralık toplamı")
                    : L10n.text("last 30 days", "son 30 gün"),
                value: formatUSD(range == .last7 ? rangeCost : data.cost30d), mono: true
            ),
            StatTileView(
                caption: L10n.text("30d in / out", "30g girdi / çıktı"),
                value: "\(ContextSnapshot.formatTokens(data.input30d)) / \(ContextSnapshot.formatTokens(data.output30d))",
                mono: false
            ),
        ]
        let row = NSStackView(views: tiles)
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        tilesStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: tilesStack.widthAnchor).isActive = true

        renderProjection(data)
        renderSavings(data)
        renderTrend(data.dailyPoints)
        renderInstances(visible)

        let src = data.pricingSource.map { srcLabel($0) } ?? "—"
        footnote.stringValue = L10n.text(
            "Rates: \(src). Estimated as if metered. Subscription usage isn't billed per token; API-key usage is — the transcripts don't record which mode a session used, so all of it is shown as an estimate.",
            "Oranlar: \(src). Ölçümlüymüş gibi tahmin. Abonelik kullanımı token başına faturalanmaz; API-key kullanımı faturalanır — transkriptler bir oturumun hangi modda olduğunu kaydetmediği için hepsi tahmin olarak gösterilir."
        )
    }

    /// Headline for a subscription user weighing a forced move to the metered
    /// API: monthly run-rate (last 30 days) and, for Claude, how it compares to
    /// the active plan's price.
    private func renderProjection(_ data: CostData) {
        let monthly = data.cost30d
        guard monthly > 0 else {
            projectionLabel.stringValue = ""
            projectionLabel.isHidden = true
            return
        }
        projectionLabel.isHidden = false
        let big = "≈ \(formatUSD(monthly)) / \(L10n.text("month", "ay"))"
        let result = NSMutableAttributedString(string: big, attributes: [
            .font: Typography.displayMono(18, weight: .semibold),
            .foregroundColor: ThemeStore.current.accent,
            .kern: -0.2,
        ])

        var sub = L10n.text(
            "On the metered API, projected from the last 30 days.",
            "Ölçümlü API'de, son 30 güne göre öngörü."
        )
        if provider == .claude, let price = planMonthlyPrice(data.planType, data.planTier) {
            let mult = monthly / price
            let multStr = mult >= 10 ? String(format: "%.0f×", mult) : String(format: "%.1f×", mult)
            let plan = planName(data.planType, data.planTier)
            sub = L10n.text(
                "Projected from the last 30 days — about \(multStr) your \(plan) plan (\(formatUSD(price))/mo).",
                "Son 30 güne göre öngörü — \(plan) planınızın (\(formatUSD(price))/ay) yaklaşık \(multStr) katı."
            )
        }
        result.append(NSAttributedString(string: "\n" + sub, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        result.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: result.length))
        projectionLabel.attributedStringValue = result
    }

    /// Cache-savings insight: the net USD prompt caching saved vs paying full
    /// input. A genuine "you're winning" line no CLI surfaces.
    private func renderSavings(_ data: CostData) {
        guard data.cacheSavings30d > 0 else {
            savingsLabel.isHidden = true
            savingsLabel.stringValue = ""
            return
        }
        savingsLabel.isHidden = false
        let saved = formatUSD(data.cacheSavings30d)
        let (pre, post) = L10n.lang == .tr
            ? ("Prompt caching son 30 günde ", " tasarruf ettirdi (tam girdi fiyatına kıyasla).")
            : ("Prompt caching saved ", " in the last 30 days vs. paying full input price.")
        let result = NSMutableAttributedString(string: pre, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        result.append(NSAttributedString(string: saved, attributes: [
            .font: Typography.bodyMono(11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))
        result.append(NSAttributedString(string: post, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        savingsLabel.attributedStringValue = result
    }

    private func renderTrend(_ points: [DailyPoint]) {
        let nonZero = points.contains { $0.cost > 0 }
        guard points.count >= 2, nonZero else {
            let empty = NSTextField(labelWithString: L10n.text("No cost trend yet.", "Henüz maliyet trendi yok."))
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = .tertiaryLabelColor
            empty.translatesAutoresizingMaskIntoConstraints = false
            sparkHost.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.leadingAnchor.constraint(equalTo: sparkHost.leadingAnchor),
                empty.centerYAnchor.constraint(equalTo: sparkHost.centerYAnchor),
            ])
            return
        }
        let total = points.reduce(0.0) { $0 + $1.cost }
        let peak = points.map(\.cost).max() ?? 0
        let caption = NSTextField(labelWithString: L10n.text(
            "30d total \(formatUSD(total))  ·  peak \(formatUSD(peak))/day  ·  hover for a day",
            "30g toplam \(formatUSD(total))  ·  zirve \(formatUSD(peak))/gün  ·  gün için üzerine gel"
        ))
        caption.font = Typography.bodyMono(10, weight: .regular)
        caption.textColor = .tertiaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false
        sparkHost.addSubview(caption)

        let chart = CostTrendChartView()
        chart.tint = ThemeStore.current.accent
        chart.points = points.map { (date: $0.date, cost: $0.cost, tokens: $0.tokens) }
        chart.usd = { ContextSnapshot.formatUSD($0) }
        chart.tokensFmt = { ContextSnapshot.formatTokens($0) }
        chart.dayLabel = { [weak self] in self?.formatDay($0) ?? $0 }
        chart.translatesAutoresizingMaskIntoConstraints = false
        sparkHost.addSubview(chart)

        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: sparkHost.leadingAnchor),
            caption.topAnchor.constraint(equalTo: sparkHost.topAnchor),
            chart.leadingAnchor.constraint(equalTo: sparkHost.leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: sparkHost.trailingAnchor),
            chart.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 6),
            chart.bottomAnchor.constraint(equalTo: sparkHost.bottomAnchor),
        ])
    }

    /// Monthly USD price of the active Anthropic plan (for the API comparison).
    /// Confirmed list prices; nil when unknown (free / no account).
    private func planMonthlyPrice(_ type: String?, _ tier: String?) -> Double? {
        guard let type else { return nil }
        switch type {
        case "pro": return 20
        case "max":
            let t = tier ?? ""
            if t.contains("20x") { return 200 }
            if t.contains("5x") { return 100 }
            return 100
        default: return nil
        }
    }

    private func planName(_ type: String?, _ tier: String?) -> String {
        switch type {
        case "pro": return "Pro"
        case "max":
            let t = tier ?? ""
            if t.contains("20x") { return "Max 20×" }
            if t.contains("5x") { return "Max 5×" }
            return "Max"
        default: return type ?? "—"
        }
    }

    private let numColW: CGFloat = 58
    private let costColW: CGFloat = 78
    private enum RowStyle { case header, day, data, total }

    private func renderInstances(_ items: [Instance]) {
        guard !items.isEmpty else {
            let empty = NSTextField(labelWithString: L10n.text(
                "No usage in this range.",
                "Bu aralıkta kullanım yok."
            ))
            empty.font = NSFont.systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            instancesStack.addArrangedSubview(empty)
            return
        }

        // One native table, ccusage-style: a column header, then per-day group
        // rows (the day's aggregate) each followed by indented per-project
        // sub-rows, and a grand Total. Fixed-width numeric columns keep every
        // row aligned without an NSTableView's chrome.
        var order: [String] = []
        var byDay: [String: [Instance]] = [:]
        for it in items {
            if byDay[it.date] == nil { order.append(it.date) }
            byDay[it.date, default: []].append(it)
        }

        let card = NSView()
        Surface.applyCard(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 1
        col.translatesAutoresizingMaskIntoConstraints = false

        func add(_ v: NSView) {
            col.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
        }

        add(gridRow(
            leading: gridLabel(L10n.text("Project", "Proje"), size: 9.5, weight: .semibold, color: .secondaryLabelColor),
            values: [L10n.text("Input", "Girdi"), L10n.text("Output", "Çıktı"),
                     L10n.text("Cache+", "Önbel+"), L10n.text("Cache↻", "Önbel↻"),
                     L10n.text("Total", "Toplam"), L10n.text("Cost", "Maliyet")],
            style: .header))
        addSep(add)

        var gIn: UInt64 = 0, gOut: UInt64 = 0, gCw: UInt64 = 0, gCr: UInt64 = 0
        var gCost = 0.0
        for (di, day) in order.enumerated() {
            let rows = (byDay[day] ?? []).sorted { $0.cost > $1.cost }
            let dIn = rows.reduce(UInt64(0)) { $0 + $1.input }
            let dOut = rows.reduce(UInt64(0)) { $0 + $1.output }
            let dCw = rows.reduce(UInt64(0)) { $0 + $1.cacheCreate }
            let dCr = rows.reduce(UInt64(0)) { $0 + $1.cacheRead }
            let dCost = rows.reduce(0.0) { $0 + $1.cost }
            gIn += dIn; gOut += dOut; gCw += dCw; gCr += dCr; gCost += dCost

            add(gridRow(
                leading: gridLabel(formatDay(day), size: 12, weight: .semibold, color: .labelColor),
                values: [tk(dIn), tk(dOut), tk(dCw), tk(dCr), tk(dIn + dOut + dCw + dCr), formatUSD(dCost)],
                style: .day))
            for it in rows {
                // Total column = all four token buckets, matching ccusage's
                // "Total Tokens" (input + output + cache create + cache read) —
                // distinct from the Stats tab's fresh-work `tokens` total.
                let rowTotal = it.input + it.output + it.cacheCreate + it.cacheRead
                add(gridRow(leading: projectLeading(it),
                            values: [tk(it.input), tk(it.output), tk(it.cacheCreate),
                                     tk(it.cacheRead), tk(rowTotal), formatUSD(it.cost)],
                            style: .data))
            }
            if di < order.count - 1 { addSep(add) }
        }

        addSep(add, strong: true)
        add(gridRow(
            leading: gridLabel(L10n.text("Total", "Toplam"), size: 12, weight: .bold, color: .labelColor),
            values: [tk(gIn), tk(gOut), tk(gCw), tk(gCr), tk(gIn + gOut + gCw + gCr), formatUSD(gCost)],
            style: .total))

        card.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            col.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        instancesStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: instancesStack.widthAnchor).isActive = true
    }

    private func tk(_ v: UInt64) -> String { ContextSnapshot.formatTokens(v) }

    private func gridLabel(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSView {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    /// Indented project name + model subtitle for a data sub-row.
    private func projectLeading(_ it: Instance) -> NSView {
        let name = NSTextField(labelWithString: it.project)
        name.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingMiddle
        let models = it.models.map(prettyModel).joined(separator: ", ")
        let sub = NSTextField(labelWithString: models)
        sub.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        sub.textColor = .tertiaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        let vs = NSStackView(views: models.isEmpty ? [name] : [name, sub])
        vs.orientation = .vertical
        vs.alignment = .leading
        vs.spacing = 1
        let indent = NSView()
        indent.translatesAutoresizingMaskIntoConstraints = false
        indent.widthAnchor.constraint(equalToConstant: 12).isActive = true
        let h = NSStackView(views: [indent, vs])
        h.orientation = .horizontal
        h.alignment = .firstBaseline
        h.spacing = 0
        return h
    }

    private func addSep(_ add: (NSView) -> Void, strong: Bool = false) {
        let sep = NSBox()
        sep.boxType = .separator
        sep.alphaValue = strong ? 1.0 : 0.5
        sep.translatesAutoresizingMaskIntoConstraints = false
        add(sep)
    }

    private func gridRow(leading: NSView, values: [String], style: RowStyle) -> NSView {
        leading.translatesAutoresizingMaskIntoConstraints = false
        leading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        leading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var cells: [NSView] = [leading]
        for (i, v) in values.enumerated() {
            let isCost = (i == values.count - 1)
            let lbl = NSTextField(labelWithString: v)
            lbl.alignment = .right
            lbl.lineBreakMode = .byClipping
            lbl.translatesAutoresizingMaskIntoConstraints = false
            switch style {
            case .header:
                lbl.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
                lbl.textColor = .secondaryLabelColor
            case .total:
                lbl.font = Typography.bodyMono(11, weight: isCost ? .bold : .semibold)
                lbl.textColor = isCost ? .labelColor : .secondaryLabelColor
            case .day:
                lbl.font = Typography.bodyMono(11, weight: isCost ? .semibold : .regular)
                lbl.textColor = isCost ? .labelColor : .secondaryLabelColor
            case .data:
                lbl.font = Typography.bodyMono(11, weight: isCost ? .semibold : .regular)
                lbl.textColor = isCost ? .secondaryLabelColor : .tertiaryLabelColor
                if isCost { lbl.textColor = .labelColor }
            }
            lbl.widthAnchor.constraint(equalToConstant: isCost ? costColW : numColW).isActive = true
            cells.append(lbl)
        }
        let r = NSStackView(views: cells)
        r.orientation = .horizontal
        r.alignment = .firstBaseline
        r.spacing = 6
        r.edgeInsets = NSEdgeInsets(top: style == .header ? 0 : 5, left: 0, bottom: 5, right: 0)
        r.translatesAutoresizingMaskIntoConstraints = false
        return r
    }

    // MARK: - Formatting

    private func formatUSD(_ value: Double) -> String {
        if value <= 0 { return "$0.00" }
        if value < 0.01 { return "<$0.01" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "$\(s)"
    }

    private func dateFromKey(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.date(from: iso)
    }

    private func cutoffDate(daysAgo: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: -(daysAgo - 1), to: start) ?? start
    }

    private func formatDay(_ iso: String) -> String {
        guard let date = dateFromKey(iso) else { return iso }
        let cal = Calendar(identifier: .gregorian)
        if cal.isDateInToday(date) { return L10n.text("Today", "Bugün") }
        if cal.isDateInYesterday(date) { return L10n.text("Yesterday", "Dün") }
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        out.dateFormat = L10n.lang == .tr ? "d MMMM EEEE" : "EEEE, MMM d"
        return out.string(from: date)
    }

    private func srcLabel(_ source: String) -> String {
        switch source {
        case "live": return L10n.text("LiteLLM (live)", "LiteLLM (canlı)")
        case "cache": return L10n.text("LiteLLM (cached)", "LiteLLM (önbellek)")
        case "fallback": return L10n.text("bundled rates", "gömülü oranlar")
        default: return source
        }
    }

    private func prettyModel(_ id: String) -> String {
        let m = id.lowercased()
        let suffix = m.contains("[1m]") || m.contains("-1m") ? " (1M)" : ""
        let base: String
        switch true {
        case m.contains("opus-4-8"):   base = "Opus 4.8"
        case m.contains("opus-4-7"):   base = "Opus 4.7"
        case m.contains("opus-4-6"):   base = "Opus 4.6"
        case m.contains("opus-4-5"):   base = "Opus 4.5"
        case m.contains("opus-4-1"):   base = "Opus 4.1"
        case m.contains("opus-4"):     base = "Opus 4"
        case m.contains("sonnet-4-6"): base = "Sonnet 4.6"
        case m.contains("sonnet-4-5"): base = "Sonnet 4.5"
        case m.contains("sonnet-4"):   base = "Sonnet 4"
        case m.contains("haiku-4-5"):  base = "Haiku 4.5"
        case m.contains("haiku"):      base = "Haiku"
        case m.contains("mythos"):     base = "Mythos"
        case m.contains("gpt-5.5"):    base = "GPT-5.5"
        case m.contains("gpt-5.4"):    base = "GPT-5.4"
        case m.contains("gpt-5.3"):    base = "GPT-5.3"
        case m.contains("gpt-5.2"):    base = "GPT-5.2"
        case m.contains("gpt-5.1"):    base = "GPT-5.1"
        case m.contains("gpt-5"):      base = "GPT-5"
        default:                       return id
        }
        let codex = m.contains("codex") ? " codex" : ""
        return base + codex + suffix
    }
}

/// Interactive 30-day cost trend. Gradient area + line like the sparkline, but
/// with mouse tracking: hover snaps to the nearest day and draws a crosshair,
/// a highlighted dot, and a tooltip with that day's date, cost, and tokens.
final class CostTrendChartView: NSView {
    var points: [(date: String, cost: Double, tokens: UInt64)] = [] { didSet { needsDisplay = true } }
    var tint: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var usd: (Double) -> String = { String(format: "$%.2f", $0) }
    var tokensFmt: (UInt64) -> String = { "\($0)" }
    var dayLabel: (String) -> String = { $0 }

    private var hoverIndex: Int?
    private var trackingArea: NSTrackingArea?
    private let padX: CGFloat = 6
    private let padTop: CGFloat = 20   // reserve a band for the tooltip
    private let padBottom: CGFloat = 4

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Daily cost trend")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Capture-only: lets marketing/verification screenshots render the hover
        // tooltip without a live cursor. No effect in normal use.
        if let raw = ProcessInfo.processInfo.environment["CONTEXTBAR_DEBUG_HOVER"],
           let i = Int(raw), points.count >= 2 {
            hoverIndex = min(max(0, i), points.count - 1)
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil
        )
        addTrackingArea(t)
        trackingArea = t
    }

    private func point(at i: Int, maxV: Double) -> CGPoint {
        let n = points.count
        let usableW = bounds.width - padX * 2
        let x = n <= 1 ? bounds.width / 2 : padX + CGFloat(i) * (usableW / CGFloat(n - 1))
        let usableH = bounds.height - padTop - padBottom
        let norm = maxV > 0 ? CGFloat(points[i].cost / maxV) : 0
        return CGPoint(x: x, y: padBottom + norm * usableH)
    }

    override func mouseMoved(with event: NSEvent) {
        guard points.count >= 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        let n = points.count
        let usableW = max(1, bounds.width - padX * 2)
        let rel = (p.x - padX) / usableW
        let idx = max(0, min(n - 1, Int((rel * CGFloat(n - 1)).rounded())))
        if idx != hoverIndex { hoverIndex = idx; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverIndex != nil { hoverIndex = nil; needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard points.count >= 2, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let maxV = max(points.map(\.cost).max() ?? 1, 1e-9)
        let n = points.count

        let line = CGMutablePath()
        line.move(to: point(at: 0, maxV: maxV))
        for i in 1..<n { line.addLine(to: point(at: i, maxV: maxV)) }

        let area = CGMutablePath()
        area.move(to: CGPoint(x: point(at: 0, maxV: maxV).x, y: padBottom))
        for i in 0..<n { area.addLine(to: point(at: i, maxV: maxV)) }
        area.addLine(to: CGPoint(x: point(at: n - 1, maxV: maxV).x, y: padBottom))
        area.closeSubpath()

        ctx.saveGState()
        ctx.addPath(area)
        ctx.clip()
        let grad = CGGradient(
            colorsSpace: nil,
            colors: [tint.withAlphaComponent(0.22).cgColor, tint.withAlphaComponent(0.0).cgColor] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: padBottom),
                               end: CGPoint(x: 0, y: bounds.height), options: [])
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(tint.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(line)
        ctx.strokePath()
        ctx.restoreGState()

        if let i = hoverIndex {
            let pt = point(at: i, maxV: maxV)
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: pt.x, y: padBottom))
            ctx.addLine(to: CGPoint(x: pt.x, y: bounds.height - padTop + 8))
            ctx.strokePath()
            ctx.setFillColor(tint.cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
            ctx.restoreGState()
            drawTooltip(for: i)
        } else {
            let last = point(at: n - 1, maxV: maxV)
            ctx.setFillColor(tint.cgColor)
            ctx.fillEllipse(in: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5))
        }
    }

    private func drawTooltip(for i: Int) {
        let p = points[i]
        let text = "\(dayLabel(p.date))   \(usd(p.cost))   \(tokensFmt(p.tokens))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let boxW = size.width + 12, boxH = size.height + 6
        let maxV = max(points.map(\.cost).max() ?? 1, 1e-9)
        var bx = point(at: i, maxV: maxV).x - boxW / 2
        bx = max(0, min(bounds.width - boxW, bx))
        let by = bounds.height - boxH
        let box = NSRect(x: bx, y: by, width: boxW, height: boxH)
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        (text as NSString).draw(at: CGPoint(x: bx + 6, y: by + 3), withAttributes: attrs)
    }
}
