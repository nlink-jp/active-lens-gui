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

    /// Concrete color range aligned to ActivityState.allCases order — for
    /// Swift Charts' foreground style scale.
    static var chartDomain: [String] { ActivityState.allCases.map(\.label) }
    static var chartRange: [Color] { ActivityState.allCases.map(color) }
}
