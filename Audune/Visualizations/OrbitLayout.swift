import CoreGraphics
import SwiftUI

nonisolated struct OrbitSpoke: Equatable {
    var start: CGPoint
    var end: CGPoint
}

/// Ring of spokes driven by real band energy. Silence stays on the inner ring.
nonisolated enum OrbitLayout {
    static func spokes(
        spectrum: [Float],
        in bounds: CGRect,
        count: Int = AudioSnapshot.bandCount,
        innerRatio: CGFloat = 0.55,
        amplitude: CGFloat = 1
    ) -> [OrbitSpoke] {
        guard count > 0, isDrawable(bounds) else { return [] }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let limit = min(bounds.width, bounds.height)
        let outer = limit / 2 - limit * 0.04
        guard outer.isFinite, outer > 0 else { return [] }
        let ratio = innerRatio.isFinite ? min(max(innerRatio, 0.2), 0.9) : 0.55
        let inner = outer * ratio
        let gain = amplitude.isFinite ? max(amplitude, 0) : 1
        var spokes: [OrbitSpoke] = []
        spokes.reserveCapacity(count)
        for index in 0..<count {
            let raw = index < spectrum.count ? spectrum[index] : 0
            let level = raw.isFinite ? min(max(CGFloat(raw) * gain, 0), 1) : 0
            let travel = max(outer - inner, 0)
            let span = max(min(1.5, travel), travel * level)
            let radius = min(outer, inner + span)
            guard radius.isFinite, radius >= 0, radius <= outer + 0.001 else { return [] }
            let angle = (CGFloat(index) / CGFloat(count)) * 2 * CGFloat.pi - CGFloat.pi / 2
            let end = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let start = CGPoint(
                x: center.x + cos(angle) * inner,
                y: center.y + sin(angle) * inner
            )
            guard inside(start, bounds), inside(end, bounds) else { return [] }
            spokes.append(OrbitSpoke(start: start, end: end))
        }
        return spokes
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
    var color: Color
    var opacity: Double = 1
    var amplitude: Double = 1
    var lineWidth: Double = 1.5
    var innerRatio: Double = 0.55

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let count = spectrum.isEmpty ? AudioSnapshot.bandCount : spectrum.count
            let source = drawsLevels ? spectrum : Array(repeating: Float(0), count: count)
            let spokes = OrbitLayout.spokes(
                spectrum: source,
                in: bounds,
                count: count,
                innerRatio: CGFloat(innerRatio),
                amplitude: CGFloat(amplitude)
            )
            var path = Path()
            for spoke in spokes {
                path.move(to: spoke.start)
                path.addLine(to: spoke.end)
            }
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityLabel(drawsLevels ? "Orbit" : "Orbit baseline")
    }
}
