import CoreGraphics
import SwiftUI

/// Bottom-aligned spectrum bars in a top-left origin canvas.
nonisolated enum SpectrumBars {
    /// Canvas geometry shared by bars, strokes, and peak caps.
    /// Top headroom only reserves space for stroke and Peak Hold; bars still use the rest of the height.
    struct DrawMetrics: Equatable {
        var canvas: CGRect
        var plotBounds: CGRect
        var topHeadroom: CGFloat
        var sideInset: CGFloat
        var capThickness: CGFloat
    }

    /// Maps a normalized band level through visual amplitude without hard-clipping mid levels when gain > 1.
    static func displayLevel(_ raw: CGFloat, amplitude: CGFloat) -> CGFloat {
        let safe = raw.isFinite ? min(max(raw, 0), 1) : 0
        let gain = amplitude.isFinite ? max(amplitude, 0) : 1
        if gain <= 1 {
            return min(max(safe * gain, 0), 1)
        }
        let boosted = safe * gain / (1 + (gain - 1) * safe)
        guard boosted.isFinite else { return 0 }
        return min(max(boosted, 0), 1)
    }

    /// Stroke and peak-cap headroom from the current canvas size. No fixed screen padding.
    static func drawMetrics(
        in canvas: CGRect,
        lineWidth: CGFloat,
        drawsStroke: Bool,
        peakHold: Bool,
        capThickness: CGFloat = 2
    ) -> DrawMetrics? {
        guard isDrawable(canvas) else { return nil }
        let strokeWidth = lineWidth.isFinite ? max(lineWidth, 0.5) : 0.5
        let strokePad = drawsStroke ? min(strokeWidth / 2 + 0.5, canvas.height / 4) : 0
        let cap = min(max(capThickness.isFinite ? capThickness : 2, 0.5), max(canvas.height / 4, 0.5))
        let peakPad = peakHold ? cap + 1 : 0
        let topHeadroom = min(strokePad + peakPad, max(canvas.height - 1, 0))
        let sideInset = min(strokePad, max(canvas.width / 4, 0))
        let plot = CGRect(
            x: canvas.minX + sideInset,
            y: canvas.minY + topHeadroom,
            width: max(canvas.width - sideInset * 2, 0),
            height: max(canvas.height - topHeadroom, 0)
        )
        guard isDrawable(plot) else { return nil }
        return DrawMetrics(
            canvas: canvas,
            plotBounds: plot,
            topHeadroom: topHeadroom,
            sideInset: sideInset,
            capThickness: cap
        )
    }

    static func bars(
        spectrum: [Float],
        in bounds: CGRect,
        count: Int = AudioSnapshot.bandCount,
        gap requestedGap: CGFloat? = nil,
        amplitude: CGFloat = 1
    ) -> [CGRect] {
        guard let metrics = drawMetrics(
            in: bounds,
            lineWidth: 0,
            drawsStroke: false,
            peakHold: false
        ) else { return [] }
        return bars(
            spectrum: spectrum,
            metrics: metrics,
            count: count,
            gap: requestedGap,
            amplitude: amplitude
        )
    }

    static func bars(
        spectrum: [Float],
        metrics: DrawMetrics,
        count: Int = AudioSnapshot.bandCount,
        gap requestedGap: CGFloat? = nil,
        amplitude: CGFloat = 1
    ) -> [CGRect] {
        let bounds = metrics.plotBounds
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
            let level = displayLevel(CGFloat(raw), amplitude: amplitude)
            let hairline = min(1, bounds.height)
            let height = min(bounds.height, max(hairline, level * bounds.height))
            guard height.isFinite, height > 0 else { return [] }
            let rect = CGRect(x: x, y: bounds.maxY - height, width: width, height: height)
            guard isDrawable(rect), metrics.canvas.contains(rect) else { return [] }
            rects.append(rect)
            x = end + gap
        }
        return rects
    }

    /// Thin caps above bars whose held peak is higher than the bar. Always inside the canvas.
    static func caps(
        peaks: [Float],
        bars: [CGRect],
        in bounds: CGRect,
        amplitude: CGFloat = 1,
        thickness: CGFloat = 2
    ) -> [CGRect] {
        // Match bars(in:) plot geometry; keep caps inside the canvas via clamping.
        guard let metrics = drawMetrics(
            in: bounds,
            lineWidth: 0,
            drawsStroke: false,
            peakHold: false,
            capThickness: thickness
        ) else { return [] }
        return caps(peaks: peaks, bars: bars, metrics: metrics, amplitude: amplitude)
    }

    static func caps(
        peaks: [Float],
        bars: [CGRect],
        metrics: DrawMetrics,
        amplitude: CGFloat = 1
    ) -> [CGRect] {
        let canvas = metrics.canvas
        let plot = metrics.plotBounds
        guard isDrawable(canvas), isDrawable(plot) else { return [] }
        let capHeight = min(max(metrics.capThickness, 0.5), canvas.height)
        var caps: [CGRect] = []
        for (index, bar) in bars.enumerated() where index < peaks.count {
            let level = displayLevel(CGFloat(peaks[index]), amplitude: amplitude)
            let height = min(plot.height, max(min(1, plot.height), level * plot.height))
            guard height > bar.height + 0.5 else { continue }
            let top = plot.maxY - height
            let preferred = top - capHeight - 1
            let y = min(max(canvas.minY, preferred), min(bar.minY - capHeight, canvas.maxY - capHeight))
            let rect = CGRect(x: bar.minX, y: y, width: bar.width, height: capHeight)
            guard isDrawable(rect), canvas.contains(rect), rect.maxY <= bar.minY + 0.01 else { continue }
            caps.append(rect)
        }
        return caps
    }

    static func baseline(in bounds: CGRect) -> CGRect {
        guard isDrawable(bounds) else { return .zero }
        let thickness = min(1, bounds.height)
        return CGRect(x: bounds.minX, y: bounds.maxY - thickness, width: bounds.width, height: thickness)
    }

    /// Pill-shaped resting dots aligned with bar positions so silence settles into the same rhythm as active bars.
    static func restingDots(
        in bounds: CGRect,
        count: Int = AudioSnapshot.bandCount,
        gap requestedGap: CGFloat? = nil
    ) -> [CGRect] {
        guard count > 0, isDrawable(bounds) else { return [] }
        let dotHeight = min(2, bounds.height)
        let zeros = Array(repeating: Float(0), count: count)
        let baseBars = bars(spectrum: zeros, in: bounds, count: count, gap: requestedGap, amplitude: 1)
        return baseBars.compactMap { bar in
            let rect = CGRect(x: bar.minX, y: bounds.maxY - dotHeight, width: bar.width, height: dotHeight)
            return isDrawable(rect) && bounds.contains(rect) ? rect : nil
        }
    }

    /// Top and bottom opacity for vertical bar shading so tall bars have an airy base and crisp tip.
    static func verticalOpacities(baseOpacity: Double, level: Float) -> (top: Double, bottom: Double) {
        let base = baseOpacity.isFinite ? min(max(baseOpacity, 0), 1) : 1
        let safeLevel = level.isFinite ? min(max(Double(level), 0), 1) : 0
        let bottom = min(max(base * (0.48 + 0.24 * safeLevel), 0), base)
        return (top: base, bottom: bottom)
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
    var baseColor: StudioColor
    var strokeColor: Color
    var baseStrokeColor: StudioColor? = nil
    var opacity: Double = 1
    var amplitude: Double = 1
    var lineWidth: Double = 1.5
    var cornerRadius: Double = 2
    var barGap: Double = 2
    var drawsStroke: Bool = false
    var colorMode: SpectrumColorMode = .solid
    var peakHold: Bool = false

    var body: some View {
        Canvas { context, size in
            let canvas = CGRect(origin: .zero, size: size)
            context.clip(to: Path(canvas))
            if drawsBars {
                guard let metrics = SpectrumBars.drawMetrics(
                    in: canvas,
                    lineWidth: CGFloat(lineWidth),
                    drawsStroke: drawsStroke,
                    peakHold: peakHold || peaks.isEmpty == false
                ) else { return }
                let bars = SpectrumBars.bars(
                    spectrum: spectrum,
                    metrics: metrics,
                    count: spectrum.count,
                    gap: CGFloat(barGap),
                    amplitude: CGFloat(amplitude)
                )
                let outline = GraphicsContext.Shading.color(strokeColor.opacity(opacity))
                let resolvedStroke = baseStrokeColor ?? baseColor.blended(towardWhite: 0.35)
                for (index, rect) in bars.enumerated() {
                    let level = index < spectrum.count ? spectrum[index] : 0
                    let mapped = SpectrumColorMap.fill(
                        mode: colorMode,
                        base: baseColor,
                        index: index,
                        count: bars.count,
                        level: level
                    )
                    let baseSwiftUI = colorMode == .solid ? color : mapped.swiftUI
                    let opacities = SpectrumBars.verticalOpacities(baseOpacity: opacity, level: level)
                    let fill: GraphicsContext.Shading
                    if rect.height > 2 {
                        fill = .linearGradient(
                            Gradient(colors: [
                                baseSwiftUI.opacity(opacities.top),
                                baseSwiftUI.opacity(opacities.bottom)
                            ]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    } else {
                        fill = .color(baseSwiftUI.opacity(opacities.top))
                    }
                    let radius = min(CGFloat(cornerRadius), rect.width / 2, rect.height / 2)
                    let path = Path(roundedRect: rect, cornerRadius: max(radius, 0))
                    context.fill(path, with: fill)
                    if drawsStroke {
                        let barOutlineColor = SpectrumColorMap.stroke(
                            mode: colorMode,
                            base: baseColor,
                            strokeColor: resolvedStroke,
                            mappedFill: mapped
                        )
                        let barOutline = colorMode == .solid
                            ? outline
                            : GraphicsContext.Shading.color(barOutlineColor.swiftUI.opacity(opacity))
                        context.stroke(
                            path,
                            with: barOutline,
                            style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                for cap in SpectrumBars.caps(
                    peaks: peaks,
                    bars: bars,
                    metrics: metrics,
                    amplitude: CGFloat(amplitude)
                ) {
                    context.fill(Path(roundedRect: cap, cornerRadius: min(CGFloat(cornerRadius), cap.height / 2)), with: outline)
                }
            } else {
                let line = SpectrumBars.baseline(in: canvas)
                if line.width > 0, line.height > 0 {
                    context.fill(
                        Path(roundedRect: line, cornerRadius: min(CGFloat(cornerRadius), line.height / 2)),
                        with: .color(color.opacity(opacity * 0.24))
                    )
                }
                let dotCount = max(spectrum.count, AudioSnapshot.bandCount)
                let dotShading = GraphicsContext.Shading.color(color.opacity(opacity * 0.78))
                for dot in SpectrumBars.restingDots(in: canvas, count: dotCount, gap: CGFloat(barGap)) {
                    let radius = min(CGFloat(cornerRadius), dot.width / 2, dot.height / 2)
                    context.fill(Path(roundedRect: dot, cornerRadius: max(radius, 0)), with: dotShading)
                }
            }
        }
        .accessibilityLabel(drawsBars ? String(localized: "Spectrum") : String(localized: "Spectrum baseline"))
    }
}
