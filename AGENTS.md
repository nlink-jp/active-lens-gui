# AGENTS.md — ActiveLens (GUI)

## What it is

macOS menu-bar app (SwiftUI) that shows your Mac work log — when you started,
took breaks, and finished. Thin front-end over the bundled
[`active-lens`](../active-lens) CLI, which does the sampling/storage/aggregation.
**macOS 14+, Apple Silicon.** Sibling of `claude-usage-lens-gui` (same
architecture).

## Build / test / run

```sh
make build      # swift build -c release
make build-app  # assemble + Developer-ID sign dist/ActiveLens.app (bundles the CLI)
make package    # notarize + staple + zip the release asset
make test       # swift test
make run        # swift run (debug)
```

`build-app` embeds `CLI_BIN` (default `../active-lens/dist/active-lens`) into
`Contents/Resources/active-lens`; build the CLI first (`make build` in that repo).
App is `LSUIElement` (menu bar, no Dock icon). Version comes from `git describe`
via the Makefile → Info.plist.

## Layout

```
Sources/ActiveLens/
  App.swift            MenuBarExtra (state icon + the now-session's active time) + Analysis Window
  PopoverView.swift    the now-session (open/paused) + Today total + Record-in-background toggle
  AnalysisView.swift   Swift Charts: calendar work-timeline (day columns) + block hover + work-log list
  ActivityModel.swift  ObservableObject; 60s refresh; App Nap opt-out; CLI calls off-main
  CLIRunner.swift      locate + run the CLI, decode --json (PURE resolveBinary)
  Models.swift         Codable mirrors of the CLI JSON (Timeline/Now/DaemonStatus/…)
  Formatting.swift     PURE duration/axis formatting + the state color palette
Tests/ActiveLensTests/ Format, binary resolution, decode, status/recording
Info.plist  Makefile  scripts/{codesign,notarize}-darwin-app.sh, make-icns.sh
```

## Design invariants / gotchas

- **The CLI is the single source of truth.** This app only formats and charts
  `--json`. Don't reimplement sampling/aggregation here.
- **Bundled CLI is the trust anchor.** `resolveBinary` puts the bundle's signed
  copy ahead of everything; `$ACTIVE_LENS_BIN` works only in DEBUG. Keep it that
  way so a release build can't be redirected to an unsigned binary.
- **Enabling recording registers the bundled binary** as the LaunchAgent, so the
  daemon path lives inside the .app — moving/deleting the app breaks recording.
- **All CLI work is off the main thread**; @Published mutations hop to main.
  App Nap is opted out (menu-bar app) so the 60s timer keeps firing.
- **Format.duration mirrors the CLI's formatSeconds** (a test pins this) so the
  GUI and `active-lens report` never disagree.
- **The menu bar's unit is a session, not a day.** Read `now --json`; never
  reconstruct "today" by looking a date up in the timeline. Do not compute date
  ranges either — `timeline --days N` resolves them against the CLI's logical day
  boundary. Both were removed for reimplementing engine arithmetic.
- **Chart offsets are hours from `day_start_unix`, not midnight**, and the y axis
  is deliberately not clamped to 24: a session filed under the day it began may
  run past that day's own 24 hours. Axis labels map offsets back to wall clock via
  `Format.clockLabel`.
- **Hover hit-tests `blocks`, never `segments`.** At 260pt over ~13 hours one
  minute is ~0.33pt, so raw segments are sub-pixel and the one under the cursor is
  effectively random. `TimelineDay.block(atHours:)` is pure and tested.
- Chart colors: operating=green, present=blue, away=gray — one palette
  (`ActivityPalette`) shared by popover dots and chart scales.

## Status

Phase 2 complete: `swift build` / `swift test` (25 tests) green; `.app` builds,
Developer-ID signs, spctl-accepts, and was launch-verified end-to-end (the signed
app invoked the bundled CLI and created the data store under Hardened Runtime).
No app icon yet (`assets/AppIcon-1024.png` absent — builds without one).
