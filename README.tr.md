# ContextBar

<p align="center">
  <img src="logo.png" alt="ContextBar logosu" width="560">
</p>

<p align="center">
  <a href="README.md">English</a> | Türkçe
</p>

<p align="center">
  <strong>Claude Code ve Codex için kullanım ve maliyet görünürlüğü — native bir macOS menubar uygulaması ve çapraz platform bir terminal CLI.</strong>
</p>

<p align="center">
  ContextBar, Claude Code ve Codex kullanımınızın nereye gittiğini çalıştığınız her yüzeyde gösterir. <strong>Native macOS menubar uygulaması</strong> canlı oturum görünümü, rolling 5sa/7g limit göstergeleri, maliyet trendleri, bir WidgetKit widget'ı ve Share kartı sunar. <strong>Çapraz platform terminal CLI</strong>, ccusage sınıfı raporları (daily / weekly / monthly / session / blocks) ve canlı bir TUI panosunu macOS, Linux, Windows ve SSH'a taşır — saf-Rust motor, <code>python3</code> gerektirmez. Maliyet rakamları LiteLLM fiyat tablosundan (ccusage ile aynı kaynak) hesaplanan API-eşdeğeri <strong>tahminlerdir</strong>, fatura değil. Depo bağlamı yerel snapshot'larla güncel kalır; harici servis gerekmez.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-bar/releases/latest/download/ContextBar.dmg">
    <img src="docs/images/download-macos-cta.svg" alt="macOS için uygulamayı indir" width="300">
  </a>
</p>

<p align="center">
  <strong>Terminali mi tercih ediyorsun?</strong> <code>npx context-bar@latest daily</code> · <code>cargo install context-bar</code> — bkz. <a href="#kurulum">Kurulum</a>.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-bar/releases/latest">
    <img alt="Güncel sürüm" src="https://img.shields.io/github/v/release/htahaozlu/context-bar?style=flat-square&label=release&color=2F81F7">
  </a>
  <a href="https://crates.io/crates/context-bar">
    <img alt="crates.io" src="https://img.shields.io/crates/v/context-bar?style=flat-square&label=crates.io&color=E07A2B">
  </a>
  <a href="https://www.npmjs.com/package/context-bar">
    <img alt="npm" src="https://img.shields.io/npm/v/context-bar?style=flat-square&label=npm&color=CB3837">
  </a>
  <a href="LICENSE">
    <img alt="Lisans" src="https://img.shields.io/badge/license-Apache--2.0-5DADE2?style=flat-square">
  </a>
</p>

<p align="center">
  <img alt="Platformlar" src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-7DCEA0?style=flat-square">
  <img alt="Mimariler" src="https://img.shields.io/badge/arch-arm64%20%7C%20x64-7DCEA0?style=flat-square">
  <img src="https://img.shields.io/github/downloads/htahaozlu/context-bar/total?style=flat-square&label=indirme" alt="Toplam İndirme">
  <img src="https://img.shields.io/github/stars/htahaozlu/context-bar?style=flat-square" alt="Yıldız">
</p>

## Canlı demo

<p align="center">
  <img src="docs/images/context-bar-demo.gif" alt="ContextBar üzerinde Claude Code ve Codex kullanımının macOS'ta canlı güncellendiğini gösteren demo" width="100%">
</p>

Native macOS uygulaması Claude Code ve Codex bağlam kaymasını ve rolling kullanımı siz çalışırken görünür tutar; terminal CLI aynı kullanım ve maliyet rakamlarını SSH dahil her işletim sistemine taşır.

## Kurulum

ContextBar tek sürümden iki ürün sunar: **native bir macOS uygulaması** ve **çapraz platform bir terminal CLI**. Hangisi sana uyuyorsa onu seç — ya da ikisini birden.

### macOS uygulaması — Homebrew (önerilen)

Premium, native amiral gemisi: menubar durum öğesi, canlı AppKit popover, WidgetKit widget'ı ve Share kartı. macOS Ventura (13) veya üzeri gerekir.

```bash
brew install --cask htahaozlu/context-bar/context-bar
```

`brew` ilk kurulumda `htahaozlu/homebrew-context-bar` tap'ini otomatik ekler. Güncelleme:

```bash
brew update && brew upgrade --cask htahaozlu/context-bar/context-bar
```

### Terminal CLI (macOS · Linux · Windows)

Çapraz platform erişim: ccusage sınıfı kullanım ve maliyet raporları + canlı TUI panosu. Saf-Rust motor — **`python3` gerekmez**. macOS, Linux (x64/arm64, statik musl) ve Windows (x64/arm64) üzerinde, SSH dahil çalışır.

