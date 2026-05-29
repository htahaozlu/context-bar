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
        addSection(
            title: L10n.text("Estimated cost", "Tahmini maliyet"),
            subtitle: L10n.text(
                "What this usage would cost on the metered API. You're on a subscription — these are estimates, not charges.",
                "Bu kullanımın ölçümlü API'de tutacağı tahmini maliyet. Abonelik kullandığınız için bunlar tahmindir, fatura değildir."
            ),
            body: tilesStack
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
        let tokens: UInt64
        let cost: Double
    }

    private struct CostData {
        var instances: [Instance] = []
        var costToday: Double = 0
        var cost7d: Double = 0
        var cost30d: Double = 0
        var input30d: UInt64 = 0
        var output30d: UInt64 = 0
        var pricingSource: String?
        var isEstimate: Bool = true
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
                tokens: u64(o["tokens"]),
                cost: dbl(o["cost"])
            )
        }
        return out
    }

    // MARK: - Render

    func reload() {
        guard isViewLoaded else { return }
        let data = loadData()
        tilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        instancesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

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

        renderInstances(visible)

        let src = data.pricingSource.map { srcLabel($0) } ?? "—"
        footnote.stringValue = L10n.text(
            "Rates: \(src). Estimated API-equivalent cost — not billed amounts.",
            "Oranlar: \(src). Tahmini API-eşdeğeri maliyet — faturalandırılan tutar değildir."
        )
    }

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

        // Items arrive newest-day-first, cost-desc within a day. Group by day,
        // preserving that order, and render a day header + per-project rows.
        var order: [String] = []
        var byDay: [String: [Instance]] = [:]
        for it in items {
            if byDay[it.date] == nil { order.append(it.date) }
            byDay[it.date, default: []].append(it)
        }

        for day in order {
            let rows = byDay[day] ?? []
            let dayCost = rows.reduce(0.0) { $0 + $1.cost }
            let header = dayHeader(date: day, cost: dayCost)
            instancesStack.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: instancesStack.widthAnchor).isActive = true

            let card = NSView()
            Surface.applyCard(card)
            card.translatesAutoresizingMaskIntoConstraints = false
            let col = NSStackView()
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 8
            col.translatesAutoresizingMaskIntoConstraints = false
            for (i, it) in rows.enumerated() {
                col.addArrangedSubview(projectRow(it))
                col.arrangedSubviews.last?.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
                if i < rows.count - 1 {
                    let sep = NSBox()
                    sep.boxType = .separator
                    sep.translatesAutoresizingMaskIntoConstraints = false
                    col.addArrangedSubview(sep)
                    sep.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
                }
            }
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
    }

    private func dayHeader(date: String, cost: Double) -> NSView {
        let title = NSTextField(labelWithString: formatDay(date))
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor
        let costLbl = NSTextField(labelWithString: formatUSD(cost))
        costLbl.font = Typography.bodyMono(12, weight: .semibold)
        costLbl.textColor = .labelColor
        costLbl.alignment = .right
        let r = NSStackView(views: [title, NSView(), costLbl])
        r.orientation = .horizontal
        r.spacing = 8
        r.translatesAutoresizingMaskIntoConstraints = false
        r.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return r
    }

    private func projectRow(_ it: Instance) -> NSView {
        let name = NSTextField(labelWithString: it.project)
        name.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingMiddle

        let models = it.models.map(prettyModel).joined(separator: ", ")
        let metaText = models.isEmpty
            ? "↑\(ContextSnapshot.formatTokens(it.input))  ↓\(ContextSnapshot.formatTokens(it.output))"
            : "\(models)  ·  ↑\(ContextSnapshot.formatTokens(it.input))  ↓\(ContextSnapshot.formatTokens(it.output))"
        let meta = NSTextField(labelWithString: metaText)
        meta.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        meta.textColor = .secondaryLabelColor
        meta.lineBreakMode = .byTruncatingTail

        let left = NSStackView(views: [name, meta])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 2
        left.translatesAutoresizingMaskIntoConstraints = false

        let cost = NSTextField(labelWithString: formatUSD(it.cost))
        cost.font = Typography.bodyMono(13, weight: .semibold)
        cost.textColor = .labelColor
        cost.alignment = .right
        cost.setContentCompressionResistancePriority(.required, for: .horizontal)

        let r = NSStackView(views: [left, NSView(), cost])
        r.orientation = .horizontal
        r.alignment = .centerY
        r.spacing = 8
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
