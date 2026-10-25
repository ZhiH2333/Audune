import Foundation

/// How Studio bars cut up the FFT bins. The menu bar's 16 bands are separate and unchanged.
nonisolated struct SpectrumBandLayout: Equatable {
    var scale: SpectrumScale
    var minHz: Double
    var maxHz: Double
    /// Level that maps to an empty bar. Louder than 0 dBFS always maps to a full bar.
    var floorDecibels: Float

    static let standard = SpectrumBandLayout(scale: .log, minHz: 40, maxHz: 16_000, floorDecibels: -60)
}

/// Band levels from linear FFT bin magnitudes.
/// Callers choose the band count. This does not repeat or interpolate a 16-band spectrum.
/// A band wider than one bin averages its bins. A band narrower than one bin reads the real
/// bins on either side of its center, so neighboring low bands do not show a copied value.
nonisolated enum SpectrumBands {
    static let minimumHz = SpectrumBandLayout.standard.minHz
    static let maximumHzCap = SpectrumBandLayout.standard.maxHz
    static let attack: Float = 0.65
    static let release: Float = 0.18

    static func levels(
        binMagnitudes: [Float],
        sampleRate: Double,
        count: Int,
        layout: SpectrumBandLayout = .standard,
        fftLength: Int = SpectrumAnalyzer.fftLength
    ) -> [Float] {
        guard count > 0 else { return [] }
        guard sampleRate.isFinite, sampleRate >= 80, fftLength > 1 else {
            return Array(repeating: 0, count: count)
        }
        let binHz = sampleRate / Double(fftLength)
        let nyquistBin = fftLength / 2
        let range = effectiveRange(layout: layout, sampleRate: sampleRate, binHz: binHz)
        guard range.upperBound > range.lowerBound, binHz.isFinite, binHz > 0 else {
            return Array(repeating: 0, count: count)
        }

        var levels = [Float]()
        levels.reserveCapacity(count)
        for band in 0..<count {
            let startHz = edgeHz(band, count: count, layout: layout, range: range)
            let endHz = edgeHz(band + 1, count: count, layout: layout, range: range)
            let magnitude: Float
            if (endHz - startHz) / binHz >= 1 {
                magnitude = averagedMagnitude(
                    binMagnitudes,
                    range: binRange(startHz: startHz, endHz: endHz, binHz: binHz, nyquistBin: nyquistBin)
                )
            } else {
                magnitude = interpolatedMagnitude(
                    binMagnitudes,
                    position: (startHz + endHz) / 2 / binHz,
                    nyquistBin: nyquistBin
                )
            }
            levels.append(normalized(magnitude, floorDecibels: layout.floorDecibels))
        }
        return levels
    }

    /// FFT bins averaged into one band. Used when the band is at least one bin wide.
    static func binRange(
        sampleRate: Double,
        band: Int,
        count: Int,
        layout: SpectrumBandLayout = .standard,
        fftLength: Int = SpectrumAnalyzer.fftLength
    ) -> Range<Int> {
        guard count > 0, band >= 0, band < count, sampleRate.isFinite, sampleRate >= 80, fftLength > 1 else { return 0..<0 }
        let binHz = sampleRate / Double(fftLength)
        let range = effectiveRange(layout: layout, sampleRate: sampleRate, binHz: binHz)
        guard range.upperBound > range.lowerBound, binHz.isFinite, binHz > 0 else { return 0..<0 }
        return binRange(
            startHz: edgeHz(band, count: count, layout: layout, range: range),
            endHz: edgeHz(band + 1, count: count, layout: layout, range: range),
            binHz: binHz,
            nyquistBin: fftLength / 2
        )
    }

    /// Studio display mix. `smoothing` 0 follows the new frame; 1 moves slowly.
    /// The menu bar keeps `smooth`, which uses the fixed attack and release.
    static func displayMix(current: [Float], toward target: [Float], count: Int, smoothing: Float) -> [Float] {
        let amount = smoothing.isFinite ? min(max(smoothing, 0), 1) : 0
        let follow = 1 - amount * 0.85
        return blend(current: current, toward: target, count: count, follow: follow)
    }

    static func smooth(current: [Float], toward target: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        return blend(current: current, toward: target, count: count) { now, next in
            next > now ? attack : release
        }
    }

    private static func blend(
        current: [Float],
        toward target: [Float],
        count: Int,
        follow: Float
    ) -> [Float] {
        blend(current: current, toward: target, count: count) { _, _ in follow }
    }

    private static func blend(
        current: [Float],
        toward target: [Float],
        count: Int,
        coefficient: (Float, Float) -> Float
    ) -> [Float] {
        guard count > 0 else { return [] }
        var result = [Float]()
        result.reserveCapacity(count)
        for index in 0..<count {
            let now = index < current.count ? current[index] : 0
            let next = index < target.count ? target[index] : 0
            let safeNow = now.isFinite ? now : 0
            let safeNext = next.isFinite ? next : 0
            let weight = coefficient(safeNow, safeNext)
            let mixed = safeNow + (safeNext - safeNow) * weight
            result.append(mixed.isFinite ? min(max(mixed, 0), 1) : 0)
        }
        return result
    }

    /// The lowest bar starts no lower than the first FFT bin; bin 0 is not a frequency band.
    private static func effectiveRange(layout: SpectrumBandLayout, sampleRate: Double, binHz: Double) -> ClosedRange<Double> {
        let requested = layout.minHz.isFinite ? layout.minHz : SpectrumBandLayout.standard.minHz
        let low = max(requested, binHz, 1)
        let highRequest = layout.maxHz.isFinite ? layout.maxHz : SpectrumBandLayout.standard.maxHz
        let high = min(highRequest, sampleRate / 2)
        return low...max(high, low)
    }

    private static func binRange(startHz: Double, endHz: Double, binHz: Double, nyquistBin: Int) -> Range<Int> {
        let startBin = max(Int(floor(startHz / binHz)), 1)
        let endBin = min(max(Int(ceil(endHz / binHz)), startBin + 1), nyquistBin)
        guard startBin < endBin else { return 0..<0 }
        return startBin..<endBin
    }

    private static func averagedMagnitude(_ bins: [Float], range: Range<Int>) -> Float {
        var sum: Float = 0
        var used = 0
        for bin in range {
            let raw = bin < bins.count ? bins[bin] : 0
            sum += raw.isFinite && raw > 0 ? raw : 0
            used += 1
        }
        return used > 0 ? sum / Float(used) : 0
    }

    private static func interpolatedMagnitude(_ bins: [Float], position: Double, nyquistBin: Int) -> Float {
        guard position.isFinite else { return 0 }
        let clamped = min(max(position, 1), Double(nyquistBin - 1))
        let lower = Int(floor(clamped))
        let fraction = Float(clamped - Double(lower))
        let a = magnitude(bins, at: lower)
        let b = magnitude(bins, at: lower + 1)
        return a + (b - a) * fraction
    }

    private static func magnitude(_ bins: [Float], at index: Int) -> Float {
        guard index >= 0, index < bins.count else { return 0 }
        let raw = bins[index]
        return raw.isFinite && raw > 0 ? raw : 0
    }

    private static func edgeHz(_ band: Int, count: Int, layout: SpectrumBandLayout, range: ClosedRange<Double>) -> Double {
        guard count > 0 else { return range.lowerBound }
        let position = Double(band) / Double(count)
        switch layout.scale {
        case .log:
            return range.lowerBound * pow(range.upperBound / range.lowerBound, position)
        case .linear:
            return range.lowerBound + (range.upperBound - range.lowerBound) * position
        }
    }

    private static func normalized(_ magnitude: Float, floorDecibels: Float) -> Float {
        let safe = magnitude.isFinite && magnitude > 0 ? magnitude : 0
        let floor = floorDecibels.isFinite && floorDecibels < -1 ? floorDecibels : -60
        let decibels = 20 * log10(safe + 1e-7)
        let value = (decibels - floor) / -floor
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
