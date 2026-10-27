import CoreGraphics
import SwiftUI

nonisolated struct OrbitGeometry: Equatable {
    var center: CGPoint
    /// Radius where every bar starts, measured to the middle of its rounded cap.
    var startRadius: CGFloat
    /// Farthest radius a bar's cap middle can reach. The cap edge stays inside the canvas.
    var endRadius: CGFloat
    var barWidth: CGFloat
}

nonisolated struct OrbitBar: Equatable {
    /// Direction from the center, in radians. Zero points right; the first slot is just right of the top.
    var angle: CGFloat
    var start: CGPoint
    var end: CGPoint
    var width: CGFloat
}

/// Ring of rounded radial bars driven by real band energy. Silence leaves a ring of dots; nothing rotates.
nonisolated enum OrbitLayout {
    static let defaultInnerRatio: CGFloat = 0.55
    static let defaultOuterScale: CGFloat = 0.92
    static let defaultGapDegrees: CGFloat = 2.5

    /// With mirroring, the left and right halves show the same bands, low at the top and high at the bottom.
    static func bandCount(barCount: Int, mirrored: Bool) -> Int {
        guard barCount > 0 else { return 0 }
        return mirrored ? max(barCount / 2, 1) : barCount
    }

    static func geometry(
        in bounds: CGRect,
        count: Int,
        innerRatio: CGFloat = defaultInnerRatio,
        outerScale: CGFloat = defaultOuterScale,
        gapDegrees: CGFloat = defaultGapDegrees
    ) -> OrbitGeometry? {
        guard count > 0, isDrawable(bounds) else { return nil }
        let limit = min(bounds.width, bounds.height)
        let half = limit / 2
        let scale = outerScale.isFinite ? min(max(outerScale, 0.5), 1) : defaultOuterScale
        let ratio = innerRatio.isFinite ? min(max(innerRatio, 0.2), 0.9) : defaultInnerRatio
        let outer = half * scale
        let inner = outer * ratio
        let slot = 2 * CGFloat.pi / CGFloat(count)
        let gapRadians = (gapDegrees.isFinite ? max(gapDegrees, 0) : defaultGapDegrees) * CGFloat.pi / 180
        let span = max(slot - min(gapRadians, slot * 0.75), slot * 0.25)
        let width = min(max(inner * span, 0.75), max(0.75, limit * 0.1))
        let start = inner + width / 2
        let end = max(start, outer - width / 2)
        guard start.isFinite, end.isFinite, width.isFinite, end + width / 2 <= half + 0.001 else { return nil }
        return OrbitGeometry(
            center: CGPoint(x: bounds.midX, y: bounds.midY),
            startRadius: start,
            endRadius: end,
            barWidth: width
        )
    }

    static func bars(
        spectrum: [Float],
        in bounds: CGRect,
        count: Int,
        innerRatio: CGFloat = defaultInnerRatio,
        outerScale: CGFloat = defaultOuterScale,
        gapDegrees: CGFloat = defaultGapDegrees,
        amplitude: CGFloat = 1,
        mirrored: Bool = true
    ) -> [OrbitBar] {
        guard let geometry = geometry(in: bounds, count: count, innerRatio: innerRatio, outerScale: outerScale, gapDegrees: gapDegrees) else {
            return []
        }
        let gain = amplitude.isFinite ? max(amplitude, 0) : 1
        let slot = 2 * CGFloat.pi / CGFloat(count)
        let bands = bandCount(barCount: count, mirrored: mirrored)
        var bars: [OrbitBar] = []
        bars.reserveCapacity(count)
        for index in 0..<count {
            let band = mirrored && index >= bands ? count - 1 - index : index
            let raw = band < spectrum.count ? spectrum[band] : 0
            let level = raw.isFinite ? min(max(CGFloat(raw) * gain, 0), 1) : 0
            let angle = -CGFloat.pi / 2 + (CGFloat(index) + 0.5) * slot
            let radius = geometry.startRadius + (geometry.endRadius - geometry.startRadius) * level
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let start = CGPoint(
                x: geometry.center.x + direction.x * geometry.startRadius,
                y: geometry.center.y + direction.y * geometry.startRadius
            )
            let end = CGPoint(
                x: geometry.center.x + direction.x * radius,
                y: geometry.center.y + direction.y * radius
            )
            guard inside(start, bounds), inside(end, bounds) else { return [] }
            bars.append(OrbitBar(angle: angle, start: start, end: end, width: geometry.barWidth))
        }
        return bars
    }

    /// Mean absolute band energy in 0…1. Used for restrained pulse scaling.
    static func meanEnergy(_ spectrum: [Float]) -> Float {
        guard spectrum.isEmpty == false else { return 0 }
        var sum: Float = 0
        for sample in spectrum {
            sum += sample.isFinite ? abs(sample) : 0
        }
        return min(max(sum / Float(spectrum.count), 0), 1)
    }

    /// Scales amplitude by mean energy when `strength` > 0. Strength is capped at 0.35.
    static func pulsedAmplitude(base: CGFloat, spectrum: [Float], strength: Double) -> CGFloat {
        let gain = base.isFinite ? max(base, 0) : 1
        let pulse = strength.isFinite ? min(max(strength, 0), 0.35) : 0
        guard pulse > 0 else { return gain }
        return gain * (1 + CGFloat(pulse) * CGFloat(meanEnergy(spectrum)))
    }

    /// Dual-band layers: low half of `spectrum` drives the inner ring, high half drives the outer ring.
    static func dualBars(
        spectrum: [Float],
        in bounds: CGRect,
        count: Int,
        innerRatio: CGFloat = defaultInnerRatio,
        outerScale: CGFloat = defaultOuterScale,
        gapDegrees: CGFloat = defaultGapDegrees,
        amplitude: CGFloat = 1,
        mirrored: Bool = true
    ) -> (inner: [OrbitBar], outer: [OrbitBar]) {
        let ratio = innerRatio.isFinite ? min(max(innerRatio, 0.2), 0.9) : defaultInnerRatio
        let midRatio = min(max((ratio + 1) * 0.5, ratio + 0.05), 0.95)
        let half = max(spectrum.count / 2, 1)
        var low = Array(spectrum.prefix(half))
        var high = Array(spectrum.suffix(max(spectrum.count - half, 0)))
        if high.isEmpty { high = low }
        while low.count < half { low.append(0) }
        while high.count < half { high.append(0) }

        let inner = bars(
            spectrum: low,
            in: bounds,
            count: count,
            innerRatio: ratio / midRatio,
            outerScale: outerScale * midRatio,
            gapDegrees: gapDegrees,
            amplitude: amplitude,
            mirrored: mirrored
        )
        let outer = bars(
            spectrum: high,
            in: bounds,
            count: count,
            innerRatio: midRatio,
            outerScale: outerScale,
            gapDegrees: gapDegrees,
            amplitude: amplitude,
            mirrored: mirrored
        )
        return (inner, outer)
    }

    /// A rounded bar from `start` to `end` with caps of diameter `width`.
    static func capsule(for bar: OrbitBar) -> Path {
        let length = hypot(bar.end.x - bar.start.x, bar.end.y - bar.start.y)
        let rect = CGRect(x: -bar.width / 2, y: -bar.width / 2, width: length + bar.width, height: bar.width)
        let transform = CGAffineTransform(translationX: bar.start.x, y: bar.start.y).rotated(by: bar.angle)
        return Path(roundedRect: rect, cornerRadius: bar.width / 2).applying(transform)
    }

    private static func isDrawable(_ rect: CGRect) -> Bool {
        rect.width > 1 && rect.height > 1 && rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }

    private static func inside(_ point: CGPoint, _ bounds: CGRect) -> Bool {
        point.x.isFinite && point.y.isFinite
            && point.x >= bounds.minX && point.x <= bounds.maxX
            && point.y >= bounds.minY && point.y <= bounds.maxY
    }
}

