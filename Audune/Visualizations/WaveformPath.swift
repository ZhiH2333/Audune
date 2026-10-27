import CoreGraphics
import SwiftUI

/// Centered waveform in a top-left origin canvas. Positive samples go up.
nonisolated enum WaveformPath {
    /// Mild display scale on top of the user's visual amplitude. Samples stay real PCM.
    static let displayGain: CGFloat = 1.25
    /// Share of each end that fades to the baseline, so the shape starts and ends at rest.
    static let edgeFade: CGFloat = 0.12
    static let densities = [32, 64, 128]
    /// Soft fill default opacity share of the appearance opacity.
    static let defaultFillStrength: CGFloat = 0.32

    static func points(samples: [Float], in bounds: CGRect, amplitude: CGFloat = 1) -> [CGPoint] {
        guard isDrawable(bounds), samples.count >= 2 else { return [] }
        let half = bounds.height / 2
        let gain = amplitude.isFinite ? max(amplitude, 0) : 1
        let lastIndex = CGFloat(samples.count - 1)
        return samples.enumerated().map { index, sample in
            let x = bounds.minX + bounds.width * CGFloat(index) / lastIndex
            let level = sample.isFinite ? min(max(CGFloat(sample) * gain, -1), 1) : 0
            let y = bounds.midY - level * half
            return CGPoint(
                x: min(max(x, bounds.minX), bounds.maxX),
                y: min(max(y, bounds.minY), bounds.maxY)
            )
        }
    }

    static func soften(_ samples: [Float], amount: Float) -> [Float] {
        let weight = amount.isFinite ? min(max(amount, 0), 1) : 0
        guard weight > 0, samples.count >= 3 else { return samples }
        return samples.enumerated().map { index, sample in
            let left = samples[max(0, index - 1)]
            let right = samples[min(samples.count - 1, index + 1)]
            let safe = sample.isFinite ? sample : 0
            let neighbors = (left + safe + right) / 3
            let blended = safe * (1 - weight) + neighbors * weight
            return blended.isFinite ? blended : 0
        }
    }

    /// Time-based follow toward `toward`. `smoothing` 0…1 maps to a time constant (~20–450 ms).
    /// This is display motion only — not Spectrum Attack/Release and not spatial neighbor softening.
    static func mix(current: [Float], toward: [Float], smoothing: Float, dt: Double) -> [Float] {
        let count = max(toward.count, 1)
        let amount = smoothing.isFinite ? min(max(smoothing, 0), 1) : 0
        let tau = 0.02 + Double(amount) * 0.43
        let follow: Float
        if dt > 0, tau > 0 {
            follow = Float(1 - exp(-dt / tau))
        } else {
            follow = max(1 - amount * 0.85, 0.05)
        }
        var result = [Float]()
        result.reserveCapacity(count)
        for index in 0..<count {
            let now = index < current.count && current[index].isFinite ? current[index] : 0
            let next = index < toward.count && toward[index].isFinite ? toward[index] : 0
            let mixed = now + (next - now) * follow
            result.append(mixed.isFinite ? min(max(mixed, -1), 1) : 0)
        }
        return result
    }

    /// Reduces real samples to at most `count` points by keeping the largest swing in each slice.
    /// It never creates more points than it was given.
    static func reduced(_ samples: [Float], to count: Int) -> [Float] {
        guard count >= 2, samples.count > count else { return samples }
        return (0..<count).map { index in
            let start = index * samples.count / count
            let end = min(samples.count, max((index + 1) * samples.count / count, start + 1))
            var best: Float = 0
            for sample in samples[start..<end] where sample.isFinite && abs(sample) > abs(best) {
                best = sample
            }
            return min(max(best, -1), 1)
        }
    }

    /// Fades both ends toward zero. Display only; the middle keeps its real values.
    static func tapered(_ samples: [Float]) -> [Float] {
        guard samples.count >= 3 else { return samples }
        let last = CGFloat(samples.count - 1)
        return samples.enumerated().map { index, sample in
            let edge = min(CGFloat(index), last - CGFloat(index)) / last
            let t = min(max(edge / edgeFade, 0), 1)
            let weight = Float(t * t * (3 - 2 * t))
            let safe = sample.isFinite ? sample : 0
            return safe * weight
        }
    }

    /// Density, then a mild spatial soften derived from motion smoothing, then the edge fade.
    static func prepared(_ samples: [Float], density: Int, smoothing: Float) -> [Float] {
        let count = densities.contains(density) ? density : AudioSnapshot.waveformCount
        let spatial = (smoothing.isFinite ? min(max(smoothing, 0), 1) : 0) * 0.45
        return tapered(soften(reduced(samples, to: count), amount: spatial))
    }

    /// Effective canvas amplitude: user visual amplitude × display gain.
    static func canvasAmplitude(visualAmplitude: Double) -> CGFloat {
        let user = visualAmplitude.isFinite ? max(visualAmplitude, 0) : 1
        return CGFloat(user) * displayGain
    }

    /// One smooth cubic piece ending at `end`.
    struct Segment: Equatable {
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint
    }

    /// Catmull-Rom curve through `points`. Control points stay inside `bounds`, so the curve never overshoots the canvas.
    static func segments(through points: [CGPoint], in bounds: CGRect) -> [Segment] {
        guard isDrawable(bounds), points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY)
            )
        }
        return (0..<(points.count - 1)).map { index in
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            return Segment(
                control1: clamp(CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)),
                control2: clamp(CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)),
                end: p2
            )
        }
    }

    /// The same points reflected through the horizontal midline.
    static func mirrored(_ points: [CGPoint], in bounds: CGRect) -> [CGPoint] {
        guard isDrawable(bounds) else { return [] }
        return points.map { point in
            CGPoint(x: point.x, y: min(max(2 * bounds.midY - point.y, bounds.minY), bounds.maxY))
        }
    }

    static func centerline(in bounds: CGRect) -> [CGPoint] {
        guard isDrawable(bounds) else { return [] }
        return [
            CGPoint(x: bounds.minX, y: bounds.midY),
            CGPoint(x: bounds.maxX, y: bounds.midY)
        ]
    }

    private static func isDrawable(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0 && rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }
}

