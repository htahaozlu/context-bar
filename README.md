# Zed Context Pilot

`Zed Context Pilot`, Claude HUD benzeri "terminalde farkindalik" hissini Zed'in icine tasimayi hedefleyen bir extension prototipidir.

Ana urun hedefi:

- always-on context HUD
- otomatik assistant context
- zaman pencereli ozetler:
  - `now`: son 15 dakika
  - `session`: son 5 saat
  - `week`: son 7 gun

## Kullanici akisi

1. Extension'i Zed'e yukle (asagidaki "Yukleme" bolumune bak).
2. Zed'i bir repo uzerinde ac.
3. Worktree extension'a ilk kez gorundugu anda `.zed-context/` artefaktlari otomatik uretilir:
   - `.zed-context/state.json` — makine okunabilir snapshot
   - `.zed-context/brief-now.md`
   - `.zed-context/brief-session.md`
   - `.zed-context/brief-week.md`
   - `.zed-context/AGENT.md` — agent okunabilir tek dosya briefing
   - `CLAUDE.md` — Claude Code icin ayni briefing
4. Sonraki etkilesimlerde refresh idempotent ve ucuzdur; degisim olmadiginda dosyalar churn yapmaz.

Kullanicinin ilk surum icin **manuel komut calistirmasi gerekmez**. Coding agent (Codex ACP, Claude Code vb.) `.zed-context/AGENT.md` veya `CLAUDE.md` dosyasini filesystem uzerinden okur.

## Dogrulanmis sinir

`zed_extension_api` 0.7 surumunde "extension yuklendi" veya "worktree acildi" icin worktree handle'i veren resmi bir hook yok. Worktree alabilen tek dogrulanmis giris noktasi slash command callback'leridir.

Bu yuzden ilk otomatik refresh, extension'a Zed icinden ilk ulasan worktree-tasimali cagriya bagli olarak tetiklenir. Pratikte coding agent'lar acilis ardindan extension yuzeyiyle etkilestiginde context dosyalari yerine oturur. Daha guclu bir load-hook ortaya cikinca `auto_refresh::refresh` cagri yeri degistirilir; fonksiyonun kendisi degismez.

Slash command'ler (`/brief`, `/doctor`, `/hello`) sadece **fallback ve debug** yuzeyidir; urun yuzeyi degildir.

## Yukleme

Zed icinde dev extension olarak yuklemek icin:

1. `cmd-shift-x`
2. `Install Dev Extension`
3. Bu dizini sec
4. Gerekirse settings icinde `granted_extension_capabilities` altina `process:exec` izni ekle

Debug icin:

- `zed: open log`
- Terminalden `zed --foreground`

## Lisans ve Destek

Bu repo `Apache-2.0` lisansi ile yayinlanir. GitHub Sponsors yuzeyi `.github/FUNDING.yml` ile tanimlanir; public yayina hazirlanirken buraya ek sponsor baglantilari konabilir.

## Mevcut prototip

Context engine modulleri:

- `src/context_engine.rs` — `assemble(...)` non-Zed entegrasyon seam'i
- `src/git_signal.rs`
- `src/time_windows.rs`
- `src/state_writer.rs` — atomic write
- `src/agent_context.rs` — `AGENT.md` ve `CLAUDE.md` render
- `src/auto_refresh.rs` — idempotent otomatik refresh
- `src/slash_commands.rs` — fallback/debug

Toplanan sinyaller:

- aktif branch
- son 7 gundeki commit ozetleri
- staged / unstaged degisiklik ozetleri
- dosya `mtime` bilgisinden `now/session/week` gorunumu

## Gelistirici arac

`examples/snapshot.rs` Zed'i ayaga kaldirmadan engine'i native target'te dogrulamak icindir. Sadece gelistirici amaclidir, urun akisinin parcasi degildir:

```
cargo run --example snapshot
```

## Sinirlar

1. Kalici HUD/panel API'si yok — `state.json` ileride bir HUD primitifi consume etsin diye stable tutuluyor.
2. Assistant'a otomatik prompt-injection hook'u yok — agent `AGENT.md` dosyasini filesystem'den okur.
3. `process:exec` izni kullanici tarafinda verilir.
4. Load-time worktree hook'u yok — yukaridaki "Dogrulanmis sinir" bolumune bak.
