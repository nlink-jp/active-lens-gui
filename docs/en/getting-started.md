# Getting started with ActiveLens

## 1. Install

Unzip `ActiveLens-<version>-macos-arm64.zip` and move `ActiveLens.app` to
`/Applications`. Launch it — it appears in the menu bar (no Dock icon). The app
is Developer ID signed and notarized, so Gatekeeper opens it without warnings.

## 2. Start recording

Click the menu-bar item to open the popover, then turn on **Record in
background**. This registers a launchd LaunchAgent that runs the bundled
`active-lens daemon` at login, sampling your activity every 15 seconds.

The dot under the toggle turns green once the first sample lands ("Recording").

> Keep `ActiveLens.app` where you installed it — the background recorder runs the
> copy of the CLI inside the app bundle.

## 3. Read your day

- The **menu bar** shows the current state and the *active* time of the session
  you are in right now. It resets when a new session begins — after a night's
  sleep, or any absence of four hours or more.
- The **popover** shows that session: active time, when it started, the
  operating/present split, its breaks, and **Today**'s total beneath them. While
  you are briefly away it reads *paused*, not finished.
- **Analysis…** opens the calendar-style work timeline — one column per day, time
  down each column — plus a per-day work log, over the last 7 / 30 / 90 days.
  Hover a block to see its start, end, and duration. An evening that ran past
  midnight stays on the day it began, so its column extends past 24 hours.

## What the states mean

| State | Meaning |
|-------|---------|
| operating | You were typing/clicking (input within ~30s) |
| present | Screen on, but no recent input (watching / reading) |
| away | Display off, locked, or the Mac asleep |

## Privacy

ActiveLens never records *what* you do — only that input happened and the
resulting state. No keystrokes, coordinates, window titles, or app names; no
special permissions; no network access.

## Configuration

Advanced settings (sampling interval, active threshold, database location) live
in the CLI's `config.toml`
(`~/Library/Application Support/active-lens/config.toml`). Run
`active-lens doctor` from the bundled binary to see resolved values. See the
[active-lens README](../../../active-lens/README.md).
