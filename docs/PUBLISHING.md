# Publishing — crates.io + npm

Publishing is **irreversible** (crates.io names can't be deleted, npm names are hard to
reclaim) and needs **your own** credentials, so it's gated on two GitHub secrets you set
once. After that it's fully automated on every `v*` tag.

## ✅ Automated (recommended): set two secrets, then tag

`.github/workflows/release.yml` already has `publish-crates` + `publish-npm` jobs. They
**no-op until the matching secret exists**, so nothing publishes by accident. To enable:

1. **crates.io** — create a token at <https://crates.io/settings/tokens> (scope: publish-new
   + publish-update). Add repo secret **`CARGO_REGISTRY_TOKEN`**.
2. **npm** — create an automation token at <https://www.npmjs.com/settings/~/tokens> (type:
   *Automation*, so 2FA doesn't block CI). Add repo secret **`NPM_TOKEN`**. The `@context-bar`
   scope is created automatically on first publish (`--access public`).
   - `gh secret set CARGO_REGISTRY_TOKEN` / `gh secret set NPM_TOKEN` from the CLI, or the repo
     Settings → Secrets → Actions UI.

Then cut a release (bump `Cargo.toml` + `CHANGELOG.md` + `docs/releases/v<ver>.md`, push
`main`, `git tag vX.Y.Z`, push the tag). The tagged run will: build the DMG + 6
cross-platform binaries, `cargo publish` core then bin (enables `cargo install context-bar`),
and assemble + `npm publish` the meta `context-bar` package + the six
`@context-bar/context-bar-<os>-<cpu>` platform packages (enables `npx context-bar`).
Watch the first run — npm packaging is intricate; `publish-npm` is isolated (`fail-fast`
off, the DMG job is independent), so a hiccup never blocks the macOS release.

---

## Manual fallback / first-time reservation

If you'd rather run it by hand (or reserve the names before a release), the steps below do
the same thing. Read each fully before pasting.

## crates.io (A2/A4)

The workspace is split into two crates:

- `context-bar-core` — the engine **library**
- `context-bar` — the **binary**, which depends on core via a path dep that *also*
  carries a version (`context-bar-core = { path = "...", version = "0.4.0" }`)

Because the bin depends on a published `context-bar-core`, you **must publish core
first**. Both crates already carry `description` / `keywords` / `categories` /
`repository`, so no metadata work is needed.

```bash
# 1. Authenticate (one-time; token from https://crates.io/me).
cargo login

# 2. Validate each crate without uploading.
cargo publish -p context-bar-core --dry-run
cargo publish -p context-bar      --dry-run

# 3. Publish CORE FIRST, then the bin.
cargo publish -p context-bar-core
cargo publish -p context-bar
```

After the bin lands, this works for anyone:

```bash
cargo install context-bar
```

## npm name reservation (A0)

Goal for 0.4.0: **reserve** the bare name `context-bar` and the `@context-bar` scope so
nobody squats them. This is reservation only — no real distribution yet (see the note
below).

```bash
# 1. Authenticate (one-time).
npm login

# 2. Reserve the bare name with a placeholder publish.
#    (minimal package.json with name "context-bar" + a version, e.g. 0.0.0)
npm publish

# 3. Reserve the @context-bar scope by publishing one scoped placeholder.
#    (package.json name "@context-bar/placeholder"; scoped packages are private
#     by default, so --access public is required.)
npm publish --access public
```

The **full** npm distribution — `optionalDependencies` fan-out, per-platform prebuilt
binaries via `cargo-npm`, and the `taiki-e` cross-compile release matrix — is documented
in the next section. **0.4.0 only RESERVES the names**; real `npx context-bar`
distribution lands once you run the flow below.

## npm distribution — npx context-bar (A2)

Now that the engine is **pure-Rust + a self-contained cross-platform binary** (no
`python3` runtime), `npx context-bar` can ship cleanly on all three OSes. This section is
the runbook for the full distribution.

### What the release produces

Each GitHub release (cut on a `v*` tag) runs the `upload-binaries` job in `release.yml`,
which uses **`taiki-e/upload-rust-binary-action`** to cross-compile and attach **6
prebuilt binaries** as release archives:

| OS | arch | target triple |
| --- | --- | --- |
| macOS | arm64 | `aarch64-apple-darwin` |
| macOS | x64 | `x86_64-apple-darwin` |
| Linux | arm64 | `aarch64-unknown-linux-musl` |
| Linux | x64 | `x86_64-unknown-linux-musl` |
| Windows | arm64 | `aarch64-pc-windows-msvc` |
| Windows | x64 | `x86_64-pc-windows-msvc` |

(Linux uses **musl** for a fully static binary that runs on any distro.)

### Packaging with cargo-npm

Use **`abemedia/cargo-npm`** to generate and publish the meta package `context-bar`
plus a per-platform `@context-bar/context-bar-<os>-<arch>` subpackage for each triple.
The layout is **no postinstall** — the meta package lists the subpackages as
`optionalDependencies`, each subpackage gates itself with `os` / `cpu` fields so npm only
installs the one matching the host, and a tiny JS launcher in the meta package execs the
resolved native binary.

```bash
# 0. One-time: install the cargo subcommand.
cargo install cargo-npm

# 1. Download the 6 release archives from the v* GitHub release and unpack each
#    binary into target/<triple>/release/ (the path cargo-npm reads from).
#    e.g. target/aarch64-apple-darwin/release/context-bar
#         target/x86_64-apple-darwin/release/context-bar
#         target/aarch64-unknown-linux-musl/release/context-bar
#         target/x86_64-unknown-linux-musl/release/context-bar
#         target/aarch64-pc-windows-msvc/release/context-bar.exe
#         target/x86_64-pc-windows-msvc/release/context-bar.exe

# 2. Generate the meta package + per-platform subpackages.
#    Pin each optionalDependency to the EXACT version (no ^/~ ranges) so a
#    meta install can only resolve its matching prebuilt subpackage.
cargo npm generate

# 3. Publish. cargo-npm publishes the platform packages FIRST, then the meta
#    package last (so the meta's optionalDependencies already exist on the
#    registry). Scoped packages need --access public.
NODE_AUTH_TOKEN=<your-npm-token> cargo npm publish -- --access public
```

After this lands, anyone can run:

```bash
npx context-bar
```

### Platform notes

- This needs **the maintainer's own npm credentials** (`NODE_AUTH_TOKEN`), the same
  account that holds the reserved `context-bar` name and `@context-bar` scope.
- macOS-only features **degrade gracefully** on Linux/Windows: keychain account
  detection is macOS-specific, so on other platforms the binary reads
  `~/.claude/.credentials.json` directly instead.

## Security

Never commit `AuthKey_*.p8` or any crates.io / npm token to the repo. These are already
covered by `.gitignore`.
