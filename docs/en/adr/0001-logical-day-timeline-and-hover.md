# ADR 0001 — Logical-day timeline rendering and segment hover

**Status:** Proposed (awaiting confirmation)
**Date:** 2026-07-10
**Targets:** `AnalysisView`, `Models`, `ActivityModel`
**Companion:** `active-lens` ADR 0001 (session-based work-day attribution) — the
two must ship together; this app cannot render the new payload without it, and
the engine change is invisible without this one.

---

## 1. Context

Three changes land at once, for one reason each.

**The engine's day is no longer the calendar day.** `active-lens` ADR 0001
replaces midnight bucketing with logical days (`[D 04:00, D+1 04:00)`) and files
whole work sessions under the day they started in. A day's segments may therefore
extend past 24 hours from the day's origin — an evening session running to 00:59
is hour 16.7 to 20.98 of a logical day that began at 04:00. The chart currently
measures hours from calendar midnight and clamps the y range to `min(24, …)`, so
it would clip exactly the spans this fix exists to preserve.

**Hovering a segment is not physically possible.** The requested popover shows a
span's Start / End / Duration. But the timeline draws raw segments, and raw
segments are tiny: in the recorded 2026-07-09 data, `operating` and `present`
alternate every few minutes (`20:53–20:55 present`, `20:55–20:56 operating`, …).
The chart is 260 pt tall over roughly 13 hours, so **one minute is about 0.33 pt**.
Any segment under two minutes is sub-pixel, and the segment under the cursor is
effectively chosen at random among its neighbours.

**The menu bar's unit is a session, not a day.** See §2.3.

## 2. Decision

### 2.1 Measure hours from the logical day origin

`TimelineDay.hours(_:)` becomes `Double(unix - dayStartUnix) / 3600.0`, using the
new `day_start_unix` field rather than `Format.midnightEpoch(date)`. Values above
24 are legitimate and are not clamped.

`hoursBounds` drops its `min(24, …)` ceiling; the lower bound stays at 0 (a
logical day cannot begin before its own origin). The y-axis tick labels map an
offset back to wall clock as `(day_start_hour + h) mod 24`, so a session running
into the small hours reads `22:00`, `0:00`, `2:00` down the column — the axis
still shows real clock times, only the column is allowed to be longer than a day.

### 2.2 Hover reports blocks, not segments

The engine emits `blocks[]` per day: a `work` block is a contiguous run of active
segments, a `break` block is an away span of at least `break_minutes`. Together
they tile each session, and a day has a handful of them rather than hundreds.
Blocks are what the eye sees as a bar, and they are large enough to point at.

`.chartOverlay` plus `onContinuousHover` maps the cursor to `(date, hourOffset)`
via `ChartProxy.value(atX:as:)` / `value(atY:as:)`, and a pure
`blockAt(day:hourOffset:)` finds the block containing that offset. The tooltip
card shows:

- a `work` block — **Start**, **End**, **Duration**, and the operating / present
  split beneath;
- a `break` block — **Start**, **End**, **Duration**, labelled as a break.

With the cursor over a day column but outside every block, no card is shown.
The card is positioned beside the cursor and clamped inside the chart bounds so
it never renders off-screen at the right or bottom edge. Leaving the chart clears
it.

Blocks are computed in the CLI, not here: `CLAUDE.md` makes the engine the owner
of all derivation, and a pure Go function is cheaper to test than a Swift one.

### 2.3 The menu bar shows the now-session, not "today"

The menu bar's unit was never really the day. `PopoverView.workSession(_ d:
TimelineDay)` is named for a session, prints `started …` / `ended …`, and is
handed a day — the abstraction leaked because, before this change, each calendar
day derived exactly one work-session envelope. With sessions promoted to
first-class objects the proxy is unnecessary and, at 01:00 or after an overnight
run, wrong.

The popover and the menu-bar title read `active-lens now --json`, which returns
the now-session (open / paused, start, end, active split, breaks) alongside the
logical day it is filed under. `ActivityModel.todayTimeline` becomes
`nowSession`; `todayActiveLabel` becomes `sessionActiveLabel`.

- **Menu-bar headline** — the now-session's active time. It answers "how long
  this stretch", which is what the glance is for.
- **Popover body** — the session: started at, active, operating / present split,
  breaks. When paused, it says so rather than silently freezing.
- **Popover secondary row** — `Today`, the logical-day active total, from the
  same payload's `day` field.

`todayString()` and `calendarSince(_:)` are deleted. Both reimplement day
arithmetic the engine now owns: the first would look up the wrong key under
logical days, and the second would anchor a range on the calendar today. The
analysis window calls `timeline --days N --json` and lets the CLI resolve the
range.

## 3. Consequences

A day column can now be taller than 24 hours, so the shared y scale grows to fit
the longest day in the range. In the pathological case the engine's ADR describes
(a display that never sleeps for two days, producing a ~48-hour session) the
whole chart's y range stretches to match. The auto-fit is correct; the result is
merely tall.

Overnight sleep no longer appears as an away bar, because the engine stops
emitting segments outside sessions. The `Away` legend entry now only ever refers
to short absences and breaks within a work session, which is what a work log
should show.

The menu-bar number resets to `0s` when a new session opens — waking the Mac at
07:26 after a night's sleep no longer shows the hours worked before midnight.
That is the intended meaning of a session headline, but it is the most visible
behaviour change in this pair of ADRs, and the `Today` row exists to keep the old
figure one click away.

## 4. Alternatives rejected

**Hover the raw segment anyway.** It is what was originally asked for, and it is
one line of lookup. But at 0.33 pt per minute the answer is unpredictable: the
user points at a bar and gets whichever of the four sub-pixel segments under the
cursor happened to win. A tooltip that changes when the pointer moves by one
pixel teaches the user nothing.

**A two-tier card (segment on top, block beneath).** Maximum information, and it
resolves the ambiguity by showing both. Rejected because the segment line still
carries the unpredictability, now with a stable line next to it to contrast
against, and the card grows large enough to obscure the column being inspected.

**Keep the logical-day total as the menu-bar headline.** The number would never
reset, which is comfortable. Rejected because it answers a question nobody asks
of a menu bar: at 20:00 on a day that began at 09:00, "9h 40m today" tells you
nothing about the stretch you are currently in, and after an all-nighter the
figure belongs to a day that ended hours ago. The total is still worth a row in
the popover, just not the headline.

**Spill a cross-midnight session into the next day's column.** Keeps every column
exactly 24 hours. But it re-introduces the visual break at midnight that the
engine change exists to remove, and the work-log row would still have to name two
columns for one session.

## 5. Test plan

- `TimelineDay.hours(_:)` returns offsets from `day_start_unix`, including values
  above 24 for a session running past the next day's origin.
- Axis label mapping: offset 20 with `day_start_hour = 4` renders `0:00`.
- `blockAt(day:hourOffset:)` returns the containing block, `nil` in a gap, and
  `nil` past the last block.
- Decoding a payload with `blocks`, `sessions`, and `day_start_unix` present; and
  the existing defensive fallbacks for null arrays.
- Decoding `now --json`: an open session, a paused one, a closed one, and a null
  session.
- `sessionActiveLabel` shows the session's active time, `—` on error, and `0s`
  when no session exists yet.
- `Format.duration` stays in lockstep with the CLI's `formatSeconds` (existing
  test, unchanged).
