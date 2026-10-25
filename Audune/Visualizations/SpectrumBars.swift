import CoreGraphics
import SwiftUI

/// Bottom-aligned spectrum bars in a top-left origin canvas.
nonisolated enum SpectrumBars {
    static func bars(
        spectrum: [Float],
        in bounds: CGRect,
        count: Int = AudioSnapshot.bandCount,
        gap requestedGap: CGFloat? = nil,
        amplitude: CGFloat = 1
    ) -> [CGRect] {
        guard count > 0, isDrawable(bounds) else { return [] }
        let automatic = min(4, bounds.width / CGFloat(count * 4))
        let requested = requestedGap ?? automatic
        let maxGap = count > 1 ? bounds.width / CGFloat(count * 2) : 0
        let gap = min(max(requested.isFinite ? requested : automatic, 0), max(maxGap, 0))
        guard gap.isFinite, gap >= 0 else { return [] }
        let usable = bounds.width - gap * CGFloat(count - 1)
        guard usable > 0 else { return [] }
        let barWidth = usable / CGFloat(count)
        guard barWidth.isFinite, barWidth > 0 else { return [] }

        var rects: [CGRect] = []
        rects.reserveCapacity(count)
        var x = bounds.minX
        for index in 0..<count {
            let end = index == count - 1 ? bounds.maxX : x + barWidth
            let width = end - x
            guard width.isFinite, width > 0 else { return [] }
            let raw = index < spectrum.count ? spectrum[index] : 0
            let gain = amplitude.isFinite ? max(amplitude, 0) : 1
            let level = raw.isFinite ? min(max(CGFloat(raw) * gain, 0), 1) : 0
            let hairline = min(1, bounds.height)
            let height = min(bounds.height, max(hairline, level * bounds.height))
            guard height.isFinite, height > 0 else { return [] }
            let rect = CGRect(x: x, y: bounds.maxY - height, width: width, height: height)
            guard isDrawable(rect), bounds.contains(rect) else { return [] }
            rects.append(rect)
            x = end + gap
        }
        return rects
    }

    /// Thin caps above bars whose held peak is higher than the bar. Always inside `bounds`.
    static func caps(
        peaks: [Float],
        bars: [CGRect],
        in bounds: CGRect,
        amplitude: CGFloat = 1,
        thickness: CGFloat = 2
    ) -> [CGRect] {
        guard isDrawable(bounds) else { return [] }
        let gain = amplitude.isFinite ? max(amplitude, 0) : 1
        let capHeight = min(max(thickness.isFinite ? thickness : 2, 0.5), bounds.height)
        var caps: [CGRect] = []
        for (index, bar) in bars.enumerated() where index < peaks.count {
            let raw = peaks[index]
            let level = raw.isFinite ? min(max(CGFloat(raw) * gain, 0), 1) : 0
            let height = min(bounds.height, max(min(1, bounds.height), level * bounds.height))
            guard height > bar.height + 0.5 else { continue }
            let top = bounds.maxY - height
            let y = min(max(bounds.minY, top - capHeight - 1), bounds.maxY - capHeight)
            let rect = CGRect(x: bar.minX, y: y, width: bar.width, height: capHeight)
            guard isDrawable(rect), bounds.contains(rect) else { continue }
            caps.append(rect)
        }
        return caps
    }

    static func baseline(in bounds: CGRect) -> CGRect {
        guard isDrawable(bounds) else { return .zero }
        let thickness = min(1, bounds.height)
        return CGRect(x: bounds.minX, y: bounds.maxY - thickness, width: bounds.width, height: thickness)
    }

    private static func isDrawable(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0 && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }
}

struct SpectrumCanvas: View {
    var spectrum: [Float]
    var peaks: [Float] = []
    var drawsBars: Bool
    var color: Color
    var strokeColor: Color
    var opacity: Double = 1
    var amplitude: Double = 1
    var lineWidth: Double = 1.5
    var cornerRadius: Double = 2
    var barGap: Double = 2
    var drawsStroke: Bool = false

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let shade = GraphicsContext.Shading.color(color.opacity(opacity))
            if drawsBars {
                let bars = SpectrumBars.bars(
                    spectrum: spectrum,
                    in: bounds,
                    count: spectrum.count,
                    gap: CGFloat(barGap),
                    amplitude: CGFloat(amplitude)
                )
                let outline = GraphicsContext.Shading.color(strokeColor.opacity(opacity))
                for rect in bars {
                    let radius = min(CGFloat(cornerRadius), rect.width / 2, rect.height / 2)
                    let path = Path(roundedRect: rect, cornerRadius: max(radius, 0))
                    context.fill(path, with: shade)
                    if drawsStroke {
                        context.stroke(
                            path,
                            with: outline,
                            style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                for cap in SpectrumBars.caps(peaks: peaks, bars: bars, in: bounds, amplitude: CGFloat(amplitude)) {
                    context.fill(Path(roundedRect: cap, cornerRadius: min(CGFloat(cornerRadius), cap.height / 2)), with: outline)
                }
            } else {
                let line = SpectrumBars.baseline(in: bounds)
                if line.width > 0, line.height > 0 {
                    context.fill(Path(roundedRect: line, cornerRadius: min(CGFloat(cornerRadius), line.height / 2)), with: shade)
                }
            }
        }
        .accessibilityLabel(drawsBars ? "Spectrum" : "Spectrum baseline")
    }
}
