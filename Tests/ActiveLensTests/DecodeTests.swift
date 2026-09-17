import XCTest
@testable import ActiveLens

final class DecodeTests: XCTestCase {
    /// A report payload shaped exactly like `active-lens report --json`.
    func testDecodeReport() throws {
        let json = """
        {
          "since": "2026-07-03",
          "until": "2026-07-09",
          "timezone": "Local",
          "sample_count": 76,
          "total": { "operating_seconds": 21, "present_seconds": 9, "away_seconds": 75 },
          "days": [
            { "date": "2026-07-09", "totals": { "operating_seconds": 21, "present_seconds": 9, "away_seconds": 75 } }
          ],
          "hour_of_day": [
            { "operating_seconds": 21, "present_seconds": 9, "away_seconds": 0 }
          ]
        }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(Report.self, from: json)
        XCTAssertEqual(r.since, "2026-07-03")
        XCTAssertEqual(r.sampleCount, 76)
        XCTAssertEqual(r.total.operatingSeconds, 21)
        XCTAssertEqual(r.total.totalSeconds, 105)
        XCTAssertEqual(r.days.count, 1)
        XCTAssertEqual(r.days.first?.totals.presentSeconds, 9)
        XCTAssertEqual(r.hourOfDay.first?.operatingSeconds, 21)
    }

    func testDecodeStatus() throws {
        let json = """
        {
          "daemon_installed": true,
          "daemon_loaded": true,
          "daemon_label": "com.nlink-jp.active-lens",
          "config_path": "/x/config.toml",
          "db_path": "/x/activity.db",
          "interval_seconds": 15,
          "threshold_seconds": 30,
          "max_gap_seconds": 45,
          "last_sample_unix": 1783596233,
          "last_sample_state": "operating"
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(DaemonStatus.self, from: json)
        XCTAssertTrue(s.daemonLoaded)
        XCTAssertEqual(s.intervalSeconds, 15)
        XCTAssertEqual(s.lastSampleState, "operating")
        XCTAssertNotNil(s.lastSampleDate)
    }

    func testTotalsSecondsForState() {
        let t = Totals(operatingSeconds: 1, presentSeconds: 2, awaySeconds: 3)
        XCTAssertEqual(t.seconds(for: .operating), 1)
        XCTAssertEqual(t.seconds(for: .present), 2)
        XCTAssertEqual(t.seconds(for: .away), 3)
    }

    /// A logical day starting at 04:00, with an evening session that runs to 00:59
    /// the next calendar day — the shape the engine now emits.
    private func eveningTimelineJSON() -> Data {
        let dayStart = Format.midnightEpoch("2026-07-09") + 4 * 3600  // 04:00
        let start = dayStart + 16 * 3600 + 44 * 60                    // 20:44
        let end = dayStart + 20 * 3600 + 59 * 60                      // 00:59 next day
        let breakStart = dayStart + 17 * 3600 + 51 * 60               // 21:51
        let breakEnd = breakStart + 600                               // 22:01
        return """
        {
          "since": "2026-07-09", "until": "2026-07-09", "timezone": "Local",
          "sample_count": 100, "break_threshold_seconds": 600,
          "session_gap_seconds": 14400, "day_start_hour": 4,
          "days": [
            {
              "date": "2026-07-09", "day_start_unix": \(dayStart), "has_work": true,
              "work_start_unix": \(start), "work_end_unix": \(end),
              "work_start": "20:44", "work_end": "00:59",
              "operating_seconds": 20000, "present_seconds": 8000,
              "active_seconds": 28000, "span_seconds": 15300,
              "sessions": [
                {
                  "start_unix": \(start), "end_unix": \(end), "start": "20:44", "end": "00:59",
                  "operating_seconds": 20000, "present_seconds": 8000, "active_seconds": 28000,
                  "breaks": [
                    { "start_unix": \(breakStart), "end_unix": \(breakEnd), "start": "21:51", "end": "22:01", "seconds": 600 }
                  ]
                }
              ],
              "segments": [
                { "start_unix": \(start), "end_unix": \(breakStart), "start": "20:44", "end": "21:51", "state": "operating" },
                { "start_unix": \(breakStart), "end_unix": \(breakEnd), "start": "21:51", "end": "22:01", "state": "away" },
                { "start_unix": \(breakEnd), "end_unix": \(end), "start": "22:01", "end": "00:59", "state": "operating" }
              ],
              "blocks": [
                { "kind": "work", "start_unix": \(start), "end_unix": \(breakStart), "start": "20:44", "end": "21:51",
                  "seconds": 4020, "operating_seconds": 4020, "present_seconds": 0 },
                { "kind": "break", "start_unix": \(breakStart), "end_unix": \(breakEnd), "start": "21:51", "end": "22:01",
                  "seconds": 600, "operating_seconds": 0, "present_seconds": 0 },
                { "kind": "work", "start_unix": \(breakEnd), "end_unix": \(end), "start": "22:01", "end": "00:59",
                  "seconds": 10680, "operating_seconds": 8000, "present_seconds": 2680 }
              ],
              "breaks": [
                { "start_unix": \(breakStart), "end_unix": \(breakEnd), "start": "21:51", "end": "22:01", "seconds": 600 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!
    }

    func testDecodeTimeline() throws {
        let tl = try JSONDecoder().decode(TimelineReport.self, from: eveningTimelineJSON())
        XCTAssertEqual(tl.dayStartHour, 4)
        XCTAssertEqual(tl.sessionGapSeconds, 14400)
        XCTAssertEqual(tl.days.count, 1)

        let d = tl.days[0]
        XCTAssertTrue(d.hasWork)
        XCTAssertEqual(d.workStart, "20:44")
        XCTAssertEqual(d.sessions.count, 1)
        XCTAssertEqual(d.sessions.first?.breaks.count, 1)
        XCTAssertEqual(d.blocks.count, 3)
        XCTAssertEqual(d.blocks.map(\.kind), [TimelineBlock.Kind.work, .break, .work])
        XCTAssertEqual(d.segments.first?.activityState, .operating)

        // hours() measures from the logical day's start (04:00), not midnight.
        XCTAssertEqual(d.hours(d.workStartUnix), 16.733, accuracy: 0.01)
        XCTAssertEqual(d.hours(d.workEndUnix), 20.983, accuracy: 0.01)
        // An evening that ends at 00:59 still fits inside its own logical day.
        XCTAssertFalse(d.exceedsOneDay)
    }

    func testTimelineHoursPastTwentyFour() throws {
        // An all-nighter: filed under the 9th, ending 09:00 on the 10th — hour 29 of
        // a day that began at 04:00. The chart must be allowed to draw past 24.
        let dayStart = Format.midnightEpoch("2026-07-09") + 4 * 3600
        let json = """
        {
          "since": "2026-07-09", "until": "2026-07-09", "timezone": "Local",
          "sample_count": 10, "break_threshold_seconds": 600,
          "session_gap_seconds": 14400, "day_start_hour": 4,
          "days": [
            {
              "date": "2026-07-09", "day_start_unix": \(dayStart), "has_work": true,
              "work_start_unix": \(dayStart + 16 * 3600), "work_end_unix": \(dayStart + 29 * 3600),
              "work_start": "20:00", "work_end": "09:00",
              "operating_seconds": 46800, "present_seconds": 0,
              "active_seconds": 46800, "span_seconds": 46800,
              "sessions": [], "segments": [], "blocks": [], "breaks": []
            }
          ]
        }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(TimelineReport.self, from: json).days[0]
        XCTAssertEqual(d.hours(d.workEndUnix), 29.0, accuracy: 0.001)
        XCTAssertTrue(d.exceedsOneDay)
    }

    func testBlockHitTest() throws {
        let d = try JSONDecoder().decode(TimelineReport.self, from: eveningTimelineJSON()).days[0]

        // Inside the first work block (20:44–21:51 → offsets 16.73…17.85).
        XCTAssertEqual(d.block(atHours: 17.0)?.kind, .work)
        // Inside the break (21:51–22:01 → 17.85…18.02).
        XCTAssertEqual(d.block(atHours: 17.95)?.kind, .break)
        // Inside the second work block.
        XCTAssertEqual(d.block(atHours: 19.0)?.kind, .work)
        // Before the day's first block, and after its last.
        XCTAssertNil(d.block(atHours: 5.0))
        XCTAssertNil(d.block(atHours: 23.0))
    }

    func testDecodeTimelineToleratesNullArrays() throws {
        // An empty Go slice can marshal as null; the UI must not crash on it.
        let dayStart = Format.midnightEpoch("2026-07-09") + 4 * 3600
        let json = """
        {
          "since": "2026-07-09", "until": "2026-07-09", "timezone": "Local",
          "sample_count": 0, "break_threshold_seconds": 600,
          "session_gap_seconds": 14400, "day_start_hour": 4,
          "days": [
            {
              "date": "2026-07-09", "day_start_unix": \(dayStart), "has_work": false,
              "work_start_unix": 0, "work_end_unix": 0, "work_start": "", "work_end": "",
              "operating_seconds": 0, "present_seconds": 0, "active_seconds": 0, "span_seconds": 0,
              "sessions": null, "segments": null, "blocks": null, "breaks": null
            }
          ]
        }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(TimelineReport.self, from: json).days[0]
        XCTAssertTrue(d.sessions.isEmpty)
        XCTAssertTrue(d.blocks.isEmpty)
        XCTAssertFalse(d.exceedsOneDay)
        XCTAssertNil(d.block(atHours: 10))
    }

    // MARK: - now

    func testDecodeNowOpenSession() throws {
        let json = """
        {
          "state": "operating", "recording": true,
          "session": {
            "open": true, "paused": false,
            "start_unix": 1783596233, "end_unix": 1783606233,
            "start": "20:44", "end": "23:31",
            "active_seconds": 9000, "operating_seconds": 7000, "present_seconds": 2000,
            "breaks": [ { "start_unix": 1, "end_unix": 2, "start": "21:51", "end": "22:01", "seconds": 600 } ]
          },
          "day": { "date": "2026-07-09", "active_seconds": 12000 }
        }
        """.data(using: .utf8)!
        let n = try JSONDecoder().decode(NowReport.self, from: json)
        XCTAssertEqual(n.currentState, .operating)
        XCTAssertEqual(n.session?.open, true)
        XCTAssertEqual(n.session?.paused, false)
        XCTAssertEqual(n.session?.start, "20:44")
        XCTAssertEqual(n.session?.breaks.count, 1)
        XCTAssertEqual(n.day.date, "2026-07-09")
        XCTAssertEqual(n.day.activeSeconds, 12000)
    }

    func testDecodeNowPausedAndStale() throws {
        let json = """
        {
          "state": "away", "recording": false,
          "session": {
            "open": true, "paused": true,
            "start_unix": 1, "end_unix": 2, "start": "20:44", "end": "23:31",
            "active_seconds": 9000, "operating_seconds": 7000, "present_seconds": 2000,
            "breaks": null
          },
          "day": { "date": "2026-07-09", "active_seconds": 9000 }
        }
        """.data(using: .utf8)!
        let n = try JSONDecoder().decode(NowReport.self, from: json)
        XCTAssertEqual(n.session?.paused, true)
        XCTAssertTrue(n.session?.breaks.isEmpty ?? false)
        // A stale sample must not be presented as the live state.
        XCTAssertNil(n.currentState)
    }

    func testDecodeNowWithoutSession() throws {
        let json = """
        { "state": "", "recording": false, "session": null,
          "day": { "date": "2026-07-10", "active_seconds": 0 } }
        """.data(using: .utf8)!
        let n = try JSONDecoder().decode(NowReport.self, from: json)
        XCTAssertNil(n.session)
        XCTAssertNil(n.currentState)
        XCTAssertEqual(n.day.date, "2026-07-10")
    }
    // MARK: - Day boundary (CLI ADR 0002)

    /// A `strict` payload: one stretch of work cut at the 05:00 boundary, so the
    /// second day starts at a cut rather than at someone sitting down.
    func testDecodeTimelineCarriedAcrossTheDayBoundary() throws {
        let json = """
        {
          "since": "2026-09-12", "until": "2026-09-13", "timezone": "Local",
          "sample_count": 2, "break_threshold_seconds": 600,
          "session_gap_seconds": 14400, "day_start_hour": 5, "day_boundary": "strict",
          "days": [
            {
              "date": "2026-09-12", "day_start_unix": 1789000000, "has_work": true,
              "work_start_unix": 1789020000, "work_end_unix": 1789086400,
              "work_start": "10:54", "work_end": "05:00",
              "carried_in": false, "carried_out": true,
              "operating_seconds": 58000, "present_seconds": 0,
              "active_seconds": 58000, "span_seconds": 66400,
              "sessions": [ {
                "start_unix": 1789020000, "end_unix": 1789086400,
                "start": "10:54", "end": "05:00",
                "carried_in": false, "carried_out": true,
                "operating_seconds": 58000, "present_seconds": 0,
                "active_seconds": 58000, "breaks": []
              } ],
              "segments": [], "blocks": [], "breaks": []
            },
            {
              "date": "2026-09-13", "day_start_unix": 1789086400, "has_work": true,
              "work_start_unix": 1789086400, "work_end_unix": 1789100000,
              "work_start": "05:00", "work_end": "08:46",
              "carried_in": true, "carried_out": false,
              "operating_seconds": 13600, "present_seconds": 0,
              "active_seconds": 13600, "span_seconds": 13600,
              "sessions": [ {
                "start_unix": 1789086400, "end_unix": 1789100000,
                "start": "05:00", "end": "08:46",
                "carried_in": true, "carried_out": false,
                "operating_seconds": 13600, "present_seconds": 0,
                "active_seconds": 13600, "breaks": []
              } ],
              "segments": [], "blocks": [], "breaks": []
            }
          ]
        }
        """.data(using: .utf8)!
        let tl = try JSONDecoder().decode(TimelineReport.self, from: json)
        XCTAssertTrue(tl.cutsSessionsAtDayBoundary)
        XCTAssertEqual(tl.dayStartLabel, "05:00")

        XCTAssertTrue(tl.days[0].carriedOut)
        XCTAssertFalse(tl.days[0].carriedIn)
        XCTAssertTrue(tl.days[1].carriedIn)
        XCTAssertTrue(tl.days[1].sessions[0].carriedIn)
        XCTAssertEqual(Format.carryNote(tl.days[1]),
                       "Continues from the previous day: work was already under way at 05:00.")
        XCTAssertEqual(Format.carryNote(tl.days[0]),
                       "Continues into the next day: work ran past 05:00.")
    }

    /// The default rule, and any CLI older than 0.3.0: no carried flags at all.
    func testDecodeTimelineWithoutCarriedFlags() throws {
        let tl = try JSONDecoder().decode(TimelineReport.self, from: eveningTimelineJSON())
        XCTAssertNil(tl.dayBoundary)
        XCTAssertFalse(tl.cutsSessionsAtDayBoundary)
        XCTAssertFalse(tl.days[0].carriedIn)
        XCTAssertFalse(tl.days[0].carriedOut)
        XCTAssertFalse(tl.days[0].sessions[0].carriedIn)
        XCTAssertNil(Format.carryNote(tl.days[0]))
    }

    func testDecodeNowCarriedInSession() throws {
        // 05:30, having worked since the night before: the heading is small on
        // purpose, and carried_in is what lets the popover say why.
        let json = """
        {
          "state": "operating", "recording": true,
          "session": {
            "open": true, "paused": false,
            "start_unix": 1789086400, "end_unix": 1789088200,
            "start": "05:00", "end": "05:30",
            "carried_in": true, "carried_out": false,
            "active_seconds": 1800, "operating_seconds": 1800, "present_seconds": 0,
            "breaks": []
          },
          "day": { "date": "2026-09-13", "active_seconds": 1800 }
        }
        """.data(using: .utf8)!
        let n = try JSONDecoder().decode(NowReport.self, from: json)
        XCTAssertEqual(n.session?.carriedIn, true)
        XCTAssertEqual(n.session?.carriedOut, false)
        XCTAssertEqual(n.session?.activeSeconds, 1800)
        XCTAssertEqual(n.day.date, "2026-09-13")
    }

}
