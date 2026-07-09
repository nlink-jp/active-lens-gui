import AppKit
import SwiftUI

/// The dropdown shown when the menu-bar item is clicked: today's work log —
/// when you started, active time, breaks — plus the current state, the
/// background-recording toggle, and buttons to open Analysis / refresh / quit.
struct PopoverView: View {
    @EnvironmentObject var model: ActivityModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today").font(.headline)

            if let d = model.todayTimeline, d.hasWork {
                workSession(d)
            } else if let err = model.lastError {
                errorBlock(err)
            } else if model.todayTimeline != nil {
                Text("No activity recorded today yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 60)
            }

            Divider()
            currentStatusLine
            daemonSection

            if let ts = model.lastUpdated {
                Text("Updated \(ts.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Divider()
            HStack {
                Button("Analysis…") {
                    model.loadAnalysis()
                    openWindow(id: "analysis")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Refresh") { model.refreshToday() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refreshToday() }
    }

    // MARK: - Today's work session

    @ViewBuilder
    private func workSession(_ d: TimelineDay) -> some View {
        Text(Format.duration(d.activeSeconds))
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
        HStack(spacing: 6) {
            Text("active").foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Text("started \(d.workStart)")
            if model.currentState == nil || model.currentState == .away {
                Text("· ended \(d.workEnd)").foregroundStyle(.secondary)
            }
        }
        .font(.callout)

        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
            metricRow("Operating", Format.duration(d.operatingSeconds), .operating)
            metricRow("Present", Format.duration(d.presentSeconds), .present)
            if !d.breaks.isEmpty {
                GridRow {
                    Text("Breaks").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(d.breaks.count) · \(Format.duration(d.breaks.reduce(0) { $0 + $1.seconds }))")
                        .monospacedDigit().gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)

        if !d.breaks.isEmpty {
            Text(d.breaks.map { "\($0.start)–\($0.end)" }.joined(separator: "   "))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func metricRow(_ label: String, _ value: String, _ state: ActivityState) -> some View {
        GridRow {
            HStack(spacing: 6) {
                Circle().fill(ActivityPalette.color(state)).frame(width: 8, height: 8)
                Text(label).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }

    // MARK: - Current status & daemon

    @ViewBuilder
    private var currentStatusLine: some View {
        if let s = model.currentState {
            HStack(spacing: 6) {
                Image(systemName: s.icon).foregroundStyle(ActivityPalette.color(s))
                Text("Currently \(s.label.lowercased())").font(.callout)
            }
        }
    }

    @ViewBuilder
    private var daemonSection: some View {
        let recording = model.status?.isRecording() ?? false
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { model.status?.daemonLoaded ?? false },
                set: { model.setDaemonEnabled($0) }
            )) {
                Text("Record in background").font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack(spacing: 6) {
                Circle().fill(recording ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(recordingLabel).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var recordingLabel: String {
        guard let s = model.status else { return "status unknown" }
        if s.isRecording() {
            return s.daemonLoaded ? "Recording — starts at login" : "Recording"
        }
        if s.daemonLoaded { return "Enabled, waiting for first sample…" }
        return "Not recording (enable to track usage)"
    }

    @ViewBuilder
    private func errorBlock(_ err: String) -> some View {
        Label("Couldn't load activity", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        Text(err).font(.callout).fixedSize(horizontal: false, vertical: true)
        if let detail = model.lastErrorDetail {
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(3).textSelection(.enabled)
        }
    }
}
