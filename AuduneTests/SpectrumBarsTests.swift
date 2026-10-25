import CoreGraphics
import XCTest
@testable import Audune

final class SpectrumBarsTests: XCTestCase {
    func testTinyCanvasStaysInside() {
        let bounds = CGRect(x: 0, y: 0, width: 8, height: 4)
        assertInside(SpectrumBars.bars(spectrum: Array(repeating: 0.5, count: 16), in: bounds), bounds: bounds)
    }

    func testNormalCanvasUsesAllBands() {
        let bounds = CGRect(x: 12, y: 20, width: 640, height: 360)
        let spectrum = (0..<16).map { Float($0) / 15 }
        let bars = SpectrumBars.bars(spectrum: spectrum, in: bounds)

        XCTAssertEqual(bars.count, AudioSnapshot.bandCount)
        assertInside(bars, bounds: bounds)
        XCTAssertEqual(bars.last?.maxX ?? 0, bounds.maxX, accuracy: 0.001)
        XCTAssertGreaterThan(bars.last?.height ?? 0, bars.first?.height ?? 0)
    }

    func testHugeCanvasStaysInside() {
        let bounds = CGRect(x: 0, y: 0, width: 8_000, height: 5_000)
        let bars = SpectrumBars.bars(spectrum: Array(repeating: 1, count: 16), in: bounds)

        XCTAssertEqual(bars.count, 16)
        assertInside(bars, bounds: bounds)
        XCTAssertEqual(bars[0].height, bounds.height, accuracy: 0.001)
    }

    func testNonFiniteLevelsStayInside() {
        var spectrum = Array(repeating: Float(0.4), count: 16)
        spectrum[0] = .nan
        spectrum[1] = .infinity
        spectrum[2] = -.infinity
        let bounds = CGRect(x: 0, y: 0, width: 480, height: 240)
        let bars = SpectrumBars.bars(spectrum: spectrum, in: bounds)

        XCTAssertEqual(bars.count, 16)
        assertInside(bars, bounds: bounds)
        XCTAssertEqual(bars[0].height, 1, accuracy: 0.001)
    }

    func testSixtyFourBarsFitMinimumStudio() {
        let bounds = CGRect(origin: .zero, size: StudioFrame.minimumSize)
        let bars = SpectrumBars.bars(
            spectrum: Array(repeating: 0.5, count: 64),
            in: bounds,
            count: 64
        )

        XCTAssertEqual(bars.count, 64)
        assertInside(bars, bounds: bounds)
    }

    func testAmplitudeAndGapChangeRealBars() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let quiet = SpectrumBars.bars(spectrum: [0.4, 0.4], in: bounds, count: 2, gap: 10, amplitude: 1)
        let louder = SpectrumBars.bars(spectrum: [0.4, 0.4], in: bounds, count: 2, gap: 10, amplitude: 2)
        XCTAssertEqual(quiet.count, 2)
        XCTAssertEqual(louder[0].height, quiet[0].height * 2, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(quiet[1].minX - quiet[0].maxX, 9)
    }

    func testPeakCapsSitAboveHigherPeaksInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bars = SpectrumBars.bars(spectrum: [0.2, 0.5, 1], in: bounds, count: 3, gap: 4)
        let caps = SpectrumBars.caps(peaks: [0.6, 0.5, 1], bars: bars, in: bounds)

        XCTAssertEqual(caps.count, 1, "only the first bar has a peak above it")
        XCTAssertLessThan(caps[0].maxY, bars[0].minY)
        XCTAssertEqual(caps[0].minX, bars[0].minX)
        XCTAssertEqual(caps[0].width, bars[0].width)
        XCTAssertTrue(bounds.contains(caps[0]))

        let full = SpectrumBars.caps(peaks: [1], bars: [CGRect(x: 0, y: 90, width: 10, height: 10)], in: bounds, amplitude: 3)
        XCTAssertEqual(full.count, 1)
        XCTAssertTrue(bounds.contains(full[0]))
        XCTAssertTrue(SpectrumBars.caps(peaks: [.nan, .infinity], bars: bars, in: bounds).allSatisfy(bounds.contains))
        XCTAssertTrue(SpectrumBars.caps(peaks: [1], bars: bars, in: .zero).isEmpty)
    }

    func testEmptyOrInvalidBoundsProduceNoBars() {
        XCTAssertTrue(SpectrumBars.bars(spectrum: [1], in: .zero).isEmpty)
        XCTAssertTrue(SpectrumBars.bars(spectrum: [1], in: .null).isEmpty)
        XCTAssertTrue(SpectrumBars.bars(spectrum: [1], in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 40)).isEmpty)
        XCTAssertEqual(SpectrumBars.baseline(in: .zero), .zero)
        XCTAssertEqual(SpectrumBars.baseline(in: .null), .zero)
    }

    private func assertInside(_ bars: [CGRect], bounds: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(bars.isEmpty, file: file, line: line)
        for bar in bars {
            XCTAssertTrue(bounds.contains(bar), "\(bar) outside \(bounds)", file: file, line: line)
            XCTAssertGreaterThan(bar.width, 0, file: file, line: line)
            XCTAssertGreaterThan(bar.height, 0, file: file, line: line)
            XCTAssertTrue(bar.minX >= 0 || bounds.minX < 0 || bar.minX >= bounds.minX, file: file, line: line)
        }
    }
}
