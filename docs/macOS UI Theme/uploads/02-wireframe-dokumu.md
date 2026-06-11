# ContextBar — Ekran Wireframe Dökümü

> Faz 4 çıktısı · Claude Design'a beslemek için yapısal ekran tarifleri
> Her ekran: boyut + kutu hiyerarşisi + içerik + durumlar. Bunlar **mevcut** UI'ın yapısıdır (redesign'ın başlangıç noktası).
> Ölçüler `pt` (macOS nokta). `[●]` renkli/durum öğesi, `▓▓░` bar/gauge, `«mono»` monospaced sayı.

---

## EKRAN 1 — MENÜBAR BAŞLIĞI (status item)

macOS menü çubuğunda görünen canlı metin. İçerik kullanıcı tarafından sıralanabilir/açılıp kapanabilir.

```
┌─ macOS menü çubuğu ────────────────────────────────────────┐
│  ...   [◀ diğer uygulama ikonları]    [●] Claude · my-repo · «42%»  🔋 🕐 │
│                                        └──────── ContextBar başlığı ─────┘
└────────────────────────────────────────────────────────────┘

Anatomi:   [ajan] [sep] [proje] [sep] [%context]
Örnek:     ● Claude · my-repo · 42%
Font:      menuBarFont (sistem), %context rengi eşiğe göre (yeşil<60 / turuncu<85 / kırmızı≥85)

Opsiyonel ekler (şu an 3 ayrı sinyal — SADELEŞTİRME HEDEFİ):
  • Önek:  "● " (incident — kırmızı/turuncu/sarı)        → üst kaynak arızası
  • Sonek: "  ●" (budget pressure — sarı/kırmızı)        → bütçe/limit baskısı
  • Sonek: "  ⚠ proj 80%"                                → kızışan arka plan oturumu
```

**Durumlar:** aktif oturum (yeşil nokta) · boşta (gri nokta) · veri yok (`—`).
**Redesign notu:** 3 acil-durum sinyalini tek birleşik göstergeye indirmek.

---

## EKRAN 2 — POPOVER (genişlik 360pt, dikey stack)

Menü çubuğu başlığına tıklanınca açılan ana panel. Kartlar koşullu sıralanır.

```
╔══════════════════════════════════════════════════╗  ← NSVisualEffectView (.popover, blur)
║                                                    ║   genişlik 360pt
║ ┌── HERO KART ──────────────────────────────────┐ ║  ← MenubarHeroCardView (radius 16, gölge, gradient)
║ │ [●] my-repo                          «42%»     │ ║   proje 22pt semibold | context % 22pt, eşik rengi
║ │ [icon] Claude · 3.5-sonnet · 2m ago · 45m run  │ ║   meta 11pt gri, tek satır
║ │ ▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │ ║   context bar 4pt, gradient, >75% glow
║ │ «Context · 621.1k / 200k»                      │ ║   detay 11pt mono gri
║ │ [● Service disruption]  (koşullu incident pill)│ ║   ← menubar ile ÇİFT (sadeleştir)
║ └────────────────────────────────────────────────┘ ║
║                                                    ║
║ ┌── PARALEL OTURUMLAR (koşullu, ≥1 paralel) ─────┐ ║  ← max 5 satır, "+N more"
║ │ PARALEL OTURUMLAR                               │ ║   başlık 10pt caps gri
║ │ api-router · claude-3-opus           «71%» 2m  │ ║   her satır: proje·model + % + zaman
║ │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░                    │ ║   bar 4pt
║ │ web-ui · claude-3-haiku              «18%» 5m  │ ║
║ │ ▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░             │ ║
║ └────────────────────────────────────────────────┘ ║
║                                                    ║
║ ┌── LİMİT KARTI (ajan başına) ──────────────────┐ ║
║ │ [icon] Claude · 3.5-sonnet · 2m ago           │ ║   başlık satırı
║ │ 5h limit                    «42%»  ↻ in 1h47m │ ║
║ │ ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░       │ ║   bar 4pt, eşik rengi
║ │ 7d limit                    «68%»  ↻ in 4d16h │ ║
║ │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░               │ ║
║ │ Session total               «621.1k»           │ ║   bar yok, sadece değer
║ └────────────────────────────────────────────────┘ ║
║                                                    ║
║ ┌── DİĞER ARAÇLAR (koşullu, 30dk içinde aktif) ──┐ ║
║ │ OTHER TOOLS                                     │ ║
║ │ [icon] Gemini        «42.1k · 3×/wk · 2.5-pro» │ ║   satır 22pt, sağ hizalı stat
║ │ [icon] Copilot       «12.0k · 5×/wk · gpt-4o»  │ ║
║ └────────────────────────────────────────────────┘ ║
║                                                    ║
║ ┌── FOOTER (40pt, kart değil) ──────────────────┐ ║
║ │ Theme [● ● ● Default · 42% ▾]   [↑] [⚙] [↻] [⏻]│ ║   sol: tema dropdown | sağ: 4 ikon (30×28)
║ └────────────────────────────────────────────────┘ ║   Share/Settings/Refresh/Quit
╚══════════════════════════════════════════════════╝

Footer ikonları:  [↑]=Share  [⚙]=Settings  [↻]=Refresh(spin)  [⏻]=Quit
```

