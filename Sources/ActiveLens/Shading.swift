import SwiftUI

/// The share of each state inside one slice of time. The three sum to 1.
struct StateMix: Equatable {
    var operating: Double
    var present: Double
    var away: Double

    static let allAway = StateMix(operating: 0, present: 0, away: 1)
}

/// Turns a block's minute-level segments into a run of state shares the chart
/// can paint as one continuous gradient. This is drawing resolution, not
/// aggregation: it applies no threshold and decides no state — it only says
/// what fraction of a slice each recorded state covered, the way a pixel
/// covers part of a shape. What a block or a break *is* stays the engine's call.
enum Shading {
    /// Slice length. Thirty minutes was chosen by eye on real data: at ten the
    /// one-minute flicker between operating and present still read as bands;
    /// at thirty a day drifts from one colour to the next.
    static let sliceSeconds = 1800

    /// State shares for `[startUnix, endUnix)` cut into equal slices of about
    /// `sliceSeconds`. Time no segment covers counts as away. Pure.
    static func mixes(
        segments: [TimelineSegment], startUnix: Int, endUnix: Int, sliceSeconds: Int = sliceSeconds
    ) -> [StateMix] {
        let span = endUnix - startUnix
        guard span > 0, sliceSeconds > 0 else { return [] }
        let count = max(1, Int((Double(span) / Double(sliceSeconds)).rounded()))
        let width = Double(span) / Double(count)
        let inside = segments.filter { $0.endUnix > startUnix && $0.startUnix < endUnix }

        return (0..<count).map { i in
            let lo = Double(startUnix) + Double(i) * width
            let hi = lo + width
            var op = 0.0, pr = 0.0
            for seg in inside {
                let overlap = min(Double(seg.endUnix), hi) - max(Double(seg.startUnix), lo)
                guard overlap > 0 else { continue }
                switch seg.activityState {
                case .operating: op += overlap
                case .present: pr += overlap
                case .away: break
                }
            }
            let o = min(1, op / width), p = min(1 - o, pr / width)
            return StateMix(operating: o, present: p, away: max(0, 1 - o - p))
        }
    }

    /// Gradient stop positions (0…1) for `count` slices: one at each slice's
    /// centre. `ActivityPalette.gradient` adds the stops at 0 and 1 that hold
    /// the first and last colour out to the block's edges.
    static func stopLocations(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { (Double($0) + 0.5) / Double(count) }
    }
}

extension ActivityPalette {
    /// The colour of a state mix: the three state colours blended by share,
    /// in linear light so a half-and-half slice is not darker than either end.
    static func color(_ mix: StateMix, in env: EnvironmentValues) -> Color {
        let parts: [(Color.Resolved, Double)] = [
            (chartColor(.operating).resolve(in: env), mix.operating),
            (chartColor(.present).resolve(in: env), mix.present),
            (chartColor(.away).resolve(in: env), mix.away),
        ]
        // Premultiplied, because the away colour is translucent.
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for (c, w) in parts {
            let alpha = Double(c.opacity) * w
            r += Double(c.linearRed) * alpha
            g += Double(c.linearGreen) * alpha
            b += Double(c.linearBlue) * alpha
            a += alpha
        }
        guard a > 0 else { return .clear }
        return Color(.sRGBLinear, red: r / a, green: g / a, blue: b / a, opacity: a)
    }

    /// State colours as the timeline paints them. Away is lightened so a long
    /// break recedes behind the work around it.
    static func chartColor(_ s: ActivityState) -> Color {
        s == .away ? color(.away).opacity(0.45) : color(s)
    }

    /// The gradient for one block, running from its start (top) to its end.
    static func gradient(_ mixes: [StateMix], in env: EnvironmentValues) -> LinearGradient {
        let colors = mixes.map { color($0, in: env) }
        var stops = zip(Shading.stopLocations(count: colors.count), colors).map {
            Gradient.Stop(color: $1, location: $0)
        }
        if let first = colors.first, let last = colors.last {
            stops.insert(Gradient.Stop(color: first, location: 0), at: 0)
            stops.append(Gradient.Stop(color: last, location: 1))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}
