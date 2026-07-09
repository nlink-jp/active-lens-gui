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

    func testDecodeTimeline() throws {
        let mid = Format.midnightEpoch("2026-07-09")
        let start = mid + 9 * 3600      // 09:00
        let end = mid + 18 * 3600       // 18:00
        let json = """
        {
          "since": "2026-07-09", "until": "2026-07-09", "timezone": "Local",
          "sample_count": 100, "break_threshold_seconds": 600,
          "days": [
            {
              "date": "2026-07-09", "has_work": true,
              "work_start_unix": \(start), "work_end_unix": \(end),
              "work_start": "09:00", "work_end": "18:00",
              "operating_seconds": 20000, "present_seconds": 8000,
              "active_seconds": 28000, "span_seconds": 32400,
              "segments": [
                { "start_unix": \(start), "end_unix": \(end), "start": "09:00", "end": "18:00", "state": "operating" }
              ],
              "breaks": [
                { "start_unix": \(mid + 12*3600), "end_unix": \(mid + 13*3600), "start": "12:00", "end": "13:00", "seconds": 3600 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        let tl = try JSONDecoder().decode(TimelineReport.self, from: json)
        XCTAssertEqual(tl.days.count, 1)
        let d = tl.days[0]
        XCTAssertTrue(d.hasWork)
        XCTAssertEqual(d.workStart, "09:00")
        XCTAssertEqual(d.breaks.count, 1)
        XCTAssertEqual(d.segments.first?.activityState, .operating)
        // hours() maps the work start to 9.0 on the day's 0…24 axis.
        XCTAssertEqual(d.hours(start), 9.0, accuracy: 0.001)
        XCTAssertEqual(d.hours(end), 18.0, accuracy: 0.001)
    }
}