struct OrbitCanvas: View {
    var spectrum: [Float]
    var drawsLevels: Bool
    var barCount: Int
    var mirrored = true
    var color: Color
    var strokeColor: Color
    var drawsStroke = false
    var opacity: Double = 1
    var amplitude: Double = 1
    var lineWidth: Double = 1.5
    var innerRatio: Double = 0.55
    var outerScale: Double = 0.92
    var gapDegrees: Double = 2.5
    var layerMode: OrbitLayerMode = .single
    var pulseStrength: Double = 0

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let bands = OrbitLayout.bandCount(barCount: barCount, mirrored: mirrored)
            let source = drawsLevels ? spectrum : Array(repeating: Float(0), count: max(bands, 1))
            guard let geometry = OrbitLayout.geometry(
                in: bounds,
                count: barCount,
                innerRatio: CGFloat(innerRatio),
                outerScale: CGFloat(outerScale),
                gapDegrees: CGFloat(gapDegrees)
            ) else { return }
            let gain = OrbitLayout.pulsedAmplitude(
                base: CGFloat(amplitude),
                spectrum: source,
                strength: pulseStrength
            )
            let layers: [[OrbitBar]]
            switch layerMode {
            case .single:
                layers = [OrbitLayout.bars(
                    spectrum: source,
                    in: bounds,
                    count: barCount,
                    innerRatio: CGFloat(innerRatio),
                    outerScale: CGFloat(outerScale),
                    gapDegrees: CGFloat(gapDegrees),
                    amplitude: gain,
                    mirrored: mirrored
                )]
            case .dualBand:
                let dual = OrbitLayout.dualBars(
                    spectrum: source,
                    in: bounds,
                    count: barCount,
                    innerRatio: CGFloat(innerRatio),
                    outerScale: CGFloat(outerScale),
                    gapDegrees: CGFloat(gapDegrees),
                    amplitude: gain,
                    mirrored: mirrored
                )
                layers = [dual.inner, dual.outer]
            }
            let ring = Path(ellipseIn: CGRect(
                x: geometry.center.x - geometry.startRadius,
                y: geometry.center.y - geometry.startRadius,
                width: geometry.startRadius * 2,
                height: geometry.startRadius * 2
            ))
            context.stroke(ring, with: .color(color.opacity(opacity * 0.22)), style: StrokeStyle(lineWidth: 0.5))

            let fill = GraphicsContext.Shading.color(color.opacity(opacity))
            let outline = GraphicsContext.Shading.color(strokeColor.opacity(opacity))
            for (layerIndex, bars) in layers.enumerated() {
                let layerFill = layerMode == .dualBand && layerIndex == 0
                    ? GraphicsContext.Shading.color(color.opacity(opacity * 0.72))
                    : fill
                for bar in bars {
                    let shape = OrbitLayout.capsule(for: bar)
                    context.fill(shape, with: layerFill)
                    if drawsStroke {
                        context.stroke(shape, with: outline, style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineJoin: .round))
                    }
                }
            }
        }
        .accessibilityLabel(drawsLevels ? "Orbit" : "Orbit baseline")
    }
}
