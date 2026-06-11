# Claude Design Brief — ContextBar UI Redesign

> Bu dosya doğrudan Claude Design'a yapıştırmak içindir. Aşağıdaki "=== BRIEF ===" bloğunu kopyala.

=== BRIEF BAŞLANGICI ===

# Görev: ContextBar — native macOS menubar uygulaması için UI redesign mockup'ları

Sen kıdemli bir macOS ürün tasarımcısısın. Mevcut, çalışan bir uygulamanın UI'ını yeniden tasarlayacaksın. Aşağıdaki ekranların yüksek kaliteli, tutarlı mockup'larını üret.

## Ürün ne yapıyor
ContextBar, **Claude Code ve Codex** kullanımını ve maliyetini görünür kılan bir araçtır. Geliştiriciler menü çubuğundan anlık olarak şunları görür: aktif AI ajanının **context penceresi doluluğu (%)**, **kullanım limitleri (5 saatlik / 7 günlük rolling kotalar)**, ve **maliyet tahminleri** (gerçek fatura değil, API-eşdeğeri tahmin). Yerel-öncelikli; tüm veri kullanıcının makinesindeki transcript'lerden üretilir, sunucu yok.

## Sert kısıtlar (bunlara uy)
- **Platform:** native macOS (Ventura+). AppKit hissi korunmalı: menü çubuğu popover'ı, sistem materyalleri (vibrancy/blur), SF Symbols ikonları, light + dark mode.
- **Restrained UI:** Sade ve sakin olmalı. Her ekrandan öğe çıkarmak, eklemek kadar değerli. Aşırı dekoratif/gradient-bombardımanı YOK.
- **Native ama jenerik değil:** "Stok macOS" hissinden çıkıp belirgin ama sakin bir görsel karakter istiyorum.
- **Veri tipleri aynı kalır:** % değerler, token sayıları (mono), $ maliyetler, zaman damgaları. Bunları daha iyi sun; uydurma metrik ekleme.

## Görsel yön (senden istediğim imza)
1. **Tek imza renk + nötr taban:** Tüm vurgu tek bir "accent" renge bağlı (mevcut sistemde `accent = proje rengi`). Cesur ama göz yormayan bir imza renk öner; geri kalan nötr gri ölçek.
2. **Net hiyerarşi:** Her ekranda bir "kahraman metrik", gerisi destekleyici. Şu an her şey eşit ağırlıkta yarışıyor — bunu çöz.
3. **Tutarlı görsel ritim:** Spacing ölçeği 4/8/12/16/20/24/32; köşe yarıçapı chip 8 / kart 12 / hero 16. Sayılar daima monospaced (tabular).
4. **Progressive disclosure:** Yoğun ekranlarda (özellikle Stats/Cost) en değerli 4-6 öğe önde, gerisi "daha fazla" altında.

## Light + Dark mode
Her ekranı hem light hem dark için ver. Mevcut palet: primary text light #141414 / dark #F5F5F5; ikincil/üçüncül gri tonları; kartlar yarı saydam controlBackground.

---

## Tasarlanacak ekranlar (öncelik sırasıyla)

### 1. POPOVER (genişlik 360pt) — EN ÖNCELİKLİ
Menü çubuğuna tıklayınca açılan ana panel. Yukarıdan aşağıya kartlar:
- **Hero kart:** aktif ajan. İçerik: durum noktası, proje adı (büyük), **context % (kahraman metrik)**, marka ikonu + "Claude · model · 2m ago · 45m running", context progress bar (>%75 vurgulu), "Context · 621.1k / 200k" detayı.
- **Paralel oturumlar kartı (koşullu):** max 5 satır; her satır proje·model + ince bar + % + zaman.
- **Limit kartı:** 5h limit (bar + % + "↻ 1h47m"), 7d limit (bar + %), session total (değer).
- **Diğer araçlar (koşullu):** Gemini/Copilot satırları (token · N×/hafta · model).
- **Footer:** Share / Settings / Refresh / Quit ikonları. (NOT: mevcut tema dropdown'ını footer'dan çıkar, sadeleştir.)
- **Ayrıca ver:** loading durumu ("Gathering session data…") ve empty durumu ("No agent data yet").

### 2. STATS sekmesi (820×680 pencere içinde)
En yoğun ekran — sadeleştirme şart. İçerik:
- Üstte: provider seçici [Claude|Codex] + aralık [All time|30d|7d].
- **Overview:** ~10 metrik var (sessions, tokens, sub-agent %, active days, current/longest streak, longest session, most active day, favorite model). **Bunları 4-6 öne çıkar, gerisini "daha fazla"ya koy.**
- **Year heatmap ⭐:** GitHub tarzı yıllık ısı haritası (7 satır × ~52 hafta, accent yoğunluk rampası). Bu görsel imza öğesi — yıldız yap.
- **Daily breakdown:** gün/aralık seçici + proje bar chart + oturum listesi.
- **Insight kartları ⭐:** otomatik anlatı kartları (ör. "fresh token'ların %24'ü sub-agent'larda", "context %71"). icon chip + kalın metrik + açıklama. Bunlar değerli, öne çıkar.
- Token composition pill bar (input/output/cache).

### 3. COST / VALUE sekmesi
- **Hero clarity kart ⭐ (KORU, çok iyi):** "Bu bir fatura değil" mesajı. İçerik: plan satırı ("Max 5× · $100/mo"), büyük API-eşdeğeri ("≈ $2,847/mo"), açıklama metni, tasarruf satırı (yeşil "28× plan değeri"), bütçe pace bar.
- Cost tiles: today / 7d / 30d / in-out.
- 30-günlük cost trend grafiği (hover'lı alan grafik).
- **Daily cost tablosu (SADELEŞTİR):** şu an 7 sütun (project/input/output/cache+/cache↻/total/cost) — "Excel hissi" veriyor. Bunu görsel-bar ağırlıklı, daha hafif bir yapıya dönüştür; detayı tıklamayla aç.

### 4. MENÜBAR BAŞLIĞI (küçük ama önemli)
Menü çubuğundaki canlı metin: `● Claude · my-repo · 42%`. Şu an 3 ayrı acil-durum sinyali (incident noktası, budget noktası, kızışan-oturum uyarısı) aynı dar alanda yarışıyor. **Bunları tek birleşik, zarif bir duruma indir.**

### 5. GENERAL ayarlar
11 ayar bölümü tek uzun scroll. Bunları mantıklı 3 gruba böl: **Görünüm** (tema, dil, separator, başlık alanları, preview) / **Uyarılar** (bar marks, background sessions, provider status, budget) / **Davranış** (reset stili, delight). Native macOS ayar penceresi hissi.

---

## Tasarım sistemi temeli (mevcut — geliştir)
- Spacing: 4·8·12·16·20·24·32 · Radius: chip 8 / kart 12 / hero 16 / popover 20
- Tipografi: display ~24-28pt semibold (büyük sayılar), title 15pt semibold, body 12pt, caption 10pt UPPERCASE kerned; tüm sayılar monospaced tabular.
- Kartlar: yarı saydam zemin + 0.5pt ince border + yumuşak gölge (hero'da).

## Teslimat
Her ekran için light + dark varyant. Önce 1 imza renk önerisi + tipografi/spacing ölçeği (style tile), sonra ekranlar öncelik sırasıyla. Tasarım kararlarını 1-2 cümleyle gerekçelendir.

=== BRIEF SONU ===
