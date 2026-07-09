# Changelog

All notable changes to ActiveLens (GUI) are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/nlink-jp/active-lens-gui/commits/main
