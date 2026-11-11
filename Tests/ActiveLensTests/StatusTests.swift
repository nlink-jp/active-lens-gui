import XCTest
@testable import ActiveLens

final class StatusTests: XCTestCase {
    private func status(loaded: Bool, interval: Int, lastUnix: Int,
                        dayStartHour: Int? = nil, dayBoundary: String? = nil) -> DaemonStatus {
        DaemonStatus(
            daemonInstalled: loaded, daemonLoaded: loaded, dbPath: "/x",
            intervalSeconds: interval, thresholdSeconds: 30, maxGapSeconds: interval * 3,
            dayStartHour: dayStartHour, dayBoundary: dayBoundary,
            lastSampleUnix: lastUnix, lastSampleState: "operating")
    }

    func testDayBoundaryFieldsAreOptional() {
        // A bundled CLI older than 0.3.0 reports neither; "not strict" is the
        // right reading of that silence, not a crash and not a guess.
        let old = status(loaded: true, interval: 15, lastUnix: 1_000_000)
        XCTAssertFalse(old.cutsSessionsAtDayBoundary)
        XCTAssertNil(old.dayStartLabel)

        let strict = status(loaded: true, interval: 15, lastUnix: 1_000_000,
                            dayStartHour: 5, dayBoundary: "strict")
        XCTAssertTrue(strict.cutsSessionsAtDayBoundary)
        XCTAssertEqual(strict.dayStartLabel, "05:00")
    }

    func testIsRecordingFreshSample() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = status(loaded: true, interval: 15, lastUnix: 1_000_000 - 10) // 10s ago
        XCTAssertTrue(s.isRecording(now: now))
    }

    func testNotRecordingWhenStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // 5 minutes ago, well past 4×interval and the 60s floor.
        let s = status(loaded: true, interval: 15, lastUnix: 1_000_000 - 300)
        XCTAssertFalse(s.isRecording(now: now))
    }

    func testRecordingWhenUnloadedButFresh() {
        // A manually started daemon (no login agent) still counts as recording —
        // isRecording tracks data flow, not the login-item switch.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = status(loaded: false, interval: 15, lastUnix: 1_000_000 - 5)
        XCTAssertTrue(s.isRecording(now: now))
    }

    func testNotRecordingWhenLoadedButStale() {
        // Agent loaded but crashed (no fresh samples) reads as not recording.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = status(loaded: true, interval: 15, lastUnix: 1_000_000 - 300)
        XCTAssertFalse(s.isRecording(now: now))
    }

    // The range is no longer computed here: `timeline --days N` resolves it against
    // the CLI's own logical day boundary. Only the period → N mapping remains, and
    // it is covered by FormatTests.testPeriodDays.

    func testSummarizeErrors() {
        XCTAssertTrue(CLIError.summarize(exitCode: 1, crashed: true, stderr: "").contains("stopped unexpectedly"))
        XCTAssertTrue(CLIError.summarize(exitCode: 1, crashed: false, stderr: "permission denied").contains("denied"))
        XCTAssertTrue(CLIError.summarize(exitCode: 2, crashed: false, stderr: "boom").contains("boom"))
    }

    func testRecordingLabelSaysWhenTheDaemonStateIsUnknown() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        var unknown = status(loaded: false, interval: 15, lastUnix: 1_000_000)
        unknown.daemonStatusError = "launchctl: timed out"
        XCTAssertEqual(unknown.recordingLabel(now: now), "Couldn't check the background recorder")

        // Samples still arriving outrank the failed check: it is recording.
        var live = status(loaded: false, interval: 15, lastUnix: 2_000_000 - 10)
        live.daemonStatusError = "launchctl: timed out"
        XCTAssertEqual(live.recordingLabel(now: now), "Recording")

        let off = status(loaded: false, interval: 15, lastUnix: 1_000_000)
        XCTAssertEqual(off.recordingLabel(now: now), "Not recording (enable to track usage)")
        let waiting = status(loaded: true, interval: 15, lastUnix: 1_000_000)
        XCTAssertEqual(waiting.recordingLabel(now: now), "Enabled, waiting for first sample…")

        // The field is optional on the wire: an older CLI omits it.
        let json = """
        {"daemon_installed": true, "daemon_loaded": false, "db_path": "/x", "interval_seconds": 15,
         "threshold_seconds": 30, "max_gap_seconds": 45, "last_sample_unix": 0, "last_sample_state": "",
         "daemon_status_error": "launchctl: timed out"}
        """.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(DaemonStatus.self, from: json).daemonStatusError, "launchctl: timed out")
    }
}
