import Foundation

/// ActivityModel drives the UI: it periodically pulls the now-session + daemon
/// status for the menu bar / popover, and loads the range timeline for the
/// analysis window on demand. All CLI work runs off the main thread; @Published
/// mutations hop back to main.
final class ActivityModel: ObservableObject {
    @Published var now: NowReport?
    @Published var status: DaemonStatus?
    @Published var lastError: String?
    @Published var lastErrorDetail: String?
    @Published var lastUpdated: Date?

    // Analysis window state
    @Published var period: String = "7d"
    @Published var timeline: TimelineReport?

    private var timer: Timer?
    private var activity: NSObjectProtocol?  // App Nap opt-out (held for the app's lifetime)
    private let queue = DispatchQueue(label: "jp.nlink.active-lens-gui.cli", qos: .utility)

    /// The current session's active time — the menu-bar headline. It answers "how
    /// long this stretch", so it resets when a new session opens (e.g. after a
    /// night's sleep). The logical day's total lives in the popover's Today row.
    var sessionActiveLabel: String {
        guard let s = now?.session else {
            return lastError != nil ? "—" : "0s"
        }
        return Format.duration(s.activeSeconds)
    }

    /// The SF Symbol + tint reflecting the current live state (or idle look).
    var currentState: ActivityState? { now?.currentState }

    func start() {
        // Opt out of App Nap so the 60s timer keeps firing while the app sits in
        // the menu bar. System sleep is still allowed.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "activity monitoring")
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }

    /// Pull the now-session and the daemon status for the menu bar + popover.
    func refreshNow() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let now = try CLIRunner.now()
                let status = try CLIRunner.status()
                DispatchQueue.main.async {
                    self.now = now
                    self.status = status
                    self.lastError = nil
                    self.lastErrorDetail = nil
                    self.lastUpdated = Date()
                }
            } catch {
                self.setError(error)
            }
        }
    }

    /// Load the range timeline for the analysis window over the current period.
    /// The CLI resolves the range against its own logical day boundary.
    func loadAnalysis() {
        let days = Self.periodDays(period)
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let tl = try CLIRunner.timeline(days: days)
                DispatchQueue.main.async {
                    self.timeline = tl
                    self.lastError = nil
                    self.lastErrorDetail = nil
                }
            } catch {
                self.setError(error)
            }
        }
    }

    /// Enable (install) or disable (uninstall) the login-time sampling daemon,
    /// then refresh status. Background CLI call.
    func setDaemonEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if enabled { try CLIRunner.install() } else { try CLIRunner.uninstall() }
                let status = try CLIRunner.status()
                DispatchQueue.main.async {
                    self.status = status
                    self.lastError = nil
                    self.lastErrorDetail = nil
                }
            } catch {
                self.setError(error)
            }
        }
    }

    private func setError(_ error: Error) {
        let summary = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        let detail = (error as? CLIError)?.failureReason
        DispatchQueue.main.async { [weak self] in
            self?.lastError = summary
            self?.lastErrorDetail = detail
        }
    }

    /// Turn a "Nd" period into a day count for `timeline --days`. Unknown periods
    /// fall back to a week. Pure; injectable for tests.
    static func periodDays(_ period: String) -> Int {
        guard period.hasSuffix("d"), let n = Int(period.dropLast()), n > 0 else { return 7 }
        return n
    }
}
