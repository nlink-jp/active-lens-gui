import Charts
import SwiftUI

/// The analysis window: a calendar-style work timeline — one column per logical
/// day, time running down each column (the day's start at top) — so you can scan
/// across days and see *when* you started, took breaks, and finished. Plus a
/// per-day work-log list. Data comes from `active-lens timeline --json`.
struct AnalysisView: View {
    @EnvironmentObject var model: ActivityModel
    @State private var hover: HoverInfo?
    /// The chart's marks, rebuilt only when the data or the appearance changes —
    /// not on every pointer move, which re-evaluates the body.
    @State private var blockPoints: [BlockPoint] = []
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    private var days: [TimelineDay] { model.timeline?.days ?? [] }

    /// The hour a logical day begins at, from the payload. Chart offsets are
    /// measured from it; axis labels are mapped back to wall clock through it.
    private var dayStartHour: Int { model.timeline?.dayStartHour ?? 0 }

    var body: some View {
        VStack(spacing: 14) {
            header
            // The chart takes whatever height the window has; the log is a
            // scrolling list, so it is the one held to a fixed height.
            timelineBox
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            logBox
                .frame(height: 196)

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
        .onChange(of: model.timeline, initial: true) { _, _ in blockPoints = makeBlockPoints() }
        .onChange(of: colorScheme) { _, _ in blockPoints = makeBlockPoints() }
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
                // Every period fits the window's width — the columns narrow
                // instead of scrolling, so the time axis and the legend never
                // leave the screen and 90 days read at a glance.
                if days.isEmpty {
                    emptyChart.frame(maxHeight: .infinity)
                } else {
                    timelineChart.frame(minHeight: 160, maxHeight: .infinity)
                    legend
                }
            }
        }
    }

    private var timelineChart: some View {
        Chart(blockPoints) { p in
            BarMark(
                x: .value("Day", p.date),
                yStart: .value("Start", p.startHour),
                yEnd: .value("End", p.endHour),
                width: .ratio(0.72)
            )
            .cornerRadius(1.5) // the default radius turns a narrow column into beads
            .foregroundStyle(p.style)
        }
        .chartXScale(domain: days.map(\.date)) // oldest left, newest right
        // Inverted y (descending domain) puts the start of the day at the top, like
        // a calendar. The ±0.4h padding keeps the top/bottom hour labels off the
        // edge so they aren't clipped.
        .chartYScale(domain: [hoursBounds.hi + 0.4, hoursBounds.lo - 0.4])
        .chartXAxis {
            // The thinned labels are wider than a narrow day column, so each is
            // sized to its text rather than truncated to the column.
            // Filtered inside the closure: for a string axis Charts marks every
            // category whatever `values:` says, which is how 90 days came out as
            // 90 overlapping labels.
            AxisMarks { value in
                if let s = value.as(String.self), xTicks.contains(s) {
                    AxisTick()
                    AxisValueLabel(collisionResolution: .disabled) {
                        Text(Format.shortDay(s)).lineLimit(1).frame(width: 44)
                    }
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
        // Room for the newest day's label, which is wider than its column and
        // would otherwise be cut off at the chart's right edge.
        .padding(.trailing, 16)
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

    /// The three states the gradient blends between. Hand-built: the marks
    /// carry gradients, not a style scale, so Charts has no legend to offer.
    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(ActivityState.allCases) { state in
                HStack(spacing: 4) {
                    Circle().fill(ActivityPalette.chartColor(state)).frame(width: 8, height: 8)
                    Text(state.label)
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
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
    /// because over ~13 hours one minute is a fraction of a point, so a
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

    /// One vertical span in a day column: a work or break block, painted as a
    /// gradient of the states inside it. A day holds a hundred-odd minute-level
    /// segments; drawn one by one they stripe, so each block is one mark whose
    /// colour drifts between operating, present and away as the shares change.
    struct BlockPoint: Identifiable {
        let id: String
        let date: String
        let startHour: Double
        let endHour: Double
        let style: LinearGradient
    }

    private func makeBlockPoints() -> [BlockPoint] {
        days.flatMap { day in
            day.blocks.map { b in
                let mixes = b.kind == .break
                    ? [StateMix.allAway]
                    : Shading.mixes(segments: day.segments, startUnix: b.startUnix, endUnix: b.endUnix)
                return BlockPoint(
                    id: "\(day.date)-\(b.startUnix)",
                    date: day.date,
                    startHour: day.hours(b.startUnix),
                    endHour: day.hours(b.endUnix),
                    style: ActivityPalette.gradient(mixes, in: environment))
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

    private var hourTicks: [Double] { Format.hourTicks(lo: hoursBounds.lo, hi: hoursBounds.hi) }

    private var xTicks: Set<String> { Set(Format.thinned(days.map(\.date), max: 12)) }

    // MARK: - Per-day work log

    private var logBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Work log").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    if let tl = model.timeline, tl.cutsSessionsAtDayBoundary {
                        Text("day starts \(tl.dayStartLabel) · sessions cut at the boundary")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
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

    /// One work-log row. A day bounded by a boundary cut carries a tooltip
    /// explaining the cut; a day that began and ended on real activity gets no
    /// tooltip at all, rather than an empty one.
    @ViewBuilder
    private func logRow(_ d: TimelineDay) -> some View {
        if let note = Format.carryNote(d) {
            logRowContent(d).help(note)
        } else {
            logRowContent(d)
        }
    }

    @ViewBuilder
    private func logRowContent(_ d: TimelineDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Format.shortDay(d.date)).font(.callout.monospacedDigit()).frame(width: 52, alignment: .leading)
            if d.hasWork {
                // A day bounded by a boundary cut is marked, so an 05:00 start is
                // never read as someone sitting down at 05:00; the row's tooltip
                // explains it. The marks sit in fixed-width slots that are present
                // on every row, or the monospaced times would step left and right
                // between carried and ordinary days.
                markSlot(d.carriedIn ? "arrow.turn.down.right" : nil)
                // A session that ran past midnight ends on the next calendar day;
                // "22:00 → 01:00" would otherwise read as a 21-hour backwards span.
                Text("\(d.workStart) → \(d.workEnd)\(Format.nextDayMark(d))")
                    .font(.callout.monospacedDigit())
                markSlot(d.carriedOut ? "arrow.right.to.line" : nil)
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

    /// A fixed-width slot for a carry mark, empty when there is nothing to mark.
    /// Its width is reserved on every row so the time column never shifts.
    private func markSlot(_ symbol: String?) -> some View {
        // An empty slot draws the same symbol invisibly rather than a blank box:
        // it keeps the row's height and text baseline identical to a marked row,
        // which a Color.clear placeholder does not (the rows sat at uneven
        // intervals until this was rendered offscreen and looked at).
        Image(systemName: symbol ?? "arrow.turn.down.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .opacity(symbol == nil ? 0 : 1)
            .frame(width: 12)
    }

    private var emptyChart: some View {
        HStack { Spacer(); Text("No data").foregroundStyle(.secondary); Spacer() }
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
