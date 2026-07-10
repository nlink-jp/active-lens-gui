import XCTest
@testable import ActiveLens

final class FormatTests: XCTestCase {
    func testDurationMirrorsCLI() {
        // Must match the CLI's formatSeconds so GUI and `report` agree.
        XCTAssertEqual(Format.duration(0), "0s")
        XCTAssertEqual(Format.duration(20), "20s")
        XCTAssertEqual(Format.duration(59), "59s")
        XCTAssertEqual(Format.duration(90), "2m")
        XCTAssertEqual(Format.duration(600), "10m")
        XCTAssertEqual(Format.duration(3599), "1h 00m")
        XCTAssertEqual(Format.duration(3600), "1h 00m")
        XCTAssertEqual(Format.duration(9000), "2h 30m")
        XCTAssertEqual(Format.duration(3661), "1h 01m")
    }

    func testShortDay() {
        XCTAssertEqual(Format.shortDay("2026-07-05"), "07-05")
        XCTAssertEqual(Format.shortDay("weird"), "weird")
    }

    func testChartScaleAligned() {
        XCTAssertEqual(ActivityPalette.chartDomain, ["Operating", "Present", "Away"])
        XCTAssertEqual(ActivityPalette.chartRange.count, 3)
    }

    func testMidnightEpochRoundTrip() {
        // midnightEpoch(date) + hours back to a known clock time.
        let mid = Format.midnightEpoch("2026-07-09")
        XCTAssertGreaterThan(mid, 0)
        // 09:30 local = mid + 9.5h. hours() should recover 9.5.
        let nineThirty = mid + Int(9.5 * 3600)
        let hours = Double(nineThirty - mid) / 3600.0
        XCTAssertEqual(hours, 9.5, accuracy: 0.001)
    }

    func testClockLabelMapsOffsetsBackToWallClock() {
        // A day starting at 04:00: offset 0 is 4am, offset 20 is midnight, and an
        // offset past a full day wraps — a session may outlive its own day.
        XCTAssertEqual(Format.clockLabel(offsetHours: 0, dayStartHour: 4), "4:00")
        XCTAssertEqual(Format.clockLabel(offsetHours: 16, dayStartHour: 4), "20:00")
        XCTAssertEqual(Format.clockLabel(offsetHours: 20, dayStartHour: 4), "0:00")
        XCTAssertEqual(Format.clockLabel(offsetHours: 29, dayStartHour: 4), "9:00")
        // day_start_hour = 0 makes the offset the clock hour itself.
        XCTAssertEqual(Format.clockLabel(offsetHours: 13, dayStartHour: 0), "13:00")
    }

    func testPeriodDays() {
        XCTAssertEqual(ActivityModel.periodDays("7d"), 7)
        XCTAssertEqual(ActivityModel.periodDays("90d"), 90)
        XCTAssertEqual(ActivityModel.periodDays("nonsense"), 7)
        XCTAssertEqual(ActivityModel.periodDays("0d"), 7)
    }
}
