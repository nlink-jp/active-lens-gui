import XCTest
@testable import ActiveLens

final class BinaryResolutionTests: XCTestCase {
    /// The bundled (signed) binary wins over install locations, and a poisoned
    /// env override is ignored unless explicitly allowed (DEBUG only).
    func testBundledPreferredOverEnvWhenOverrideDisallowed() {
        let got = CLIRunner.resolveBinary(
            env: ["ACTIVE_LENS_BIN": "/evil/active-lens"],
            allowEnvOverride: false,
            bundled: "/App.app/Contents/Resources/active-lens",
            devPaths: [],
            isExecutable: { _ in true }
        )
        XCTAssertEqual(got, "/App.app/Contents/Resources/active-lens")
    }

    func testEnvOverrideHonoredWhenAllowed() {
        let got = CLIRunner.resolveBinary(
            env: ["ACTIVE_LENS_BIN": "/dev/active-lens"],
            allowEnvOverride: true,
            bundled: "/App.app/Contents/Resources/active-lens",
            devPaths: [],
            isExecutable: { _ in true }
        )
        XCTAssertEqual(got, "/dev/active-lens")
    }

    func testFallsBackToInstallLocations() {
        let got = CLIRunner.resolveBinary(
            env: [:],
            allowEnvOverride: false,
            bundled: nil,
            devPaths: [],
            isExecutable: { $0 == "/opt/homebrew/bin/active-lens" }
        )
        XCTAssertEqual(got, "/opt/homebrew/bin/active-lens")
    }

    func testNilWhenNothingExecutable() {
        let got = CLIRunner.resolveBinary(
            env: [:], allowEnvOverride: true, bundled: "/x", devPaths: ["/y"],
            isExecutable: { _ in false }
        )
        XCTAssertNil(got)
    }

    // A child that writes more than a pipe holds to stderr must not hang the
    // call, whether it then succeeds or fails.
    //
    // The calls run off the test's thread with a deadline: the defect this
    // guards against is a deadlock, and a deadlock inline would hang the suite
    // instead of failing the test.
    func testRunDrainsStderrWhileReadingStdout() throws {
        let noisy = "head -c 300000 /dev/zero | tr '\\0' 'e' >&2; printf ok"
        let finished = expectation(description: "both calls return")
        DispatchQueue.global().async {
            let out = try? CLIRunner.run(executable: "/bin/sh", ["-c", noisy])
            XCTAssertEqual(out.flatMap { String(data: $0, encoding: .utf8) }, "ok")

            do {
                _ = try CLIRunner.run(executable: "/bin/sh", ["-c", noisy + "; exit 3"])
                XCTFail("a non-zero exit did not throw")
            } catch CLIError.runFailed(_, let detail) {
                XCTAssertEqual(detail.count, 300_000, "the whole of stderr is kept for the detail")
            } catch {
                XCTFail("unexpected error: \(error)")
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 20)
    }

    // A grandchild that keeps stderr open must not hold the call past the
    // child's exit by more than the drain's grace period.
    func testRunDoesNotWaitForeverOnAStderrHeldOpen() throws {
        let finished = expectation(description: "the call returns")
        DispatchQueue.global().async {
            let out = try? CLIRunner.run(executable: "/bin/sh", ["-c", "(sleep 30 >/dev/null) & printf ok"])
            XCTAssertEqual(out.flatMap { String(data: $0, encoding: .utf8) }, "ok")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 15)
    }
}
