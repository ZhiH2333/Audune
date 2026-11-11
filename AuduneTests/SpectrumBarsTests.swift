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

    func testSoftAmplitudeKeepsMidLevelsDistinctAndBounded() {
        let lows: [CGFloat] = [0.3, 0.4, 0.5, 0.556, 0.7, 0.85, 1]
        let gain: CGFloat = 1.8
        let mapped = lows.map { SpectrumBars.displayLevel($0, amplitude: gain) }
        for index in 1..<mapped.count {
            XCTAssertGreaterThan(mapped[index], mapped[index - 1], "soft gain must stay strictly ordered")
        }
        XCTAssertLessThan(mapped[3], 0.95, "raw ~0.556 must not hard-clip to full height at gain 1.8")
        XCTAssertEqual(mapped.last ?? 0, 1, accuracy: 0.000_1)

        let linear = SpectrumBars.displayLevel(CGFloat(0.4), amplitude: 0.85)
        XCTAssertEqual(linear, 0.4 * 0.85, accuracy: 0.000_1)

        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let quiet = SpectrumBars.bars(spectrum: [0.4, 0.55], in: bounds, count: 2, gap: 10, amplitude: 1)
        let louder = SpectrumBars.bars(spectrum: [0.4, 0.55], in: bounds, count: 2, gap: 10, amplitude: 1.8)
        XCTAssertEqual(quiet.count, 2)
        XCTAssertGreaterThan(louder[0].height, quiet[0].height)
        XCTAssertGreaterThan(louder[1].height, louder[0].height)
        XCTAssertLessThan(louder[0].height, bounds.height)
        XCTAssertLessThan(louder[1].height, bounds.height)
        XCTAssertGreaterThanOrEqual(quiet[1].minX - quiet[0].maxX, 9)
        XCTAssertEqual(SpectrumBars.displayLevel(CGFloat.nan, amplitude: 2), 0, accuracy: 0.000_1)
        XCTAssertEqual(SpectrumBars.displayLevel(CGFloat(2), amplitude: 2), 1, accuracy: 0.000_1)
    }

    func testDrawMetricsReservesPeakAndStrokeHeadroomWithoutCrushingBars() throws {
        let canvas = CGRect(x: 0, y: 0, width: 640, height: 360)
        let plain = try XCTUnwrap(SpectrumBars.drawMetrics(
            in: canvas,
            lineWidth: 1.5,
            drawsStroke: false,
            peakHold: false
        ))
        XCTAssertEqual(plain.topHeadroom, 0, accuracy: 0.001)
        XCTAssertEqual(plain.plotBounds, canvas)

        let stroked = try XCTUnwrap(SpectrumBars.drawMetrics(
            in: canvas,
            lineWidth: 4,
            drawsStroke: true,
            peakHold: false
        ))
        XCTAssertGreaterThan(stroked.topHeadroom, 0)
        XCTAssertEqual(stroked.plotBounds.height, canvas.height - stroked.topHeadroom, accuracy: 0.001)
        XCTAssertGreaterThan(stroked.plotBounds.height / canvas.height, 0.9)

        let peaked = try XCTUnwrap(SpectrumBars.drawMetrics(
            in: canvas,
            lineWidth: 4,
            drawsStroke: true,
            peakHold: true,
            capThickness: 2
        ))
        XCTAssertGreaterThan(peaked.topHeadroom, stroked.topHeadroom)
        XCTAssertGreaterThan(peaked.plotBounds.height / canvas.height, 0.85)
        XCTAssertTrue(canvas.contains(peaked.plotBounds))

        let tiny = CGRect(x: 0, y: 0, width: 40, height: 20)
        let tinyMetrics = try XCTUnwrap(SpectrumBars.drawMetrics(
            in: tiny,
            lineWidth: 3,
            drawsStroke: true,
            peakHold: true
        ))
        XCTAssertTrue(tiny.contains(tinyMetrics.plotBounds))
        XCTAssertGreaterThan(tinyMetrics.plotBounds.height, 0)
        XCTAssertNil(SpectrumBars.drawMetrics(in: .zero, lineWidth: 1, drawsStroke: false, peakHold: false))
    }

    func testPeakCapsSitAboveBarsInsideCanvasWithHeadroom() throws {
        let canvas = CGRect(x: 0, y: 0, width: 200, height: 100)
        let metrics = try XCTUnwrap(SpectrumBars.drawMetrics(
            in: canvas,
            lineWidth: 3,
            drawsStroke: true,
            peakHold: true,
            capThickness: 2
        ))
        let bars = SpectrumBars.bars(
            spectrum: [0.2, 0.5, 0.65],
            metrics: metrics,
            count: 3,
            gap: 4,
            amplitude: 1.8
        )
        let caps = SpectrumBars.caps(
            peaks: [0.9, 0.5, 1],
            bars: bars,
            metrics: metrics,
            amplitude: 1.8
        )

        XCTAssertEqual(caps.count, 2, "first and third bars hold peaks above the live level")
        for cap in caps {
            XCTAssertTrue(canvas.contains(cap))
            XCTAssertGreaterThanOrEqual(cap.minY, canvas.minY)
            XCTAssertTrue(cap.minX.isFinite && cap.minY.isFinite && cap.width.isFinite && cap.height.isFinite)
        }
        let first = caps[0]
        let firstBar = bars[0]
        XCTAssertLessThanOrEqual(first.maxY, firstBar.minY + 0.01)
        XCTAssertEqual(first.minX, firstBar.minX, accuracy: 0.001)
        XCTAssertEqual(first.width, firstBar.width, accuracy: 0.001)

        let fullCap = caps[1]
        let fullBar = bars[2]
        XCTAssertEqual(fullCap.minX, fullBar.minX, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(fullCap.minY, canvas.minY)
        XCTAssertLessThan(fullCap.minY, metrics.plotBounds.minY)
        XCTAssertLessThanOrEqual(fullCap.maxY, fullBar.minY + 0.01)

        let plainBars = SpectrumBars.bars(spectrum: [0.2, 0.5, 1], in: canvas, count: 3, gap: 4)
        let plainCaps = SpectrumBars.caps(peaks: [0.6, 0.5, 1], bars: plainBars, in: canvas)
        XCTAssertEqual(plainCaps.count, 1, "only the first bar has a peak above it")
        XCTAssertTrue(canvas.contains(plainCaps[0]))
        XCTAssertTrue(SpectrumBars.caps(peaks: [.nan, .infinity], bars: plainBars, in: canvas).allSatisfy(canvas.contains))
        XCTAssertTrue(SpectrumBars.caps(peaks: [1], bars: plainBars, in: .zero).isEmpty)
    }

    func testEmptyOrInvalidBoundsProduceNoBars() {
        XCTAssertTrue(SpectrumBars.bars(spectrum: [1], in: .zero).isEmpty)
        XCTAssertTrue(SpectrumBars.bars(spectrum: [1], in: .null).isEmpty)
        XCTAssertTrue(SpectrumBars.bars(spectrum: [1], in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 40)).isEmpty)
        XCTAssertEqual(SpectrumBars.baseline(in: .zero), .zero)
        XCTAssertEqual(SpectrumBars.baseline(in: .null), .zero)
    }

    func testColorMappingModesStayFiniteAndDiffer() {
        let base = StudioAccent.amber.color
        let solid = SpectrumColorMap.fill(mode: .solid, base: base, index: 0, count: 8, level: 0.5)
        XCTAssertEqual(solid, base)

        let low = SpectrumColorMap.fill(mode: .frequency, base: base, index: 0, count: 8, level: 0.2)
        let high = SpectrumColorMap.fill(mode: .frequency, base: base, index: 7, count: 8, level: 0.2)
        XCTAssertNotEqual(low, high)
        XCTAssertTrue([low.red, low.green, low.blue, high.red, high.green, high.blue].allSatisfy { $0.isFinite })

        let quiet = SpectrumColorMap.fill(mode: .amplitude, base: base, index: 0, count: 1, level: 0.1)
        let loud = SpectrumColorMap.fill(mode: .amplitude, base: base, index: 0, count: 1, level: 1)
        XCTAssertNotEqual(quiet, loud)
        let broken = SpectrumColorMap.fill(mode: .amplitude, base: base, index: 0, count: 1, level: .nan)
        XCTAssertTrue([broken.red, broken.green, broken.blue].allSatisfy { $0.isFinite })
    }

    func testRestingDotsAndVerticalOpacitiesStayBoundedAndAligned() {
        let bounds = CGRect(x: 10, y: 20, width: 320, height: 120)
        let dots = SpectrumBars.restingDots(in: bounds, count: 32, gap: 2)
        let activeBars = SpectrumBars.bars(spectrum: Array(repeating: 0.5, count: 32), in: bounds, count: 32, gap: 2)

        XCTAssertEqual(dots.count, 32)
        assertInside(dots, bounds: bounds)
        for (dot, bar) in zip(dots, activeBars) {
            XCTAssertEqual(dot.minX, bar.minX, accuracy: 0.001)
            XCTAssertEqual(dot.width, bar.width, accuracy: 0.001)
            XCTAssertEqual(dot.maxY, bounds.maxY, accuracy: 0.001)
            XCTAssertLessThanOrEqual(dot.height, 2)
        }
        XCTAssertTrue(SpectrumBars.restingDots(in: .zero, count: 16).isEmpty)

        let lowOpacities = SpectrumBars.verticalOpacities(baseOpacity: 0.9, level: 0.1)
        let highOpacities = SpectrumBars.verticalOpacities(baseOpacity: 0.9, level: 1.0)
        XCTAssertEqual(lowOpacities.top, 0.9, accuracy: 0.000_1)
        XCTAssertGreaterThan(lowOpacities.top, lowOpacities.bottom)
        XCTAssertGreaterThan(highOpacities.bottom, lowOpacities.bottom)
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
