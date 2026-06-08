import AppKit
import Foundation

/// Stats pane — Claude-app style usage overview computed locally from
/// ~/.context-bar/context.json (the same artifact the Usage tab reads).
///
/// All numbers come from the `claude` AgentBlock written by
/// src/usage_signal.py — no synthetic data. Fields used:
///   - by_day:        last 30 days [{date, tokens, sessions}]
///   - by_month:      last 12 months [{date "YYYY-MM", tokens, sessions}]
///   - by_model:      all-time, sorted by tokens
///   - recent_sessions: last 20 with duration_minutes
///   - total_tokens_30d / total_sessions_30d
final class StatsViewController: PreferencePaneViewController {
    enum Range: Int { case all = 0, last30 = 1, last7 = 2 }
    enum Provider: Int { case claude = 0, codex = 1 }
    enum DayMode: Int { case day = 0, range = 1 }
    private var range: Range = .all
    private var provider: Provider = .claude
    private var dayMode: DayMode = .day

    private let rangeControl = NSSegmentedControl()
    private let providerControl = NSSegmentedControl()
    private let tilesStack = NSStackView()
    private let comparisonLabel = NSTextField(labelWithString: "")

    // Year heatmap + its live hover caption.
    private let heatmapView = YearHeatmapView()
    private let hoverLabel = NSTextField(labelWithString: "")

    // Daily / range drill-down.
    private let modeControl = NSSegmentedControl()
    /// Native graphical calendar, shown inside a popover off `dateButton`.
    private let datePicker = NSDatePicker()
    private let dateButton = NSButton()
    private var datePopover: NSPopover?
    private let todayButton = NSButton()
    private let selDateLabel = NSTextField(labelWithString: "")
    private let selTotalLabel = NSTextField(labelWithString: "")
    private let selMetaLabel = NSTextField(labelWithString: "")
    private let breakdownView = ProjectBreakdownView()
    private let sessionsLabel = NSTextField(labelWithString: "")
    private let sessionListView = SessionListView()
    private let breakdownNote = NSTextField(wrappingLabelWithString: "")

    /// Currently selected day (day mode) or range bounds — start-of-day, local.
    private var selStart = Calendar.current.startOfDay(for: Date())
    private var selEnd = Calendar.current.startOfDay(for: Date())

    /// Cached snapshot so picker / heatmap interactions don't re-read disk.
    private var snapshot = Snapshot()