**Alternatif durumlar:**
```
LOADING:                          EMPTY:
┌────────────────────────────┐    ┌────────────────────────────┐
│ Gathering session data…    │    │           ✦                │
│ Scanning transcripts…      │    │   No agent data yet        │
│ ▞▞▞▞▞▞▞ (animasyonlu çizgi) │    │ Start a Claude/Codex session│
└────────────────────────────┘    └────────────────────────────┘
```
**Redesign notları:** tema dropdown footer'da fazla yer (Settings'te de var) · hero kartında hiyerarşi (kahraman metrik) · incident çifti.

---

## EKRAN 3 — DETAIL PENCERESİ kabuğu (820×680pt)

```
╔═══════════════════════════════════════════════════════════════╗
║ [Usage] [Stats] [Value] [General] [Privacy] [About]            ║  ← NSToolbar .preference stili
╠═══════════════════════════════════════════════════════════════╣     SF Symbol + etiket, sekme başına
║                                                                 ║
║              ( seçili sekmenin scroll'lanan içeriği )           ║  ← NSVisualEffectView arka plan
║                                                                 ║     min 720×560, resizable
╚═══════════════════════════════════════════════════════════════╝
Kısayollar: ⌘D pencereyi aç · ⌘R yenile
```

---

## EKRAN 3a — USAGE sekmesi

```
┌─ AKTİF AJAN KARTI ────────────────────────────────────────────┐
│ [●] [icon] Claude                                              │  durum + ad 16pt semibold
│ claude-opus-4-7 · my-project · 2 minutes ago                  │  meta 11pt gri
│                                                                │
│ ┌─context─┐ ┌─session─┐ ┌─5h window─┐ ┌─7d window─┐           │  4 tile, eşit genişlik
│ │  «42%»  │ │  «58K»  │ │ «42.3M»   │ │ «41.0M»   │           │  caption 10pt caps + değer büyük mono
│ │2.4M win │ │42m run  │ │resets 1h23│ │resets 4d16│           │  alt-satır 11pt gri
│ └─────────┘ └─────────┘ └───────────┘ └───────────┘           │
│                                                                │
│ 30-day tokens                                    «1.20M»      │  caption + toplam (sağ)
│ ╱╲    ╱╲╱╲                                                     │  sparkline 56pt, gradient dolgu
│╱   ╲╱╲╱    ╲╱╲___╱╲___╱╲╱╲___                                 │  accent çizgi + uç nokta
└────────────────────────────────────────────────────────────────┘

┌─ OTHER AI TOOLS (koşullu) ────────────────────────────────────┐
│ [🔧] Other AI tools                                            │
│   [icon] Gemini              «12.5M · 3×/wk · 2.5-pro»        │  ← popover ile örtüşüyor
└────────────────────────────────────────────────────────────────┘
```
**Redesign notu:** Usage ≈ popover hero+limit'in geniş hali → rol ayrımı fırsatı (Usage = geçmiş/derinlik).

