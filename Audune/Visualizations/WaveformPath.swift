import CoreGraphics
import SwiftUI

/// Centered waveform in a top-left origin canvas. Positive samples go up.
nonisolated enum WaveformPath {
    static func points(samples: [Float], in bounds: CGRect) -> [CGPoint] {
        guard isDrawable(bounds), samples.count >= 2 else { return [] }
        let amplitude = bounds.height / 2
        let lastIndex = CGFloat(samples.count - 1)
        return samples.enumerated().map { index, sample in
            let x = bounds.minX + bounds.width * CGFloat(index) / lastIndex
            let level = sample.isFinite ? min(max(CGFloat(sample), -1), 1) : 0
            let y = bounds.midY - level * amplitude
            return CGPoint(
                x: min(max(x, bounds.minX), bounds.maxX),
                y: min(max(y, bounds.minY), bounds.maxY)
            )
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

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let plotted = WaveformPath.points(samples: samples, in: bounds)
            let points = plotted.count >= 2 ? plotted : WaveformPath.centerline(in: bounds)
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(Color(red: 0.96, green: 0.94, blue: 0.90)),
                lineWidth: 1.5
            )
        }
        .accessibilityLabel("Waveform")
    }
}
