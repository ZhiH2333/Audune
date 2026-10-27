import XCTest
@testable import Audune

final class SpectrumAnalyzerTests: XCTestCase {
    func testSilenceIsNearZeroAndSilent() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        let snapshot = analyzer.process(Array(repeating: 0, count: SpectrumAnalyzer.fftLength))

        XCTAssertEqual(snapshot.spectrum.count, AudioSnapshot.bandCount)
        XCTAssertEqual(snapshot.rms, 0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.peak, 0, accuracy: 0.000_001)
        XCTAssertTrue(snapshot.isSilent)
        XCTAssertTrue(snapshot.spectrum.allSatisfy { $0 < 0.02 })
        assertFiniteUnit(snapshot)
    }

    func testSinePeaksLandInExpectedBands() {
        let low = SpectrumAnalyzer(sampleRate: 48_000).process(sine(frequency: 440, amplitude: 0.5))
        let high = SpectrumAnalyzer(sampleRate: 48_000).process(sine(frequency: 4_000, amplitude: 0.5))
        let lowPeak = dominantBand(low.spectrum)
        let highPeak = dominantBand(high.spectrum)
        let expectedLow = SpectrumAnalyzer.bandIndex(sampleRate: 48_000, frequency: 440)
        let expectedHigh = SpectrumAnalyzer.bandIndex(sampleRate: 48_000, frequency: 4_000)

        XCTAssertEqual(lowPeak, expectedLow, "spectrum \(low.spectrum)")
        XCTAssertEqual(highPeak, expectedHigh, "spectrum \(high.spectrum)")
        XCTAssertGreaterThan(abs(lowPeak - highPeak), 2)
        XCTAssertFalse(isFlat(low.spectrum))
        XCTAssertFalse(isFlat(high.spectrum))
        XCTAssertGreaterThan(low.spectrum[lowPeak], 0.05)
        XCTAssertGreaterThan(high.spectrum[highPeak], 0.05)
        assertFiniteUnit(low)
        assertFiniteUnit(high)
    }

    func testAmplitudeIncreasesRMSWithinUnitInterval() {
        let quiet = SpectrumAnalyzer(sampleRate: 48_000).process(sine(frequency: 440, amplitude: 0.1))
        let loud = SpectrumAnalyzer(sampleRate: 48_000).process(sine(frequency: 440, amplitude: 0.8))

        XCTAssertGreaterThan(loud.rms, quiet.rms)
        XCTAssertGreaterThan(loud.peak, quiet.peak)
        assertFiniteUnit(quiet)
        assertFiniteUnit(loud)
    }

    func testConstantSignalIsNotCopiedOntoEveryBand() {
        let snapshot = SpectrumAnalyzer(sampleRate: 48_000).process(Array(repeating: 0.2, count: SpectrumAnalyzer.fftLength))

        XCTAssertGreaterThan(snapshot.rms, 0.15)
        XCTAssertFalse(snapshot.isSilent)
        XCTAssertFalse(snapshot.spectrum.allSatisfy { abs($0 - snapshot.rms) < 0.01 })
        assertFiniteUnit(snapshot)
    }

    func testNonFiniteAndEmptyInputsStayFinite() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        var broken = sine(frequency: 440, amplitude: 0.4)
        broken[4] = .nan
        broken[5] = .infinity
        broken[6] = -.infinity
        let noisy = analyzer.process(broken)
        let empty = SpectrumAnalyzer(sampleRate: 48_000).process([])

        XCTAssertEqual(empty.spectrum.count, AudioSnapshot.bandCount)
        XCTAssertEqual(empty.rms, 0)
        XCTAssertTrue(empty.isSilent)
        assertFiniteUnit(noisy)
        assertFiniteUnit(empty)
        XCTAssertEqual(dominantBand(noisy.spectrum), SpectrumAnalyzer.bandIndex(sampleRate: 48_000, frequency: 440))
    }

    func testInvalidSampleRatePublishesZeros() {
        let snapshot = SpectrumAnalyzer(sampleRate: 0).process(sine(frequency: 440, amplitude: 0.8))

        XCTAssertEqual(snapshot.spectrum, Array(repeating: 0, count: AudioSnapshot.bandCount))
        XCTAssertEqual(snapshot.binMagnitudes, Array(repeating: 0, count: AudioSnapshot.binCount))
        XCTAssertEqual(snapshot.sampleRate, 0)
        XCTAssertEqual(snapshot.rms, 0)
        XCTAssertTrue(snapshot.isSilent)
        XCTAssertGreaterThan(snapshot.timestampNanoseconds, 0)
    }

    func testSilenceHysteresisDoesNotFlicker() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        XCTAssertFalse(analyzer.process(constant(0.2)).isSilent)

        for _ in 0..<7 {
            XCTAssertFalse(analyzer.process(constant(0.0005)).isSilent)
        }
        XCTAssertTrue(analyzer.process(constant(0.0005)).isSilent)
        XCTAssertTrue(analyzer.process(constant(0.001)).isSilent)
        XCTAssertFalse(analyzer.process(constant(0.002)).isSilent)

        XCTAssertFalse(analyzer.process(constant(0.2)).isSilent)
        for _ in 0..<20 {
            XCTAssertFalse(analyzer.process(constant(0.0005)).isSilent)
            XCTAssertFalse(analyzer.process(constant(0.001)).isSilent)
        }
    }

    func testCustomSilenceThresholdChangesEnterPoint() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        analyzer.applySilenceSettings(SilenceGateSettings.from(enabled: true, threshold: 0.01))
        XCTAssertFalse(analyzer.process(constant(0.2)).isSilent)

        for _ in 0..<7 {
            XCTAssertFalse(analyzer.process(constant(0.005)).isSilent)
        }
        XCTAssertTrue(analyzer.process(constant(0.005)).isSilent)
        XCTAssertTrue(analyzer.process(constant(0.015)).isSilent)
        XCTAssertFalse(analyzer.process(constant(0.02)).isSilent)
    }

    func testDisabledSilenceGateKeepsWeakSignalActive() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        analyzer.applySilenceSettings(SilenceGateSettings.from(enabled: false, threshold: 0.0008))
        XCTAssertFalse(analyzer.process(constant(0.2)).isSilent)
        for _ in 0..<20 {
            XCTAssertFalse(analyzer.process(constant(0.0002)).isSilent)
        }
    }

    func testSilenceGateSettingsDeriveHysteresisFromThreshold() {
        let gate = SilenceGateSettings.from(enabled: true, threshold: 0.002)
        XCTAssertEqual(gate.enterRMS, 0.002, accuracy: 0.000_000_1)
        XCTAssertEqual(gate.exitRMS, 0.002 * (0.0015 / 0.0008), accuracy: 0.000_000_1)
        XCTAssertEqual(gate.enterFrames, SilenceGateSettings.standard.enterFrames)
    }

    func testBandCountStaysStable() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        for _ in 0..<4 {
            XCTAssertEqual(analyzer.process(sine(frequency: 1_000, amplitude: 0.3)).spectrum.count, AudioSnapshot.bandCount)
        }
    }

    private func sine(frequency: Double, amplitude: Float) -> [Float] {
        let length = SpectrumAnalyzer.fftLength
        let step = 2 * Float.pi * Float(frequency) / 48_000
        var samples = [Float](repeating: 0, count: length)
        for index in 0..<length {
            samples[index] = amplitude * sin(step * Float(index))
        }
        return samples
    }

    private func constant(_ value: Float) -> [Float] {
        Array(repeating: value, count: SpectrumAnalyzer.fftLength)
    }

    private func dominantBand(_ spectrum: [Float]) -> Int {
        spectrum.indices.max(by: { spectrum[$0] < spectrum[$1] }) ?? 0
    }

    private func isFlat(_ spectrum: [Float]) -> Bool {
        guard let first = spectrum.first else { return true }
        return spectrum.allSatisfy { abs($0 - first) < 0.000_1 }
    }

    private func assertFiniteUnit(_ snapshot: AudioSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(snapshot.rms.isFinite && snapshot.rms >= 0 && snapshot.rms <= 1, file: file, line: line)
        XCTAssertTrue(snapshot.peak.isFinite && snapshot.peak >= 0 && snapshot.peak <= 1, file: file, line: line)
        XCTAssertEqual(snapshot.spectrum.count, AudioSnapshot.bandCount, file: file, line: line)
        for value in snapshot.spectrum {
            XCTAssertTrue(value.isFinite && value >= 0 && value <= 1, file: file, line: line)
        }
        XCTAssertEqual(snapshot.binMagnitudes.count, AudioSnapshot.binCount, file: file, line: line)
        XCTAssertTrue(snapshot.sampleRate.isFinite && snapshot.sampleRate >= 0, file: file, line: line)
        for value in snapshot.binMagnitudes {
            XCTAssertTrue(value.isFinite && value >= 0, file: file, line: line)
        }
        XCTAssertEqual(snapshot.waveform.count, AudioSnapshot.waveformCount, file: file, line: line)
        for value in snapshot.waveform {
            XCTAssertEqual(value, 0, file: file, line: line)
        }
    }
}