---

## EKRAN 3b — STATS sekmesi (en yoğun — progressive disclosure hedefi)

```
[ Claude | Codex ]              ← provider segmented           (sağda) [ All time | 30 days | 7 days ]

┌─ OVERVIEW TILES (4 sütun grid, ~10 tile — SADELEŞTİR) ─────────────────────┐
│ ┌sessions┐ ┌tokens─┐ ┌sub-agent┐ ┌active days┐                             │
│ │ «247»  │ │«58.2M»│ │ «24%»   │ │ «18/30»  │                             │
│ ┌streak──┐ ┌longest┐ ┌long sess┐ ┌most active┐                            │
│ │ «5d»   │ │«12d»  │ │«2h 14m» │ │ «Mar 14»  │                            │
│ ┌fav model┐ ┌fav effort (Codex)┐                                          │
│ │«Opus4.7»│ │ «High»          │                                           │
│ └─────────┘ └──────────────────┘                                          │
└───────────────────────────────────────────────────────────────────────────┘

┌─ YEAR HEATMAP ⭐ (görsel imza) ───────────────────────────────────────────┐
│      Jan   Feb   Mar   Apr   May   Jun ...                                 │  ay etiketleri
│ Mon  ▢▢▣▣▤▥▢▢▣▤▥▥▣▢▢▣▤▥▥▥▣▤▢▢▣▤▥...                                       │  7 satır × ~52 hafta
│ Wed  ▢▣▤▥▥▣▢▢▣▤▥▥▥▣▤▢▢▣▤▥▣▢▢▣▤▥▥...                                       │  log-ramp accent yoğunluk
│ Fri  ▣▤▥▥▥▣▤▢▢▣▤▥▣▢▢▣▤▥▥▣▤▢▢▣▤▥▥...                                       │  hover+tıkla detay
│                                            Less ▢▣▤▥█ More                  │  legend
│ "Hover a day for details · click to break it down."                        │  hover caption
└───────────────────────────────────────────────────────────────────────────┘

┌─ DAILY BREAKDOWN ─────────────────────────────────────────────────────────┐
│ [Day|Range]      [📅 Mar 14, 2024 ▾]                    [Today]            │  mod + takvim pill
│ Mar 14, 2024                                          «1.2M»              │  başlık 14pt + toplam
│ 18 sessions · $3.47                                                       │  meta 11pt
│                                                                            │
│ PROJE BAR CHART (max 12):                                                  │
│ api-router    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓        «42.3M · $1.24»                 │  yatay bar/satır 38pt
│ web-ui        ▓▓▓▓▓▓▓▓▓▓▓                  «18.1M · $0.73»                 │
│                                                                            │
│ Sessions:                                                                  │
│ 14:32   «1.2M · $0.34»                                          ›          │  oturum satırı 42pt
│ Opus 4.7 · api-router                                                      │  tıkla→context detay popover
└───────────────────────────────────────────────────────────────────────────┘

┌─ INSIGHTS ⭐ ─────────────────────────────────────────────────────────────┐
│ Token composition:  [■input ■output ■cache]  62% / 14% / 24%              │  pill bar + legend
│                                                                            │
│ [◧] «24%» of fresh tokens run inside sub-agents.                          │  insight kartı (max 6)
│      Multi-agent work costs ~15× normal…                                  │  icon chip + headline + detay
│ [◧] «3.2×» more replayed (cached) context than fresh.                     │
│ [◧] «128K tokens» context in your last session («71%»).                   │
│                                                                            │
│ [ Analyze my usage with AI ]  ⟳                                           │  AI deep-dive butonu+spinner
│                                                                            │
│ You've used ~1.2× more tokens than War and Peace.                         │  fun fact
└───────────────────────────────────────────────────────────────────────────┘
```
**Redesign notu:** 10 tile → en değerli 4-6 öne, gerisi "daha fazla". Heatmap & insight kartları yıldız olabilir.

