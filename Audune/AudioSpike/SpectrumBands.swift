import Foundation

/// Log-band levels from linear FFT bin magnitudes.
/// Callers choose the band count. This does not repeat or interpolate a 16-band spectrum.
nonisolated enum SpectrumBands {
    static let minimumHz = 40.0
    static let maximumHzCap = 16_000.0
    static let attack: Float = 0.65
    static let release: Float = 0.18

    static func levels(
        binMagnitudes: [Float],
        sampleRate: Double,
        count: Int,
        fftLength: Int = SpectrumAnalyzer.fftLength
    ) -> [Float] {
        guard count > 0 else { return [] }
        guard sampleRate.isFinite, sampleRate >= 80, fftLength > 1 else {
            return Array(repeating: 0, count: count)
        }
        let binHz = sampleRate / Double(fftLength)
        let nyquistBin = fftLength / 2
        let maximumHz = min(maximumHzCap, sampleRate / 2)
        guard maximumHz > minimumHz, binHz.isFinite, binHz > 0 else {
            return Array(repeating: 0, count: count)
        }

        var levels = [Float]()
        levels.reserveCapacity(count)
        for band in 0..<count {
            let range = binRange(band: band, count: count, binHz: binHz, nyquistBin: nyquistBin, maximumHz: maximumHz)
            var sum: Float = 0
            var used = 0
            for bin in range {
                let raw = bin < binMagnitudes.count ? binMagnitudes[bin] : 0
                sum += raw.isFinite && raw > 0 ? raw : 0
                used += 1
            }
            let mean = used > 0 ? sum / Float(used) : 0
            levels.append(normalized(mean))
        }
        return levels
    }

    /// FFT bins averaged into one log band. Adjacent low bands can share a bin.
    static func binRange(sampleRate: Double, band: Int, count: Int, fftLength: Int = SpectrumAnalyzer.fftLength) -> Range<Int> {
        guard count > 0, band >= 0, band < count, sampleRate.isFinite, sampleRate >= 80, fftLength > 1 else { return 0..<0 }
        let binHz = sampleRate / Double(fftLength)
        let maximumHz = min(maximumHzCap, sampleRate / 2)
        guard maximumHz > minimumHz, binHz.isFinite, binHz > 0 else { return 0..<0 }
        return binRange(band: band, count: count, binHz: binHz, nyquistBin: fftLength / 2, maximumHz: maximumHz)
    }

    static func smooth(current: [Float], toward target: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var result = [Float]()
        result.reserveCapacity(count)
        for index in 0..<count {
            let now = index < current.count ? current[index] : 0
            let next = index < target.count ? target[index] : 0
            let safeNow = now.isFinite ? now : 0
            let safeNext = next.isFinite ? next : 0
            let coefficient = safeNext > safeNow ? attack : release
            let mixed = safeNow + (safeNext - safeNow) * coefficient
            result.append(mixed.isFinite ? min(max(mixed, 0), 1) : 0)
        }
        return result
    }

    private static func binRange(band: Int, count: Int, binHz: Double, nyquistBin: Int, maximumHz: Double) -> Range<Int> {
        let startHz = edgeHz(band, count: count, maximumHz: maximumHz)
        let endHz = edgeHz(band + 1, count: count, maximumHz: maximumHz)
        let startBin = max(Int(floor(startHz / binHz)), 1)
        let endBin = min(max(Int(ceil(endHz / binHz)), startBin + 1), nyquistBin)
        guard startBin < endBin else { return 0..<0 }
        return startBin..<endBin
    }

    private static func edgeHz(_ band: Int, count: Int, maximumHz: Double) -> Double {
        guard count > 0, maximumHz > minimumHz else { return minimumHz }
        return minimumHz * pow(maximumHz / minimumHz, Double(band) / Double(count))
    }

    private static func normalized(_ magnitude: Float) -> Float {
        let safe = magnitude.isFinite && magnitude > 0 ? magnitude : 0
        let decibels = 20 * log10(safe + 1e-7)
        let value = (decibels + 60) / 60
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
