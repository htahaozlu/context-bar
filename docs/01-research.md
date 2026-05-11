# Zed Context Pilot: Verified Research Notes

Tarih: 2026-05-11

Bu not, ilk ürün fikrini Zed'in Mayıs 2026 itibarıyla doğrulanmış extension yüzeyiyle hizalamak için hazırlandı.

## Doğrulanan gerçekler

1. Zed extension manifest dosyası `extension.json` değil, `extension.toml`.
2. Zed extension'ları Rust ile yazılıyor ve Wasm olarak çalışıyor.
3. Slash command tanımlamak doğrudan destekleniyor.
4. Extension tarafında süreç çalıştırma için capability tabanlı bir `process:exec` modeli var.
5. Resmi örnekler arasında doğrudan slash command extension'ı (`perplexity`) ve context server extension'ı (`postgres-context-server`) bulunuyor.

## Tasarım notundaki düzeltmeler

### 1. Manifest ve temel iskelet

İlk nottaki `extension.json` varsayımı güncel değil. Doğru dosya:

- `extension.toml`

Temel alanlar:

- `id`
- `name`
- `version`
- `schema_version`
- `authors`
- `description`
- `repository`

## Slash command yüzeyi

Resmi örnek `perplexity` extension'ı şu iki noktayı doğruluyor:

1. `extension.toml` içinde `[slash_commands.<name>]` bloğu tanımlanıyor.
2. Rust tarafında `run_slash_command(...) -> Result<SlashCommandOutput, String>` implement ediliyor.

Örnek manifest biçimi:

```toml
[slash_commands.perplexity]
description = "Ask a question to Perplexity AI"
requires_argument = true
tooltip_text = "Ask Perplexity"
```

## Extension API yüzeyi

`docs.rs` üzerindeki güncel crate sürümü araştırma sırasında `zed_extension_api 0.7.0` olarak görünüyor.

Bizim ilk prototip için kritik parçalar:

- `Extension` trait
- `SlashCommand`
- `SlashCommandOutput`
- `Worktree`
- `process::Command`

`Worktree` üzerinde doğrulanmış erişimler:

- `root_path()`
- `read_text_file(...)`
- `shell_env()`
- `which(...)`

Bu, `/hello` ve ileride git tabanlı briefing için yeterli bir başlangıç.

## Diagnostics / LSP erişimi

Burada önemli bir belirsizlik var:

- Zed'in kendi AI agent araçlarında diagnostics erişimi var.
- Ancak extension API dokümanlarında diagnostics veya LSP hata listesine doğrudan erişen açık bir yöntem araştırma sırasında görünmedi.

Bu yüzden "LSP'den son hata çekme" fikri şu an için doğrulanmış bir extension capability değil. Bunu faz 2 riski olarak ele almak gerekiyor.

## Context server ile slash command aynı şey değil

`postgres-context-server` örneği context server uzantısıdır. Bu yapı Assistant/Agent tarafına araç sağlayabilir, ama doğrudan "özel briefing slash command" gereksinimi için ilk ve en kısa yol bu değil.

İlk milestone için doğru seçim:

- doğrudan slash command extension

Sonraki aşamada değerlendirilecek alternatif:

- slash command + MCP/context server hibrit yapı

## Bu proje için çıkarım

En düşük riskli başlangıç mimarisi:

1. Zed dev extension
2. özel slash command (`/hello`, sonra `/brief`)
3. briefing üretimini önce `git` ve çalışma alanı verisiyle sınırlamak
4. diagnostics entegrasyonunu doğrulanana kadar opsiyonel tutmak

## İncelenen kaynaklar

- Zed Developing Extensions: https://zed.dev/docs/extensions/developing-extensions
- Zed Extension Capabilities: https://zed.dev/docs/extensions/capabilities
- Zed MCP Server Extensions: https://zed.dev/docs/extensions/mcp-extensions
- Zed Text Threads: https://zed.dev/docs/ai/text-threads
- docs.rs `zed_extension_api`: https://docs.rs/zed_extension_api/latest/zed_extension_api/
- Örnek extension: https://github.com/zed-extensions/perplexity
- Örnek context server: https://github.com/zed-extensions/postgres-context-server
