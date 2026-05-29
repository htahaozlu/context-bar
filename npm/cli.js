#!/usr/bin/env node
// Launcher for the `context-bar` npm package. The real binary ships in a
// per-platform optional dependency (@context-bar/context-bar-<os>-<cpu>);
// npm/pnpm/bun install only the one matching this host's os/cpu. We resolve it
// and exec it. No postinstall — works under `npm ci --ignore-scripts`.
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import { chmodSync, statSync } from 'node:fs'
import process from 'node:process'

const require = createRequire(import.meta.url)

function platformPackage(p = process.platform, a = process.arch) {
  if (p === 'darwin') {
    if (a === 'arm64') return 'context-bar-darwin-arm64'
    if (a === 'x64') return 'context-bar-darwin-x64'
  } else if (p === 'linux') {
    if (a === 'arm64') return 'context-bar-linux-arm64'
    if (a === 'x64') return 'context-bar-linux-x64'
  } else if (p === 'win32') {
    if (a === 'arm64') return 'context-bar-win32-arm64'
    if (a === 'x64') return 'context-bar-win32-x64'
  }
  return undefined
}

function binRelativePath() {
  return process.platform === 'win32' ? 'bin/context-bar.exe' : 'bin/context-bar'
}

function resolveBinary() {
  const pkg = platformPackage()
  if (!pkg) return undefined
  try {
    return require.resolve(`${pkg}/${binRelativePath()}`)
  } catch {
    return undefined
  }
}

const binary = resolveBinary()
if (!binary) {
  process.stderr.write(
    `context-bar: no prebuilt binary for ${process.platform}-${process.arch}. ` +
      `Reinstall so the optional platform package downloads, or use \`cargo install context-bar\`.\n`,
  )
  process.exit(1)
}

// Some registries/tar pipelines drop the +x bit; restore it.
if (process.platform !== 'win32') {
  try {
    if (!(statSync(binary).mode & 0o111)) chmodSync(binary, 0o755)
  } catch {}
}

const child = spawn(binary, process.argv.slice(2), { stdio: 'inherit' })
child.on('error', (err) => {
  process.stderr.write(`${err.message}\n`)
  process.exit(1)
})
child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal)
  else process.exit(code ?? 1)
})
