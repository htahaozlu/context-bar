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
    private let heroCard = CostHeroView()
    private let tilesStack = NSStackView()
    private let savingsLabel = NSTextField(labelWithString: "")
    private let sparkHost = NSView()
    private let instancesStack = NSStackView()
    private let instancesView = CostInstancesView()
    private var costDetailPopover: NSPopover?
    private let footnote = NSTextField(labelWithString: "")
    private let aiButton = NSButton()
    private let aiSpinner = NSProgressIndicator()
    private let aiResult = NSTextField(wrappingLabelWithString: "")
    private let machinesHost = NSStackView()
    private let modelsHost = NSStackView()
    /// Host opens Settings → Privacy (where the AI key lives) — a gentle,
    /// one-click discovery path, not a nag.
    var onShowPrivacy: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reload()
    }

    private func buildUI() {
        // Clarity banner first (Codex/UX review): what you actually pay, the
        // hypothetical metered-API value, the subscription saving, and budget
        // pace — so the big number never reads as a bill.
        addHero(heroCard)

        let controlsStack = NSStackView()
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 10
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        providerControl.segmentStyle = .texturedRounded
        providerControl.segmentCount = 2
        providerControl.setLabel("Claude", forSegment: 0)
        providerControl.setLabel("Codex", forSegment: 1)
        providerControl.selectedSegment = 0
        providerControl.target = self
        providerControl.action = #selector(providerChanged(_:))
        providerControl.translatesAutoresizingMaskIntoConstraints = false

        rangeControl.segmentStyle = .texturedRounded
        rangeControl.segmentCount = 2
        rangeControl.setLabel(L10n.text("Last 7 days", "Son 7 gün"), forSegment: 0)
        rangeControl.setLabel(L10n.text("Last 30 days", "Son 30 gün"), forSegment: 1)
        rangeControl.selectedSegment = 1
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged(_:))
        rangeControl.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Cost & value", "Maliyet ve değer"),
            subtitle: L10n.text("Provider and rolling window for the estimate.",
                                "Tahmin için sağlayıcı ve kayan pencere."),
            symbol: "dollarsign.circle",
            info: L10n.text(
                "Each provider is priced from its own transcripts. The hero keeps the 'not a bill' explanation pinned above the rest of the tab.",
                "Her sağlayıcı kendi transkriptlerinden fiyatlanır. Hero kart 'fatura değil' açıklamasını sekmenin üstünde sabit tutar."),
            body: controlsStack
        )
        controlsStack.addArrangedSubview(providerControl)
        controlsStack.addArrangedSubview(rangeControl)

        tilesStack.orientation = .vertical
        tilesStack.alignment = .leading
        tilesStack.spacing = 10
        tilesStack.translatesAutoresizingMaskIntoConstraints = false

        savingsLabel.font = NSFont.systemFont(ofSize: 11)
        savingsLabel.textColor = .secondaryLabelColor
        savingsLabel.maximumNumberOfLines = 0
        savingsLabel.translatesAutoresizingMaskIntoConstraints = false

        let costStack = NSStackView(views: [tilesStack, savingsLabel])
        costStack.orientation = .vertical
        costStack.alignment = .leading
        costStack.spacing = 10
        costStack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Estimated cost", "Tahmini maliyet"),
            subtitle: L10n.text(
                "Priced as if metered — not your bill.",
                "Ölçümlüymüş gibi fiyatlandı — fatura değil."
            ),
            symbol: "function",
            info: L10n.text(
                "What this usage would cost on the pay-per-token API. You're on a subscription, so these are estimates, not charges. today / 7d / 30d windows, plus 30-day input vs output token totals.",
                "Bu kullanımın token başına ödenen API'de tutacağı tutar. Aboneliktesin, bu yüzden bunlar tahmindir, fatura değil. bugün / 7g / 30g pencereleri ve 30 günlük girdi/çıktı token toplamları."
            ),
            body: costStack
        )
        tilesStack.widthAnchor.constraint(equalTo: costStack.widthAnchor).isActive = true
        savingsLabel.widthAnchor.constraint(equalTo: costStack.widthAnchor).isActive = true

        // Cross-machine combined cost — a headline summary, so it sits right
        // under the estimate tiles (only meaningful once a sync folder is set).
        machinesHost.orientation = .vertical
        machinesHost.alignment = .leading
        machinesHost.spacing = 6
        machinesHost.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Across your Macs", "Mac'lerin arasında"),
            subtitle: L10n.text("Combined 30-day cost across machines.",
                                "Makineler arası birleşik 30 günlük maliyet."),
            symbol: "macbook.and.iphone",
            info: L10n.text(
                "Combined 30-day estimated cost from every Mac writing to your sync folder (set it in Privacy settings).",
                "Senkron klasörüne yazan her Mac'in son 30 günlük tahmini maliyeti birleşik (Gizlilik ayarlarından klasörü gir)."),
            body: machinesHost
        )

        sparkHost.translatesAutoresizingMaskIntoConstraints = false
        sparkHost.heightAnchor.constraint(equalToConstant: 150).isActive = true
        addSection(
            title: L10n.text("Cost trend (30 days)", "Maliyet trendi (30 gün)"),
            subtitle: L10n.text("Estimated daily cost — hover for a day.",
                                "Tahmini günlük maliyet — gün için üzerine gel."),
            symbol: "chart.xyaxis.line",
            body: sparkHost
        )

        // Per-model cost — REAL `by_model` dollars (Claude only), each tagged
        // with its plan/API availability, over a compact "how this is
        // calculated" note. Mirrors the redesign's model-filter surface.
        modelsHost.orientation = .vertical
        modelsHost.alignment = .leading
        modelsHost.spacing = Spacing.s
        modelsHost.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Cost by model", "Modele göre maliyet"),
            subtitle: L10n.text("Where the estimate comes from, model by model.",
                                "Tahminin model model nereden geldiği."),
            symbol: "square.stack.3d.up",
            info: L10n.text(
                "Per-model API-equivalent cost from your transcripts. Plan models show value your flat plan covers; models removed from the plan (or API-only) show real spend billed to your key.",
                "Transkriptlerinden model başına API-eşdeğeri maliyet. Plan modelleri planının karşıladığı değeri gösterir; plandan çıkan (veya yalnızca-API) modeller anahtarına faturalanan gerçek harcamayı gösterir."),
            body: modelsHost
        )
        modelsHost.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        instancesStack.orientation = .vertical
        instancesStack.alignment = .leading
        instancesStack.spacing = 8
        instancesStack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Daily cost by project", "Projeye göre günlük maliyet"),
            subtitle: L10n.text("One row per project per day. Click a row for detail.",
                                "Gün başına proje başına bir satır. Detay için satıra tıkla."),
            symbol: "tablecells",
            info: L10n.text(
                "One row per project per day — like `better-ccusage daily --instances`. Click any row for a token-bucket breakdown and a plain-language cache explainer.",
                "Gün başına proje başına bir satır — `better-ccusage daily --instances` gibi. Token dağılımı ve sade önbellek açıklaması için bir satıra tıkla."),
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
            subtitle: L10n.text("Usage tips from your own AI key.",
                                "Kendi AI anahtarınla kullanım önerileri."),
            symbol: "sparkles",
            info: L10n.text(
                "Get usage-efficiency tips from your own OpenAI / Gemini key (set it in Privacy settings). Sends an aggregate summary only — no transcripts, no project names.",
                "Kendi OpenAI / Gemini anahtarınla kullanım verimliliği önerileri al (Gizlilik ayarlarından gir). Yalnızca özet gönderir — transcript yok, proje adı yok."),
            body: aiStack
        )

        footnote.font = NSFont.systemFont(ofSize: 10)
        footnote.textColor = .tertiaryLabelColor
        footnote.maximumNumberOfLines = 0
        footnote.translatesAutoresizingMaskIntoConstraints = false
        addSection(title: L10n.text("Source", "Kaynak"), subtitle: nil,
                   symbol: "doc.text", body: footnote)
    }

    private func populateMachines() {
        machinesHost.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func line(_ s: String, color: NSColor = .secondaryLabelColor, bold: Bool = false) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = bold ? Typography.bodyMono(12, weight: .semibold) : Typography.bodyMono(11.5, weight: .regular)
            l.textColor = color
            return l
        }
        // PLANE 1 — Account · all machines · live. Rolling 5h/7d limits come
        // from the account usage API, so they already count every machine in
        // real time (no shared folder needed). This is the honest "account
        // overall" view; cross-machine token/cost TOTALS aren't exposed by the
        // API, only these utilization windows.
        machinesHost.addArrangedSubview(line(
            L10n.text("Account · all machines · live", "Hesap · tüm makineler · canlı"),
            color: .labelColor, bold: true))
        let (_, agents, _) = ContextSnapshot().load()
        var anyLimit = false
        for ag in agents {
            let p5 = ag.session5hPercent.map { "\(Int($0.rounded()))%" }
            let p7 = ag.week7dPercent.map { "\(Int($0.rounded()))%" }
            guard p5 != nil || p7 != nil else { continue }
            anyLimit = true
            machinesHost.addArrangedSubview(line("  \(ag.name) — "
                + L10n.text("5h ", "5sa ") + (p5 ?? "—") + "  ·  "
                + L10n.text("7d ", "7g ") + (p7 ?? "—")))
        }
        machinesHost.addArrangedSubview(line(anyLimit
            ? L10n.text("Rolling limits — count every machine, in real time.",
                        "Yuvarlanan limitler — her makineyi gerçek zamanlı sayar.")
            : L10n.text("Sign in to Claude/Codex to see account-wide limits.",
                        "Hesap-geneli limitler için Claude/Codex'e giriş yap."),
            color: .tertiaryLabelColor))

        // PLANE 2 — Per machine · local 30-day cost (optional, via a synced
        // folder; the API can't break cost down by machine).
        machinesHost.addArrangedSubview(line(
            L10n.text("Per machine · local 30-day", "Makine başına · yerel 30 gün"),
            color: .labelColor, bold: true))
        if DisplayPrefs.syncFolder.isEmpty {
            machinesHost.addArrangedSubview(line(L10n.text(
                "Optional. Pick a folder you already sync (Settings → Privacy) so each Mac shows separately.",
                "İsteğe bağlı. Zaten senkronladığın bir klasör seç (Ayarlar → Gizlilik) ki her Mac ayrı görünsün."),
                color: .tertiaryLabelColor))
            return
        }
        let machines = MachineSync.readAll()
        if machines.isEmpty {
            machinesHost.addArrangedSubview(line(L10n.text(
                "No machine data yet — appears once each Mac has written + synced.",
                "Henüz makine verisi yok — her Mac yazıp senkronlayınca görünür."), color: .tertiaryLabelColor))
            return
        }
        let combined = machines.reduce(0.0) { $0 + $1.grandCost }
        machinesHost.addArrangedSubview(line(
            L10n.text("Combined: ", "Birleşik: ") + ContextSnapshot.formatUSD(combined)
                + "  ·  \(machines.count) " + L10n.text("Macs", "Mac")))
        // "This Mac" first, then by cost; bar = share of the busiest Mac.
        let sorted = machines.sorted {
            ($0.isSelf ? 1 : 0, $0.grandCost) > ($1.isSelf ? 1 : 0, $1.grandCost)
        }
        let maxCost = machines.map(\.grandCost).max() ?? 0
        let bars = ProjectBreakdownView()
        bars.translatesAutoresizingMaskIntoConstraints = false
        bars.rows = sorted.map { m in
            let tag = m.isSelf ? "  ·  " + L10n.text("this Mac", "bu Mac") : ""
            return ProjectBreakdownView.Row(
                name: m.machine + tag,
                tokens: m.grandTokens,
                cost: m.grandCost,
                share: maxCost > 0 ? m.grandCost / maxCost : 0)
        }
        machinesHost.addArrangedSubview(bars)
        bars.widthAnchor.constraint(equalTo: machinesHost.widthAnchor).isActive = true
    }

    /// Switch the AI button between "connect a key" (discovery) and "analyze".
    private func updateAIButton() {
        let ready = DisplayPrefs.aiProvider != .off && AIKeychain.hasKey(for: DisplayPrefs.aiProvider)
        if ready {
            aiButton.title = L10n.text("Analyze my usage", "Kullanımımı analiz et")
            aiButton.action = #selector(analyzeAI)
        } else {
            aiButton.title = L10n.text("Connect a key to get tips →", "İpuçları için anahtar bağla →")
            aiButton.action = #selector(openAISettings)
        }
    }

    @objc private func openAISettings() { onShowPrivacy?() }

    @objc private func analyzeAI() {
        guard DisplayPrefs.aiProvider != .off, AIKeychain.hasKey(for: DisplayPrefs.aiProvider) else {
            updateAIButton()
            onShowPrivacy?()
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
    /// One row of REAL per-model cost from the snapshot's `by_model` bucket
    /// (all-time within the scanned window). `cost` and `tokens` are exact;
    /// nothing here is fabricated.
    private struct ModelCost { let model: String; let tokens: UInt64; let cost: Double }
    private struct CostData {
        var instances: [Instance] = []
        var dailyPoints: [DailyPoint] = []   // last 30 days, oldest → newest
        var byModel: [ModelCost] = []        // real per-model cost, tokens-desc
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
        // Real per-model cost (all-time within scanned files), tokens-desc as
        // the engine emits it. Carries an exact `cost` — never synthesized.
        out.byModel = ((c["by_model"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let m = o["model"] as? String else { return nil }
            return ModelCost(model: m, tokens: u64(o["tokens"]), cost: dbl(o["cost"]))
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
        populateMachines()
        updateAIButton()
        let data = loadData()

        // Clarity hero — plan price only for Claude (Codex has no per-plan list
        // price). Estimated monthly drives the big "API value" number + budget.
        let planPrice = (provider == .claude) ? planMonthlyPrice(data.planType, data.planTier) : nil
        let planLabel = planPrice != nil ? planName(data.planType, data.planTier) : nil
        heroCard.update(planName: planLabel, planPrice: planPrice,
                        estMonthly: data.cost30d, budget: DisplayPrefs.monthlyBudgetUSD)

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

        renderSavings(data)
        renderTrend(data.dailyPoints)
        renderModels(data.byModel)
        renderInstances(visible)

        let src = data.pricingSource.map { srcLabel($0) } ?? "—"
        footnote.stringValue = L10n.text(
            "Rates: \(src). Estimated as if metered. Subscription usage isn't billed per token; API-key usage is — the transcripts don't record which mode a session used, so all of it is shown as an estimate.",
            "Oranlar: \(src). Ölçümlüymüş gibi tahmin. Abonelik kullanımı token başına faturalanmaz; API-key kullanımı faturalanır — transkriptler bir oturumun hangi modda olduğunu kaydetmediği için hepsi tahmin olarak gösterilir."
        )
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
        chart.tint = Palette.accent
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

    // MARK: - Per-model cost

    /// Static availability for a prettified Claude model name. Mirrors the
    /// redesign's `models.jsx`: Sonnet 3.7 sunsets Jun 22 (API-only after),
    /// Opus 4.8 is API-only, everything else is covered by the plan.
    private func availability(for pretty: String) -> ModelAvail {
        let p = pretty.lowercased()
        if p.hasPrefix("sonnet 3.7") { return .sunset("Jun 22") }
        if p.hasPrefix("opus 4.8") { return .api }
        return .plan
    }

    /// Per-model cost card — REAL `by_model` dollars, Claude-only (the per-plan
    /// vs API-only distinction is an Anthropic concept; Codex has no plan), a
    /// thin accent bar for share of the top model, and an availability badge.
    /// Always followed by the "how this is calculated" note. When there's no
    /// Claude per-model data we still show the note — never a fabricated row.
    private func renderModels(_ models: [ModelCost]) {
        modelsHost.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Claude only: collapse repeated-suffix variants under one pretty name,
        // keep tokens-desc, drop empties. Codex/GPT rows are excluded entirely.
        var byName: [(name: String, tokens: UInt64, cost: Double)] = []
        var index: [String: Int] = [:]
        for m in models where m.cost > 0 || m.tokens > 0 {
            let lower = m.model.lowercased()
            guard !(lower.contains("gpt") || lower.contains("codex")
                    || lower.contains("gemini") || lower.contains("o1")
                    || lower.contains("o3") || lower.contains("o4")) else { continue }
            let pretty = prettyModel(m.model)
            if let i = index[pretty] {
                byName[i].tokens += m.tokens
                byName[i].cost += m.cost
            } else {
                index[pretty] = byName.count
                byName.append((pretty, m.tokens, m.cost))
            }
        }
        byName.sort { $0.cost > $1.cost }

        let card = NSView()
        Surface.applyCard(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: Spacing.s),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Spacing.m),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Spacing.m),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Spacing.s),
        ])

        // Caption strip — "value · billed", the right-side meaning legend.
        let head = NSStackView()
        head.orientation = .horizontal
        head.distribution = .fill
        head.alignment = .firstBaseline
        let headL = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(L10n.text("Cost by model · 30d", "Modele göre maliyet · 30g"),
                                         color: Palette.secondaryText))
        headL.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headR = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(L10n.text("value · billed", "değer · faturalı"),
                                         color: Palette.tertiaryText))
        headR.setContentHuggingPriority(.required, for: .horizontal)
        head.addArrangedSubview(headL)
        head.addArrangedSubview(headR)
        inner.addArrangedSubview(head)
        head.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        inner.setCustomSpacing(Spacing.xs, after: head)

        if byName.isEmpty {
            let empty = NSTextField(labelWithString: L10n.text(
                "No Claude per-model cost yet.", "Henüz Claude model maliyeti yok."))
            empty.font = Typography.body(12)
            empty.textColor = Palette.secondaryText
            inner.addArrangedSubview(empty)
        } else {
            let maxCost = byName.map(\.cost).max() ?? 0
            for (i, m) in byName.enumerated() {
                let row = ModelCostRowView(
                    name: m.name,
                    avail: availability(for: m.name),
                    tokens: m.tokens,
                    cost: m.cost,
                    share: maxCost > 0 ? CGFloat(m.cost / maxCost) : 0,
                    tokensFmt: { ContextSnapshot.formatTokens($0) },
                    usd: formatUSD)
                row.translatesAutoresizingMaskIntoConstraints = false
                inner.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
                if i < byName.count - 1 {
                    let hair = NSView()
                    hair.wantsLayer = true
                    hair.layer?.backgroundColor = Palette.hairline.cgColor
                    hair.translatesAutoresizingMaskIntoConstraints = false
                    hair.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                    inner.addArrangedSubview(hair)
                    hair.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
                }
            }
        }

        modelsHost.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: modelsHost.widthAnchor).isActive = true

        // "How this is calculated" — always present (legend + Σ formula).
        let note = CostCalcNoteView()
        note.translatesAutoresizingMaskIntoConstraints = false
        modelsHost.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: modelsHost.widthAnchor).isActive = true
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

        // Build a flat, lightened row model: a caption header, one row per
        // project-per-day (date · project · input/output/cache segmented bar ·
        // total · chevron), then a grand Total. A single custom view draws only
        // the rows intersecting the dirty rect — no per-cell NSViews, so the tab
        // opens instantly regardless of row count. The date column repeats only
        // when the day changes, so a busy day reads as one dated group.
        var order: [String] = []
        var byDay: [String: [Instance]] = [:]
        for it in items {
            if byDay[it.date] == nil { order.append(it.date) }
            byDay[it.date, default: []].append(it)
        }

        var modelRows: [CostRow] = [
            CostRow(kind: .header, date: "",
                    project: L10n.text("Daily breakdown", "Günlük dağılım"),
                    cost: L10n.text("input · output · cache", "girdi · çıktı · önbellek"),
                    segments: []),
        ]
        var gIn: UInt64 = 0, gOut: UInt64 = 0, gCache: UInt64 = 0
        var gCost = 0.0
        for day in order {
            let dayRows = (byDay[day] ?? []).sorted { $0.cost > $1.cost }
            let shortDay = shortDayLabel(day)
            for (j, it) in dayRows.enumerated() {
                // Total = all four token buckets (ccusage "Total Tokens"); the
                // bar collapses the two cache buckets into one "cache" segment.
                let cacheTok = it.cacheCreate + it.cacheRead
                let rowTotal = it.input + it.output + cacheTok
                gIn += it.input; gOut += it.output; gCache += cacheTok; gCost += it.cost
                let denom = Double(rowTotal)
                let seg: [CGFloat] = denom > 0
                    ? [CGFloat(Double(it.input) / denom),
                       CGFloat(Double(it.output) / denom),
                       CGFloat(Double(cacheTok) / denom)]
                    : []
                modelRows.append(CostRow(kind: .data,
                    date: j == 0 ? shortDay : "",   // show the date once per day
                    project: it.project,
                    cost: formatUSD(it.cost),
                    segments: seg,
                    detail: CostRowDetail(dayLabel: formatDay(day), project: it.project,
                        models: it.models.map(prettyModel), input: it.input, output: it.output,
                        cacheCreate: it.cacheCreate, cacheRead: it.cacheRead,
                        totalTokens: it.input + it.output + it.cacheCreate + it.cacheRead,
                        totalCost: it.cost)))
            }
        }
        let gTotal = gIn + gOut + gCache
        let gDenom = Double(gTotal)
        let gSeg: [CGFloat] = gDenom > 0
            ? [CGFloat(Double(gIn) / gDenom), CGFloat(Double(gOut) / gDenom), CGFloat(Double(gCache) / gDenom)]
            : []
        modelRows.append(CostRow(kind: .total, date: "",
            project: L10n.text("Total", "Toplam"), cost: formatUSD(gCost), segments: gSeg))

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

    /// Compact mono date for the daily-breakdown rows ("Jun 9" / "9 Haz").
    private func shortDayLabel(_ iso: String) -> String {
        guard let date = dateFromKey(iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        out.dateFormat = L10n.lang == .tr ? "d MMM" : "MMM d"
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
    enum Kind { case header, data, total }
    let kind: Kind
    /// `.data`: short mono date (e.g. "Jun 9"). `.total`: "Total". `.header`: "".
    let date: String
    /// `.data`: project name. `.header`/`.total`: a leading caption.
    let project: String
    /// Formatted cost (mono), right-aligned. Empty for the header row.
    let cost: String
    /// Segment fractions [input, output, cache] for the bar (sum ≤ 1). The
    /// header carries an empty array; rows draw the accent/58%/26% segments.
    let segments: [CGFloat]
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

    // Fixed left columns: a short mono date, then the project name; the
    // segmented bar flexes to fill the middle; cost + chevron are right-anchored.
    private let dateW: CGFloat = 50
    private let projW: CGFloat = 124
    private let costW: CGFloat = 56
    private let chevW: CGFloat = 16
    private let colGap: CGFloat = 12

    private func rowHeight(_ k: CostRow.Kind) -> CGFloat {
        switch k {
        case .header: return 26
        case .data: return 36
        case .total: return 38
        }
    }

    private var totalHeight: CGFloat { rows.reduce(0) { $0 + rowHeight($1.kind) } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(totalHeight))
    }

    override func layout() {
        super.layout()
        // Width changes (window resize) reflow the flexible segmented bar.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let h = rowHeight(row.kind)
            let rect = NSRect(x: 0, y: y, width: bounds.width, height: h)
            if rect.intersects(dirtyRect) {
                // Hover affordance on clickable rows.
                if i == hoveredRowIndex, row.detail != nil {
                    Palette.accent.withAlphaComponent(0.08).setFill()
                    NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: 1), xRadius: 6, yRadius: 6).fill()
                }
                // Top hairline between rows (not before the header).
                if i > 0 {
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: 0, y: rect.minY + 0.25))
                    line.line(to: NSPoint(x: bounds.width, y: rect.minY + 0.25))
                    Palette.hairline.setStroke()
                    line.lineWidth = 0.5
                    line.stroke()
                }
                drawRow(row, rect: rect)
            }
            y += h
        }
    }

    private func drawRow(_ row: CostRow, rect: NSRect) {
        let accent = Palette.accent

        // Geometry: date | project | [flex bar] | cost | chevron.
        let barLeft = rect.minX + dateW + colGap + projW + colGap
        let chevX = rect.maxX - chevW
        let costX = chevX - costW
        let barRight = costX - colGap
        let barW = max(0, barRight - barLeft)

        switch row.kind {
        case .header:
            // Caption row — leading label left, "input · output · cache" right.
            drawText(row.project.uppercased(),
                     in: vCenter(NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.5, height: rect.height), lineH: 14),
                     font: Typography.caption(), color: Palette.tertiaryText,
                     align: .left, mode: .byTruncatingTail, kern: 0.8)
            drawText(row.cost.uppercased(),
                     in: vCenter(NSRect(x: rect.maxX - rect.width * 0.5, y: rect.minY, width: rect.width * 0.5, height: rect.height), lineH: 14),
                     font: Typography.caption(), color: Palette.tertiaryText,
                     align: .right, mode: .byTruncatingTail, kern: 0.5)
            return
        case .data, .total:
            let isTotal = row.kind == .total
            // Date (mono) — left.
            drawText(row.date,
                     in: vCenter(NSRect(x: rect.minX, y: rect.minY, width: dateW, height: rect.height), lineH: 15),
                     font: Typography.bodyMono(11, weight: .regular),
                     color: Palette.secondaryText, align: .left, mode: .byClipping)
            // Project / "Total" — body.
            let projX = rect.minX + dateW + colGap
            drawText(isTotal ? row.project : row.project,
                     in: vCenter(NSRect(x: projX, y: rect.minY, width: projW, height: rect.height), lineH: 15),
                     font: isTotal ? Typography.title(12.5) : Typography.body(12),
                     color: Palette.primaryText, align: .left, mode: .byTruncatingMiddle)
            // Segmented bar — accent / 58% / 26% over the neutral track.
            if barW > 4 {
                drawSegmentedBar(row.segments, in: NSRect(x: barLeft, y: rect.midY - 3.5, width: barW, height: 7), accent: accent)
            }
            // Cost (mono) — right.
            drawText(row.cost,
                     in: vCenter(NSRect(x: costX, y: rect.minY, width: costW, height: rect.height), lineH: 15),
                     font: Typography.bodyMono(12.5, weight: isTotal ? .bold : .semibold),
                     color: Palette.primaryText, align: .right, mode: .byClipping)
            // Chevron — only on clickable data rows.
            if !isTotal {
                drawChevron(at: NSPoint(x: chevX + 3, y: rect.midY), color: Palette.tertiaryText)
            }
        }
    }

    /// Three-segment bar (input · output · cache) tinted accent / 58% / 26% of
    /// the accent, seated on the neutral track. Mirrors the redesign's `cb-seg`.
    private func drawSegmentedBar(_ segments: [CGFloat], in rect: NSRect, accent: NSColor) {
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        Palette.track.setFill(); track.fill()
        guard segments.count == 3, segments.reduce(0, +) > 0 else { return }
        let colors = [accent, accent.withAlphaComponent(0.58), accent.withAlphaComponent(0.26)]
        NSGraphicsContext.current?.saveGraphicsState()
        track.addClip()
        var x = rect.minX
        for (i, frac) in segments.enumerated() {
            let w = rect.width * max(0, min(1, frac))
            guard w > 0.3 else { continue }
            colors[i].setFill()
            NSBezierPath(rect: NSRect(x: x, y: rect.minY, width: w + 0.5, height: rect.height)).fill()
            x += w
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// A small right-pointing chevron (drill-down affordance).
    private func drawChevron(at center: NSPoint, color: NSColor) {
        let s: CGFloat = 3.2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x - s / 2, y: center.y + s))
        path.line(to: NSPoint(x: center.x + s / 2, y: center.y))
        path.line(to: NSPoint(x: center.x - s / 2, y: center.y - s))
        color.setStroke()
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
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

        let accent = Palette.accent
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

// MARK: - Cost clarity hero
//
// The banner that answers the #1 confusion: "I pay $20/mo but the Cost tab
// shows thousands." It states, in order: what you actually pay (plan price),
// the big hypothetical metered-API value, a plain "this is not a bill" line,
// the subscription saving (positive framing), and — when set — how the pace
// compares to the user's monthly budget (same thresholds as the menubar tint).
final class CostHeroView: NSView {
    private let stack = NSStackView()
    /// 2.5pt clay accent stripe seated along the hero's top edge — the redesign
    /// signature. Drawn as a sublayer so it follows the continuous corner.
    private let stripe = CALayer()
    /// Last inputs, so a theme switch or light/dark toggle can re-render with
    /// freshly contrast-corrected colors (text colors are baked, not dynamic).
    private var pending: (name: String?, price: Double?, est: Double, budget: Double)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Surface.applyHero(self)
        // Clip the stripe to the rounded top; the elevation shadow still shows
        // because it's cast by the layer itself (masksToBounds stays false on
        // the host — the stripe rides a dedicated, clipped sublayer instead).
        stripe.cornerRadius = Radius.hero
        stripe.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        stripe.backgroundColor = Palette.accent.cgColor
        layer?.addSublayer(stripe)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.m),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.l),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.l),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.m),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // Top stripe spans the full width; height 2.5pt. Corner radius matches
        // the hero so the stripe's top corners hug the card.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stripe.frame = CGRect(x: 0, y: bounds.height - 2.5, width: bounds.width, height: 2.5)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshHeroChrome(self)
        stripe.backgroundColor = Palette.accent.cgColor
        render()   // re-bake colors for the new light/dark appearance
    }

    func update(planName: String?, planPrice: Double?, estMonthly: Double, budget: Double) {
        pending = (planName, planPrice, estMonthly, budget)
        render()
    }

    private func render() {
        guard let p = pending else { isHidden = true; return }
        let planName = p.name, planPrice = p.price, estMonthly = p.est, budget = p.budget
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard estMonthly > 0 else { isHidden = true; return }
        isHidden = false
        // Theme accents range from system blue to neon yellow / pale lavender;
        // contrast-correct so a chip/bar accent stays legible on every theme in
        // both light and dark — never a near-invisible yellow on a light card.
        let accent = readableAccent(Palette.accent)
        stripe.backgroundColor = accent.cgColor
        let usd = ContextSnapshot.formatUSD
        let perMo = L10n.text(" / mo", " / ay")

        // Row A — caption + plan chip. "ESTIMATED VALUE · NOT A BILL" on the
        // left; on the right, the plan pill ("Max 5× · $100/mo") when known.
        let caption = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(
                L10n.text("Estimated value · not a bill", "Tahmini değer · fatura değil"),
                color: Palette.secondaryText))
        caption.lineBreakMode = .byTruncatingTail
        caption.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let captionRow: NSStackView
        if let planName, let planPrice {
            let chip = pill(text: planName + " · " + usd(planPrice) + perMo,
                            bg: Palette.track, fg: Palette.secondaryText, accentValue: usd(planPrice) + perMo)
            chip.setContentHuggingPriority(.required, for: .horizontal)
            captionRow = NSStackView(views: [caption, chip])
        } else {
            captionRow = NSStackView(views: [caption])
        }
        captionRow.orientation = .horizontal
        captionRow.distribution = .fill
        captionRow.alignment = .centerY
        captionRow.spacing = 8
        stack.addArrangedSubview(captionRow)
        pin(captionRow)
        stack.setCustomSpacing(Spacing.s, after: captionRow)

        // Row B — the big API-equivalent figure in NEUTRAL primaryText (never an
        // accent that reads as "you owe this"), with a quiet "/mo" tail.
        let bigStr = NSMutableAttributedString(string: "≈ " + usd(estMonthly), attributes: [
            .font: Typography.displayMono(40, weight: .semibold),
            .foregroundColor: Palette.primaryText,
            .kern: -0.5,
        ])
        bigStr.append(NSAttributedString(string: perMo, attributes: [
            .font: Typography.displayMono(15, weight: .regular),
            .foregroundColor: Palette.tertiaryText,
        ]))
        let big = NSTextField(labelWithAttributedString: bigStr)
        big.lineBreakMode = .byClipping
        stack.addArrangedSubview(big)
        pin(big)

        // Row C — the reassurance. The single most important line on the tab.
        let disclaimer = NSTextField(wrappingLabelWithString: L10n.text(
            "This is not a bill. You're on a subscription — it's what the same token usage would cost on the pay-per-token API.",
            "Bu bir fatura değil. Aboneliktesin — aynı token kullanımının token başına ödenen API'de tutacağı tahmini tutar."))
        disclaimer.font = .systemFont(ofSize: 12)
        disclaimer.textColor = Palette.secondaryText
        disclaimer.maximumNumberOfLines = 0
        stack.addArrangedSubview(disclaimer)
        pin(disclaimer)

        // Row D — positive framing: an accent-green "N× plan value" pill, then
        // the plain "$X more than your $Y plan" line beside it.
        if let planPrice, planPrice > 0, estMonthly > planPrice {
            let saved = estMonthly - planPrice
            let mult = estMonthly / planPrice
            let multStr = mult >= 10 ? String(format: "%.0f×", mult) : String(format: "%.1f×", mult)
            let chip = pill(
                text: multStr + " " + L10n.text("plan value", "plan değeri"),
                bg: Palette.positive.withAlphaComponent(0.16), fg: Palette.positive,
                glyph: "arrow.up.right")
            chip.setContentHuggingPriority(.required, for: .horizontal)
            let line = NSTextField(labelWithString: L10n.text(
                "\(usd(saved)) more than your \(usd(planPrice)) plan",
                "\(usd(planPrice)) planından \(usd(saved)) fazla"))
            line.font = .systemFont(ofSize: 11)
            line.textColor = Palette.secondaryText
            line.lineBreakMode = .byTruncatingTail
            let row = NSStackView(views: [chip, line])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            stack.addArrangedSubview(row)
            pin(row)
        }

        // Row E — billing-cycle pace (accent) vs the monthly budget. Warn ≥ 80%,
        // critical ≥ 100% — matches the menubar tint. One-line hook when unset.
        if budget > 0 {
            let ratio = estMonthly / budget
            let tint: NSColor = ratio >= 1.0 ? Palette.urgencyRed
                : (ratio >= 0.8 ? Palette.urgencyAmber : accent)
            let capL = NSTextField(labelWithAttributedString:
                Typography.captionAttributed(L10n.text("Billing cycle pace", "Fatura dönemi hızı"),
                                             color: Palette.tertiaryText))
            capL.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let capR = NSTextField(labelWithString: usd(estMonthly) + " / " + usd(budget)
                + String(format: " · %.0f%%", min(999, ratio * 100)))
            capR.font = Typography.bodyMono(10.5, weight: .medium)
            capR.textColor = Palette.secondaryText
            capR.alignment = .right
            capR.setContentHuggingPriority(.required, for: .horizontal)
            let capRow = NSStackView(views: [capL, capR])
            capRow.orientation = .horizontal
            capRow.distribution = .fill
            capRow.alignment = .firstBaseline
            capRow.spacing = 6

            let bar = ProgressBarView()
            bar.value = Double(min(1.0, ratio))
            bar.tint = tint
            bar.trackColor = Palette.track
            bar.corner = 3
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.heightAnchor.constraint(equalToConstant: 6).isActive = true

            let budgetStack = NSStackView(views: [capRow, bar])
            budgetStack.orientation = .vertical
            budgetStack.alignment = .leading
            budgetStack.spacing = 5
            stack.addArrangedSubview(budgetStack)
            pin(budgetStack)
            pin(capRow)
            pin(bar)
        } else {
            let hint = NSTextField(labelWithString: L10n.text(
                "Tip: set a monthly budget in Settings → General to track your pace here.",
                "İpucu: hızını burada izlemek için Ayarlar → Genel'den aylık bütçe gir."))
            hint.font = .systemFont(ofSize: 10.5)
            hint.textColor = Palette.tertiaryText
            hint.maximumNumberOfLines = 0
            stack.addArrangedSubview(hint)
            pin(hint)
        }
    }

    /// Small rounded pill — neutral or accent-tinted, optionally led by an SF
    /// Symbol and with one emphasized value substring (used for the plan chip's
    /// price). All text baked for the current appearance.
    private func pill(text: String, bg: NSColor, fg: NSColor,
                      glyph: String? = nil, accentValue: String? = nil) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.cornerRadius = Radius.chip
        host.layer?.cornerCurve = .continuous
        host.layer?.backgroundColor = bg.cgColor
        host.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: text)
        lbl.font = .systemFont(ofSize: 11.5, weight: .semibold)
        lbl.textColor = fg
        lbl.lineBreakMode = .byTruncatingTail
        if let accentValue, let r = text.range(of: accentValue) {
            let attr = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: fg,
            ])
            let ns = NSRange(r, in: text)
            attr.addAttributes([
                .font: Typography.bodyMono(11.5, weight: .semibold),
                .foregroundColor: Palette.primaryText,
            ], range: ns)
            lbl.attributedStringValue = attr
        }
        lbl.translatesAutoresizingMaskIntoConstraints = false

        let content: NSView
        if let glyph {
            let iv = symbol(glyph, fg, size: 11, weight: .bold)
            let row = NSStackView(views: [iv, lbl])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4
            row.translatesAutoresizingMaskIntoConstraints = false
            content = row
        } else {
            content = lbl
        }
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: host.topAnchor, constant: 5),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -5),
        ])
        return host
    }

    /// Adapts a theme accent so it always contrasts the frosted card: pulls
    /// over-light accents (terminal yellow, pastel lavender) down on a light
    /// card, and over-dark accents up on a dark card. Resolved against this
    /// view's effective appearance so dynamic accents (system blue, mono
    /// black/white) resolve to the right side first.
    private func readableAccent(_ color: NSColor) -> NSColor {
        var resolved = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var r = resolved.redComponent, g = resolved.greenComponent, b = resolved.blueComponent
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if !isDark, lum > 0.6 {
            let k = min(0.7, (lum - 0.45) / 0.55)
            r *= (1 - k); g *= (1 - k); b *= (1 - k)
        } else if isDark, lum < 0.35 {
            let k = min(0.7, (0.5 - lum) / 0.5)
            r += (1 - r) * k; g += (1 - g) * k; b += (1 - b) * k
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private func symbol(_ name: String, _ color: NSColor,
                        size: CGFloat = 12, weight: NSFont.Weight = .semibold) -> NSImageView {
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        iv.contentTintColor = color
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }

    private func pin(_ v: NSView) {
        v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

// MARK: - Per-model cost row + calc note

/// Plan availability for a model, driving its badge. Static product-level map —
/// the transcripts don't record which billing mode a session used, so this
/// describes how the *plan* treats each model, not a per-session fact.
/// `.sunset` carries the date the model leaves the plan (API-only after).
enum ModelAvail { case plan, sunset(String), api }

/// One model in the per-model cost card: name + availability sub-line on the
/// left, a thin accent share-bar in the middle, real USD + "value"/"billed" on
/// the right, and a small neutral/accent availability badge. Pure AppKit, drawn
/// with constraints; the dollar figure is the engine's exact `by_model` cost.
private final class ModelCostRowView: NSView {
    init(name: String, avail: ModelAvail, tokens: UInt64, cost: Double,
         share: CGFloat, tokensFmt: (UInt64) -> String, usd: (Double) -> String) {
        super.init(frame: .zero)
        let billed: Bool
        switch avail { case .plan: billed = false; default: billed = true }
        let accent = Palette.accent

        // Left: model name + availability sub-line.
        let nameLbl = NSTextField(labelWithString: name)
        nameLbl.font = Typography.body(12)
        nameLbl.textColor = Palette.primaryText
        nameLbl.lineBreakMode = .byTruncatingTail
        let subLbl = NSTextField(labelWithString: availabilitySub(avail))
        subLbl.font = Typography.body(10)
        subLbl.textColor = billed ? accent : Palette.tertiaryText
        subLbl.lineBreakMode = .byTruncatingTail
        let left = NSStackView(views: [nameLbl, subLbl])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 1
        left.translatesAutoresizingMaskIntoConstraints = false
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Middle: thin share bar (accent fill over neutral track).
        let bar = ProgressBarView()
        bar.value = Double(max(0, min(1, share)))
        bar.tint = accent
        bar.trackColor = Palette.track
        bar.corner = 2
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 5).isActive = true

        // Right: real USD + value/billed meaning. API-only spend is tinted
        // accent (it's real money on your key); plan value stays neutral.
        let isApiOnly: Bool = { if case .api = avail { return true } else { return false } }()
        let costLbl = NSTextField(labelWithString: usd(cost))
        costLbl.font = Typography.bodyMono(12, weight: .semibold)
        costLbl.textColor = isApiOnly ? accent : Palette.primaryText
        costLbl.alignment = .right
        let kindLbl = NSTextField(labelWithString: billed
            ? L10n.text("billed", "faturalı") : L10n.text("value", "değer"))
        kindLbl.font = Typography.body(9)
        kindLbl.textColor = Palette.tertiaryText
        kindLbl.alignment = .right
        let right = NSStackView(views: [costLbl, kindLbl])
        right.orientation = .vertical
        right.alignment = .trailing
        right.spacing = 1
        right.translatesAutoresizingMaskIntoConstraints = false
        right.setContentHuggingPriority(.required, for: .horizontal)
        right.setContentCompressionResistancePriority(.required, for: .horizontal)

        let badge = AvailBadgeView(avail: avail)
        badge.translatesAutoresizingMaskIntoConstraints = false

        [left, bar, right, badge].forEach { addSubview($0) }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            left.leadingAnchor.constraint(equalTo: leadingAnchor),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.widthAnchor.constraint(equalToConstant: 124),
            badge.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: Spacing.xs),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: Spacing.s),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: Spacing.s),
            right.trailingAnchor.constraint(equalTo: trailingAnchor),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.widthAnchor.constraint(equalToConstant: 64),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel("\(name), \(availabilitySub(avail))")
        setAccessibilityValue("\(usd(cost)), \(tokensFmt(tokens))")
    }
    required init?(coder: NSCoder) { fatalError() }

    private func availabilitySub(_ a: ModelAvail) -> String {
        switch a {
        case .plan: return L10n.text("In your plan", "Planında")
        case .sunset(let d): return L10n.text("Plan ends \(d)", "Plan \(d) bitiyor")
        case .api: return L10n.text("Billed to API key", "API anahtarına faturalı")
        }
    }
}

