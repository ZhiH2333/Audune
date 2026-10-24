import CoreGraphics
import SwiftUI

nonisolated struct OrbitSpoke: Equatable {
    var start: CGPoint
    var end: CGPoint
}

/// Fixed-angle spokes from the same 16 spectrum bands. Zero level keeps a short base radius.
nonisolated enum OrbitLayout {
    static func spokes(spectrum: [Float], in bounds: CGRect, count: Int = AudioSnapshot.bandCount) -> [OrbitSpoke] {
        guard count > 0, isDrawable(bounds) else { return [] }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let limit = min(bounds.width, bounds.height)
        let margin = limit * 0.08
        let outer = limit / 2 - margin
        guard outer.isFinite, outer > 0 else { return [] }
        let base = outer * 0.22
        var spokes: [OrbitSpoke] = []
        spokes.reserveCapacity(count)
        for index in 0..<count {
            let raw = index < spectrum.count ? spectrum[index] : 0
            let level = raw.isFinite ? min(max(CGFloat(raw), 0), 1) : 0
            let radius = base + (outer - base) * level
            guard radius.isFinite, radius >= 0, radius <= outer + 0.001 else { return [] }
            let angle = (CGFloat(index) / CGFloat(count)) * 2 * CGFloat.pi - CGFloat.pi / 2
            let end = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let start = CGPoint(
                x: center.x + cos(angle) * base * 0.35,
                y: center.y + sin(angle) * base * 0.35
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

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let source = drawsLevels ? spectrum : Array(repeating: Float(0), count: AudioSnapshot.bandCount)
            let spokes = OrbitLayout.spokes(spectrum: source, in: bounds)
            var path = Path()
            for spoke in spokes {
                path.move(to: spoke.start)
                path.addLine(to: spoke.end)
            }
            context.stroke(
                path,
                with: .color(color),
                lineWidth: 2
            )
        }
        .accessibilityLabel(drawsLevels ? "Orbit" : "Orbit baseline")
    }
}