---

## EKRAN 3c — VALUE / COST sekmesi

```
┌─ HERO CLARITY KART ⭐ ("bu bir fatura değil") ────────────────────────────┐
│ ✓ Your plan · Max 5×                                        «$100.00 /mo» │  plan satırı (koşullu)
│ 📈 ≈ «$2,847.50» / mo                                                     │  API-eşdeğeri 24pt accent
│    estimated API value of your usage                                      │  caption
│ This is not a bill. You're on a subscription — it's what the same         │  ← EN ÖNEMLİ satır
│ token usage would cost on the pay-per-token API.                          │
│ ↓ ≈$2,747/mo saved vs metered API — about 28× your plan's value.         │  tasarruf (yeşil, koşullu)
│ 🎯 Budget · $45.20 / $100.00 · 45%   ▓▓▓▓▓▓▓░░░░░░░░░░                     │  bütçe pace (koşullu)
└───────────────────────────────────────────────────────────────────────────┘

[ Claude | Codex ]                                      [ 7 days | 30 days ]

┌─ COST TILES (4) ──────────────────────────────────────────────────────────┐
│ ┌today─┐ ┌last 7d┐ ┌last 30d┐ ┌30d in/out──┐                              │
│ │«$1.24»│ │«$8.73»│ │«$25.10»│ │«1.5M/342K» │                             │
│ └───────┘ └───────┘ └────────┘ └────────────┘                             │
│ Prompt caching saved «$4.20» in the last 30 days.                         │  cache savings (koşullu)
└───────────────────────────────────────────────────────────────────────────┘

┌─ CROSS-MACHINE (koşullu, niş) ────────────────────────────────────────────┐
│ Account · all machines · live    Claude — 5h 42% · 7d 68%                 │
│ Per machine · local 30-day       Combined: $12.47 · 3 Macs               │
│ MacBook Pro   ▓▓▓▓▓▓▓▓▓▓▓▓  «$7.20 · this Mac»                            │
└───────────────────────────────────────────────────────────────────────────┘

┌─ 30-DAY COST TREND ───────────────────────────────────────────────────────┐
│ 30d total $127.43 · peak $6.21/day · hover for a day                      │
│        ╱╲      ╱╲                                                          │  alan grafik 150pt
│ ___╱╲╱   ╲╱╲╱╲╱  ╲___╱╲___                                                │  hover crosshair+tooltip
└───────────────────────────────────────────────────────────────────────────┘

┌─ DAILY COST TABLE (7 sütun — SADELEŞTİR, "Excel hissi") ──────────────────┐
│ PROJECT      INPUT   OUTPUT  CACHE+  CACHE↻   TOTAL    COST                │  başlık 9.5pt caps
│ ─────────────────────────────────────────────────────────────────────     │
│ Today                 1.2M    340K    80K     12M      13.6M   «$3.47»     │  gün toplamı (bold)
│   api-router          800K    210K    50K     8M       9.0M    «$2.10» ›   │  proje satırı (tıkla→detay)
│   web-ui              400K    130K    30K     4M       4.6M    «$1.37» ›   │
│ ─────────────────────────────────────────────────────────────────────     │
│ TOTAL                 8.1M    2.0M    400K    95M      105M    «$25.10»    │  grand total
└───────────────────────────────────────────────────────────────────────────┘

[ Analyze my usage ]  ⟳                                                       AI advisor
Rates: LiteLLM (live) · Estimated as if metered…                             kaynak dipnotu
```
**Redesign notu:** Hero clarity kartı korunmalı (mükemmel). 7 sütunlu tablo → görsel-bar ağırlıklı, isteğe bağlı detay.

---

## EKRAN 3d — GENERAL ayarlar (11 bölüm — GRUPLAMA hedefi)

Her bölüm: `[SF symbol] BAŞLIK` + alt yazı + kart gövdesi (PreferenceSectionCard).

