import Foundation

/// ActivityModel drives the UI: it periodically pulls today's work-log timeline +
/// daemon status for the menu bar / popover, and loads the range timeline for the
/// analysis window on demand. All CLI work runs off the main thread; @Published
/// mutations hop back to main.
final class ActivityModel: ObservableObject {
    @Published var todayTimeline: TimelineDay?
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

    /// Today's active (operating + present) time — the menu-bar headline.
    var todayActiveLabel: String {
        guard let d = todayTimeline, d.hasWork else {
            return lastError != nil ? "—" : "0s"
        }
        return Format.duration(d.activeSeconds)
    }

    /// The SF Symbol + tint reflecting the current live state (or idle look).
    var currentState: ActivityState? { status?.currentState }

    func start() {
        // Opt out of App Nap so the 60s timer keeps firing while the app sits in
        // the menu bar. System sleep is still allowed.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "activity monitoring")
        refreshToday()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshToday()
        }
    }

    /// Pull today's work-log timeline and the daemon status for the menu bar +
    /// popover.
    func refreshToday() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let today = Self.todayString()
                let tl = try CLIRunner.timeline(since: today)
                let status = try CLIRunner.status()
                let day = tl.days.first(where: { $0.date == today }) ?? tl.days.last
                DispatchQueue.main.async {
                    self.todayTimeline = day
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
    func loadAnalysis() {
        let period = self.period
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let since = Self.calendarSince(period)
                let tl = try CLIRunner.timeline(since: since)
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

    /// Today's date as YYYY-MM-DD in the local zone.
    static func todayString(from now: Date = Date(), tz: TimeZone = .current) -> String {
        calendarSince("1d", from: now, tz: tz)
    }

    /// Turn a "Nd" period into a YYYY-MM-DD start date (today − (N−1) days) in the
    /// local zone, so a daily series spans exactly N calendar days aligned to the
    /// CLI's day buckets. Non-"Nd" periods pass through. Injectable for tests.
    static func calendarSince(_ period: String, from now: Date = Date(), tz: TimeZone = .current) -> String {
        guard period.hasSuffix("d"), let n = Int(period.dropLast()), n > 0 else { return period }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.date(byAdding: .day, value: -(n - 1), to: cal.startOfDay(for: now)) ?? now
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: start)
    }
}
