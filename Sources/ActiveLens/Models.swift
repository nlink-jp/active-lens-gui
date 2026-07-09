import Foundation

/// Totals mirrors the per-state second counts from `active-lens --json`.
struct Totals: Codable, Equatable {
    let operatingSeconds: Int
    let presentSeconds: Int
    let awaySeconds: Int

    enum CodingKeys: String, CodingKey {
        case operatingSeconds = "operating_seconds"
        case presentSeconds = "present_seconds"
        case awaySeconds = "away_seconds"
    }

    var totalSeconds: Int { operatingSeconds + presentSeconds + awaySeconds }
    static let zero = Totals(operatingSeconds: 0, presentSeconds: 0, awaySeconds: 0)

    /// Seconds for a given state key ("operating"/"present"/"away").
    func seconds(for state: ActivityState) -> Int {
        switch state {
        case .operating: return operatingSeconds
        case .present: return presentSeconds
        case .away: return awaySeconds
        }
    }
}

/// The three activity states, in display order.
enum ActivityState: String, CaseIterable, Identifiable {
    case operating, present, away
    var id: String { rawValue }
    var label: String {
        switch self {
        case .operating: return "Operating"
        case .present: return "Present"
        case .away: return "Away"
        }
    }

    /// SF Symbol reflecting the state, for the menu bar / indicators.
    var icon: String {
        switch self {
        case .operating: return "cursorarrow.rays"
        case .present: return "eye"
        case .away: return "moon.zzz"
        }
    }
}

/// DayTotals mirrors one entry of the report's `days` array.
struct DayTotals: Codable, Identifiable, Equatable {
    let date: String
    let totals: Totals
    var id: String { date }
}

/// Report mirrors `active-lens report --json` / `today --json`.
struct Report: Codable, Equatable {
    let since: String
    let until: String
    let timezone: String
    let sampleCount: Int
    let total: Totals
    let days: [DayTotals]
    let hourOfDay: [Totals]

    enum CodingKeys: String, CodingKey {
        case since, until, timezone, total, days
        case sampleCount = "sample_count"
        case hourOfDay = "hour_of_day"
    }
}

/// DaemonStatus mirrors `active-lens status --json`.
struct DaemonStatus: Codable, Equatable {
    let daemonInstalled: Bool
    let daemonLoaded: Bool
    let dbPath: String
    let intervalSeconds: Int
    let thresholdSeconds: Double
    let maxGapSeconds: Int
    let lastSampleUnix: Int
    let lastSampleState: String

    enum CodingKeys: String, CodingKey {
        case daemonInstalled = "daemon_installed"
        case daemonLoaded = "daemon_loaded"
        case dbPath = "db_path"
        case intervalSeconds = "interval_seconds"
        case thresholdSeconds = "threshold_seconds"
        case maxGapSeconds = "max_gap_seconds"
        case lastSampleUnix = "last_sample_unix"
        case lastSampleState = "last_sample_state"
    }

    var lastSampleDate: Date? {
        lastSampleUnix > 0 ? Date(timeIntervalSince1970: TimeInterval(lastSampleUnix)) : nil
    }

    /// Whether activity is actually being recorded right now — i.e. a sample
    /// landed within a few intervals of now. This is deliberately independent of
    /// `daemonLoaded` (the login-agent switch): data can flow from a manually
    /// started daemon too, and a loaded-but-crashed agent should read as *not*
    /// recording. It answers "is my activity being tracked?", not "is the login
    /// item installed?".
    func isRecording(now: Date = Date()) -> Bool {
        guard let last = lastSampleDate else { return false }
        let staleAfter = TimeInterval(max(intervalSeconds * 4, 60))
        return now.timeIntervalSince(last) <= staleAfter
    }

    /// The current state, if a fresh sample exists.
    var currentState: ActivityState? {
        guard isRecording() else { return nil }
        return ActivityState(rawValue: lastSampleState)
    }
}

// MARK: - Timeline (work-log)

/// TimelineSegment mirrors one span from `active-lens timeline --json`.
struct TimelineSegment: Codable, Identifiable, Equatable {
    let startUnix: Int
    let endUnix: Int
    let start: String
    let end: String
    let state: String

    var id: String { "\(startUnix)-\(state)" }
    var activityState: ActivityState { ActivityState(rawValue: state) ?? .away }

    enum CodingKeys: String, CodingKey {
        case startUnix = "start_unix"
        case endUnix = "end_unix"
        case start, end, state
    }
}

/// TimelineBreak mirrors one break span.
struct TimelineBreak: Codable, Identifiable, Equatable {
    let startUnix: Int
    let endUnix: Int
    let start: String
    let end: String
    let seconds: Int

    var id: Int { startUnix }

    enum CodingKeys: String, CodingKey {
        case startUnix = "start_unix"
        case endUnix = "end_unix"
        case start, end, seconds
    }
}

/// TimelineDay mirrors one day of the timeline: spans + derived work markers.
struct TimelineDay: Codable, Identifiable, Equatable {
    let date: String
    let hasWork: Bool
    let workStartUnix: Int
    let workEndUnix: Int
    let workStart: String
    let workEnd: String
    let operatingSeconds: Int
    let presentSeconds: Int
    let activeSeconds: Int
    let spanSeconds: Int
    let segments: [TimelineSegment]
    let breaks: [TimelineBreak]

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, segments, breaks
        case hasWork = "has_work"
        case workStartUnix = "work_start_unix"
        case workEndUnix = "work_end_unix"
        case workStart = "work_start"
        case workEnd = "work_end"
        case operatingSeconds = "operating_seconds"
        case presentSeconds = "present_seconds"
        case activeSeconds = "active_seconds"
        case spanSeconds = "span_seconds"
    }

    // Defensive decode: tolerate segments/breaks arriving as null or missing
    // (e.g. an empty Go slice marshaled as null) rather than crashing the UI.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        hasWork = try c.decode(Bool.self, forKey: .hasWork)
        workStartUnix = try c.decode(Int.self, forKey: .workStartUnix)
        workEndUnix = try c.decode(Int.self, forKey: .workEndUnix)
        workStart = try c.decode(String.self, forKey: .workStart)
        workEnd = try c.decode(String.self, forKey: .workEnd)
        operatingSeconds = try c.decode(Int.self, forKey: .operatingSeconds)
        presentSeconds = try c.decode(Int.self, forKey: .presentSeconds)
        activeSeconds = try c.decode(Int.self, forKey: .activeSeconds)
        spanSeconds = try c.decode(Int.self, forKey: .spanSeconds)
        // decode throws on null or missing; fall back to an empty array.
        segments = (try? c.decode([TimelineSegment].self, forKey: .segments)) ?? []
        breaks = (try? c.decode([TimelineBreak].self, forKey: .breaks)) ?? []
    }

    /// Local hours-from-midnight (0…24) for a unix time on this day — the x value
    /// for the timeline chart.
    func hours(_ unix: Int) -> Double {
        Double(unix - Format.midnightEpoch(date)) / 3600.0
    }
}

/// TimelineReport mirrors the full `timeline --json` payload.
struct TimelineReport: Codable, Equatable {
    let since: String
    let until: String
    let timezone: String
    let sampleCount: Int
    let breakThresholdSeconds: Int
    let days: [TimelineDay]

    enum CodingKeys: String, CodingKey {
        case since, until, timezone, days
        case sampleCount = "sample_count"
        case breakThresholdSeconds = "break_threshold_seconds"
    }
}
