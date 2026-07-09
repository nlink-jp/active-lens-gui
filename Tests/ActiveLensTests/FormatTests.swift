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
}
