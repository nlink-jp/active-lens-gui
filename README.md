# ActiveLens (GUI)

A macOS menu-bar app that shows your Mac **work log** — when you started, took
breaks, and finished each day — **without recording anything about *what* you
do**. It's a thin SwiftUI front-end over the [`active-lens`](../active-lens) CLI,
which does all the sampling, storage, and aggregation.

- **Menu bar**: the current state (operating / present / away) and the active time
  of the **session you are in right now**, at a glance.
- **Popover**: that session — active time, when it started, the operating/present
  split and its breaks — plus today's total and a switch to enable background
  recording (installs a login-time launchd agent).
- **Analysis window**: a calendar-style **work timeline** — one column per day,
  time running down each column, colored by state — so you can scan across days
  and see *when* you were at the machine. Hover any block for its start, end, and
  duration. Below it, a per-day work log (start → end · active · breaks). Over the
  last 7 / 30 / 90 days, rendered with Swift Charts.

The three states:

- **operating** — awake, display on, input within the threshold
- **present** — awake, display on, no recent input (watching / reading)
- **away** — display off, locked, or asleep

> **Platform:** macOS 14+ on Apple Silicon. Developer ID signed + notarized.

## Sessions, not days

The menu-bar number is a **session**: one unbroken stretch of work, ended by an
absence of four hours or more. It therefore starts fresh each morning rather than
carrying the hours you put in before midnight — the popover's **Today** row keeps
that figure. Nor is a session cut at midnight: an evening that runs to 00:59 stays
one session, filed under the evening it began, and its column in the analysis
window simply extends past 24 hours to show it.

While you are away for less than the session gap the session is **paused**, not
finished; nothing can yet say whether a thirty-minute absence is a break or the
end of the day. Its start time never changes.

The CLI owns all of this. See
[its README](../active-lens/README.md#sessions-and-logical-days) for the session
gap and the logical day boundary, both configurable.

## How it fits together

```
┌─────────────────────────┐        ┌──────────────────────────┐
│  ActiveLens.app (SwiftUI)│  --json │  active-lens (Go CLI)     │
│  menu bar + Swift Charts │───────▶│  sample · store · aggregate│
└─────────────────────────┘        └──────────────────────────┘
        thin front-end                 single source of truth
```

The signed `active-lens` CLI ships **bundled** inside the app
(`Contents/Resources/active-lens`) and is the trust anchor — the app runs the
bundled copy, not an arbitrary one on your PATH. Enabling background recording
registers that bundled binary as a launchd LaunchAgent, so keep the app where
you install it from.

## Install

Download the notarized `active-lens-gui-<version>-darwin-arm64.zip` from Releases,
unzip, and drag `ActiveLens.app` to `/Applications`. Launch it; it lives in the
menu bar (no Dock icon).

Then open the menu-bar popover and turn on **Record in background** to start
collecting your daily activity.

## Build from source

```sh
make build        # swift build -c release
make build-app    # assemble + sign dist/ActiveLens.app (bundles the CLI)
make package      # notarize + staple + zip for release
make test         # swift test
make run          # build & run (debug)
```

`build-app` embeds the CLI from `../active-lens/dist/active-lens` (override with
`CLI_BIN=…`); build the CLI first with `make build` in that repo.

## Privacy

ActiveLens shows only aggregate time in three states. The underlying CLI reads
only seconds-since-last-input and two presence booleans — never keystrokes,
mouse coordinates, window titles, or app identity — and needs no Accessibility
or Input Monitoring permission. Nothing leaves your machine.

## License

MIT — see [LICENSE](LICENSE).
