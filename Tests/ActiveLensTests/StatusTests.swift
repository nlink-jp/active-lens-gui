import XCTest
@testable import ActiveLens

final class StatusTests: XCTestCase {
    private func status(loaded: Bool, interval: Int, lastUnix: Int) -> DaemonStatus {
        DaemonStatus(
            daemonInstalled: loaded, daemonLoaded: loaded, dbPath: "/x",
            intervalSeconds: interval, thresholdSeconds: 30, maxGapSeconds: interval * 3,
            lastSampleUnix: lastUnix, lastSampleState: "operating")
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

    func testCalendarSinceSpansNCalendarDays() {
        let tz = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_783_600_000) // fixed instant
        let since = ActivityModel.calendarSince("7d", from: now, tz: tz)
        // 7d window: start is 6 days before today's date.
        XCTAssertEqual(since.count, 10) // YYYY-MM-DD
        XCTAssertEqual(ActivityModel.calendarSince("bogus", from: now, tz: tz), "bogus")
    }

    func testSummarizeErrors() {
        XCTAssertTrue(CLIError.summarize(exitCode: 1, crashed: true, stderr: "").contains("stopped unexpectedly"))
        XCTAssertTrue(CLIError.summarize(exitCode: 1, crashed: false, stderr: "permission denied").contains("denied"))
        XCTAssertTrue(CLIError.summarize(exitCode: 2, crashed: false, stderr: "boom").contains("boom"))
    }
}
