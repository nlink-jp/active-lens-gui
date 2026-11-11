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
    func testRunDrainsStderrWhileReadingStdout() throws {
        let noisy = "head -c 300000 /dev/zero | tr '\\0' 'e' >&2; printf ok"
        let out = try CLIRunner.run(executable: "/bin/sh", ["-c", noisy])
        XCTAssertEqual(String(data: out, encoding: .utf8), "ok")

        XCTAssertThrowsError(try CLIRunner.run(executable: "/bin/sh", ["-c", noisy + "; exit 3"])) { error in
            guard case CLIError.runFailed(_, let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(detail.count, 300_000, "the whole of stderr is kept for the detail")
        }
    }
}