**npm (kurulum yok — en güncelini çalıştırır):**

```bash
npx context-bar@latest daily
# diğer paket yöneticileriyle de:
bunx context-bar daily
pnpm dlx context-bar daily
```

Global kurmak için:

```bash
npm install -g context-bar
```

Meta paket, platformuna uygun önceden derlenmiş ikiliyi opsiyonel bir bağımlılıkla çözer (`@htahaozlu/context-bar-<os>-<cpu>`); postinstall yok, `npm ci --ignore-scripts` altında da çalışır.

**Cargo (crates.io):**

```bash
cargo install context-bar
```

`context-bar`'ı (ve motoru `context-bar-core`'u) crates.io'dan derler.

**Önceden derlenmiş ikililer (GitHub release):**

Her [release](https://github.com/htahaozlu/context-bar/releases/latest) altı hedef için, her biri `.sha256` checksum'lı, bağımsız bir ikili ekler:

| İşletim sistemi | mimari | dosya |
| --- | --- | --- |
| macOS | arm64 | `context-bar-aarch64-apple-darwin.tar.gz` |
| macOS | x64 | `context-bar-x86_64-apple-darwin.tar.gz` |
| Linux | arm64 | `context-bar-aarch64-unknown-linux-musl.tar.gz` |
| Linux | x64 | `context-bar-x86_64-unknown-linux-musl.tar.gz` |
| Windows | arm64 | `context-bar-aarch64-pc-windows-msvc.zip` |
| Windows | x64 | `context-bar-x86_64-pc-windows-msvc.zip` |

Platformuna uygun arşivi indir, checksum'ı doğrula, aç ve `context-bar`'ı `PATH`'e koy. (Linux ikilileri musl'a statik bağlıdır, her dağıtımda çalışır.)

### macOS uygulaması — doğrudan indirme (DMG)

Homebrew kullanmıyorsan:

