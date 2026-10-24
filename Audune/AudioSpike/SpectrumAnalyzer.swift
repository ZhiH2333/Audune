import Accelerate
import Darwin
import Foundation

/// Log-band spectrum from one mono window. Call it off the realtime callback.
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    static let fftLength = 1024
    static let bandCount = AudioSnapshot.bandCount
    static let silenceEnterRMS: Float = 0.0008
    static let silenceExitRMS: Float = 0.0015
    static let silenceEnterFrames = 8

    private let sampleRate: Double
    private let isValid: Bool
    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length = 10
    private let hann: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var smoothed: [Float]
    private let bandRanges: [Range<Int>]
    private var sequence: UInt64 = 0
    private var silentFrames = 0
    private var isSilent = true

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        isValid = sampleRate.isFinite && sampleRate >= 80
        if isValid {
            fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
            bandRanges = Self.makeBandRanges(sampleRate: sampleRate)
        } else {
            fftSetup = nil
            bandRanges = []
        }
        hann = Self.makeHann(length: Self.fftLength)
        windowed = Array(repeating: 0, count: Self.fftLength)
        real = Array(repeating: 0, count: Self.fftLength / 2)
        imag = Array(repeating: 0, count: Self.fftLength / 2)
        magnitudes = Array(repeating: 0, count: Self.fftLength / 2)
        smoothed = Array(repeating: 0, count: Self.bandCount)
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    /// Band that should contain `frequency` for this analyzer's mapping.
    static func bandIndex(sampleRate: Double, frequency: Double) -> Int {
        let minimumHz = 40.0
        let maximumHz = min(16_000.0, sampleRate / 2)
        guard frequency.isFinite, maximumHz > minimumHz else { return 0 }
        if frequency <= minimumHz { return 0 }
        if frequency >= maximumHz { return bandCount - 1 }
        let position = log(frequency / minimumHz) / log(maximumHz / minimumHz)
        let index = Int(position * Double(bandCount))
        return min(max(index, 0), bandCount - 1)
    }

    func process(_ samples: [Float]) -> AudioSnapshot {
        sequence &+= 1
        let timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        guard isValid, let fftSetup else {
            return AudioSnapshot(
                sequence: sequence,
                timestampNanoseconds: timestamp,
                spectrum: Array(repeating: 0, count: Self.bandCount),
                rms: 0,
                peak: 0,
                isSilent: true
            )
        }

        let frame = preparedFrame(from: samples)
        updateSilence(rms: frame.rms)
        smooth(toward: bandTargets(frame.values, setup: fftSetup))
        return AudioSnapshot(
            sequence: sequence,
            timestampNanoseconds: timestamp,
            spectrum: smoothed.map(unit),
            rms: unit(frame.rms),
            peak: unit(frame.peak),
            isSilent: isSilent
        )
    }

    private func preparedFrame(from samples: [Float]) -> (values: [Float], rms: Float, peak: Float) {
        let usedCount: Int
        let source: ArraySlice<Float>
        if samples.count >= Self.fftLength {
            source = samples.suffix(Self.fftLength)
            usedCount = Self.fftLength
        } else {
            source = samples[...]
            usedCount = samples.count
        }

        var values = [Float](repeating: 0, count: Self.fftLength)
        var sumSquares = 0.0
        var peak: Float = 0
        var index = 0
        for sample in source {
            let value = sample.isFinite ? sample : 0
            values[index] = value
            sumSquares += Double(value) * Double(value)
            peak = max(peak, abs(value))
            index += 1
        }
        let rms = usedCount > 0 ? Float((sumSquares / Double(usedCount)).squareRoot()) : 0
        return (values, rms.isFinite ? rms : 0, peak.isFinite ? peak : 0)
    }

    private func updateSilence(rms: Float) {
        let level = rms.isFinite ? rms : 0
        if isSilent {
            if level > Self.silenceExitRMS {
                isSilent = false
                silentFrames = 0
            }
            return
        }
        if level < Self.silenceEnterRMS {
            silentFrames += 1
            if silentFrames >= Self.silenceEnterFrames {
                isSilent = true
                silentFrames = 0
            }
        } else {
            silentFrames = 0
        }
    }

    private func smooth(toward target: [Float]) {
        let attack: Float = 0.65
        let release: Float = 0.18
        for index in 0..<Self.bandCount {
            let current = smoothed[index]
            let next = index < target.count ? target[index] : 0
            let coefficient = next > current ? attack : release
            let mixed = current + (next - current) * coefficient
            smoothed[index] = mixed.isFinite ? mixed : 0
        }
    }

    private func bandTargets(_ samples: [Float], setup: FFTSetup) -> [Float] {
        var targets = [Float](repeating: 0, count: Self.bandCount)
        guard samples.count == Self.fftLength else { return targets }
        applyHann(samples)
        transform(setup: setup)
        for (band, range) in bandRanges.enumerated() {
            var sum: Float = 0
            var count = 0
            for bin in range where bin < magnitudes.count {
                sum += magnitudes[bin]
                count += 1
            }
            let mean = count > 0 ? sum / Float(count) : 0
            targets[band] = normalizedMagnitude(mean)
        }
        return targets
    }

    private func applyHann(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { source in
            hann.withUnsafeBufferPointer { hannBuffer in
                windowed.withUnsafeMutableBufferPointer { destination in
                    guard let sourceBase = source.baseAddress,
                          let hannBase = hannBuffer.baseAddress,
                          let destinationBase = destination.baseAddress else { return }
                    vDSP_vmul(sourceBase, 1, hannBase, 1, destinationBase, 1, vDSP_Length(Self.fftLength))
                }
            }
        }
    }

    private func transform(setup: FFTSetup) {
        real.withUnsafeMutableBufferPointer { realBuffer in
            imag.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realBase = realBuffer.baseAddress, let imagBase = imagBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                windowed.withUnsafeMutableBufferPointer { windowBuffer in
                    guard let windowBase = windowBuffer.baseAddress else { return }
                    windowBase.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftLength / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(Self.fftLength / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                // Packed real FFT is scaled by 2N. Multiply by 2 afterward to undo the Hann window's coherent gain.
                var scale = Float(1) / Float(2 * Self.fftLength)
                vDSP_vsmul(realBase, 1, &scale, realBase, 1, vDSP_Length(Self.fftLength / 2))
                vDSP_vsmul(imagBase, 1, &scale, imagBase, 1, vDSP_Length(Self.fftLength / 2))
                for bin in 1..<(Self.fftLength / 2) {
                    let realPart = realBuffer[bin]
                    let imagPart = imagBuffer[bin]
                    let magnitude = (realPart * realPart + imagPart * imagPart).squareRoot() * 4
                    magnitudes[bin] = magnitude.isFinite ? magnitude : 0
                }
                magnitudes[0] = 0
            }
        }
    }

    private func normalizedMagnitude(_ magnitude: Float) -> Float {
        let safe = magnitude.isFinite && magnitude > 0 ? magnitude : 0
        let decibels = 20 * log10(safe + 1e-7)
        return unit((decibels + 60) / 60)
    }

    private func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func makeHann(length: Int) -> [Float] {
        guard length > 1 else { return Array(repeating: 0, count: length) }
        return (0..<length).map { index in
            let phase = 2 * Float.pi * Float(index) / Float(length - 1)
            return 0.5 * (1 - cos(phase))
        }
    }

    private static func makeBandRanges(sampleRate: Double) -> [Range<Int>] {
        let binHz = sampleRate / Double(fftLength)
        let nyquistBin = fftLength / 2
        return (0..<bandCount).map { band in
            let startHz = edgeHz(band, sampleRate: sampleRate)
            let endHz = edgeHz(band + 1, sampleRate: sampleRate)
            let startBin = max(Int(floor(startHz / binHz)), 1)
            let endBin = min(max(Int(ceil(endHz / binHz)), startBin + 1), nyquistBin)
            return startBin..<endBin
        }
    }

    private static func edgeHz(_ band: Int, sampleRate: Double) -> Double {
        let minimumHz = 40.0
        let maximumHz = min(16_000.0, sampleRate / 2)
        guard maximumHz > minimumHz else { return minimumHz }
        return minimumHz * pow(maximumHz / minimumHz, Double(band) / Double(bandCount))
    }
}