    // Insights — local narrative + token composition + optional AI deep-dive.
    private let compositionView = TokenCompositionView()
    private let insightsStack = NSStackView()
    private let aiButton = NSButton()
    private let aiSpinner = NSProgressIndicator()
    private let aiResult = NSTextField(wrappingLabelWithString: "")
    /// Set by DetailWindow — opens Settings → Privacy where the AI key lives.
    var onShowPrivacy: (() -> Void)?

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
            subtitle: L10n.text("Stats source.", "İstatistik kaynağı."),
            symbol: "cpu",
            info: L10n.text(
                "Stats source. Each provider is scanned from its own transcripts.",
                "İstatistik kaynağı. Her sağlayıcı kendi transkriptlerinden taranır."),
            body: providerControl
        )

        rangeControl.segmentStyle = .texturedRounded
        rangeControl.segmentCount = 3
        rangeControl.setLabel(L10n.text("All time", "Tüm zaman"), forSegment: 0)
        rangeControl.setLabel(L10n.text("Last 30 days", "Son 30 gün"), forSegment: 1)
        rangeControl.setLabel(L10n.text("Last 7 days", "Son 7 gün"), forSegment: 2)
        rangeControl.selectedSegment = 0
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged(_:))
        rangeControl.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Range", "Aralık"),
            subtitle: L10n.text("Summary scope.", "Özet kapsamı."),
            symbol: "calendar",
            info: L10n.text(
                "Summary scope. Streaks and most-active day always reflect available history.",
                "Özet kapsamı. Seriler ve en aktif gün her zaman mevcut geçmişi yansıtır."),
            body: rangeControl
        )

        tilesStack.orientation = .vertical
        tilesStack.alignment = .leading
        tilesStack.spacing = 10
        tilesStack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Overview", "Genel bakış"),
            subtitle: nil,
            symbol: "chart.bar.xaxis",
            body: tilesStack
        )

        buildInsightsSection()
        buildHeatmapSection()
        buildBreakdownSection()

        comparisonLabel.font = NSFont.systemFont(ofSize: 11)
        comparisonLabel.textColor = .secondaryLabelColor
        comparisonLabel.maximumNumberOfLines = 0
        comparisonLabel.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Fun fact", "Eğlenceli bilgi"),
            subtitle: nil,
            symbol: "lightbulb",
            body: comparisonLabel
        )
    }

    private func buildHeatmapSection() {
        heatmapView.translatesAutoresizingMaskIntoConstraints = false
        heatmapView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        heatmapView.onHoverDay = { [weak self] day in self?.updateHoverLabel(day) }
        heatmapView.onSelectDay = { [weak self] day in self?.selectDayFromHeatmap(day) }

        hoverLabel.font = Typography.bodyMono(11, weight: .medium)
        hoverLabel.textColor = .secondaryLabelColor
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false
        updateHoverLabel(nil)

        let stack = NSStackView(views: [heatmapView, hoverLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Activity (last year)", "Aktivite (son 1 yıl)"),
            subtitle: L10n.text("Each cell = a day. Click one to break it down.",
                                "Her hücre = bir gün. Kırılım için birine tıkla."),
            symbol: "square.grid.3x3",
            info: L10n.text(
                "Each cell is one day. Darker means more tokens. Click a day to break it down below.",
                "Her hücre bir gün. Koyu renk daha fazla token. Kırılımı görmek için bir güne tıkla."),
            body: stack
        )
        // Heatmap fills the section width.
        heatmapView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func buildBreakdownSection() {
        modeControl.segmentStyle = .texturedRounded
        modeControl.segmentCount = 2
        modeControl.setLabel(L10n.text("Day", "Gün"), forSegment: 0)
        modeControl.setLabel(L10n.text("Range", "Aralık"), forSegment: 1)
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.setContentHuggingPriority(.required, for: .horizontal)

        datePicker.datePickerStyle = .clockAndCalendar
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.datePickerMode = .single
        datePicker.dateValue = selStart
        datePicker.maxDate = Calendar.current.startOfDay(for: Date())
        datePicker.target = self
        datePicker.action = #selector(dateChanged(_:))
        datePicker.translatesAutoresizingMaskIntoConstraints = false

        // A clean pill that opens the native calendar in a popover — minimal in
        // the row, full graphical month grid on demand.
        dateButton.bezelStyle = .texturedRounded
        dateButton.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        dateButton.imagePosition = .imageLeading
        dateButton.imageHugsTitle = true
        dateButton.target = self
        dateButton.action = #selector(openCalendar)
        dateButton.translatesAutoresizingMaskIntoConstraints = false
        dateButton.setContentHuggingPriority(.required, for: .horizontal)

        todayButton.title = L10n.text("Today", "Bugün")
        todayButton.bezelStyle = .rounded
        todayButton.controlSize = .small
        todayButton.target = self
        todayButton.action = #selector(jumpToToday)
        todayButton.translatesAutoresizingMaskIntoConstraints = false
        todayButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let controls = NSStackView(views: [modeControl, dateButton, todayButton, spacer])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false

        // Header: selected label (left) + big total (right).
        selDateLabel.font = Typography.title(14)
        selDateLabel.textColor = .labelColor
        selDateLabel.translatesAutoresizingMaskIntoConstraints = false
        selDateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        selTotalLabel.translatesAutoresizingMaskIntoConstraints = false
        selTotalLabel.setContentHuggingPriority(.required, for: .horizontal)

        let headerSpacer = NSView()
        headerSpacer.translatesAutoresizingMaskIntoConstraints = false
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [selDateLabel, headerSpacer, selTotalLabel])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        selMetaLabel.font = NSFont.systemFont(ofSize: 11)
        selMetaLabel.textColor = .secondaryLabelColor
        selMetaLabel.translatesAutoresizingMaskIntoConstraints = false

        breakdownView.translatesAutoresizingMaskIntoConstraints = false

        sessionsLabel.attributedStringValue = Typography.captionAttributed(
            L10n.text("Sessions", "Oturumlar"), color: .secondaryLabelColor)
        sessionsLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionListView.translatesAutoresizingMaskIntoConstraints = false

        breakdownNote.font = NSFont.systemFont(ofSize: 11)
        breakdownNote.textColor = .tertiaryLabelColor
        breakdownNote.maximumNumberOfLines = 0
        breakdownNote.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [controls, header, selMetaLabel, breakdownView, sessionsLabel, sessionListView, breakdownNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(14, after: controls)
        stack.setCustomSpacing(4, after: header)
        stack.setCustomSpacing(14, after: selMetaLabel)
        stack.setCustomSpacing(14, after: breakdownView)
        stack.setCustomSpacing(6, after: sessionsLabel)

        addSection(
            title: L10n.text("Daily breakdown", "Günlük kırılım"),
            subtitle: L10n.text("Usage by day/range, and which project.",
                                "Gün/aralık başına kullanım ve hangi proje."),
            symbol: "list.bullet.rectangle",
            info: L10n.text(
                "Pick a day or a date range to see total usage and which project it went to.",
                "Bir gün veya tarih aralığı seç; toplam kullanımı ve hangi projeye gittiğini gör."),
            body: stack
        )
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        breakdownView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        sessionListView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// Show the native graphical calendar in a transient popover off the pill.
    @objc private func openCalendar() {
        datePicker.datePickerMode = (dayMode == .day) ? .single : .range
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: host.topAnchor, constant: Spacing.s),
            datePicker.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: Spacing.s),
            datePicker.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -Spacing.s),
            datePicker.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -Spacing.s),
        ])
        let vc = NSViewController()
        vc.view = host
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = vc
        datePopover = pop
        pop.show(relativeTo: dateButton.bounds, of: dateButton, preferredEdge: .maxY)
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        range = Range(rawValue: sender.selectedSegment) ?? .all
        reload()
    }

    @objc private func providerChanged(_ sender: NSSegmentedControl) {
        provider = Provider(rawValue: sender.selectedSegment) ?? .claude
        reload()
    }

    // MARK: - Daily drill-down interaction

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        dayMode = DayMode(rawValue: sender.selectedSegment) ?? .day
        let today = Calendar.current.startOfDay(for: Date())
        if dayMode == .day {
            datePicker.datePickerMode = .single
            selStart = min(selStart, today)
            selEnd = selStart
            datePicker.dateValue = selStart
        } else {
            datePicker.datePickerMode = .range
            // Default to the trailing week.
            selEnd = today
            selStart = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
            datePicker.dateValue = selStart
            datePicker.timeInterval = selEnd.timeIntervalSince(selStart)
        }
        refreshBreakdown()
    }

    @objc private func dateChanged(_ sender: NSDatePicker) {
        let cal = Calendar.current
        if dayMode == .day {
            selStart = cal.startOfDay(for: sender.dateValue)
            selEnd = selStart
        } else {
            let s = cal.startOfDay(for: sender.dateValue)
            let e = cal.startOfDay(for: sender.dateValue.addingTimeInterval(sender.timeInterval))
            selStart = min(s, e)
            selEnd = max(s, e)
        }
        refreshBreakdown()
        // A single-day pick is a complete action — dismiss the calendar.
        if dayMode == .day { datePopover?.close() }
    }

    @objc private func jumpToToday() {
        let today = Calendar.current.startOfDay(for: Date())
        dayMode = .day
        modeControl.selectedSegment = 0
        datePicker.datePickerMode = .single
        selStart = today
        selEnd = today
        datePicker.dateValue = today
        refreshBreakdown()
    }

    /// Heatmap cell click → jump to that day in day mode.
    private func selectDayFromHeatmap(_ day: YearHeatmapView.Day) {
        dayMode = .day
        modeControl.selectedSegment = 0
        datePicker.datePickerMode = .single
        selStart = Calendar.current.startOfDay(for: day.date)
        selEnd = selStart
        datePicker.dateValue = selStart
        refreshBreakdown()
    }

    // MARK: - Insights

    private func buildInsightsSection() {
        compositionView.translatesAutoresizingMaskIntoConstraints = false

        insightsStack.orientation = .vertical
        insightsStack.alignment = .leading
        insightsStack.spacing = 12
        insightsStack.translatesAutoresizingMaskIntoConstraints = false

        // AI deep-dive (BYO key) — same advisor the Cost tab uses.
        aiButton.bezelStyle = .rounded
        aiButton.target = self
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
        aiRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [compositionView, insightsStack, aiRow, aiResult])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(18, after: compositionView)

        addSection(
            title: L10n.text("Insights", "İçgörüler"),
            subtitle: L10n.text("Where your tokens go and what drives them.",
                                "Tokenlerin nereye gittiği ve neyin sürüklediği."),
            symbol: "sparkles",
            info: L10n.text(
                "Computed locally over the last 30 days. The AI deep-dive sends only privacy-safe aggregates (never transcripts) to your own key.",
                "Son 30 günden yerel hesaplanır. AI derin analizi yalnızca gizliliğe uygun toplamları (asla transkript değil) kendi anahtarına gönderir."),
            body: stack
        )
        compositionView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        insightsStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        aiResult.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: AI deep-dive (reuses AIAdvisor)

    private func updateAIButton() {
        let provider = DisplayPrefs.aiProvider
        if provider != .off, AIKeychain.hasKey(for: provider) {
            aiButton.title = L10n.text("Analyze my usage with AI", "Kullanımımı AI ile analiz et")
            aiButton.action = #selector(analyzeAI)
        } else {
            aiButton.title = L10n.text("Connect a key for AI analysis →", "AI analizi için anahtar bağla →")
            aiButton.action = #selector(openAISettings)
        }
    }

    @objc private func openAISettings() { onShowPrivacy?() }

    @objc private func analyzeAI() {
        let provider = DisplayPrefs.aiProvider
        guard provider != .off, AIKeychain.hasKey(for: provider) else {
            updateAIButton(); onShowPrivacy?(); return
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

    // MARK: Local insight engine

    private struct Insight {
        let symbol: String
        let tint: NSColor
        let headline: NSAttributedString
        let detail: String
    }

    /// Locale-correct percent: "%51" in Turkish, "51%" in English.
    private func pctStr(_ pct: Double) -> String {
        let n = Int(pct.rounded())
        return L10n.lang == .tr ? "%\(n)" : "\(n)%"
    }

    private func insightHeadline(_ metric: String, _ rest: String, tint: NSColor) -> NSAttributedString {
        let s = NSMutableAttributedString(string: metric, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: tint,
        ])
        s.append(NSAttributedString(string: rest, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]))
        return s
    }

    /// Build the narrative insight list from 30-day aggregates, ordered by
    /// importance. The section shows the top few.
    private func computeInsights(_ snap: Snapshot) -> [Insight] {
        var out: [Insight] = []
        let accent = ThemeStore.current.accent
        let fresh = Double(snap.total30dTokens)

        // 1) Sub-agent burn.
        if fresh > 0, snap.subagent30dTokens > 0 {
            let pct = Double(snap.subagent30dTokens) / fresh * 100
            let hot = pct >= 40
            let tint: NSColor = hot ? .systemOrange : accent
            let costStr = snap.subagent30dCost > 0 ? " ≈ \(ContextSnapshot.formatUSD(snap.subagent30dCost))." : ""
            out.append(Insight(
                symbol: "person.2.fill", tint: tint,
                headline: insightHeadline(pctStr(pct),
                    L10n.text(" of fresh tokens run inside sub-agents.",
                              " taze token alt-ajanların içinde harcanıyor."), tint: tint),
                detail: L10n.text(
                    "Multi-agent runs can burn ~15× a normal chat\(costStr) Great for parallel work, pricey for simple asks.",
                    "Çoklu-ajan koşumları normal sohbetin ~15 katı token yakabilir\(costStr) Paralel iş için ideal, basit istekler için pahalı.")
            ))
        }

        // 2) Cache dominance / savings.
        if fresh > 0, snap.cacheRead30d > 0 {
            let mult = Double(snap.cacheRead30d) / fresh
            let saved = snap.cacheSavings30d
            out.append(Insight(
                symbol: "arrow.triangle.2.circlepath", tint: .systemGreen,
                headline: insightHeadline(String(format: "%.0f×", mult),
                    L10n.text(" more replayed (cached) context than fresh tokens.",
                              " kat daha fazla tekrar-oynatılan (önbellekli) bağlam, taze tokene kıyasla."), tint: .systemGreen),
                detail: saved > 0
                    ? L10n.text("Prompt caching saved ≈ \(ContextSnapshot.formatUSD(saved)) this month — cache-read bills at ~0.1× input.",
                                "Önbellekleme bu ay ≈ \(ContextSnapshot.formatUSD(saved)) tasarruf etti — önbellek-okuma girdinin ~0.1 katı fiyatlanır.")
                    : L10n.text("Cache-read bills at ~0.1× input — cheap per token, huge by volume.",
                                "Önbellek-okuma girdinin ~0.1 katı fiyatlanır — token başına ucuz, hacimce büyük.")
            ))
        }

        // 3) Context-window pressure (latest session).
        if snap.lastContextWindow > 0 {
            let pct = snap.lastContextPct
            let hot = pct >= 70
            let tint: NSColor = hot ? .systemOrange : (pct >= 50 ? .systemYellow : .systemGreen)
            out.append(Insight(
                symbol: "gauge.with.dots.needle.67percent", tint: tint,
                headline: insightHeadline(ContextSnapshot.formatTokens(snap.lastContextWindow),
                    L10n.text(" context in your last session (\(Int(pct.rounded()))%).",
                              " son oturum bağlamı (%\(Int(pct.rounded())))."), tint: tint),
                detail: hot
                    ? L10n.text("Above ~70% quality dips and every turn re-bills the full window — /compact or a fresh session helps.",
                                "~%70 üstünde kalite düşer ve her tur tüm pencereyi yeniden faturalar — /compact veya yeni oturum yardımcı olur.")
                    : L10n.text("Comfortable headroom. Each turn re-bills the whole window, so trimming early still pays off.",
                                "Rahat alan var. Her tur tüm pencereyi yeniden faturalar, erken kırpmak yine kazandırır.")
            ))
        }

        // 4) Model mix.
        let modelTotal = snap.byModel.reduce(0.0) { $0 + Double($1.tokens) }
        if let top = snap.byModel.first, modelTotal > 0 {
            let pct = Double(top.tokens) / modelTotal * 100
            let name = prettyModelName(top.model)
            let isOpus = name.lowercased().contains("opus")
            out.append(Insight(
                symbol: "cpu", tint: accent,
                headline: insightHeadline(pctStr(pct),
                    L10n.text(" of tokens on \(name).", " token \(name) üzerinde."), tint: accent),
                detail: (isOpus && pct >= 60)
                    ? L10n.text("Routine edits on Sonnet or Haiku would cut cost a lot.",
                                "Rutin düzenlemeleri Sonnet veya Haiku'ya almak maliyeti epey düşürür.")
                    : L10n.text("A balanced model mix.", "Dengeli bir model dağılımı.")
            ))
        }

        // 5) Project concentration.
        let projTotal = snap.byProject.reduce(0.0) { $0 + Double($1.tokens) }
        if snap.byProject.count > 1, let top = snap.byProject.first, projTotal > 0 {
            let pct = Double(top.tokens) / projTotal * 100
            if pct >= 40 {
                out.append(Insight(
                    symbol: "folder.fill", tint: accent,
                    headline: insightHeadline(pctStr(pct),
                        L10n.text(" of usage on a single project.", " kullanım tek bir projede."), tint: accent),
                    detail: L10n.text("\(top.model) is your main focus across \(snap.byProject.count) projects.",
                                      "\(snap.byProject.count) proje arasında ana odağın \(top.model).")
                ))
            }
        }

        // 6) Cadence — busiest weekday.
        if let weekday = busiestWeekday(snap) {
            out.append(Insight(
                symbol: "calendar", tint: accent,
                headline: insightHeadline(weekday,
                    L10n.text(" is your most active day.", " en aktif günün."), tint: accent),
                detail: L10n.text("Longest session \(durationString(minutes: longestSession(snap))).",
                                  "En uzun oturum \(durationString(minutes: longestSession(snap))).")
            ))
        }

        return Array(out.prefix(6))
    }

    /// Localized weekday name with the most tokens across by_day.
    private func busiestWeekday(_ snap: Snapshot) -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        let cal = Calendar(identifier: .gregorian)
        var sums = [UInt64](repeating: 0, count: 8) // weekday 1…7
        for d in snap.byDay where d.tokens > 0 {
            guard let date = fmt.date(from: d.date) else { continue }
            sums[cal.component(.weekday, from: date)] += d.tokens
        }
        guard let best = (1...7).max(by: { sums[$0] < sums[$1] }), sums[best] > 0 else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        let symbols = out.weekdaySymbols ?? []
        guard best - 1 < symbols.count else { return nil }
        return symbols[best - 1]
    }

    private func refreshInsights() {
        let accent = ThemeStore.current.accent
        compositionView.segments = [
            .init(label: L10n.text("Input", "Girdi"), value: snapshot.input30d, color: accent),
            .init(label: L10n.text("Output", "Çıktı"), value: snapshot.output30d, color: accent.withAlphaComponent(0.55)),
            .init(label: L10n.text("Cache", "Önbellek"), value: snapshot.cacheRead30d, color: .tertiaryLabelColor),
        ]

        insightsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let insights = computeInsights(snapshot)
        if insights.isEmpty {
            let empty = NSTextField(labelWithString: L10n.text("No usage recorded yet.", "Henüz kullanım kaydı yok."))
            empty.font = NSFont.systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            insightsStack.addArrangedSubview(empty)
        } else {
            for ins in insights {
                let card = InsightCardView(symbol: ins.symbol, tint: ins.tint, headline: ins.headline, detail: ins.detail)
                insightsStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: insightsStack.widthAnchor).isActive = true
            }
        }
        updateAIButton()
    }

    // MARK: - Data

    private struct Day { let date: String; let tokens: UInt64; let sessions: Int; let cost: Double }
    private struct ModelBucket { let model: String; let tokens: UInt64; let sessions: Int }
    private struct Session {
        let startedAt: String
        let durationMinutes: Double
        let tokens: UInt64
        let model: String
        let project: String
        let cost: Double
    }
    private struct ProjInst { let date: String; let project: String; let tokens: UInt64; let cost: Double }

    private struct Snapshot {
        var byDay: [Day] = []          // newest-first, up to ~365
        var byMonth: [Day] = []        // newest-first, up to 12 (date="YYYY-MM")
        var byModel: [ModelBucket] = []
        var byProject: [ModelBucket] = [] // .model holds the project name
        var instances: [ProjInst] = [] // by_day_project rows (last ~30 days)
        var recent: [Session] = []
        var total30dTokens: UInt64 = 0
        var subagent30dTokens: UInt64 = 0   // fresh tokens spent inside sub-agents (30d)
        var subagent30dCost: Double = 0
        var total30dSessions: Int = 0
        var maxSessionMinutes: Double = 0
        var favoriteEffort: String? = nil   // Codex reasoning effort, if recorded
        // Insight inputs.
        var input30d: UInt64 = 0
        var output30d: UInt64 = 0
        var cacheRead30d: UInt64 = 0
        var cacheSavings30d: Double = 0
        var totalCost30d: Double = 0
        var lastContextWindow: UInt64 = 0
        var lastContextPct: Double = 0
        var activeSessionTokens: UInt64 = 0
        var activeSessionSubagentTokens: UInt64 = 0
    }

    private func loadSnapshot() -> Snapshot {
        let path = ContextSnapshot.resolveSnapshotPath()
        let key: String = (provider == .codex) ? "codex" : "claude"
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let c = root[key] as? [String: Any]
        else {
            return Snapshot()
        }
        func u64(_ any: Any?) -> UInt64 {
            (any as? UInt64) ?? UInt64(any as? Int ?? 0)
        }
        func dbl(_ any: Any?) -> Double {
            if let d = any as? Double { return d }
            if let n = any as? NSNumber { return n.doubleValue }
            return 0
        }
        var snap = Snapshot()
        snap.total30dTokens = u64(c["total_tokens_30d"])
        snap.subagent30dTokens = u64(c["subagent_tokens_30d"])
        snap.subagent30dCost = dbl(c["subagent_cost_30d"])
        snap.total30dSessions = (c["total_sessions_30d"] as? Int) ?? 0
        snap.maxSessionMinutes = (c["max_session_minutes"] as? Double) ?? 0
        snap.input30d = u64(c["total_input_30d"])
        snap.output30d = u64(c["total_output_30d"])
        snap.cacheRead30d = u64(c["cache_read_tokens_30d"])
        snap.cacheSavings30d = dbl(c["cache_savings_30d"])
        snap.totalCost30d = dbl(c["total_cost_30d"])
        snap.lastContextWindow = u64(c["last_context_window"])
        snap.lastContextPct = dbl(c["last_context_pct"])
        snap.activeSessionTokens = u64(c["active_session_tokens"])
        snap.activeSessionSubagentTokens = u64(c["active_session_subagent_tokens"])
        snap.favoriteEffort = (c["favorite_effort"] as? String)?.trimmingCharacters(in: .whitespaces)
        snap.byDay = ((c["by_day"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let d = o["date"] as? String else { return nil }
            return Day(date: d, tokens: u64(o["tokens"]), sessions: (o["sessions"] as? Int) ?? 0, cost: dbl(o["cost"]))
        }
        snap.byMonth = ((c["by_month"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let d = (o["date"] as? String) ?? (o["month"] as? String) else { return nil }
            return Day(date: d, tokens: u64(o["tokens"]), sessions: (o["sessions"] as? Int) ?? 0, cost: dbl(o["cost"]))
        }
        snap.instances = ((c["by_day_project"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let d = o["date"] as? String, let p = o["project"] as? String else { return nil }
            return ProjInst(date: d, project: p, tokens: u64(o["tokens"]), cost: dbl(o["cost"]))
        }
        snap.byModel = ((c["by_model"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let m = o["model"] as? String else { return nil }
            return ModelBucket(model: m, tokens: u64(o["tokens"]), sessions: (o["sessions"] as? Int) ?? 0)
        }
        // by_project serializes the project name under the "model" key.
        snap.byProject = ((c["by_project"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let m = o["model"] as? String else { return nil }
            return ModelBucket(model: m, tokens: u64(o["tokens"]), sessions: (o["sessions"] as? Int) ?? 0)
        }
        snap.recent = ((c["recent_sessions"] as? [[String: Any]]) ?? []).compactMap { o in
            Session(
                startedAt: (o["started_at"] as? String) ?? "",
                durationMinutes: (o["duration_minutes"] as? Double) ?? 0,
                tokens: u64(o["tokens"]),
                model: (o["model"] as? String) ?? "",
                project: (o["project"] as? String) ?? "",
                cost: dbl(o["cost"])
            )
        }
        return snap
    }

    // MARK: - Aggregates

    private func tokensInRange(_ snap: Snapshot) -> UInt64 {
        switch range {
        case .all:    return snap.byMonth.reduce(0) { $0 + $1.tokens }
        case .last30: return snap.total30dTokens
        case .last7:  return snap.byDay.prefix(7).reduce(0) { $0 + $1.tokens }
        }
    }

    private func sessionsInRange(_ snap: Snapshot) -> Int {
        switch range {
        case .all:    return snap.byMonth.reduce(0) { $0 + $1.sessions }
        case .last30: return snap.total30dSessions
        case .last7:  return snap.byDay.prefix(7).reduce(0) { $0 + $1.sessions }
        }
    }

    private func activeDaysInRange(_ snap: Snapshot) -> (active: Int, total: Int) {
        switch range {
        case .all:
            // Total = calendar days since first recorded activity (so the
            // ratio stays meaningful instead of always being X/365).
            let active = snap.byDay.filter { $0.tokens > 0 }.count
            guard let firstActive = snap.byDay.last(where: { $0.tokens > 0 }) else {
                return (0, 0)
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = .current
            guard let firstDate = fmt.date(from: firstActive.date) else { return (active, active) }
            let days = Calendar(identifier: .gregorian).dateComponents([.day], from: firstDate, to: Date()).day ?? 0
            return (active, max(active, days + 1))
        case .last30:
            let slice = Array(snap.byDay.prefix(30))
            return (slice.filter { $0.tokens > 0 }.count, 30)
        case .last7:
            let slice = Array(snap.byDay.prefix(7))
            return (slice.filter { $0.tokens > 0 }.count, 7)
        }
    }

    /// Walks by_day (newest-first) and counts consecutive non-empty days from
    /// the most recent entry. If today has no entry yet, the streak still
    /// counts yesterday and earlier as a continuous run.
    private func currentStreak(_ snap: Snapshot) -> Int {
        var streak = 0
        var leadingSkipped = false
        for d in snap.byDay {
            if d.tokens > 0 {
                streak += 1
                leadingSkipped = true
            } else if !leadingSkipped {
                leadingSkipped = true
                continue
            } else {
                break
            }
        }
        return streak
    }

    private func longestStreak(_ snap: Snapshot) -> Int {
        var best = 0, run = 0
        for d in snap.byDay {
            if d.tokens > 0 { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }

    private func longestSession(_ snap: Snapshot) -> Double {
        // Prefer the server-computed all-history max so it isn't capped
        // by the 20-row recent_sessions tail.
        let recentMax = snap.recent.map(\.durationMinutes).max() ?? 0
        return max(snap.maxSessionMinutes, recentMax)
    }

    private func mostActiveDay(_ snap: Snapshot) -> Day? {
        snap.byDay.max(by: { $0.tokens < $1.tokens })
    }

    private func favoriteModel(_ snap: Snapshot) -> String? {
        snap.byModel.first.map { prettyModelName($0.model) }
    }

    /// Map Anthropic / OpenAI model IDs to the short labels each vendor shows
    /// Pretty label for a Codex reasoning-effort value.
    private func prettyEffort(_ raw: String) -> String {
        switch raw.lowercased() {
        case "xhigh", "x-high": return L10n.text("X-High", "Çok Yüksek")
        case "high":            return L10n.text("High", "Yüksek")
        case "medium":          return L10n.text("Medium", "Orta")
        case "low":             return L10n.text("Low", "Düşük")
        case "minimal":         return L10n.text("Minimal", "Minimal")
        default:                return raw.capitalized
        }
    }

    /// in its own UI. Unknown IDs fall back to the raw string.
    private func prettyModelName(_ id: String) -> String {
        let m = id.lowercased()
        let suffix = m.contains("[1m]") || m.contains("-1m") ? " (1M)" : ""
        let base: String
        switch true {
        case m.contains("opus-4-9"):    base = "Opus 4.9"
        case m.contains("opus-4-8"):    base = "Opus 4.8"
        case m.contains("opus-4-7"):    base = "Opus 4.7"
        case m.contains("opus-4-6"):    base = "Opus 4.6"
        case m.contains("opus-4-5"):    base = "Opus 4.5"
        case m.contains("opus-4"):      base = "Opus 4"
        case m.contains("sonnet-4-7"):  base = "Sonnet 4.7"
        case m.contains("sonnet-4-6"):  base = "Sonnet 4.6"
        case m.contains("sonnet-4-5"):  base = "Sonnet 4.5"
        case m.contains("sonnet-4"):    base = "Sonnet 4"
        case m.contains("haiku-4-5"):   base = "Haiku 4.5"
        case m.contains("haiku-4"):     base = "Haiku 4"
        case m.contains("gpt-5-5"), m.contains("gpt-5.5"): base = "GPT-5.5"
        case m.contains("gpt-5"):       base = "GPT-5"
        case m.contains("gpt-4"):       base = "GPT-4"
        case m.contains("mythos"):      base = "Claude Mythos"
        default:                        return id
        }
        return base + suffix
    }

    // MARK: - Render

    func reload() {
        guard isViewLoaded else { return }
        snapshot = loadSnapshot()
        let snap = snapshot
        tilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let tokens = tokensInRange(snap)
        let sessions = sessionsInRange(snap)
        let (active, total) = activeDaysInRange(snap)

        var tiles: [NSView] = [
            StatTileView(
                caption: L10n.text("sessions", "oturum"),
                value: numberString(sessions)
            ),
            StatTileView(
                // Fresh work only (input + output, NO cache). Deliberately NOT
                // the cache-inclusive "Total Tokens" Claude Code / ccusage show —
                // labelled explicitly so the two don't look like a mismatch.
                caption: L10n.text("tokens (in + out)", "token (girdi + çıktı)"),
                value: ContextSnapshot.formatTokens(tokens)
            ),
            StatTileView(
                // Share of fresh tokens spent inside sub-agents (Task /
                // dynamic-workflow runs) — the multi-agent burn the boss flagged.
                caption: L10n.text("via sub-agents", "alt-ajanlarla"),
                value: snap.total30dTokens > 0
                    ? String(format: "%.0f%%", Double(snap.subagent30dTokens) / Double(snap.total30dTokens) * 100)
                    : "—"
            ),
            StatTileView(
                caption: L10n.text("active days", "aktif gün"),
                value: total > 0 ? "\(active)/\(total)" : "—"
            ),
            StatTileView(
                caption: L10n.text("current streak", "mevcut seri"),
                value: streakString(currentStreak(snap))
            ),
            StatTileView(
                caption: L10n.text("longest streak", "en uzun seri"),
                value: streakString(longestStreak(snap))
            ),
            StatTileView(
                caption: L10n.text("longest session", "en uzun oturum"),
                value: durationString(minutes: longestSession(snap))
            ),
            StatTileView(
                caption: L10n.text("most active day", "en aktif gün"),
                value: mostActiveDay(snap).map { formatDay($0.date) } ?? "—",
                mono: false
            ),
            StatTileView(
                caption: L10n.text("favorite model", "favori model"),
                value: favoriteModel(snap) ?? "—",
                mono: false
            ),
        ]
        // Codex records a reasoning effort per turn; Claude does not — only show
        // the tile when the transcripts actually carried one.
        if let eff = snap.favoriteEffort, !eff.isEmpty {
            tiles.append(StatTileView(
                caption: L10n.text("favorite effort", "favori effort"),
                value: prettyEffort(eff),
                mono: false
            ))
        }

        let rows = stride(from: 0, to: tiles.count, by: 4).map { start -> NSStackView in
            let end = min(start + 4, tiles.count)
            let row = NSStackView(views: Array(tiles[start..<end]))
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        rows.forEach {
            tilesStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: tilesStack.widthAnchor).isActive = true
        }

        // Feed the full ≈365-day window — the heatmap lays it out as a year
        // grid. (Streak / longest-streak math also reads the same byDay.)
        heatmapView.values = snap.byDay.map { (date: $0.date, tokens: $0.tokens) }

        // Clamp the selection to recorded history, then redraw the breakdown.
        clampSelectionToHistory()
        refreshBreakdown()
        refreshInsights()

        comparisonLabel.stringValue = comparisonString(totalAllTime: snap.byMonth.reduce(0) { $0 + $1.tokens })
    }

    // MARK: - Breakdown render

    private static let dayKeyFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private func dayKey(_ d: Date) -> String { Self.dayKeyFmt.string(from: d) }

    private static let isoParserFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoParserBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()
    private func parseISO(_ s: String) -> Date? {
        Self.isoParserFull.date(from: s) ?? Self.isoParserBasic.date(from: s)
    }

    /// Rows for the per-day session list: recent_sessions whose start day falls
    /// inside the selection, newest-first, capped. (recent_sessions is the last
    /// ~20, so older days show none — totals/projects still cover the full year.)
    private func sessionRowsForSelection(_ keys: Set<String>) -> [SessionListView.Row] {
        let matched: [(Date, Session)] = snapshot.recent.compactMap { s in
            guard let d = parseISO(s.startedAt), keys.contains(dayKey(d)) else { return nil }
            return (d, s)
        }
        return matched
            .sorted { $0.0 > $1.0 }
            .prefix(15)
            .map { (date, s) in
                let detail = [s.model.isEmpty ? nil : prettyModelName(s.model),
                              s.project.isEmpty ? nil : s.project]
                    .compactMap { $0 }.joined(separator: " · ")
                return SessionListView.Row(
                    time: Self.timeFmt.string(from: date),
                    duration: s.durationMinutes > 0 ? durationString(minutes: s.durationMinutes) : "",
                    detail: detail,
                    tokens: s.tokens,
                    cost: s.cost
                )
            }
    }

    /// Keep the picked day/range inside the recorded window so an empty pick
    /// after a provider switch lands on a day that actually has data.
    private func clampSelectionToHistory() {
        let today = Calendar.current.startOfDay(for: Date())
        if selStart > today { selStart = today }
        if selEnd > today { selEnd = today }
        if dayMode == .day {
            selEnd = selStart
            datePicker.dateValue = selStart
        }
    }

    /// All "yyyy-MM-dd" keys in the inclusive selected range.
    private func selectedKeys() -> Set<String> {
        var keys = Set<String>()
        var d = selStart
        let cal = Calendar.current
        while d <= selEnd {
            keys.insert(dayKey(d))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return keys
    }

    private func refreshBreakdown() {
        let keys = selectedKeys()

        // Totals come from by_day (accurate across the full year).
        var totalTokens: UInt64 = 0
        var totalSessions = 0
        var totalCost = 0.0
        for day in snapshot.byDay where keys.contains(day.date) {
            totalTokens += day.tokens
            totalSessions += day.sessions
            totalCost += day.cost
        }

        // Per-project split from by_day_project (covers the last ~30 days).
        var projTokens: [String: UInt64] = [:]
        var projCost: [String: Double] = [:]
        for inst in snapshot.instances where keys.contains(inst.date) {
            projTokens[inst.project, default: 0] += inst.tokens
            projCost[inst.project, default: 0] += inst.cost
        }
        let maxProj = projTokens.values.max() ?? 0
        let projRows = projTokens
            .sorted { $0.value > $1.value }
            .prefix(12)
            .map { name, tok in
                ProjectBreakdownView.Row(
                    name: name,
                    tokens: tok,
                    cost: projCost[name] ?? 0,
                    share: maxProj > 0 ? Double(tok) / Double(maxProj) : 0
                )
            }

        // Header.
        selDateLabel.stringValue = selectionTitle()
        selTotalLabel.attributedStringValue = Typography.displayNumberAttributed(
            ContextSnapshot.formatTokens(totalTokens), size: 20, weight: .semibold
        )
        let sU = L10n.text(totalSessions == 1 ? "session" : "sessions", "oturum")
        selMetaLabel.stringValue = "\(numberString(totalSessions)) \(sU) · \(ContextSnapshot.formatUSD(totalCost))"

        breakdownView.rows = Array(projRows)
        heatmapView.selectedKey = (dayMode == .day) ? dayKey(selStart) : nil
        dateButton.title = selectionTitle()

        // Sessions behind the selection (recent_sessions = last ~20).
        let sessionRows = sessionRowsForSelection(keys)
        sessionListView.rows = sessionRows
        sessionsLabel.isHidden = sessionRows.isEmpty

        // Note / empty state.
        if totalTokens == 0 {
            breakdownNote.stringValue = L10n.text(
                "No usage in this selection.",
                "Bu seçimde kullanım yok."
            )
        } else if projRows.isEmpty {
            breakdownNote.stringValue = L10n.text(
                "Per-project breakdown is available for the last 30 days.",
                "Proje kırılımı son 30 gün için mevcuttur."
            )
        } else {
            breakdownNote.stringValue = ""
        }
        breakdownNote.isHidden = breakdownNote.stringValue.isEmpty
    }

    private func selectionTitle() -> String {
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        if dayMode == .day {
            // Friendly "Today" / "Yesterday" when it applies.
            let cal = Calendar.current
            if cal.isDateInToday(selStart) { return L10n.text("Today", "Bugün") }
            if cal.isDateInYesterday(selStart) { return L10n.text("Yesterday", "Dün") }
            out.dateFormat = L10n.lang == .tr ? "d MMMM yyyy" : "MMM d, yyyy"
            return out.string(from: selStart)
        }
        out.dateFormat = L10n.lang == .tr ? "d MMM" : "MMM d"
        let startStr = out.string(from: selStart)
        out.dateFormat = L10n.lang == .tr ? "d MMM yyyy" : "MMM d, yyyy"
        let endStr = out.string(from: selEnd)
        return "\(startStr) – \(endStr)"
    }

    private func updateHoverLabel(_ day: YearHeatmapView.Day?) {
        guard let day else {
            hoverLabel.stringValue = L10n.text(
                "Hover a day for details · click to break it down.",
                "Detay için bir günün üzerine gel · kırılım için tıkla."
            )
            hoverLabel.textColor = .tertiaryLabelColor
            return
        }
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        out.dateFormat = L10n.lang == .tr ? "d MMMM yyyy" : "MMM d, yyyy"
        let dateStr = out.string(from: day.date)
        if day.tokens == 0 {
            hoverLabel.stringValue = L10n.text("\(dateStr) · no usage", "\(dateStr) · kullanım yok")
        } else {
            let tok = ContextSnapshot.formatTokens(day.tokens)
            hoverLabel.stringValue = L10n.text("\(dateStr) · \(tok) tokens", "\(dateStr) · \(tok) token")
        }
        hoverLabel.textColor = .secondaryLabelColor
    }

    // MARK: - Formatting

    private func numberString(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func streakString(_ days: Int) -> String {
        if days <= 0 { return "—" }
        return L10n.text("\(days)d", "\(days)g")
    }

    private func durationString(minutes m: Double) -> String {
        if m <= 0 { return "—" }
        if m < 60 { return String(format: "%.0f%@", m, L10n.text("m", "dk")) }
        let h = Int(m / 60)
        let mm = Int(m.truncatingRemainder(dividingBy: 60))
        let hU = L10n.text("h", "sa")
        let mU = L10n.text("m", "dk")
        if h < 24 {
            return mm == 0 ? "\(h)\(hU)" : "\(h)\(hU) \(mm)\(mU)"
        }
        let d = h / 24
        let hh = h % 24
        let dU = L10n.text("d", "g")
        return hh == 0 ? "\(d)\(dU)" : "\(d)\(dU) \(hh)\(hU)"
    }

    private func formatDay(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inFmt.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        out.dateFormat = L10n.lang == .tr ? "d MMM" : "MMM d"
        return out.string(from: date)
    }

    /// War and Peace ≈ 587,287 words. At ~0.75 words/token that is ~783,000
    /// tokens — used as a stable reference so users get a sense of scale.
    /// Same idea as Claude's "X× more than The Hobbit" line, but with a book
    /// that scales better for heavy users.
    private static let warAndPeaceTokens: Double = 783_000

    private func comparisonString(totalAllTime: UInt64) -> String {
        guard totalAllTime > 0 else {
            return L10n.text(
                "No usage recorded yet.",
                "Henüz kullanım kaydı yok."
            )
        }
        let ratio = Double(totalAllTime) / Self.warAndPeaceTokens
        let ratioStr: String = {
            if ratio >= 10 { return String(format: "%.0f×", ratio) }
            return String(format: "%.1f×", ratio)
        }()
        return L10n.text(
            "You've used ~\(ratioStr) more tokens than War and Peace.",
            "Savaş ve Barış'tan ~\(ratioStr) daha fazla token kullandınız."
        )
    }
}