/// Small availability badge: neutral chip for plan models, an accent-tinted
/// chip for plan→API (sunset) and API-only. Drawn as a rounded pill.
private final class AvailBadgeView: NSView {
    init(avail: ModelAvail) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        let accent = Palette.accent
        let text: String
        let fg: NSColor
        let bg: NSColor
        var border: NSColor?
        switch avail {
        case .plan:
            text = L10n.text("In plan", "Planda")
            fg = Palette.tertiaryText; bg = Palette.track
        case .sunset(let d):
            text = L10n.text("Plan → API · \(d)", "Plan → API · \(d)")
            fg = accent; bg = Palette.accentSofter; border = Palette.accentSoft
        case .api:
            text = L10n.text("API-only", "Yalnızca API")
            fg = accent; bg = Palette.accentSoft
        }
        layer?.backgroundColor = bg.cgColor
        if let border {
            layer?.borderWidth = 0.5
            layer?.borderColor = border.cgColor
        }
        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = fg
        lbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            lbl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            lbl.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            lbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// "How this is calculated" note: info glyph + caption, the per-million-rate
/// explanation (cache-write ×1.25 / cache-read ×0.1), the plan-value vs
/// API-only-spend distinction, and the Σ formula. Static — no figures.
private final class CostCalcNoteView: NSView {
    init() {
        super.init(frame: .zero)
        Surface.applyCard(self)
        translatesAutoresizingMaskIntoConstraints = false

        let glyph = NSImageView()
        glyph.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        glyph.contentTintColor = Palette.secondaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        let head = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(L10n.text("How this is calculated", "Bu nasıl hesaplanıyor"),
                                         color: Palette.secondaryText))
        let headRow = NSStackView(views: [glyph, head])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 6
        headRow.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: L10n.text(
            "Tokens are read from your local transcripts and multiplied by each model's published per-million rates — input, output, cache-write (×1.25) and cache-read (×0.1). Plan models show the API-equivalent value your flat plan already covers; API-only models show real spend billed to your key.",
            "Token'lar yerel transkriptlerinden okunur ve her modelin yayımlanmış milyon-başına oranlarıyla çarpılır — girdi, çıktı, önbellek-yazma (×1.25) ve önbellek-okuma (×0.1). Plan modelleri planının zaten karşıladığı API-eşdeğeri değeri gösterir; yalnızca-API modelleri anahtarına faturalanan gerçek harcamayı gösterir."))
        body.font = Typography.body(11.5)
        body.textColor = Palette.secondaryText
        body.maximumNumberOfLines = 0

        let formula = NSTextField(labelWithString: "Σ ( tokensₘ ÷ 1M × rateₘ )   "
            + L10n.text("for each model m", "her model m için"))
        formula.font = Typography.bodyMono(10.5, weight: .regular)
        formula.textColor = Palette.tertiaryText

        let stack = NSStackView(views: [headRow, body, formula])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.s),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.m),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.m),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.s),
        ])
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        headRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}
