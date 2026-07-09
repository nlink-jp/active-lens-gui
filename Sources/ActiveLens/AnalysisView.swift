import Charts
import SwiftUI

/// The analysis window: a calendar-style work timeline — one column per day, time
/// running down each column (morning at top) — so you can scan across days and
/// see *when* you started, took breaks, and finished. Plus a per-day work-log
/// list. Data comes from `active-lens timeline --json`.
struct AnalysisView: View {
    @EnvironmentObject var model: ActivityModel

    private var days: [TimelineDay] { model.timeline?.days ?? [] }

    var body: some View {
        VStack(spacing: 14) {
            header
            timelineBox
            logBox
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Period", selection: $model.period) {
                    Text("7 days").tag("7d")
                    Text("30 days").tag("30d")
                    Text("90 days").tag("90d")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button { model.loadAnalysis() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .onChange(of: model.period) { _, _ in model.loadAnalysis() }
        .onAppear { model.loadAnalysis() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(periodLabel).font(.headline)
            Spacer()
            let workDays = days.filter(\.hasWork)
            if !workDays.isEmpty {
                let active = workDays.reduce(0) { $0 + $1.activeSeconds }
                Text("\(workDays.count) work days · active \(Format.duration(active))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var periodLabel: String {
        if model.period.hasSuffix("d"), let n = Int(model.period.dropLast()) {
            return "Last \(n) days"
        }
        return "Selected period"
    }

    // MARK: - Timeline (day columns)

    private var timelineBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("When you were at the machine")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if days.isEmpty {
                    emptyChart.frame(height: 260)
                } else {
                    GeometryReader { geo in
                        let needed = CGFloat(days.count) * 46
                        if needed > geo.size.width {
                            // Only scroll (and show the indicator) when the columns
                            // actually overflow — otherwise it left a scrollbar ghost.
                            ScrollView(.horizontal, showsIndicators: true) {
                                timelineChart.frame(width: needed, height: geo.size.height)
                            }
                        } else {
                            timelineChart.frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .frame(height: 260)
                }
            }
        }
    }

    private var timelineChart: some View {
        Chart(segmentPoints) { p in
            BarMark(
                x: .value("Day", p.date),
                yStart: .value("Start", p.startHour),
                yEnd: .value("End", p.endHour),
                width: .ratio(0.7)
            )
            .foregroundStyle(by: .value("State", p.stateLabel))
        }
        .chartForegroundStyleScale(domain: ActivityPalette.chartDomain, range: ActivityPalette.chartRange)
        .chartXScale(domain: days.map(\.date)) // oldest left, newest right
        // Inverted y (descending domain) puts morning at the top, like a calendar.
        // The ±0.4h padding keeps the top/bottom hour labels off the edge so they
        // aren't clipped.
        .chartYScale(domain: [hoursBounds.hi + 0.4, hoursBounds.lo - 0.4])
        .chartXAxis {
            AxisMarks(values: xTicks) { value in
                AxisTick()
                if let s = value.as(String.self) {
                    AxisValueLabel(Format.shortDay(s), orientation: .vertical)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: hourTicks) { value in
                AxisGridLine()
                if let h = value.as(Double.self) {
                    AxisValueLabel { Text(String(format: "%d:00", Int(h.rounded()))) }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
    }

    // MARK: - Chart data & scales

    /// One vertical span in a day column. Precomputed (a single flat array) so the
    /// Chart body type-checks quickly.
    struct SegPoint: Identifiable {
        let id: String
        let date: String
        let stateLabel: String
        let startHour: Double
        let endHour: Double
    }

    private var segmentPoints: [SegPoint] {
        days.flatMap { day in
            day.segments.map { seg in
                SegPoint(
                    id: "\(day.date)-\(seg.startUnix)-\(seg.state)",
                    date: day.date,
                    stateLabel: seg.activityState.label,
                    startHour: day.hours(seg.startUnix),
                    endHour: day.hours(seg.endUnix))
            }
        }
    }

    /// Auto-fit the time (y) axis to the hours actually worked (padded, 0…24).
    private var hoursBounds: (lo: Double, hi: Double) {
        let work = days.filter(\.hasWork)
        let starts = work.map { $0.hours($0.workStartUnix) }
        let ends = work.map { $0.hours($0.workEndUnix) }
        guard let lo = starts.min(), let hi = ends.max(), lo < hi else { return (0, 24) }
        return (max(0, (lo - 0.5).rounded(.down)), min(24, (hi + 0.5).rounded(.up)))
    }

    private var hourTicks: [Double] {
        let (lo, hi) = hoursBounds
        let step = (hi - lo) > 10 ? 3.0 : 2.0
        var ticks: [Double] = []
        var h = lo.rounded(.up)
        while h <= hi {
            ticks.append(h)
            h += step
        }
        return ticks
    }

    /// Thin the day (x) labels to ~12 so long ranges don't crowd.
    private var xTicks: [String] {
        let keys = days.map(\.date)
        guard keys.count > 12 else { return keys }
        let step = Int(ceil(Double(keys.count) / 12))
        var out: [String] = []
        var i = 0
        while i < keys.count {
            out.append(keys[i])
            i += step
        }
        if let last = keys.last, out.last != last { out.append(last) }
        return out
    }

    // MARK: - Per-day work log

    private var logBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Work log").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if days.isEmpty {
                    emptyChart
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(days.reversed()) { day in
                                logRow(day)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logRow(_ d: TimelineDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Format.shortDay(d.date)).font(.callout.monospacedDigit()).frame(width: 52, alignment: .leading)
            if d.hasWork {
                Text("\(d.workStart) → \(d.workEnd)").font(.callout.monospacedDigit())
                Text("active \(Format.duration(d.activeSeconds))")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if d.breaks.isEmpty {
                    Text("no breaks").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("\(d.breaks.count) break\(d.breaks.count > 1 ? "s" : "") · \(Format.duration(d.breaks.reduce(0) { $0 + $1.seconds }))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text("no activity").font(.callout).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.vertical, 1)
    }

    private var emptyChart: some View {
        HStack { Spacer(); Text("No data").foregroundStyle(.secondary); Spacer() }
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
