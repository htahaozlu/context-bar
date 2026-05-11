# Zed Context Pilot: Architecture v0

Tarih: 2026-05-11

## Hedef

Aktif Zed worktree'si için yüksek sinyalli bir proje özeti üretmek ve bunu Assistant paneline tek komutla sokmak.

İlk hedef komut:

- `/hello`

İkinci hedef komut:

- `/brief`

## Fazlara bölünmüş yaklaşım

### Faz 0: API doğrulama

Amaç:

- slash command yüzeyini çalıştırmak
- worktree bilgisini Assistant içine akıtmak

Çıktı:

- `/hello` komutu

Beklenen davranış:

- aktif worktree yolunu okur
- Assistant içine kısa bir metin enjekte eder

### Faz 1: Git tabanlı briefing

Amaç:

- en güvenilir ve düşük maliyetli sinyalleri toplamak

Planlanan briefing alanları:

1. aktif worktree yolu
2. aktif branch
3. son 3 commit özeti
4. çalışma ağacında değişen dosyalar
5. son N dakikada dokunulan dosyalar

Teknik yöntem:

- `Worktree::root_path()`
- `process:exec` ile `git`
- gerekiyorsa dosya mtime taraması

Not:

Burada "The Sentinel" için sürekli çalışan arka plan worker yerine önce "on-demand snapshot" almak daha doğru. Zed extension Wasm yüzeyinde ilk sürüm için bu daha basit ve daha savunulabilir.

### Faz 2: Diagnostics entegrasyonu

Amaç:

- briefing içine derleyici/LSP hata bilgisini eklemek

Risk:

- extension API üzerinden diagnostics erişimi araştırma aşamasında doğrulanmadı

Seçenekler:

1. extension API'de varsa doğrudan çekmek
2. yoksa bunu kapsam dışı bırakmak
3. alternatif olarak proje komutlarından türetilmiş hata özeti üretmek

Bu faz için önce Zed kaynak kodunda ya da güncel API belgelerinde net erişim noktası bulunmalı.

### Faz 3: Prompt ergonomisi

Amaç:

- `/brief` çıktısını sadece ham metin değil, iyi biçimlenmiş bir briefing haline getirmek

Örnek çıktı şablonu:

```md
## Project Brief

- Worktree: /Users/ozlu/projeler/hususi/backend/zed-context
- Branch: main

### Recent Commits
- abc123 Fix slash command registration
- def456 Add worktree summary
- ghi789 Write architecture notes

### Local Changes
- modified: src/lib.rs
- added: docs/02-architecture.md
```

## Kararlar

### Neden önce slash command?

- kullanıcı deneyimi hedefi doğrudan burada
- resmi örnek mevcut
- düşük entegrasyon riski

### Neden önce `git` tabanlı sinyal?

- güvenilir
- deterministik
- extension API ile uyumlu görünmesi daha olası

### Neden sürekli watcher ile başlamıyoruz?

- ilk sürüm için gereksiz karmaşıklık
- Wasm ve capability sınırları erken aşamada tasarımı zorlar
- kullanıcı değeri önce tek komutla da üretilebilir

## Minimal dosya yapısı

```text
zed-context/
  extension.toml
  Cargo.toml
  src/
    lib.rs
  docs/
    01-research.md
    02-architecture.md
```

## Sonraki teknik adımlar

1. `/hello` komutunu ayağa kaldır
2. Zed içinde dev extension olarak yükle
3. `/brief` için `git` snapshot helper'ını ekle
4. `process:exec` capability gereksinimini manifest ve kullanıcı dokümantasyonuna yaz
5. diagnostics erişimini ayrı bir araştırma başlığı olarak çöz
