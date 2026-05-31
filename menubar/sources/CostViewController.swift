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
    private let instancesView = CostInstancesView()
    private var costDetailPopover: NSPopover?
    private let footnote = NSTextField(labelWithString: "")
    private let aiButton = NSButton()
    private let aiSpinner = NSProgressIndicator()
    private let aiResult = NSTextField(wrappingLabelWithString: "")

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

        aiButton.bezelStyle = .rounded
        aiButton.title = L10n.text("Analyze my usage", "Kullanımımı analiz et")
        aiButton.target = self
        aiButton.action = #selector(analyzeAI)
        aiButton.translatesAutoresizingMaskIntoConstraints = false
        aiSpinner.style = .spinning
        aiSpinner.controlSize = .small
        aiSpinner.isDisplayedWhenStopped = false
        aiSpinner.translatesAutoresizingMaskIntoConstraints = false
        aiResult.font = NSFont.systemFont(ofSize: 11.5)
        aiResult.textColor = .secondaryLabelColor
        aiResult.maximumNumberOfLines = 0
        aiResult.translatesAutoresizingMaskIntoConstraints = false
        let aiRow = NSStackView(views: [aiButton, aiSpinner])
        aiRow.orientation = .horizontal
        aiRow.spacing = 8
        aiRow.alignment = .centerY
        let aiStack = NSStackView(views: [aiRow, aiResult])
        aiStack.orientation = .vertical
        aiStack.alignment = .leading
        aiStack.spacing = 8
        aiStack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("AI Advisor", "AI Danışman"),
            subtitle: L10n.text(
                "Get usage-efficiency tips from your own OpenAI / Gemini key (set it in Privacy settings). Sends an aggregate summary only — no transcripts, no project names.",
                "Kendi OpenAI / Gemini anahtarınla kullanım verimliliği önerileri al (Gizlilik ayarlarından gir). Yalnızca özet gönderir — transcript yok, proje adı yok."
            ),
            body: aiStack
        )

        footnote.font = NSFont.systemFont(ofSize: 10)
        footnote.textColor = .tertiaryLabelColor
        footnote.maximumNumberOfLines = 0
        footnote.translatesAutoresizingMaskIntoConstraints = false
        addSection(title: L10n.text("Source", "Kaynak"), subtitle: nil, body: footnote)
    }

    @objc private func analyzeAI() {
        guard DisplayPrefs.aiProvider != .off, AIKeychain.hasKey(for: DisplayPrefs.aiProvider) else {
            aiResult.textColor = .systemOrange
            aiResult.stringValue = L10n.text(
                "Connect an OpenAI or Gemini API key in Settings → Privacy → AI Advisor first.",
                "Önce Ayarlar → Gizlilik → AI Danışman'dan bir OpenAI veya Gemini API anahtarı bağla."
            )
            return
        }
        aiButton.isEnabled = false
        aiSpinner.startAnimation(nil)
        aiResult.textColor = .secondaryLabelColor
        aiResult.stringValue = L10n.text("Analyzing your 30-day usage…", "Son 30 günlük kullanımın analiz ediliyor…")
        AIAdvisor.analyze { [weak self] result in
            guard let self else { return }
            self.aiButton.isEnabled = true
            self.aiSpinner.stopAnimation(nil)
            switch result {
            case .success(let text):
                self.aiResult.textColor = .labelColor
                self.aiResult.stringValue = text
            case .failure(let err):
                self.aiResult.textColor = .systemOrange
                self.aiResult.stringValue = L10n.text("Couldn't analyze: ", "Analiz edilemedi: ") + "\(err)"
            }
        }
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

        // Build a flat row model (header → per-day aggregate + indented project
        // sub-rows → grand Total) and hand it to a single custom view that draws
        // only the rows intersecting the dirty rect — no per-cell NSViews or
        // constraints, so the tab opens instantly regardless of row count.
        var order: [String] = []
        var byDay: [String: [Instance]] = [:]
        for it in items {
            if byDay[it.date] == nil { order.append(it.date) }
            byDay[it.date, default: []].append(it)
        }

        var modelRows: [CostRow] = [
            CostRow(kind: .header, leading: L10n.text("Project", "Proje"), sub: "",
                    values: [L10n.text("Input", "Girdi"), L10n.text("Output", "Çıktı"),
                             L10n.text("Cache+", "Önbel+"), L10n.text("Cache↻", "Önbel↻"),
                             L10n.text("Total", "Toplam"), L10n.text("Cost", "Maliyet")]),
        ]
        var gIn: UInt64 = 0, gOut: UInt64 = 0, gCw: UInt64 = 0, gCr: UInt64 = 0
        var gCost = 0.0
        for (di, day) in order.enumerated() {
            let dayRows = (byDay[day] ?? []).sorted { $0.cost > $1.cost }
            let dIn = dayRows.reduce(UInt64(0)) { $0 + $1.input }
            let dOut = dayRows.reduce(UInt64(0)) { $0 + $1.output }
            let dCw = dayRows.reduce(UInt64(0)) { $0 + $1.cacheCreate }
            let dCr = dayRows.reduce(UInt64(0)) { $0 + $1.cacheRead }
            let dCost = dayRows.reduce(0.0) { $0 + $1.cost }
            gIn += dIn; gOut += dOut; gCw += dCw; gCr += dCr; gCost += dCost
            modelRows.append(CostRow(kind: .day, leading: formatDay(day), sub: "",
                values: [tk(dIn), tk(dOut), tk(dCw), tk(dCr), tk(dIn + dOut + dCw + dCr), formatUSD(dCost)]))
            for it in dayRows {
                // Total = all four token buckets (ccusage "Total Tokens"),
                // distinct from the Stats tab's fresh-work total.
                let rowTotal = it.input + it.output + it.cacheCreate + it.cacheRead
                modelRows.append(CostRow(kind: .data, leading: it.project,
                    sub: it.models.map(prettyModel).joined(separator: ", "),
                    values: [tk(it.input), tk(it.output), tk(it.cacheCreate), tk(it.cacheRead), tk(rowTotal), formatUSD(it.cost)],
                    detail: CostRowDetail(dayLabel: formatDay(day), project: it.project,
                        models: it.models.map(prettyModel), input: it.input, output: it.output,
                        cacheCreate: it.cacheCreate, cacheRead: it.cacheRead,
                        totalTokens: rowTotal, totalCost: it.cost)))
            }
            if di < order.count - 1 {
                modelRows.append(CostRow(kind: .separator, leading: "", sub: "", values: []))
            }
        }
        modelRows.append(CostRow(kind: .separatorStrong, leading: "", sub: "", values: []))
        modelRows.append(CostRow(kind: .total, leading: L10n.text("Total", "Toplam"), sub: "",
            values: [tk(gIn), tk(gOut), tk(gCw), tk(gCr), tk(gIn + gOut + gCw + gCr), formatUSD(gCost)]))

        instancesView.onRowClick = { [weak self] detail, rowRect in
            self?.presentCostDetail(detail, relativeTo: rowRect)
        }
        instancesView.rows = modelRows

        let card = NSView()
        Surface.applyCard(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        instancesView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(instancesView)
        NSLayoutConstraint.activate([
            instancesView.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            instancesView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            instancesView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            instancesView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        instancesStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: instancesStack.widthAnchor).isActive = true
    }

    private func tk(_ v: UInt64) -> String { ContextSnapshot.formatTokens(v) }

    /// Row click → drill-down popover with the 4-bucket breakdown + a
    /// plain-language cache explainer (the "tıklayınca detay" + "öğretici"
    /// request). Anchored to the clicked row; transient so it dismisses on
    /// click-away without disturbing the scroll position.
    private func presentCostDetail(_ detail: CostRowDetail, relativeTo rowRect: NSRect) {
        costDetailPopover?.close()
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = CostDetailViewController(detail: detail)
        costDetailPopover = pop
        pop.show(relativeTo: rowRect, of: instancesView, preferredEdge: .maxX)
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

/// One row in the cost-by-project table.
/// Raw payload for a clickable row — drives the drill-down detail popover.
/// Per-bucket cost is closed-form from tokens for Claude rows (output = 5×
/// input, cache-write = 1.25×, cache-read = 0.1× across all current Claude
/// tiers, so the absolute rate cancels: bucketCost = total × weightShare).
struct CostRowDetail {
    let dayLabel: String
    let project: String
    let models: [String]
    let input: UInt64
    let output: UInt64
    let cacheCreate: UInt64
    let cacheRead: UInt64
    let totalTokens: UInt64
    let totalCost: Double
}

private struct CostRow {
    enum Kind { case header, day, data, total, separator, separatorStrong }
    let kind: Kind
    let leading: String
    let sub: String          // model list, for `.data` rows
    let values: [String]     // [input, output, cache+, cache↻, total, cost]
    var detail: CostRowDetail? = nil  // present on clickable `.data` rows only
}

/// Draws the per-day-per-project cost table in a single view. Only the rows
/// intersecting the dirty rect are drawn, so even a full 30-day breakdown
/// renders in microseconds and scrolls smoothly — no per-cell NSViews or
/// Auto-Layout constraints (the previous NSStackView approach built ~1.8k
/// views and stalled the Cost tab on open).
private final class CostInstancesView: NSView {
    var rows: [CostRow] = [] {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    /// Fired when a clickable (`.data`) row is clicked. Rect is in this view's
    /// (flipped) coordinates — pass it straight to `NSPopover.show(relativeTo:)`.
    var onRowClick: ((CostRowDetail, NSRect) -> Void)?

    private var hoveredRowIndex: Int? {
        didSet {
            guard oldValue != hoveredRowIndex else { return }
            if let oldValue { setNeedsDisplay(rowRect(at: oldValue)) }
            if let hoveredRowIndex { setNeedsDisplay(rowRect(at: hoveredRowIndex)) }
        }
    }
    private var hoverTracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        hoveredRowIndex = rowIndex(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) { hoveredRowIndex = nil }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = rowIndex(at: p), let detail = rows[i].detail else {
            super.mouseDown(with: event); return
        }
        let r = rowRect(at: i)
        onRowClick?(detail, r.intersection(visibleRect).isEmpty ? r : r.intersection(visibleRect))
    }

    /// Row index at a point (flipped coords), but only for clickable rows.
    private func rowIndex(at p: NSPoint) -> Int? {
        guard bounds.contains(p) else { return nil }
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let h = rowHeight(row.kind)
            if NSRect(x: 0, y: y, width: bounds.width, height: h).contains(p) {
                return row.detail == nil ? nil : i
            }
            y += h
        }
        return nil
    }

    private func rowRect(at target: Int) -> NSRect {
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let h = rowHeight(row.kind)
            if i == target { return NSRect(x: 0, y: y, width: bounds.width, height: h) }
            y += h
        }
        return .zero
    }

    // Fixed numeric grid: [input, output, cache+, cache↻, TOTAL, COST]. Columns
    // are LEFT-anchored to the end of the project column (NOT to bounds.width),
    // so the grid hugs the leading edge and any extra width is harmless trailing
    // margin — never an internal gap. Same colX shared by every row kind so the
    // digits stack vertically.
    private let colGap: CGFloat = 14
    private let numW: [CGFloat] = [60, 60, 60, 60, 66, 92]
    private let projMin: CGFloat = 130
    private let projMax: CGFloat = 300
    private var numericBlock: CGFloat { numW.reduce(0, +) + colGap * CGFloat(numW.count) }

    private func rowHeight(_ k: CostRow.Kind) -> CGFloat {
        switch k {
        case .header: return 22
        case .day: return 26
        case .data: return 36
        case .total: return 28
        case .separator, .separatorStrong: return 10
        }
    }

    private var totalHeight: CGFloat { rows.reduce(0) { $0 + rowHeight($1.kind) } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(totalHeight))
    }

    override func layout() {
        super.layout()
        // Width changes (window resize) shift the right-aligned columns.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Project column flexes between projMin..projMax; the numeric block is
        // fixed. Numerics start at the project column's right edge — leftover
        // width becomes trailing margin, so wide windows never open an internal gap.
        let projectColW = min(projMax, max(projMin, bounds.width - numericBlock))
        let tableW = projectColW + numericBlock
        var gx = projectColW
        var colX: [CGFloat] = []
        for w in numW { gx += colGap; colX.append(gx); gx += w }
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let h = rowHeight(row.kind)
            let rect = NSRect(x: 0, y: y, width: bounds.width, height: h)
            if rect.intersects(dirtyRect) {
                // Hover affordance on clickable rows.
                if i == hoveredRowIndex, row.detail != nil {
                    ThemeStore.current.accent.withAlphaComponent(0.10).setFill()
                    NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
                }
                drawRow(row, rect: rect, projectColW: projectColW, colX: colX, tableW: tableW)
            }
            y += h
        }
    }

    private func drawRow(_ row: CostRow, rect: NSRect, projectColW: CGFloat, colX: [CGFloat], tableW: CGFloat) {
        if row.kind == .separator || row.kind == .separatorStrong {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: rect.midY))
            line.line(to: NSPoint(x: tableW, y: rect.midY))
            NSColor.separatorColor
                .withAlphaComponent(row.kind == .separatorStrong ? 1.0 : 0.45)
                .setStroke()
            line.lineWidth = 1
            line.stroke()
            return
        }

        let accent = ThemeStore.current.accent
        let leadFont: NSFont
        let leadColor: NSColor
        let valFont: NSFont        // four component columns: input/output/cache+/cache↻
        let valColor: NSColor
        let totalFont: NSFont      // TOTAL column (index 4)
        let totalColor: NSColor
        let costFont: NSFont       // COST column (index 5) — the figure users scan
        let costColor: NSColor
        switch row.kind {
        case .header:
            leadFont = .systemFont(ofSize: 9.5, weight: .semibold); leadColor = .tertiaryLabelColor
            valFont = leadFont; valColor = .tertiaryLabelColor
            totalFont = leadFont; totalColor = .tertiaryLabelColor
            costFont = leadFont; costColor = .tertiaryLabelColor
        case .day:
            leadFont = .systemFont(ofSize: 12.5, weight: .semibold); leadColor = .labelColor
            valFont = Typography.bodyMono(11.5, weight: .semibold); valColor = .secondaryLabelColor
            totalFont = valFont; totalColor = .labelColor
            costFont = valFont; costColor = accent
        case .total:
            leadFont = .systemFont(ofSize: 12.5, weight: .bold); leadColor = .labelColor
            valFont = Typography.bodyMono(11.5, weight: .semibold); valColor = .secondaryLabelColor
            totalFont = valFont; totalColor = .labelColor
            costFont = valFont; costColor = accent
        default: // .data
            leadFont = .systemFont(ofSize: 12, weight: .regular); leadColor = .labelColor
            valFont = Typography.bodyMono(11, weight: .regular); valColor = .tertiaryLabelColor
            totalFont = Typography.bodyMono(11, weight: .medium); totalColor = .secondaryLabelColor
            costFont = Typography.bodyMono(11, weight: .semibold); costColor = .labelColor
        }

        // Leading (PROJECT) column — left edge, indented for data rows.
        let indent: CGFloat = row.kind == .data ? 16 : 0
        let leadWidth = max(0, projectColW - indent - 4)
        if row.kind == .data && !row.sub.isEmpty {
            drawText(row.leading,
                     in: NSRect(x: rect.minX + indent, y: rect.minY + 3, width: leadWidth, height: 16),
                     font: leadFont, color: leadColor, align: .left, mode: .byTruncatingMiddle)
            drawText(row.sub,
                     in: NSRect(x: rect.minX + indent, y: rect.minY + 19, width: leadWidth, height: 13),
                     font: .monospacedSystemFont(ofSize: 9.5, weight: .regular),
                     color: .tertiaryLabelColor, align: .left, mode: .byTruncatingTail)
        } else {
            let lead = row.kind == .header ? row.leading.uppercased() : row.leading
            drawText(lead,
                     in: vCenter(NSRect(x: rect.minX + indent, y: rect.minY, width: leadWidth, height: rect.height), lineH: 15),
                     font: leadFont, color: leadColor, align: .left,
                     mode: .byTruncatingTail, kern: row.kind == .header ? 0.6 : 0)
        }

        // Numeric columns — shared colX/numW, identical across every row kind so
        // the digits stack vertically. TOTAL + COST styled distinctly.
        for (i, val) in row.values.enumerated() where i < colX.count {
            let isTotal = (i == 4), isCost = (i == 5)
            let f = isCost ? costFont : (isTotal ? totalFont : valFont)
            let c = isCost ? costColor : (isTotal ? totalColor : valColor)
            let s = row.kind == .header ? val.uppercased() : val
            drawText(s,
                     in: vCenter(NSRect(x: colX[i], y: rect.minY, width: numW[i], height: rect.height), lineH: 15),
                     font: f, color: c, align: .right,
                     mode: .byClipping, kern: row.kind == .header ? 0.6 : 0)
        }

        // Hairline seating the header grid; ends at the table edge, not bounds.
        if row.kind == .header {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: rect.maxY - 0.5))
            line.line(to: NSPoint(x: tableW, y: rect.maxY - 0.5))
            NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
            line.lineWidth = 1
            line.stroke()
        }
    }

    private func vCenter(_ r: NSRect, lineH: CGFloat) -> NSRect {
        NSRect(x: r.minX, y: r.minY + (r.height - lineH) / 2, width: r.width, height: lineH)
    }

    private func drawText(_ s: String, in rect: NSRect, font: NSFont, color: NSColor,
                          align: NSTextAlignment, mode: NSLineBreakMode, kern: CGFloat = 0) {
        guard !s.isEmpty, rect.width > 0 else { return }
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = mode
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: p,
        ]
        if kern != 0 { attrs[.kern] = kern }
        (s as NSString).draw(in: rect, withAttributes: attrs)
    }
}

