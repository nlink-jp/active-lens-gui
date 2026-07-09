# CLAUDE.md — ActiveLens (GUI)

Organization rules: https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md
Workspace rules also apply (see the parent `nlink-jp/CLAUDE.md`).

## What this is

macOS menu-bar SwiftUI app that visualizes Mac operating time. Thin front-end
over the bundled [`active-lens`](../active-lens) Go CLI (the engine). Sibling of
`claude-usage-lens-gui`. macOS 14+, Apple Silicon.

## Build & test

- **`make build-app`** → signed `dist/ActiveLens.app` (bundles the CLI). Never
  ship an unsigned bundle.
- `make test` / `swift test` — must pass before committing.
- Build the CLI first (`make build` in `../active-lens`) so `build-app` can embed
  a fresh signed binary.

## Rules of thumb

- The CLI owns sampling/storage/aggregation. This app only calls `--json`,
  decodes, formats, and charts. Don't duplicate engine logic.
- Keep the **bundled** signed CLI as the trust anchor in `CLIRunner.resolveBinary`
  (env override is DEBUG-only).
- `Format.duration` must stay in lockstep with the CLI's `formatSeconds` (a test
  enforces it).
- Docs: README.md + README.ja.md kept in sync; `docs/{en,ja}` mirror.
