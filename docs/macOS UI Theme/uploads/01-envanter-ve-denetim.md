# ContextBar — UI Envanteri, Denetimi ve İyileştirme Analizi

> Faz 1 (nerede ne var) · Faz 2 (gerekli mi gereksiz mi) · Faz 3 (daha iyi nasıl sunarız)
> Hazırlayan: Claude Code · Kaynak: `repo/menubar/sources/*.swift` (saf AppKit, SwiftUI yok)

---

## 0. Genel Bakış — UI yüzeyleri

ContextBar'ın görsel yüzeyi **5 ana alandan** oluşuyor:

| # | Yüzey | Dosya | Rol |
|---|-------|-------|-----|
| A | **Menubar başlığı** (status item) | `AppDelegate.swift` | macOS menü çubuğundaki canlı metin: `ajan · proje · %42` |
| B | **Popover** (tıklayınca açılan panel) | `PopoverViewController.swift` | Anlık durum: hero kart + paralel oturumlar + limitler + diğer araçlar + footer |
| C | **Detail penceresi** (6 sekme) | `DetailWindow.swift` | Usage · Stats · Value · General · Privacy · About |
| D | **Tasarım sistemi** | `DesignTokens.swift`, `Theme.swift` | Spacing/radius/tipografi/palet + 6 tema |
| E | **Yan ürünler** | `Widget.swift`, `ShareCard.swift` | WidgetKit widget'ı + paylaşım kartı (PNG) |

**Mimari notlar (tasarımı etkileyen):**
- Tüm layout programatik (`NSStackView` + AutoLayout). Storyboard/XIB yok → değişiklikler kodla yapılır.
- **Merkezi tasarım sistemi var** (`DesignTokens`, `Theme`, `Surface` reçeteleri) → renk/spacing/tipografi değişiklikleri tek noktadan yönetiliyor. Bu, redesign'ı çok kolaylaştırır.
- Veri tek kaynaktan: Rust motoru `~/.context-bar/context.json` üretir; Swift UI bunu okur. **UI değişikliği için Rust gerekmez.**
- Yoğun grafikler (heatmap, tablo, sparkline) `NSView.draw()` ile elle çiziliyor — yani yeniden tasarımda bu custom çizim kodu da elden geçecek.

---

## FAZ 1 + 2 — Ekran ekran envanter & denetim

> Her öğe için karar: **TUT** (iyi çalışıyor) · **SADELEŞTİR** (var ama yük/karmaşık) · **TAŞI** (yanlış yerde) · **GÖZDEN GEÇİR** (değeri tartışmalı)

---

### A. MENUBAR BAŞLIĞI

| Öğe | Ne gösterir | Karar | Gerekçe |
|-----|-------------|-------|---------|
| Ajan + proje + `%` | `Claude · my-repo · 42%` | **TUT** | Ürünün özü; menü çubuğunda anlık bağlam. |
| Yapılandırılabilir alanlar | agent / project / pct aç-kapa + sıralama | **TUT** | Güçlü kişiselleştirme, az yer kaplıyor. |
| Incident prefix (`● `) | Üst kaynak (Anthropic/OpenAI) arıza noktası | **GÖZDEN GEÇİR** | Değerli ama menü çubuğunu kalabalıklaştırıyor; popover'da zaten var. |
| Budget pressure suffix (`●`) | Bütçe/limit baskısı uyarısı | **GÖZDEN GEÇİR** | İyi fikir ama 3 ayrı sinyal (incident + budget + critical-bg) aynı dar alanda yarışıyor → görsel gürültü. |
| Critical background suffix (`⚠ proj 80%`) | Arka plan oturumu kızıştığında uyarı | **GÖZDEN GEÇİR** | Çok niş; menü çubuğu başlığını uzatıyor. Belki sadece popover/bildirim. |

**Denetim özeti:** Çekirdek (ajan·proje·%) mükemmel. Sorun: **menü çubuğuna 3 ayrı acil-durum sinyali sığdırılmaya çalışılmış** → sadeleştirme fırsatı.

---

### B. POPOVER (360pt genişlik, yukarıdan aşağıya)

| Bölüm | Öğeler | Karar | Not |
|-------|--------|-------|-----|
| **Hero kart** | Durum noktası, proje adı (22pt), context %, marka ikonu, model·zaman·süre satırı, context progress bar, "Context · 621k/200k" detayı | **TUT** (ama yoğun) | En değerli yüzey. 6+ bilgi tek kartta — hiyerarşi netleştirilebilir. |
| Hero: incident badge | "Service disruption" pill | **SADELEŞTİR** | Menubar'daki ile çift; tek yerde kalsın. |
| Hero: celebration (konfeti) | Limit sıfırlanınca parçacık patlaması | **TUT** | Hoş "delight" anı, kapatılabilir. |
| Loading / empty state | "Gathering session data…" / "No agent data yet" | **TUT** | İyi onboarding; görsel dili yenilenebilir. |
| **Paralel oturumlar** | Max 5 satır: proje·model + bar + % + zaman | **TUT** | Çok-oturum kullanıcısı için kritik fark yaratan özellik. |
| **Limit kartları** | Ajan başına 5h / 7d / session-total bar + reset | **TUT** | Ürünün ikinci ana değeri (kota görünürlüğü). |
| **Diğer araçlar** | Gemini/Copilot vb. satırlar: token · N×/hafta · model | **GÖZDEN GEÇİR** | Faydalı ama popover'ı uzatıyor; 30dk içinde kullanılmazsa gizleniyor (iyi). |
| **Footer** | Theme dropdown + Share/Settings/Refresh/Quit ikonları | **SADELEŞTİR** | Theme seçici footer'da fazla yer kaplıyor (zaten Settings'te de var). İkonlar iyi. |

