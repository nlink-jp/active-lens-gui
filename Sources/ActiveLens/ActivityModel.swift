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
    @Published var period: Period = .lastDays(7)
    @Published var timeline: TimelineReport?
    /// The period `timeline` was loaded for. The header names the data on screen,
    /// which lags the picker until the CLI answers.
    @Published var timelinePeriod: Period?

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
        let period = self.period
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let tl = try CLIRunner.timeline(period)
                DispatchQueue.main.async {
                    // A slower answer for a period the picker has already left
                    // must not replace the newer one.
                    guard self.period == period else { return }
                    self.timeline = tl
                    self.timelinePeriod = period
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

}

/// A period of the analysis window. The CLI resolves each against its own logical
/// day boundary (`timeline --days N` / `timeline --month`), so this app never
/// does date arithmetic.
enum Period: Hashable {
    /// The last N logical days, ending now.
    case lastDays(Int)
    /// The current month: its first logical day through now. The month is the
    /// logical day's, so just after midnight on the 1st it is still last month.
    case thisMonth
    /// The whole of the month before `thisMonth`.
    case lastMonth

    /// The choices offered in the picker, in order. The two months read left to
    /// right in time, as the chart's columns do.
    static let choices: [Period] = [.lastDays(7), .lastDays(30), .lastDays(90), .lastMonth, .thisMonth]

    var pickerLabel: String {
        switch self {
        case .lastDays(let n): return "\(n) days"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        }
    }

    /// The `timeline` arguments asking the CLI for this period. Pure.
    var timelineArgs: [String] {
        switch self {
        case .lastDays(let n): return ["timeline", "--days", String(max(n, 1)), "--json"]
        case .thisMonth: return ["timeline", "--month", "--json"]
        case .lastMonth: return ["timeline", "--last-month", "--json"]
        }
    }

    /// The header for a timeline loaded for this period. `since` is the
    /// timeline's first logical day, which names the month — the CLI's month,
    /// not one recomputed here. Pure.
    func title(since: String?) -> String {
        switch self {
        case .lastDays(let n):
            return "Last \(n) days"
        case .thisMonth, .lastMonth:
            guard let since, let month = Format.monthTitle(since) else {
                return pickerLabel
            }
            return "\(pickerLabel) · \(month)"
        }
    }
}
