# ADR 0002 — Showing a day-boundary cut

**Status:** Accepted
**Date:** 2026-09-17
**Targets:** `Models`, `Formatting`, `PopoverView`, `AnalysisView`
**Companion:** `active-lens` ADR 0002 (configurable day boundary) — the two must
ship together: the engine's new rule is invisible without this, and this app
cannot show it without the bundled CLI that emits the flags.

---

## 1. Context

`active-lens` ADR 0002 adds `work.day_boundary`. Under `"strict"` — the setting
for a workplace whose working day is defined for the user — a session running
through the boundary is cut there, and each piece is filed under its own day.

That rule produces two things this app cannot render honestly as they stand:

**A work day that starts at exactly 05:00.** A day whose work was already under
way when the boundary passed has a `work_start` that is the boundary itself. A
column of such days reads as an improbably punctual worker, and nothing in the
old payload distinguishes it from someone who genuinely sat down at 05:00.

**A menu-bar heading that restarts mid-work.** The heading is the now-session
(ADR 0001 §2.7). Under `strict` the boundary opens a new session, so at 05:00,
with hands on the keyboard, the number returns to `0s`. That is the intended
behaviour — the figure worth glancing at is the one that counts against today —
but on the surface people look at most, an unexplained reset reads as lost data.

## 2. Decision

**Decode the flags, do not re-derive them.** `carried_in` / `carried_out` arrive
on every day, session, and now-session; `day_boundary` and `day_start_hour` on
the timeline payload and on `status`. The app keeps no opinion about where a day
begins — that stayed with the engine in ADR 0001 and stays there now.

**Every new field is optional.** A bundled CLI older than 0.3.0 emits none of
them, and the app must still run: absent means "not carried", `day_boundary`
absent means the default rule. Silence is read as the old behaviour, never
guessed at.

**Mark the cut where the cut shows.**

- Work log: a carried-in row is prefixed with `arrow.turn.down.right`, a
  carried-out row suffixed with `arrow.right.to.line`, and the row carries a
  tooltip spelling the note out. A row with two real ends gets no tooltip rather
  than an empty one.
- The Work log header states the rule when it is `strict`: "day starts 05:00 ·
  sessions cut at the boundary". Under the default rule it says nothing — the
  default needs no explanation.
- Popover: a carried-in session reads "since the day began, 05:00" instead of
  "started 05:00", and gains one sentence explaining where the earlier hours
  went. Shown only when it happened.

**The chart is unchanged.** Under `strict` a column can still reach exactly 24h
but never exceeds it, so the y-domain from ADR 0001 (which had to allow more)
already covers it. Nothing in the drawing code needs to know the mode.

## 3. Consequences

- The app renders both rules from one payload shape; there is no mode switch in
  the UI and no second code path.
- A cut is never silent: the surface that shows a boundary time also shows that
  it is a boundary.
- Setting `work.day_boundary` in `config.toml` changes the GUI only once the
  app bundles a CLI that supports it — the bundled copy is the trust anchor, and
  it is refreshed at release.

## 4. Test plan

- A `strict` timeline payload decodes with the flags on both the day and its
  session, and `Format.carryNote` renders each of the three cases.
- A payload with no carried fields (the default rule, or an older CLI) decodes
  with every flag false and no note.
- `status` without `day_start_hour` / `day_boundary` decodes, reports
  `cutsSessionsAtDayBoundary == false`, and no day-start label.
- A now-session with `carried_in` decodes, keeping the small `active_seconds`
  that the boundary reset produced.
