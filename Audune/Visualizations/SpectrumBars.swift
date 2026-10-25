import CoreGraphics
import SwiftUI

/// Bottom-aligned spectrum bars in a top-left origin canvas.
nonisolated enum SpectrumBars {
    static func bars(spectrum: [Float], in bounds: CGRect, count: Int = AudioSnapshot.bandCount) -> [CGRect] {
        guard count > 0, isDrawable(bounds) else { return [] }
        let gap = min(4, bounds.width / CGFloat(count * 4))
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
            let level = raw.isFinite ? min(max(CGFloat(raw), 0), 1) : 0
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
    var drawsBars: Bool
    var color: Color

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let shade = GraphicsContext.Shading.color(color)
            if drawsBars {
                for rect in SpectrumBars.bars(spectrum: spectrum, in: bounds, count: spectrum.count) {
                    context.fill(Path(rect), with: shade)
                }
            } else {
                let line = SpectrumBars.baseline(in: bounds)
                if line.width > 0, line.height > 0 {
                    context.fill(Path(line), with: shade)
                }
            }
        }
        .accessibilityLabel(drawsBars ? "Spectrum" : "Spectrum baseline")
    }
}
