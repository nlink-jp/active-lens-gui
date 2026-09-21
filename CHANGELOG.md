# Changelog

All notable changes to ActiveLens (GUI) are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- **Bundled CLI updated to active-lens v0.3.1**, which fixes sessions being
  reported a whole day late on a Mac kept awake for more than two days. The
  read that derives sessions started a fixed 48 hours before the window, which
  cuts a chain of day-boundary sessions in the wrong place; it now widens until
  it reaches a real break. The app shows what the bundled CLI derives, and a
  release build resolves its bundled copy first, so this build is the only way
  the fix reaches the app.

### Fixed

- **`make verify-release` now checks which CLI is inside the bundle.** It
  verified the notarization marker, the stapled ticket, the release zip and the
  linked SDK, but not the one thing that decides what the app shows: nothing
  compared `Contents/Resources/active-lens --version` against the CLI version
  the release claims to ship, so a bundle built against a stale binary passed
  every gate. `CLI_VERSION` in the Makefile now states it and the gate enforces
  it.

## [0.3.1] - 2026-09-17

### Fixed

- **The app rendered with the previous generation of window chrome** (square
  corners). macOS reads the SDK an app was linked against from
  `LC_BUILD_VERSION` to decide which design to draw, and since the Xcode 27 /
  Swift 6.4 toolchain `swift build` stamps that field with the deployment target
  instead of the SDK actually used — v0.3.0 shipped recording `sdk 14.0` where
  v0.2.2 records `sdk 26.5`. The release build now passes `-platform_version`
  explicitly, taking the deployment target from `Package.swift` so there is only
  one of it, and `make verify-release` refuses to release a bundle whose linked
  SDK is not the current one. Nothing else changed: same sources as v0.3.0.

## [0.3.0] - 2026-09-17

### Added

- **Shows a day-boundary cut.** With the CLI's `work.day_boundary = "strict"`
  (active-lens 0.3.0), a session running through the logical day boundary is cut
  there. The work log now marks a day whose work carried in or out, with a
  tooltip explaining it, and states the rule in its header; the popover explains
  a session that began at the boundary rather than when you sat down — which is
  why the menu-bar heading can restart mid-work. See
  [ADR 0002](docs/en/adr/0002-day-boundary-marks.md).
- Decodes `carried_in` / `carried_out` (day, timeline session; `carried_in` only
  on the now-session, which the boundary never cuts),
  `day_boundary` (timeline), and `day_start_hour` / `day_boundary` (status). All
  optional: with an older bundled CLI the app reads the absence as the previous
  behaviour and runs unchanged.

### Changed

- The bundled `active-lens` CLI is 0.3.0. Nothing in the display changes unless
  you set `work.day_boundary = "strict"` yourself.

## [0.2.2] - 2026-08-25

### Fixed

- Clicking a notification banner could start a second instance (two menu
  bar items, double polling): notificationd opens the app via
  LaunchServices by bundle identifier, and with more than one registered
  copy of the .app (dev build in `dist/`, `/Applications`) it may launch
  a different copy than the running one. The app is now single-instance
  at two layers: `LSMultipleInstancesProhibited` in Info.plist stops
  LaunchServices launches, and a startup guard exits with a stderr note
  when another instance is already running (covers direct binary exec
  and `open -n`)

## [0.2.1] - 2026-07-12

### Changed

- **Release archive renamed** to `active-lens-gui-<version>-darwin-arm64.zip`
  (was `ActiveLens-<version>-macos-arm64.zip`), per `nlink-jp/.github`
  CONVENTIONS.md §Release Archive Standard. The `.app` inside is still
  `ActiveLens.app`.
- Bundles `active-lens` **v0.2.1**.

Packaging-only release; no change to the app's behaviour.

## [0.2.0] - 2026-07-10

> Requires `active-lens` v0.2.0, which ships bundled inside the app.

### Changed

- **The menu bar now shows the session you are in, not "today".** The headline is
  the current session's active time, so it starts fresh when a new session opens
  (e.g. after a night's sleep) instead of carrying yesterday's evening across
  midnight. The logical day's total moved to a **Today** row in the popover. The
  popover also names a session as `paused` while you are briefly away, and only
  shows an end time once the session has closed. Backed by the new
  `active-lens now --json`. See
  [ADR 0001](docs/en/adr/0001-logical-day-timeline-and-hover.md).
- Chart offsets are measured from each logical day's start (`day_start_unix`)
  rather than from midnight, and the time axis is no longer clamped to 24 hours —
  an all-nighter filed under the day it began now draws in full. Axis labels still
  read in wall-clock time.
- Overnight sleep no longer draws as an away bar, because the engine stops
  emitting segments outside a session.
- The analysis window asks for `timeline --days N`; the app no longer computes
  date ranges, which the CLI's logical day boundary now owns.

### Added

- Hovering a timeline column shows a card with the **block** under the pointer:
  its kind (work / break), start, end, duration, and for work the
  operating/present split. Blocks rather than raw segments — at 260pt over ~13
  hours a two-minute segment is sub-pixel and cannot be aimed at.
- The work log marks a session that ended after midnight with `(+1)`, and names
  the session count on days with more than one.

## [0.1.0] - 2026-07-09

### Added — Phase 2 (menu-bar GUI)

- SwiftUI menu-bar app showing the current state + today's active time, a thin
  front-end over the bundled, signed `active-lens` CLI (`timeline` / `status`
  `--json`).
- Popover: today's **work session** — active time, start time, operating/present
  split, and breaks — plus a live recording indicator and a **Record in
  background** switch that installs/removes the login-time launchd agent.
- Analysis window: a calendar-style **work timeline** (one column per day, time
  down each column, colored by state, morning at top) over a dense 7 / 30 / 90
  day range (empty days shown), plus a per-day work-log list. Swift Charts.
- Secure CLI resolution: the bundled signed binary is the trust anchor; a
  `$ACTIVE_LENS_BIN` override is honored only in DEBUG builds.
- Resilient decoding: tolerates null/empty JSON arrays from the CLI.
- Developer ID signed + notarizable `.app` (Hardened Runtime), with the CLI
  bundled in `Contents/Resources`.

[Unreleased]: https://github.com/nlink-jp/active-lens-gui/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/nlink-jp/active-lens-gui/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nlink-jp/active-lens-gui/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/nlink-jp/active-lens-gui/compare/v0.2.1...v0.2.2
[0.2.0]: https://github.com/nlink-jp/active-lens-gui/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nlink-jp/active-lens-gui/releases/tag/v0.1.0
