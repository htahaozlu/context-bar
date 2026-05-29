# Publishing names — crates.io + npm

This is a **maintainer checklist** for reserving and publishing the project's names on
crates.io and npm (EPIC A0/A2/A4). Every step here needs **your own** crates.io/npm
credentials and most are **irreversible** — crates.io names can never be deleted (only
*yanked*), and npm names, once taken, are hard to reclaim. So this is a runbook for a
human to run by hand, not automation. Read each section fully before you paste anything.

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
