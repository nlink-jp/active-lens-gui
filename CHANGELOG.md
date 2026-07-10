# Changelog

All notable changes to ActiveLens (GUI) are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/nlink-jp/active-lens-gui/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/nlink-jp/active-lens-gui/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nlink-jp/active-lens-gui/releases/tag/v0.1.0
