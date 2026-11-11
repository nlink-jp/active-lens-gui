import XCTest
@testable import ActiveLens

final class ShadingTests: XCTestCase {
    private func seg(_ start: Int, _ end: Int, _ state: String) throws -> TimelineSegment {
        let json = """
        {"start_unix": \(start), "end_unix": \(end), "start": "", "end": "", "state": "\(state)"}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(TimelineSegment.self, from: json)
    }

    func testSharesFollowTheSegmentsInEachSlice() throws {
        // One hour: 30 min operating, then 15 present + 15 away.
        let segs = [try seg(0, 1800, "operating"), try seg(1800, 2700, "present"), try seg(2700, 3600, "away")]
        let m = Shading.mixes(segments: segs, startUnix: 0, endUnix: 3600, sliceSeconds: 1800)
        XCTAssertEqual(m, [
            StateMix(operating: 1, present: 0, away: 0),
            StateMix(operating: 0, present: 0.5, away: 0.5),
        ])
    }

    func testFlickerBlendsInsteadOfStriping() throws {
        // Alternating one-minute operating/present: every slice is half and half.
        let segs = try (0..<60).map { try seg($0 * 60, ($0 + 1) * 60, $0 % 2 == 0 ? "operating" : "present") }
        let m = Shading.mixes(segments: segs, startUnix: 0, endUnix: 3600, sliceSeconds: 1800)
        XCTAssertEqual(m.count, 2)
        for mix in m {
            XCTAssertEqual(mix.operating, 0.5, accuracy: 1e-9)
            XCTAssertEqual(mix.present, 0.5, accuracy: 1e-9)
            XCTAssertEqual(mix.away, 0, accuracy: 1e-9)
        }
    }

    func testShortBlockIsOneSliceAndUncoveredTimeIsAway() throws {
        let segs = [try seg(0, 300, "operating")]
        let m = Shading.mixes(segments: segs, startUnix: 0, endUnix: 600, sliceSeconds: 1800)
        XCTAssertEqual(m, [StateMix(operating: 0.5, present: 0, away: 0.5)])
    }

    func testSegmentsOutsideTheBlockAreIgnoredAndEmptySpanYieldsNothing() throws {
        let segs = [try seg(0, 1800, "operating"), try seg(1800, 3600, "present")]
        let m = Shading.mixes(segments: segs, startUnix: 1800, endUnix: 3600, sliceSeconds: 1800)
        XCTAssertEqual(m, [StateMix(operating: 0, present: 1, away: 0)])
        XCTAssertTrue(Shading.mixes(segments: segs, startUnix: 10, endUnix: 10).isEmpty)
    }

    func testStopsSitAtSliceCentres() {
        XCTAssertEqual(Shading.stopLocations(count: 2), [0.25, 0.75])
        XCTAssertEqual(Shading.stopLocations(count: 1), [0.5])
        XCTAssertTrue(Shading.stopLocations(count: 0).isEmpty)
    }
}
