import Charts
import SwiftUI

/// The analysis window: a calendar-style work timeline — one column per logical
/// day, time running down each column (the day's start at top) — so you can scan
/// across days and see *when* you started, took breaks, and finished. Plus a
/// per-day work-log list. Data comes from `active-lens timeline --json`.
struct AnalysisView: View {
    @EnvironmentObject var model: ActivityModel
    @State private var hover: HoverInfo?

    private var days: [TimelineDay] { model.timeline?.days ?? [] }

    /// The hour a logical day begins at, from the payload. Chart offsets are
    /// measured from it; axis labels are mapped back to wall clock through it.
    private var dayStartHour: Int { model.timeline?.dayStartHour ?? 0 }

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
        // Inverted y (descending domain) puts the start of the day at the top, like
        // a calendar. The ±0.4h padding keeps the top/bottom hour labels off the
        // edge so they aren't clipped.
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
                    AxisValueLabel { Text(Format.clockLabel(offsetHours: h, dayStartHour: dayStartHour)) }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): hover = hoverInfo(at: point, proxy: proxy, geo: geo)
                        case .ended: hover = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let hover {
                blockTooltip(hover)
                    .offset(x: hover.cardX, y: hover.cardY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Hover

    /// What the pointer is over, plus where to draw the card.
    struct HoverInfo: Equatable {
        let date: String
        let block: TimelineBlock
        let cardX: CGFloat
        let cardY: CGFloat
    }

    private static let cardSize = CGSize(width: 190, height: 96)

    /// Map a pointer position to the block under it. Blocks — not raw segments —
    /// because at 260pt over ~13 hours one minute is about a third of a point, so a
    /// two-minute `present` segment is sub-pixel and cannot be aimed at.
    private func hoverInfo(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> HoverInfo? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let rect = geo[plotFrame]
        guard rect.contains(point) else { return nil }

        let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        guard let date: String = proxy.value(atX: local.x),
              let hours: Double = proxy.value(atY: local.y),
              let day = days.first(where: { $0.date == date }),
              let block = day.block(atHours: hours)
        else { return nil }

        // Keep the card inside the chart: flip it left / up near the far edges.
        let size = Self.cardSize
        let x = min(max(point.x + 12, 0), max(geo.size.width - size.width, 0))
        let y = min(max(point.y + 12, 0), max(geo.size.height - size.height, 0))
        return HoverInfo(date: date, block: block, cardX: x, cardY: y)
    }

    @ViewBuilder
    private func blockTooltip(_ h: HoverInfo) -> some View {
        let b = h.block
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(b.kind == .work ? ActivityPalette.color(.operating) : ActivityPalette.color(.away))
                    .frame(width: 7, height: 7)
                Text(b.kind == .work ? "Work" : "Break").font(.caption.weight(.semibold))
                Spacer()
                Text(Format.shortDay(h.date)).font(.caption2).foregroundStyle(.secondary)
            }
            Text("\(b.start) – \(b.end)").font(.callout.monospacedDigit())
            Text(Format.duration(b.seconds)).font(.caption).foregroundStyle(.secondary)
            if b.kind == .work {
                HStack(spacing: 10) {
                    splitLabel("Operating", b.operatingSeconds, .operating)
                    splitLabel("Present", b.presentSeconds, .present)
                }
                .font(.caption2)
            }
        }
        .padding(8)
        .frame(width: Self.cardSize.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .shadow(radius: 3, y: 1)
    }

    private func splitLabel(_ title: String, _ seconds: Int, _ state: ActivityState) -> some View {
        HStack(spacing: 4) {
            Circle().fill(ActivityPalette.color(state)).frame(width: 5, height: 5)
            Text(title).foregroundStyle(.secondary)
            Text(Format.duration(seconds)).monospacedDigit()
        }
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

    /// Auto-fit the time (y) axis to the hours actually worked. The upper bound is
    /// deliberately *not* clamped to 24: a session that ran through the next day's
    /// boundary is filed here whole, and clipping it would hide the very spans the
    /// engine keeps intact.
    private var hoursBounds: (lo: Double, hi: Double) {
        let work = days.filter(\.hasWork)
        let starts = work.map { $0.hours($0.workStartUnix) }
        let ends = work.map { $0.hours($0.workEndUnix) }
        guard let lo = starts.min(), let hi = ends.max(), lo < hi else { return (0, 24) }
        return (max(0, (lo - 0.5).rounded(.down)), (hi + 0.5).rounded(.up))
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
                // A session that ran past midnight ends on the next calendar day;
                // "22:00 → 01:00" would otherwise read as a 21-hour backwards span.
                Text("\(d.workStart) → \(d.workEnd)\(Format.nextDayMark(d))")
                    .font(.callout.monospacedDigit())
                Text("active \(Format.duration(d.activeSeconds))")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if d.sessions.count > 1 {
                    Text("\(d.sessions.count) sessions").font(.caption2).foregroundStyle(.tertiary)
                }
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