```
[🎨] THEME · "Pick a menubar palette."
     ┌Default┐ ┌Mono─┐ ┌Neon─┐        ← 3 sütun tema kart grid (148×82), 6 tema
     ┌Pastel┐ ┌Term─┐ ┌Compact┐
[🌐] LANGUAGE · "System, English, or Turkish."     [ Auto | EN | TR ]
[▭]  SEPARATOR · "Character between fields."        [ · | | | - | — | / | none ]
[≡]  TITLE CONTENT · "Toggle fields; drag to reorder."
     [⠿ Agent icon ☑] [⠿ Project ☑] [⠿ Context % ☑]   ← sürüklenebilir chip'ler
[👁] PREVIEW · "Live menubar sample."   [ ● Claude · my-repo · 42% ]
[🕐] RESET TIME · "Duration or clock time."         [ Relative | Absolute ]
[📏] BAR MARKS · "Ticks at 70%/90%."                ☐ Warning marks on bars
[▦]  BACKGROUND SESSIONS                             ☑ Surface critical bg sessions
[🎯] MONTHLY BUDGET · "Tints menubar near budget."  $ [____] USD/month
[📡] PROVIDER STATUS                                 ☑ Show upstream incident overlay
[✨] DELIGHT                                          ☑ Celebrate quota resets
```
**Redesign notu:** 11 bölüm tek scroll çok uzun → "Görünüm / Uyarılar / Davranış" gruplaması.

---

## EKRAN 3e — PRIVACY ayarlar

```
[✨] AI ADVISOR (bring your own key)     [ Off|OpenAI|Gemini ▾]  [secure key field……]
[👁] SHARED OUTPUT       ☑ Mask project paths and emails
[↑]  SHARE CARD          ☑ Mask project names on share card
[💻] ACROSS YOUR MACS    [Choose folder…]  ~/Dropbox/cb   [Clear]
```
**Karar:** İyi organize, gizlilik-önce. TUT.

---

## EKRAN 3f — ABOUT

```
            [ LOGO ]
           ContextBar
       Version 0.7.10 (42)
   "Native repository context…"

[⬇] UPDATES            [Check for Updates]  [View Changelog]
[📁] REPOSITORY CONTEXT   Artifacts: ~/.context-bar · Brief: .context-bar/AGENT.md · CLAUDE.md
[📥] DATA SOURCES         Git · ~/.claude/projects · ~/.codex/sessions · → context.json
[⌨] FILES & SHORTCUTS     v0.7.10 · dist/ContextBar.app · ⌘D open · ⌘R refresh
```
**Karar:** Standart, temiz. TUT.

---

## EKRAN 4 — WIDGET & SHARE CARD (yan ürünler)

```
WIDGET (WidgetKit):              SHARE CARD (PNG export):
┌──────────────────┐            ┌────────────────────────────┐
│ ContextBar       │            │  Today's HUD               │
│ Claude    «42%»  │            │  Claude · 42% context      │
│ ▓▓▓▓▓░░░░░        │            │  5h 42% · 7d 68% · $3.47   │
│ 5h 42% · 7d 68%  │            │  [proje adları maskeli]    │
└──────────────────┘            └────────────────────────────┘
```
**Not:** Redesign'da ana yüzeylerle görsel tutarlılık sağlanmalı (aynı imza renk/tipografi).

---

## Redesign için özet öncelik haritası (bu wireframe'ler üzerinden)

| Ekran | Birincil hamle |
|-------|----------------|
| Menubar | 3 acil-durum sinyali → tek birleşik gösterge |
| Popover | Hero hiyerarşisi + footer'dan tema dropdown'ı kaldır |
| Usage | Popover ile rol ayrımı (geçmiş/derinlik) |
| Stats | 10 tile → 4-6 + progressive disclosure; heatmap/insight'ı yıldız yap |
| Cost | Hero clarity'yi koru; 7 sütun tabloyu hafiflet |
| Settings | General'i 3 gruba böl |
| Tüm yüzeyler | Tek imza renk + tutarlı görsel ritim (token üzerinden) |