// MARK: - Cost drill-down detail (click a row)

/// A thin rounded proportional bar (track + fill) for the bucket breakdown.
private final class ProportionBar: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var fill: NSColor = .systemBlue { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 5) }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5)
        NSColor.separatorColor.withAlphaComponent(0.35).setFill(); track.fill()
        let w = max(0, min(1, fraction)) * bounds.width
        guard w > 0.5 else { return }
        let f = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 2.5, yRadius: 2.5)
        fill.setFill(); f.fill()
    }
}

/// Popover content for a clicked Cost row: the four token buckets with their
/// cost share, the dominant line highlighted, and a plain-language cache
/// explainer — the "click for detail" + "teach me what cache is" request.
final class CostDetailViewController: NSViewController {
    private let detail: CostRowDetail
    init(detail: CostRowDetail) { self.detail = detail; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    private struct Bucket { let name: String; let tokens: UInt64; let cost: Double?; let frac: CGFloat; let color: NSColor }

    override func loadView() {
        let width: CGFloat = 360
        let root = NSView(); root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true

        // Per-bucket cost share. Closed-form & exact for Claude-only rows
        // (output 5×, cache-write 1.25×, cache-read 0.1× of input — rate cancels);
        // for rows that include a non-Claude (Codex/GPT) model the ratios differ,
        // so we show token volume only and skip the per-bucket dollar split.
        let isAllClaude = detail.models.allSatisfy { m in
            let l = m.lowercased()
            return !l.contains("gpt") && !l.contains("codex") && !l.contains("o1")
                && !l.contains("o3") && !l.contains("o4") && !l.contains("gemini")
        }
        let wIn = Double(detail.input) * 1.0
        let wOut = Double(detail.output) * 5.0
        let wCw = Double(detail.cacheCreate) * 1.25
        let wCr = Double(detail.cacheRead) * 0.1
        let wSum = wIn + wOut + wCw + wCr
        func cost(_ w: Double) -> Double? { (isAllClaude && wSum > 0) ? detail.totalCost * (w / wSum) : nil }
        func frac(_ w: Double) -> CGFloat { wSum > 0 ? CGFloat(w / wSum) : 0 }

        let accent = ThemeStore.current.accent
        let buckets = [
            Bucket(name: L10n.text("Input", "Girdi"), tokens: detail.input, cost: cost(wIn), frac: frac(wIn), color: .systemGray),
            Bucket(name: L10n.text("Output", "Çıktı"), tokens: detail.output, cost: cost(wOut), frac: frac(wOut), color: .systemTeal),
            Bucket(name: L10n.text("Cache write (cache+)", "Önbellek yazma (önbel+)"), tokens: detail.cacheCreate, cost: cost(wCw), frac: frac(wCw), color: .systemOrange),
            Bucket(name: L10n.text("Cache read (cache↻)", "Önbellek okuma (önbel↻)"), tokens: detail.cacheRead, cost: cost(wCr), frac: frac(wCr), color: accent),
        ]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        // Header: project + day · models, total cost on the right.
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.distribution = .fill
        let title = NSTextField(labelWithString: detail.project)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let cost = NSTextField(labelWithString: ContextSnapshot.formatUSD(detail.totalCost))
        cost.font = Typography.bodyMono(14, weight: .bold)
        cost.textColor = accent
        cost.setContentHuggingPriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(cost)
        stack.addArrangedSubview(titleRow)
        titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let sub = NSTextField(labelWithString: "\(detail.dayLabel) · \(detail.models.joined(separator: ", "))")
        sub.font = .systemFont(ofSize: 10.5, weight: .regular)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(sub)
        sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.addArrangedSubview(divider(width: width))

        // Bucket rows — emphasize the dominant cost line (usually cache read).
        let weights = [wIn, wOut, wCw, wCr]
        let topIdx = weights.firstIndex(of: weights.max() ?? 0) ?? 3
        for (i, b) in buckets.enumerated() {
            stack.addArrangedSubview(bucketRow(b, emphasize: i == topIdx, width: width))
        }

        stack.addArrangedSubview(divider(width: width))

        // Plain-language explainer (the educational ask).
        let explainTitle = NSTextField(labelWithString: L10n.text("Where the money goes", "Para nereye gidiyor"))
        explainTitle.font = .systemFont(ofSize: 10, weight: .semibold)
        explainTitle.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(explainTitle)

        let lines = [
            L10n.text(
                "Cache read (cache↻) is replayed context — served from cache at 0.1× the input price. It's the cheapest per token, but a long session replays it every turn, so its volume usually makes it the biggest line.",
                "Önbellek okuma (önbel↻), tekrar oynatılan bağlamdır — önbellekten girdi fiyatının 0.1 katına gelir. Token başına en ucuzu, ama uzun bir oturum onu her turda tekrar oynatır; bu yüzden hacmi genelde en büyük kalemi yapar."),
            L10n.text(
                "Cache write (cache+) stores context for reuse, billed 1.25× input (5-min) or 2× (1-hour). Total Tokens sums all four buckets — it measures replay, not fresh work.",
                "Önbellek yazma (önbel+) bağlamı tekrar kullanım için saklar; girdinin 1.25 katı (5 dk) veya 2 katı (1 saat). Toplam Token dört kovayı toplar — yapılan işi değil, tekrarı ölçer."),
            L10n.text(
                "To spend less: keep sessions focused and clear context between tasks; reserve multi-agent / parallel runs for hard problems — they use far more tokens.",
                "Daha az harcamak için: oturumları odaklı tut, görevler arası bağlamı temizle; çoklu-ajan / paralel çalıştırmaları zor problemlere sakla — çok daha fazla token harcarlar."),
        ]
        for t in lines {
            let l = NSTextField(wrappingLabelWithString: t)
            l.font = .systemFont(ofSize: 11, weight: .regular)
            l.textColor = .secondaryLabelColor
            l.preferredMaxLayoutWidth = width - 2 * Spacing.m
            stack.addArrangedSubview(l)
            l.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if !isAllClaude {
            let note = NSTextField(wrappingLabelWithString: L10n.text(
                "Per-bucket cost is shown only for Claude-only rows (this row mixes providers, so only token volumes are shown).",
                "Kova başına maliyet yalnızca Claude-only satırlarda gösterilir (bu satır sağlayıcıları karıştırıyor, sadece token hacmi gösteriliyor)."))
            note.font = .systemFont(ofSize: 10, weight: .regular)
            note.textColor = .tertiaryLabelColor
            note.preferredMaxLayoutWidth = width - 2 * Spacing.m
            stack.addArrangedSubview(note)
            note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: width),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Spacing.m),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Spacing.m),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Spacing.m),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Spacing.m),
        ])
        view = root
        root.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: width, height: ceil(root.fittingSize.height))
    }

    private func bucketRow(_ b: Bucket, emphasize: Bool, width: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: b.name)
        name.font = .systemFont(ofSize: 11.5, weight: emphasize ? .semibold : .regular)
        name.textColor = emphasize ? .labelColor : .secondaryLabelColor
        name.lineBreakMode = .byTruncatingTail
        let right = NSTextField(labelWithString: b.cost.map { ContextSnapshot.formatUSD($0) } ?? ContextSnapshot.formatTokens(b.tokens))
        right.font = Typography.bodyMono(11.5, weight: emphasize ? .semibold : .regular)
        right.textColor = emphasize ? b.color : .secondaryLabelColor
        right.alignment = .right
        right.setContentHuggingPriority(.required, for: .horizontal)
        let toks = NSTextField(labelWithString: ContextSnapshot.formatTokens(b.tokens) + L10n.text(" tok", " tok"))
        toks.font = Typography.bodyMono(9.5, weight: .regular)
        toks.textColor = .tertiaryLabelColor
        let bar = ProportionBar(); bar.fraction = b.frac; bar.fill = b.color
        bar.translatesAutoresizingMaskIntoConstraints = false
        [name, right, toks, bar].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; container.addSubview($0) }
        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: container.topAnchor),
            name.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            right.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
            right.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
            bar.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 5),
            toks.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            toks.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toks.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: width - 2 * Spacing.m),
        ])
        // Hide the redundant token line when the right side already shows tokens (no cost).
        toks.isHidden = (b.cost == nil)
        return container
    }

    private func divider(width: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        v.widthAnchor.constraint(equalToConstant: width - 2 * Spacing.m).isActive = true
        return v
    }
}
