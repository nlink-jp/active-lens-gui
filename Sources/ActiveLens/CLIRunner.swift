import Foundation

enum CLIError: LocalizedError {
    case binaryNotFound
    case launchFailed(detail: String)
    case runFailed(summary: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "active-lens CLI not found. Reinstall ActiveLens.app (the CLI ships bundled), or install active-lens on your PATH."
        case .launchFailed:
            return "Couldn't start the active-lens CLI. Reinstall the app if this keeps happening."
        case .runFailed(let summary, _):
            return summary
        }
    }

    var failureReason: String? {
        switch self {
        case .binaryNotFound: return nil
        case .launchFailed(let d): return d.isEmpty ? nil : d
        case .runFailed(_, let d): return d.isEmpty ? nil : d
        }
    }

    /// Translate a CLI failure into a short, actionable summary. Pure (testable);
    /// the raw stderr stays available separately as the detail.
    static func summarize(exitCode: Int32, crashed: Bool, stderr: String) -> String {
        let s = stderr.lowercased()
        if crashed {
            return "The active-lens CLI stopped unexpectedly. Try Refresh; if it keeps happening, reinstall the app."
        }
        if s.contains("permission denied") || s.contains("operation not permitted") {
            return "The CLI was denied access it needed. Reinstall the app if this keeps happening."
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "The active-lens CLI exited with an error (code \(exitCode))."
        }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return "The active-lens CLI reported: \(firstLine)"
    }
}

/// CLIRunner locates and invokes the active-lens CLI, decoding its --json output.
/// The CLI is the single source of truth for sampling, storage, and aggregation;
/// this GUI is a thin front-end over it.
enum CLIRunner {
    /// Resolve the CLI binary. The **bundled** copy in the .app's Resources is the
    /// trust anchor: it ships Developer-ID signed + notarized, so it can't be
    /// swapped without invalidating the signature. In a release build it comes
    /// first and no environment variable can redirect execution. In DEBUG builds
    /// the `$ACTIVE_LENS_BIN` override and the local dev path are honored.
    static func findBinary() -> String? {
        var allowEnvOverride = false
        var devPaths: [String] = []
        #if DEBUG
        allowEnvOverride = true
        devPaths = [NSHomeDirectory() + "/works/nlink-jp/_wip/active-lens/dist/active-lens"]
        #endif
        return resolveBinary(
            env: ProcessInfo.processInfo.environment,
            allowEnvOverride: allowEnvOverride,
            bundled: Bundle.main.resourceURL?.appendingPathComponent("active-lens").path,
            devPaths: devPaths,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    /// Pure resolution logic (injectable for tests). Order:
    ///   [env, only if allowEnvOverride] → bundled → /usr/local, /opt/homebrew → [devPaths]
    static func resolveBinary(
        env: [String: String],
        allowEnvOverride: Bool,
        bundled: String?,
        devPaths: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        var order: [String] = []
        if allowEnvOverride, let p = env["ACTIVE_LENS_BIN"] {
            order.append(p)
        }
        if let bundled {
            order.append(bundled)
        }
        order += ["/usr/local/bin/active-lens", "/opt/homebrew/bin/active-lens"]
        order += devPaths
        return order.first(where: isExecutable)
    }

    @discardableResult
    static func run(_ args: [String]) throws -> Data {
        guard let bin = findBinary() else { throw CLIError.binaryNotFound }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw CLIError.launchFailed(detail: error.localizedDescription)
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let stderr = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let crashed = proc.terminationReason == .uncaughtSignal
            throw CLIError.runFailed(
                summary: CLIError.summarize(exitCode: proc.terminationStatus, crashed: crashed, stderr: stderr),
                detail: stderr
            )
        }
        return data
    }

    // MARK: - Typed queries

    static func today() throws -> Report {
        try JSONDecoder().decode(Report.self, from: run(["today", "--json"]))
    }

    static func report(since: String, until: String? = nil) throws -> Report {
        var args = ["report", "--since", since, "--json"]
        if let until { args += ["--until", until] }
        return try JSONDecoder().decode(Report.self, from: run(args))
    }

    static func status() throws -> DaemonStatus {
        try JSONDecoder().decode(DaemonStatus.self, from: run(["status", "--json"]))
    }

    /// The session in progress right now, plus the logical day it is filed under.
    static func now() throws -> NowReport {
        try JSONDecoder().decode(NowReport.self, from: run(["now", "--json"]))
    }

    /// The last `days` logical days. The CLI resolves the range against its own
    /// day boundary, so this app never reimplements that arithmetic.
    static func timeline(days: Int) throws -> TimelineReport {
        try JSONDecoder().decode(
            TimelineReport.self, from: run(["timeline", "--days", String(days), "--json"]))
    }

    static func timeline(since: String, until: String? = nil) throws -> TimelineReport {
        var args = ["timeline", "--since", since, "--json"]
        if let until { args += ["--until", until] }
        return try JSONDecoder().decode(TimelineReport.self, from: run(args))
    }

    static func install() throws { _ = try run(["install"]) }
    static func uninstall() throws { _ = try run(["uninstall"]) }
}
