import CoreGraphics
import SwiftUI

/// Centered waveform in a top-left origin canvas. Positive samples go up.
nonisolated enum WaveformPath {
    /// Display scale applied on top of the user's amplitude. Samples stay real PCM.
    static let displayGain: CGFloat = 3

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

    static func mix(current: [Float], toward: [Float], smoothing: Float) -> [Float] {
        let count = max(toward.count, 1)
        let amount = smoothing.isFinite ? min(max(smoothing, 0), 1) : 0
        let follow = 1 - amount * 0.85
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
    var amplitude: Double = 1
    var lineWidth: Double = 1.5
    var smoothing: Double = 0.35

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let softened = WaveformPath.soften(samples, amount: Float(smoothing))
            let plotted = WaveformPath.points(
                samples: softened,
                in: bounds,
                amplitude: CGFloat(amplitude) * WaveformPath.displayGain
            )
            let points = plotted.count >= 2 ? plotted : WaveformPath.centerline(in: bounds)
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityLabel("Waveform")
    }
}