**Denetim özeti:** Popover bilgi açısından zengin ama **dikey olarak uzayabiliyor** (hero + paralel + N limit kartı + diğer araçlar + footer). Tema seçici hem footer'da hem General'de → tekrar. Hero kartında bilgi yoğunluğu yüksek, hiyerarşi rafine edilebilir.

---

### C1. USAGE sekmesi

| Öğe | Ne gösterir | Karar |
|-----|-------------|-------|
| Aktif ajan kartı (durum + ad + meta) | Şu an çalışan ajan | **TUT** |
| 4 stat tile (context / session / 5h / 7d) | Anlık metrikler | **TUT** |
| 30-günlük sparkline | Token trendi | **TUT** |
| "Other AI tools" kartı | Diğer araç özetleri | **GÖZDEN GEÇİR** — popover'daki ile örtüşüyor |

**Not:** Usage sekmesi büyük ölçüde **popover hero + limitlerin daha geniş hali**. İkisi arasında ciddi içerik tekrarı var → "popover = anlık, Usage = geçmiş/derinlik" şeklinde rolleri ayrıştırmak iyi bir fırsat.

---

### C2. STATS sekmesi (en yoğun ekran)

| Bölüm | Öğeler | Karar | Not |
|-------|--------|-------|-----|
| Provider kontrol | Claude / Codex | **TUT** | |
| Range kontrol | All time / 30d / 7d | **TUT** | |
| Overview tiles | ~10 tile: sessions, tokens, sub-agent %, active days, streak, longest session, favorite model/effort… | **SADELEŞTİR** | 10 tile bir anda çok; en değerli 4-6'sı öne çıkarılabilir, gerisi "daha fazla"da. |
| **Year heatmap** | GitHub tarzı yıllık ısı haritası + hover + tıkla-detay | **TUT** ⭐ | Görsel imza öğesi; redesign'da yıldız olabilir. |
| Daily breakdown | Day/Range modu, takvim, proje bar chart, oturum listesi | **TUT** | Güçlü drill-down. |
| Token composition bar | Input/Output/Cache pill | **TUT** | |
| Insight kartları (6 adet) | Otomatik anlatı ("%24'ü sub-agent'larda") | **TUT** ⭐ | Çok değerli, "akıllı" hissi veriyor. |
| AI deep-dive | Kendi API key'inle LLM analizi | **TUT** | İsteğe bağlı, gizlilik korunmuş. |
| Fun fact | "War and Peace'ten 1.2× fazla" | **TUT** | Hoş delight; küçük yer. |

**Denetim özeti:** Stats **özellik bakımından çok zengin** — neredeyse aşırı. Risk: tek sayfada provider + range + 10 tile + heatmap + breakdown + 6 insight + AI + fun fact = **bilişsel yük**. Redesign'ın en büyük fırsatı burada: **aynı veriyi daha sakin, kademeli (progressive disclosure) sunmak.**

---

### C3. VALUE / COST sekmesi

| Bölüm | Öğeler | Karar | Not |
|-------|--------|-------|-----|
| **Hero clarity card** | "Bu bir fatura değil" + plan fiyatı + API-eşdeğeri + tasarruf + bütçe pace | **TUT** ⭐ | Ürünün en akıllı UX kararı: kafa karışıklığını ("neden binlerce $?") önler. |
| Provider / Range | Claude/Codex · 7d/30d | **TUT** | |
| Cost tiles | today / 7d / 30d / in-out | **TUT** | |
| Cache savings insight | "Caching $X kazandırdı" | **TUT** | |
| Cross-machine summary | Hesap geneli limitler + makine başına 30g | **GÖZDEN GEÇİR** | Güçlü ama niş (çok-Mac kullanan). Opsiyonel kalmalı. |
| 30g cost trend chart | Hover'lı alan grafiği | **TUT** | |
| **Daily cost table** | 7 sütunlu tablo (project/in/out/cache+/cache↻/total/cost) + tıkla-detay | **SADELEŞTİR** | Çok güçlü ama **7 sütun bir menubar uygulaması için yoğun** (Excel hissi). Mobil/dar pencerede zorlanır. |
| AI advisor | LLM maliyet ipuçları | **TUT** | |
| Source footnote | LiteLLM atfı + "tahmin" açıklaması | **TUT** | Güven için gerekli. |

