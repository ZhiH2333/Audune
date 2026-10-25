import XCTest
@testable import Audune

final class SpectrumBandsTests: XCTestCase {
    private let counts = [8, 12, 16, 24, 32, 48, 64]

    func testBinCountMatchesFFT() {
        XCTAssertEqual(AudioSnapshot.binCount, SpectrumAnalyzer.fftLength / 2)
    }

    func testSinePeaksLandInLogBands() {
        for count in counts {
            let low = SpectrumAnalyzer(sampleRate: 48_000).process(sine(frequency: 440, amplitude: 0.5))
            let high = SpectrumAnalyzer(sampleRate: 48_000).process(sine(frequency: 4_000, amplitude: 0.5))
            let lowBands = SpectrumBands.levels(binMagnitudes: low.binMagnitudes, sampleRate: low.sampleRate, count: count)
            let highBands = SpectrumBands.levels(binMagnitudes: high.binMagnitudes, sampleRate: high.sampleRate, count: count)
            let expectedLow = SpectrumAnalyzer.bandIndex(sampleRate: 48_000, frequency: 440, count: count)
            let expectedHigh = SpectrumAnalyzer.bandIndex(sampleRate: 48_000, frequency: 4_000, count: count)

            XCTAssertEqual(lowBands.count, count)
            XCTAssertEqual(highBands.count, count)
            assertPeakCovers(frequency: 440, bands: lowBands, count: count, expected: expectedLow)
            assertPeakCovers(frequency: 4_000, bands: highBands, count: count, expected: expectedHigh)
            XCTAssertGreaterThan(abs(dominant(lowBands) - dominant(highBands)), 2)
            if count <= 16 {
                XCTAssertEqual(dominant(lowBands), expectedLow, "low \(count) \(lowBands)")
                XCTAssertEqual(dominant(highBands), expectedHigh, "high \(count) \(highBands)")
            }
            XCTAssertEqual(low.spectrum.count, AudioSnapshot.bandCount)
            XCTAssertEqual(low.binMagnitudes.count, AudioSnapshot.binCount)
        }
    }

    func testWideBandsAreNotRepeatedNarrowBands() {
        let snapshot = SpectrumAnalyzer(sampleRate: 48_000).process(sine(frequency: 440, amplitude: 0.6))
        let narrow = SpectrumBands.levels(binMagnitudes: snapshot.binMagnitudes, sampleRate: 48_000, count: 16)
        let wide = SpectrumBands.levels(binMagnitudes: snapshot.binMagnitudes, sampleRate: 48_000, count: 64)
        let repeated = (0..<64).allSatisfy { index in
            abs(wide[index] - narrow[index / 4]) < 0.000_1
        }

        XCTAssertFalse(repeated)
        assertPeakCovers(
            frequency: 440,
            bands: wide,
            count: 64,
            expected: SpectrumAnalyzer.bandIndex(sampleRate: 48_000, frequency: 440, count: 64)
        )
    }

    private func assertPeakCovers(frequency: Double, bands: [Float], count: Int, expected: Int) {
        let binHz = 48_000.0 / Double(SpectrumAnalyzer.fftLength)
        let bin = Int((frequency / binHz).rounded())
        let peak = dominant(bands)
        let range = SpectrumBands.binRange(sampleRate: 48_000, band: peak, count: count)

        XCTAssertLessThanOrEqual(abs(peak - expected), 1, "\(frequency) Hz count \(count) \(bands)")
        XCTAssertTrue(range.contains(bin), "bin \(bin) outside \(range) for \(frequency) Hz")
    }

    func testSilenceEmptyAndInvalidInputsAreZero() {
        let silent = SpectrumAnalyzer(sampleRate: 48_000).process(Array(repeating: 0, count: SpectrumAnalyzer.fftLength))
        let silentBands = SpectrumBands.levels(binMagnitudes: silent.binMagnitudes, sampleRate: silent.sampleRate, count: 32)
        XCTAssertEqual(silentBands.count, 32)
        XCTAssertTrue(silentBands.allSatisfy { $0 < 0.02 })

        XCTAssertEqual(
            SpectrumBands.levels(binMagnitudes: [], sampleRate: 48_000, count: 16),
            Array(repeating: 0, count: 16)
        )
        XCTAssertEqual(
            SpectrumBands.levels(binMagnitudes: [Float.nan, .infinity, -.infinity, 0.2], sampleRate: 48_000, count: 8).count,
            8
        )
        XCTAssertTrue(
            SpectrumBands.levels(binMagnitudes: [Float.nan, .infinity], sampleRate: 48_000, count: 8).allSatisfy(\.isFinite)
        )
        XCTAssertEqual(
            SpectrumBands.levels(binMagnitudes: [1, 1, 1], sampleRate: 0, count: 16),
            Array(repeating: 0, count: 16)
        )
        XCTAssertTrue(SpectrumBands.levels(binMagnitudes: [1], sampleRate: 48_000, count: 0).isEmpty)
    }

    func testSmoothingAttacksAndReleasesWithoutLeavingUnitInterval() {
        let rising = SpectrumBands.smooth(current: [0], toward: [1], count: 1)
        let falling = SpectrumBands.smooth(current: [1], toward: [0], count: 1)

        XCTAssertEqual(rising, [SpectrumBands.attack])
        XCTAssertEqual(falling, [1 - SpectrumBands.release])
        let broken = SpectrumBands.smooth(current: [.nan], toward: [.infinity], count: 4)
        XCTAssertEqual(broken.count, 4)
        XCTAssertTrue(broken.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
    }

    private func sine(frequency: Double, amplitude: Float) -> [Float] {
        let length = SpectrumAnalyzer.fftLength
        let step = 2 * Float.pi * Float(frequency) / 48_000
        return (0..<length).map { index in
            amplitude * sin(step * Float(index))
        }
    }

    private func dominant(_ spectrum: [Float]) -> Int {
        spectrum.indices.max(by: { spectrum[$0] < spectrum[$1] }) ?? 0
    }
}
