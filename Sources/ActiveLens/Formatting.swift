import SwiftUI

/// Pure formatting helpers (unit-tested) shared across the UI.
enum Format {
    /// Seconds → "2h 30m" / "45m" / "20s". Mirrors the CLI's formatSeconds so the
    /// GUI and `active-lens report` agree. Sub-minute values show seconds so a
    /// just-started day doesn't read as "0m".
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let mins = (seconds + 30) / 60 // round to nearest minute
        if mins < 60 { return "\(mins)m" }
        return String(format: "%dh %02dm", mins / 60, mins % 60)
    }

    /// Seconds as fractional hours, for chart axes.
    static func hours(_ seconds: Int) -> Double { Double(seconds) / 3600 }

    /// A compact hours axis label: "1.5h", "0.2h".
    static func hoursAxis(_ h: Double) -> String {
        if h >= 10 { return String(format: "%.0fh", h) }
        return String(format: "%.1fh", h)
    }

    /// "2026-07-05" → "07-05"; anything else passes through.
    static func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        return parts.count == 3 ? "\(parts[1])-\(parts[2])" : key
    }

    /// Hour index 0…23 → "0", "6", "12", … label.
    static func hourLabel(_ h: Int) -> String { "\(h)" }

    /// A clock-hour axis label for a fractional hour-of-day (0…24): "9", "13".
    static func clockAxis(_ h: Double) -> String { "\(Int(h.rounded()))" }

    /// An axis label for an offset in hours from a logical day's start, mapped back
    /// to the wall clock. A day beginning at 04:00 renders offset 20 as "0:00", so
    /// a column running into the small hours still reads in real clock time.
    /// Offsets past 24 wrap, since a session may outlive its own day.
    static func clockLabel(offsetHours h: Double, dayStartHour: Int) -> String {
        let hour = (dayStartHour + Int(h.rounded())) % 24
        return String(format: "%d:00", (hour + 24) % 24)
    }

    /// Hour ticks for the timeline's time axis between two offsets. The step
    /// widens with the span so a column stretched by a two-day session still
    /// gets a readable number of labels rather than one every few points.
    static func hourTicks(lo: Double, hi: Double) -> [Double] {
        let span = hi - lo
        let step: Double = span > 30 ? 6 : span > 10 ? 3 : 2
        var ticks: [Double] = []
        var h = lo.rounded(.up)
        while h <= hi {
            ticks.append(h)
            h += step
        }
        return ticks
    }

    /// Thin a list of axis keys to about `max` evenly spaced ones, always
    /// keeping the last (the newest day) so the right edge is labeled.
    static func thinned(_ keys: [String], max: Int) -> [String] {
        guard max > 0, keys.count > max else { return keys }
        let step = Int(ceil(Double(keys.count) / Double(max)))
        var out = stride(from: 0, to: keys.count, by: step).map { keys[$0] }
        if let last = keys.last, out.last != last {
            // Drop a neighbour that would collide with the forced last label:
            // one in the very next column always does, whatever the step.
            if (keys.count - 1) % step < Swift.max(2, (step + 1) / 2) { out.removeLast() }
            out.append(last)
        }
        return out
    }

    /// "(+1)" when the day's work ended on the following calendar day.
    static func nextDayMark(_ d: TimelineDay) -> String {
        guard d.hasWork else { return "" }
        let cal = Calendar.current
        let start = Date(timeIntervalSince1970: TimeInterval(d.workStartUnix))
        let end = Date(timeIntervalSince1970: TimeInterval(d.workEndUnix))
        return cal.isDate(start, inSameDayAs: end) ? "" : " (+1)"
    }

    /// A note for a day whose work log is bounded by a day-boundary cut rather
    /// than by the user putting their hands down — nil when both ends are real.
    /// Without it, a run of days all starting at exactly 05:00 reads as an
    /// improbably punctual worker rather than as one long stretch, cut.
    static func carryNote(_ d: TimelineDay) -> String? {
        switch (d.carriedIn, d.carriedOut) {
        case (true, true): return "Continues from the previous day and into the next."
        case (true, false): return "Continues from the previous day: work was already under way at \(d.workStart)."
        case (false, true): return "Continues into the next day: work ran past \(d.workEnd)."
        default: return nil
        }
    }

    /// Local midnight (epoch seconds) for a "yyyy-MM-dd" date string. Cached
    /// formatter keeps the per-segment lookups cheap.
    static func midnightEpoch(_ dateString: String) -> Int {
        guard let d = dayFormatter.date(from: dateString) else { return 0 }
        return Int(d.timeIntervalSince1970)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// The palette tying each state to a consistent color across popover + charts.
enum ActivityPalette {
    static func color(_ s: ActivityState) -> Color {
        switch s {
        case .operating: return .green
        case .present: return .blue
        case .away: return .gray
        }
    }

}
