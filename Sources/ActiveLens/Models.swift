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

/// TimelineSession mirrors one unbroken stretch of work. A session is never split
/// at midnight, so it may end on the following calendar day.
struct TimelineSession: Codable, Identifiable, Equatable {
    let startUnix: Int
    let endUnix: Int
    let start: String
    let end: String
    let operatingSeconds: Int
    let presentSeconds: Int
    let activeSeconds: Int
    let breaks: [TimelineBreak]

    var id: Int { startUnix }

    enum CodingKeys: String, CodingKey {
        case start, end, breaks
        case startUnix = "start_unix"
        case endUnix = "end_unix"
        case operatingSeconds = "operating_seconds"
        case presentSeconds = "present_seconds"
        case activeSeconds = "active_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startUnix = try c.decode(Int.self, forKey: .startUnix)
        endUnix = try c.decode(Int.self, forKey: .endUnix)
        start = try c.decode(String.self, forKey: .start)
        end = try c.decode(String.self, forKey: .end)
        operatingSeconds = try c.decode(Int.self, forKey: .operatingSeconds)
        presentSeconds = try c.decode(Int.self, forKey: .presentSeconds)
        activeSeconds = try c.decode(Int.self, forKey: .activeSeconds)
        breaks = (try? c.decode([TimelineBreak].self, forKey: .breaks)) ?? []
    }
}

/// TimelineBlock is a session's coarse structure — the unit the pointer hits.
/// Raw segments alternate operating/present every few minutes and are sub-pixel
/// on a day column; blocks are a handful per day and large enough to point at.
struct TimelineBlock: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case work, `break`
    }

    let kind: Kind
    let startUnix: Int
    let endUnix: Int
    let start: String
    let end: String
    let seconds: Int
    let operatingSeconds: Int
    let presentSeconds: Int

    var id: Int { startUnix }

    enum CodingKeys: String, CodingKey {
        case kind, start, end, seconds
        case startUnix = "start_unix"
        case endUnix = "end_unix"
        case operatingSeconds = "operating_seconds"
        case presentSeconds = "present_seconds"
    }
}

/// TimelineDay mirrors one logical day of the timeline: spans + derived work
/// markers. The day begins at `dayStartUnix` (the CLI's `work.day_start_hour`),
/// not at midnight, and a session filed under it may run past `dayStartUnix + 24h`.
struct TimelineDay: Codable, Identifiable, Equatable {
    let date: String
    let dayStartUnix: Int
    let hasWork: Bool
    let workStartUnix: Int
    let workEndUnix: Int
    let workStart: String
    let workEnd: String
    let operatingSeconds: Int
    let presentSeconds: Int
    let activeSeconds: Int
    let spanSeconds: Int
    let sessions: [TimelineSession]
    let segments: [TimelineSegment]
    let blocks: [TimelineBlock]
    let breaks: [TimelineBreak]

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, segments, breaks, sessions, blocks
        case dayStartUnix = "day_start_unix"
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

    // Defensive decode: tolerate the arrays arriving as null or missing (e.g. an
    // empty Go slice marshaled as null) rather than crashing the UI.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        dayStartUnix = try c.decode(Int.self, forKey: .dayStartUnix)
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
        sessions = (try? c.decode([TimelineSession].self, forKey: .sessions)) ?? []
        segments = (try? c.decode([TimelineSegment].self, forKey: .segments)) ?? []
        blocks = (try? c.decode([TimelineBlock].self, forKey: .blocks)) ?? []
        breaks = (try? c.decode([TimelineBreak].self, forKey: .breaks)) ?? []
    }

    /// Hours elapsed since this logical day began — the y value for the timeline
    /// chart. Values above 24 are legitimate: a session that started before the
    /// next day's boundary is filed here whole, however late it ran.
    func hours(_ unix: Int) -> Double {
        Double(unix - dayStartUnix) / 3600.0
    }

    /// The block containing an offset in hours-from-day-start, or nil in a gap.
    /// Pure, so the hover hit-test is unit-testable without a chart.
    func block(atHours h: Double) -> TimelineBlock? {
        let unix = dayStartUnix + Int((h * 3600).rounded())
        return blocks.first { unix >= $0.startUnix && unix < $0.endUnix }
    }

    /// Whether the day's work ran past its own 24 hours (an all-nighter through
    /// the next boundary), which is what lets a column exceed a full day.
    var exceedsOneDay: Bool { hasWork && workEndUnix >= dayStartUnix + 86_400 }
}

/// TimelineReport mirrors the full `timeline --json` payload.
struct TimelineReport: Codable, Equatable {
    let since: String
    let until: String
    let timezone: String
    let sampleCount: Int
    let breakThresholdSeconds: Int
    let sessionGapSeconds: Int
    let dayStartHour: Int
    let days: [TimelineDay]

    enum CodingKeys: String, CodingKey {
        case since, until, timezone, days
        case sampleCount = "sample_count"
        case breakThresholdSeconds = "break_threshold_seconds"
        case sessionGapSeconds = "session_gap_seconds"
        case dayStartHour = "day_start_hour"
    }
}

// MARK: - Now (the current session)

/// NowSession mirrors `active-lens now --json`'s `session`. It is `open` while the
/// last activity is less than a session gap old, and `paused` when it is open but
/// the user is away right now. Its `start` never changes: at the live edge only
/// `open` can flip, once an absence passes the gap.
struct NowSession: Codable, Equatable {
    let open: Bool
    let paused: Bool
    let startUnix: Int
    let endUnix: Int
    let start: String
    let end: String
    let activeSeconds: Int
    let operatingSeconds: Int
    let presentSeconds: Int
    let breaks: [TimelineBreak]

    enum CodingKeys: String, CodingKey {
        case open, paused, start, end, breaks
        case startUnix = "start_unix"
        case endUnix = "end_unix"
        case activeSeconds = "active_seconds"
        case operatingSeconds = "operating_seconds"
        case presentSeconds = "present_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        open = try c.decode(Bool.self, forKey: .open)
        paused = try c.decode(Bool.self, forKey: .paused)
        startUnix = try c.decode(Int.self, forKey: .startUnix)
        endUnix = try c.decode(Int.self, forKey: .endUnix)
        start = try c.decode(String.self, forKey: .start)
        end = try c.decode(String.self, forKey: .end)
        activeSeconds = try c.decode(Int.self, forKey: .activeSeconds)
        operatingSeconds = try c.decode(Int.self, forKey: .operatingSeconds)
        presentSeconds = try c.decode(Int.self, forKey: .presentSeconds)
        breaks = (try? c.decode([TimelineBreak].self, forKey: .breaks)) ?? []
    }
}

/// NowDay is the logical day the now-session is filed under — not necessarily the
/// day the wall clock is in, which differ during an all-nighter.
struct NowDay: Codable, Equatable {
    let date: String
    let activeSeconds: Int

    enum CodingKeys: String, CodingKey {
        case date
        case activeSeconds = "active_seconds"
    }
}

/// NowReport mirrors the full `now --json` payload: what the menu bar asks for.
struct NowReport: Codable, Equatable {
    let state: String
    let recording: Bool
    let session: NowSession?
    let day: NowDay

    /// The live state, when a sample landed recently enough to trust it.
    var currentState: ActivityState? {
        recording ? ActivityState(rawValue: state) : nil
    }
}
