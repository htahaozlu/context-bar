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
binaries via `cargo-npm`, and the `taiki-e` cross-compile release matrix — is **deferred
to 0.5.0**. The engine needs `python3` at runtime, which is broken on stock Windows, so a
real `npx context-bar` install can't ship cleanly yet. **0.4.0 only RESERVES the names.**

## Security

Never commit `AuthKey_*.p8` or any crates.io / npm token to the repo. These are already
covered by `.gitignore`.