struct WaveformCanvas: View {
    var samples: [Float]
    var color: Color
    var opacity: Double = 1
    var amplitude: Double = 0.55
    var lineWidth: Double = 1.25
    var smoothing: Double = 0.4
    var density: Int = 64
    var style: WaveformStyle = .line
    var fillStrength: Double = 0.32

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let prepared = WaveformPath.prepared(samples, density: density, smoothing: Float(smoothing))
            let plotted = WaveformPath.points(
                samples: prepared,
                in: bounds,
                amplitude: WaveformPath.canvasAmplitude(visualAmplitude: amplitude)
            )
            let points = plotted.count >= 2 ? plotted : WaveformPath.centerline(in: bounds)
            guard let first = points.first else { return }

            var base = Path()
            base.move(to: CGPoint(x: bounds.minX, y: bounds.midY))
            base.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
            context.stroke(base, with: .color(color.opacity(opacity * 0.18)), style: StrokeStyle(lineWidth: 0.5))

            let line = Self.curve(points, in: bounds, from: first)
            let fill = fillStrength.isFinite ? min(max(fillStrength, 0), 1) : 0.32

            switch style {
            case .line:
                context.stroke(
                    line,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
                )
            case .softFill:
                if fill > 0 {
                    Self.fillRibbon(context: context, line: line, points: points, in: bounds, color: color, opacity: opacity * fill)
                }
                context.stroke(
                    line,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
                )
            case .mirror:
                let reflected = WaveformPath.mirrored(points, in: bounds)
                if fill > 0 {
                    Self.fillRibbon(context: context, line: line, points: points, in: bounds, color: color, opacity: opacity * fill * 0.55)
                }
                context.stroke(
                    line,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
                )
                if let mirrorFirst = reflected.first {
                    let mirrorLine = Self.curve(reflected, in: bounds, from: mirrorFirst)
                    context.stroke(
                        mirrorLine,
                        with: .color(color.opacity(opacity * 0.85)),
                        style: StrokeStyle(lineWidth: CGFloat(max(lineWidth * 0.85, 0.5)), lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .accessibilityLabel("Waveform")
    }

    private static func fillRibbon(
        context: GraphicsContext,
        line: Path,
        points: [CGPoint],
        in bounds: CGRect,
        color: Color,
        opacity: Double
    ) {
        var ribbon = line
        let reflected = WaveformPath.mirrored(points, in: bounds).reversed()
        guard let start = reflected.first else { return }
        ribbon.addLine(to: start)
        let backwards = Array(reflected)
        for segment in WaveformPath.segments(through: backwards, in: bounds) {
            ribbon.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }
        ribbon.closeSubpath()
        context.fill(ribbon, with: .color(color.opacity(opacity)))
    }

    private static func curve(_ points: [CGPoint], in bounds: CGRect, from first: CGPoint) -> Path {
        var path = Path()
        path.move(to: first)
        let segments = WaveformPath.segments(through: points, in: bounds)
        if segments.isEmpty {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        } else {
            for segment in segments {
                path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
            }
        }
        return path
    }
}