1. [En son sürümden](https://github.com/htahaozlu/context-bar/releases/latest) `ContextBar.dmg` indir (evrensel: Apple Silicon + Intel).
2. `ContextBar.app`'i `Applications` klasörüne sürükle.
3. Aç. Uygulama **Apple tarafından imzalı ve notarize edilmiştir**, karantina uyarısı olmadan açılır.
4. DMG'yi çıkarıp sil.

## Önizleme

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar yerel kullanım penceresi" width="100%">
</p>

Claude Code ve Codex için sürekli oturum görünürlüğüne sahip yerel macOS kullanım penceresi.

<p align="center">
  <img src="docs/images/context-bar-menubar.png" alt="ContextBar menubar" width="400">
</p>

Aktif ajan, proje ve bağlam kullanımını gösteren kompakt menubar durum öğesi. Tıklandığında aktif oturum, bağlam penceresi, 5sa/7g limitleri, paralel oturumlar ve canlı tema seçici içeren yerel bir popover açılır.

<p align="center">
  <img src="docs/images/context-bar-cost.png" alt="ContextBar Maliyet sekmesi — proje başına günlük tahmini API-eşdeğeri maliyet" width="100%">
</p>

**Maliyet** sekmesi, abonelik kullanımınızın ölçümlü API'de ne kadara mal olacağını tahmin eder — gün gün, proje proje, Claude ve Codex için — ve bunu plan fiyatınızla karşılaştırır (örn. *"~41× Max 20× planınız"*). `better-ccusage daily --instances`'i native olarak çoğaltır, üstüne bir CLI'nin pasif gösteremeyeceği aylık projeksiyon ve maliyet trendi ekler. Sayılar, LiteLLM oran tablosundan (ccusage ile aynı kaynak) fiyatlanan tahminlerdir, fatura değildir.

## Ne işe yarar

ContextBar, ajan destekli geliştirmede sürekli tekrar eden iki sorunu hedefler:

- depo bağlamı, ajan özeti güncellenmeden daha hızlı değişir
- kullanım ve oturum durumu terminal çıktısı ile yerel kayıtlar arasında kaybolur

Bu iki problemi, sürekli kararlı proje özetleri üreten yerel bir işlem hattıyla ve Claude Code ile Codex etkinliğini gösteren yerel bir macOS HUD arayüzüyle çözer.

### Temel yüzeyler

- `.context-bar/` altında depo snapshot'ları
- Kararlı `AGENT.md` ve `CLAUDE.md`
- refresh, watch ve global görünümler için CLI
- Yerel AppKit menubar yardımcı uygulaması
- Proje başına günlük tahmini API-eşdeğeri maliyet (Claude + Codex)
- Araçlar için Markdown ve JSON çıktıları

## Temel yetenekler

### Depo bağlamı üretimi

Her yenileme, ajanların okuyabileceği durumu `.context-bar/` altına yazar:

- `state.json`
- `brief-now.md`
- `brief-session.md`
- `brief-week.md`
- `AGENT.md`
- `hud.md`

Claude Code uyumluluğu için `CLAUDE.md`, depo köküne de aynalanır.

### CLI iş akışı

- `context-bar hud` mevcut depoyu yeniler ve HUD çıktısını basar
- `context-bar snapshot` HUD basmadan artifact yazar
- `context-bar watch 30 .` depo bağlamını belirli aralıklarla taze tutar
- `context-bar global` `~/.context-bar/` altında projeler arası HUD oluşturur

### Yerel macOS yardımcısı

Yardımcı uygulama `~/.context-bar/context.json` (v0.3.13'e kadar `hud.json`) dosyasını okur ve şunları sağlar:

- kompakt menubar durum öğesi (aktif ajan + proje + bağlam %)
- modern AppKit popover: aktif ajan, bağlam penceresi, ilerleme barlı 5sa/7g
  limitleri, paralel oturumlar ve tespit edilen diğer AI araçları için kartlar
- inline renk swatch'leri ve canlı önizlemeli tema seçici — bir temanın
  üzerinde gezinirken menubar başlığı o paletle yeniden çizilir
- üç veri görünümü (Kullanım, İstatistik, Maliyet) artı sade, Apple-tarzı ayar seti (Genel · Görünüm · Gizlilik) ve Hakkında
- paralel Claude / Codex oturumları için per-session bağlam yüzdesi

### Tahmini maliyet ve plan değeri

**Maliyet** sekmesi, abonelik kullanıcılarının giderek daha çok sorduğu soruyu yanıtlar — *"ölçümlü API'ye zorlanırsam bu bana ne kadara mal olur?"*

- gün başına, proje başına maliyet kırılımı (`better-ccusage daily --instances`'in native karşılığı), hem Claude hem Codex için
- bugün / son 7 gün / son 30 gün için tahmini maliyet, artı 30 günlük girdi/çıktı token toplamları
- gerçek plan fiyatınızla karşılaştırmalı **aylık projeksiyon** (örn. *"≈ $8.268/ay — Max 20× planınızın ~41 katı"*)
- interaktif 30 günlük maliyet trend grafiği — herhangi bir günün üzerine gelince tarih, tahmini maliyet ve token
- **model bazında turn turn** fiyatlama, LiteLLM oran tablosundan (ccusage ile aynı kanonik kaynak) — 24s disk cache + gömülü offline fallback ile canlı çekilir; Anthropic'in prompt-cache ve >200K uzun-bağlam kuralları gözetilir
- her şey açıkça **tahmin** olarak etiketli — abonelik planları token başına faturalandırılmaz. Canlı oran çekimini atlamak için `CONTEXTBAR_PRICING_OFFLINE=1`.

### Masaüstü ve Bildirim Merkezi widget'ı

ContextBar üç boyutta native bir WidgetKit eklentisiyle gelir:
`systemSmall`, `systemMedium`, `systemLarge`. Widget aynı `context.json`'u
menubar ile paylaşılan App Group container'ı
(`DQJT5BCZCM.com.htahaozlu.contextbar`) üzerinden okur; aktif agent,
proje, model, context %, 5h/7d limitleri ve agent başına dökümünü ekstra
bir daemon olmadan gösterir.

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar widget önizleme" width="100%">
</p>

Eklemek için:

1. ContextBar 0.3.12+ sürümünü kurun ve bir kez başlatın. macOS extension'ı
   indeksleyecek (`pluginkit -m -v -i com.htahaozlu.contextbar.widget`
   listede çıkmalı).
2. Bildirim Merkezi'ni açın (saati tıklayın) → **Widget'ları Düzenle**,
   veya masaüstüne sağ tıklayın → **Widget'ları Düzenle**.
3. **ContextBar** araması yapın, küçük/orta/büyük varyantı istediğiniz
   yere bırakın.

Widget extension sandboxlu ve App Group entitlement'ı ile imzalı. macOS 14+
(macOS 26 Tahoe dahil) `chronod` sandboxsuz widget extension'larını sessizce
reddediyordu (`Ignoring restricted or unknown extension`). Host menubar
uygulaması her refresh'te `~/.context-bar/context.json`'u App Group container'a
mirror'lar; sandbox içindeki widget bunu okur.

### Bugünün HUD'unu paylaş

Popover footer'da **Paylaş** butonu (`square.and.arrow.up`) mevcut HUD'u
PNG kartı olarak render eder: aktif agent, model, context %, 5h/7d
kullanım ve tespit edilen diğer araçlar. Varsayılan olarak proje isimleri
maskelenir, böylece repo adlarınız sızmaz. PNG geçici bir yola yazılır ve
Preview / kaydetme diyaloğuyla açılır; ekran görüntüsü alıp kırpmadan
Slack, X veya durum güncellemelerine drop edebilirsiniz.

<p align="center">
  <img src="docs/images/context-bar-screenshot-full.png" alt="ContextBar paylaşım kartı önizleme" width="100%">
</p>

UI olmadan headless render (otomasyon için):

```bash
CONTEXTBAR_SHARE_RENDER_PATH=/tmp/hud.png \
CONTEXTBAR_SHARE_MASK=1 \
/Applications/ContextBar.app/Contents/MacOS/context-bar
```

Gerçek proje isimlerinin kartta kalması için `CONTEXTBAR_SHARE_MASK=0`.

Menubar simgesi taşma nedeniyle gizlenirse (Bartender, Hidden Bar veya
kalabalık menubar), uygulamayı Finder / Spotlight'tan tekrar açtığınızda
doğrudan Ayarlar penceresi açılır; tercihlere erişim hep kalır.

Masaüstü arayüzü yerel AppKit'tir (NSPopover + NSVisualEffectView, sürekli
köşe eğrileri, SF Symbol toolbar). `detail.html`, ana deneyim değil, bir
export artifact'idir.

## Kullanım

### Mevcut depoyu yenile

```bash
context-bar hud
```

### HUD yazdırmadan artifact üret

```bash
context-bar snapshot
```

### Depo bağlamını taze tut

```bash
context-bar watch 30 .
```

### Global HUD üret

```bash
context-bar global
context-bar watch-global 30
```

Global HUD `~/.context-bar/hud.md` konumuna yazılır.

## Terminal CLI

**Terminal CLI**, macOS uygulamasını çalıştıran aynı saf-Rust maliyet motoru üzerine kuruludur (uygulama premium amiral gemisi olmaya devam ediyor). macOS, Linux ve Windows (arm64 + x64) üzerinde çalışır, `python3` gerektirmez, SSH üzerinde çalışır ve `npx context-bar`, `cargo install context-bar` veya önceden derlenmiş bir ikiliyle kurulur. Rapor fiilleri Claude Code ve Codex kullanımı için ccusage tarzı tablolar üretir:

### Fiiller

- `daily` — gün başına kullanım + maliyet tablosu (Claude + Codex); bir "All" satırı, ajan başına alt satırlar ve bir Total satırıyla gruplanır
- `weekly` — ISO-hafta başına tablo
- `monthly` — ay başına tablo
- `session` — son oturumlar tablosu
- `blocks` — ajan başına aktif 5sa blok: limitin %'si, yakım hızı ($/sa · tok/dk), öngörülen toplam, sıfırlanma geri sayımı, limite tahmini süre
- `context-bar live` — aynı 5sa blok yakım metrikleri, otomatik yenilenen bir terminal panosu olarak (`ratatui`): ajan başına renk-katmanlı bir gösterge, `--interval` saniyede bir yenilenir; çıkmak için `q`, hemen yenilemek için `r`. SSH üzerinden ve Linux/Windows'ta çalışır.

### Rapor bayrakları

- `--instances` — günlük tabloyu proje bazında böler (gün × proje)
- `--breakdown`, `-b` — ayrıca model bazında bir kırılım tablosu basar
- `--agent <claude|codex|all>` — tek bir ajanla sınırlar (varsayılan all)
- `--since <YYYYMMDD>` / `--until <YYYYMMDD>` — dahil edici tarih filtresi
- `--json` — raporu JSON olarak verir (boru hattı / jq için)
- `--offline` — canlı fiyat çekimini atlar (önbellekli/gömülü oranlar)
- `--lang <en|tr>` — arayüz dilini zorlar (varsayılan: locale; tablolar + başlıklar tamamen iki dilli EN/TR)
- `--no-color` — ANSI rengini devre dışı bırakır (boru hattına yönlendirildiğinde veya `NO_COLOR` ayarlıyken otomatik kapanır)

### Değişmeyen motor fiilleri

`hud`, `snapshot`, `global`, `claude-statusline`, `watch`, `watch-global`, `--version`.

### Sütunlar

ccusage günlük tablosuyla eşleşir: Tarih · Ajan · Modeller · Girdi · Çıktı · Önbellek Oluşturma · Önbellek Okuma · Toplam · Maliyet (USD). "Toplam", ccusage'ın Total Tokens değeridir = girdi + çıktı + önbellek oluşturma + önbellek okuma. Maliyetler, ölçümlü API'nin ne ücretlendireceğine dair **tahminlerdir** — fatura değil (abonelik kullanıcıları token başına faturalandırılmaz).

### Çalışma zamanı notu

Motor saf Rust'tur (`python3` gerektirmez); npm, cargo, önceden derlenmiş ikili dosyalar ve `npx` ile macOS / Linux / Windows üzerinde çalışır.

### Örnek

Coding Agent Usage Report — Daily

```
| Tarih      | Ajan       | Modeller          | Girdi   | Çıktı     | Önbellek Oluşturma | Önbellek Okuma | Toplam        | Maliyet (USD) |
| 2026-05-29 | All        | opus-4-8, gpt-5.5 | 937,053 | 5,372,832 | 17,259,276         | 997,890,608    | 1,021,459,769 | $746.00       |
|            |   - Claude | opus-4-8          | 652,442 | 5,336,901 | 17,259,276         | 995,772,208    | 1,019,020,827 | $742.44       |
|            |   - Codex  | gpt-5.5           | 284,611 | 35,931    | 0                  | 2,118,400      | 2,438,942     | $3.56         |
| Total      |            |                   | ...     | ...       | ...                | ...            | ...           | $1,682.65     |
```

(Gerçek terminalde bunlar comfy-table aracılığıyla Unicode kutu-çizim tablolarıdır.)

## Artifact düzeni

Her yenileme aşağıdaki dosyaları atomik olarak yazar:

- `.context-bar/state.json`
- `.context-bar/brief-now.md`
- `.context-bar/brief-session.md`
- `.context-bar/brief-week.md`
- `.context-bar/AGENT.md`
- `.context-bar/hud.md`
- `CLAUDE.md`

Atomik yazım sayesinde ajanlar yenileme sırasında yarı yazılmış durumu görmez.

## Veri kaynakları

ContextBar şu kaynakları birleştirir:

- Git branch, son commit'ler ve worktree durumu
- depo `mtime` verilerinden çıkarılan dosya etkinliği
- `~/.context-bar/claude-statusline.json` altındaki isteğe bağlı Claude Code statusline snapshot'ı
- `~/.claude/projects/**/*.jsonl` içinden Claude Code kullanım verisi
- `~/.codex/sessions/**/*.jsonl` içinden Codex CLI kullanım verisi

Temel depo özetleri için harici servis gerekmez. Kullanım toplama, yerel transcript verilerine ve isteğe bağlı Claude Code statusline verisine dayanır; saf Rust bir çapraz platform motorla ayrıştırılır (`python3` gerekmez).

### Claude Code parity

Claude context yüzdesi için en iyi kaynak, Claude Code'un native statusline payload'ıdır. ContextBar bunu yerelde saklayabilir:

```json
{
  "statusLine": {
    "type": "command",
    "command": "context-bar claude-statusline"
  }
}
```

Bu komut `~/.context-bar/claude-statusline.json` dosyasını yazar ve ContextBar bu dosyayı Claude context için birincil kaynak olarak okur. Snapshot eksikse veya bayatsa transcript tabanlı tahmine geri düşer.

## Paketleme

Depoda macOS yardımcı uygulaması derlemesi için scriptler bulunur:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

Doğrudan app build'inde WidgetKit extension'ı app bundle'a dahil etmek için:

```bash
WIDGET_BUILD=1 scripts/build-menubar-app.sh
```

`scripts/create-macos-dmg.sh` widget build'ini varsayılan olarak açar.

Artifact'ler:

- `dist/ContextBar.app`
- `dist/ContextBar.dmg`

## Depo düzeni

- `src/` çekirdek motor, artifact render etme ve kullanım toplama
- `src/bin/context-bar.rs` bağımsız CLI giriş noktası
- `menubar/context-bar.swift` macOS yardımcı uygulaması
- `examples/snapshot.rs` yerel geliştirme harness'i

## Geliştirme

```bash
cargo check
cargo run --example snapshot
```

## Topluluk

- Sorular ve kullanım yardımı: GitHub Discussions
- Hatalar ve özellik istekleri: GitHub Issues
- Katkı rehberi: `CONTRIBUTING.md`
- Güvenlik bildirimi: `SECURITY.md`

## Lisans

Apache-2.0