**Denetim özeti:** Value sekmesi **kavramsal olarak çok iyi** (hero clarity card örnek bir UX kararı). Sorun: 7 sütunlu maliyet tablosu görsel olarak en "ağır" eleman.

---

### C4-6. Ayar sekmeleri (General / Privacy / About)

| Sekme | Durum | Karar |
|-------|-------|-------|
| **General** | 11 bölüm: tema, dil, separator, başlık alanları, preview, reset stili, bar marks, background sessions, budget, provider status, delight | **SADELEŞTİR** — 11 bölüm tek scroll çok uzun; gruplama ("Görünüm" / "Uyarılar" / "Davranış") gerekli |
| **Privacy** | AI Advisor key, redaction, share card maskeleme, cross-Mac folder | **TUT** | İyi organize, gizlilik-önce yaklaşımı net |
| **About** | Logo, sürüm, güncelleme, veri kaynakları, dosya yolları, kısayollar | **TUT** | Standart, temiz |

---

### D. TASARIM SİSTEMİ & TEMALAR

**Token'lar (sağlam temel):**
- Spacing: 4·8·12·16·20·24·32 · Radius: chip 8 / card 12 / hero 16 / popover 20
- Tipografi: display (28), title (15), body (12), caption (10) + monospaced varyantlar
- Palet: primary/secondary/tertiary text (light+dark dinamik)
- Surface reçeteleri: `applyCard()`, `applyHero()` (gölge, border, alpha)

**6 tema:** Default · Mono · Neon · Pastel · Terminal · Compact

| Karar | Detay |
|-------|-------|
| **TUT** | Token mimarisi sağlam — redesign'ın temeli bu. |
| **GÖZDEN GEÇİR** | 6 tema biraz fazla; bazıları (Neon/Pastel) zorlama. Belki 3-4 cilalı tema + 1 imza tema. |
| **FIRSAT** | `accent = projectColor` kuralı tüm vurguyu tek renge bağlıyor → yeni görsel kimlik buradan kolayca enjekte edilir. |

---

## FAZ 3 — Mevcudu daha iyi nasıl sunarız (fırsat haritası)

Denetimden çıkan **en yüksek etkili 7 fırsat**, etki/emek ile:

| # | Fırsat | Sorun | Yön | Etki | Emek |
|---|--------|-------|-----|------|------|
| 1 | **Bilişsel yükü azalt (progressive disclosure)** | Stats/Cost sekmeleri tek sayfada çok şey gösteriyor | En değerli 4-6 metrik öne, gerisi "daha fazla" altına | ★★★ | Orta |
| 2 | **Popover ↔ Usage rol ayrımı** | İçerik tekrarı (hero/limitler iki yerde) | Popover = anlık & hızlı; Detail = geçmiş & derinlik | ★★★ | Orta |
| 3 | **Menü çubuğu sinyallerini sadeleştir** | 3 acil-durum eki dar alanda yarışıyor | Tek birleşik durum noktası + detayı popover'da | ★★ | Düşük |
| 4 | **Yeni görsel kimlik / imza renk** | Native ama "jenerik macOS" hissi | accent token üzerinden cesur ama sakin bir palet | ★★★ | Düşük (token) + Orta (uygulama) |
| 5 | **Hero kart hiyerarşisi** | 6+ bilgi eşit ağırlıkta yarışıyor | Bir "kahraman metrik" (context %) + destekleyiciler | ★★ | Düşük |
| 6 | **Maliyet tablosunu hafiflet** | 7 sütun Excel hissi | Özet + isteğe bağlı detay; görsel bar ağırlıklı | ★★ | Orta |
| 7 | **Tema setini rafine et** | 6 tema, bazıları zorlama | 3-4 cilalı tema + 1 imza tema | ★ | Düşük |

**Tasarım ilkeleri (CONTRIBUTING ile uyumlu):**
- "Native his korunsun" → macOS davranışları (popover, materyaller, SF Symbols) kalsın.
- "Restrained UI" → daha az ama daha iyi; her ekrandan 1-2 öğe çıkarmak ekleme kadar değerli.
- Tek imza fikir: tutarlı bir **görsel ritim** (spacing/hiyerarşi) + bir **imza renk/an**.

---

## Sonraki adım — "Ekranları getirme" planı

Sen Claude Design'da çalışacağın için elimizdeki seçenekler:

- **Seçenek 1 — Gerçek ekran görüntüleri:** Swift UI'ı `swiftc` ile derleyip (Rust gerekmez, `context.json` zaten canlı) uygulamayı çalıştırıp her ekranın gerçek screenshot'ını çekmek. **Avantaj:** birebir gerçek. **Maliyet:** derleme + çalıştırma + computer-use ile yakalama.
- **Seçenek 2 — Yapısal ekran dökümü:** Her ekranın bu dokümandaki envanterini bir "wireframe tarifi" (kutu/hiyerarşi) olarak çıkarmak — Claude Design'a metinle beslemek için.
- **Seçenek 3 — İkisi:** Önce gerçek screenshot, sonra her biri için kısa wireframe notu.

Karar senin; bir sonraki turda netleştireceğiz.
