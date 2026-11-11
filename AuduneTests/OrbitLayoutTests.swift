import CoreGraphics
import XCTest
@testable import Audune

final class OrbitLayoutTests: XCTestCase {
    private let counts = [8, 12, 16, 24, 32, 48, 64]

    func testBarsAndCapsStayInsideTinyNormalAndHugeCanvases() {
        for bounds in [
            CGRect(x: 0, y: 0, width: 8, height: 6),
            CGRect(x: 12, y: 20, width: 360, height: 240),
            CGRect(x: 4, y: 8, width: 9_000, height: 4_000)
        ] {
            for count in counts {
                for gap in [0, 2.5, 10] as [CGFloat] {
                    for mirrored in [true, false] {
                        let bands = OrbitLayout.bandCount(barCount: count, mirrored: mirrored)
                        let bars = OrbitLayout.bars(
                            spectrum: Array(repeating: 1, count: bands),
                            in: bounds,
                            count: count,
                            gapDegrees: gap,
                            mirrored: mirrored
                        )
                        XCTAssertEqual(bars.count, count, "\(bounds) \(count) \(gap)")
                        for bar in bars {
                            assertInside(bar.start, bounds)
                            assertInside(bar.end, bounds)
                            let reach = bar.width / 2
                            XCTAssertGreaterThanOrEqual(min(bar.end.x, bar.start.x) - reach, bounds.minX - 0.01)
                            XCTAssertLessThanOrEqual(max(bar.end.x, bar.start.x) + reach, bounds.maxX + 0.01)
                            XCTAssertGreaterThanOrEqual(min(bar.end.y, bar.start.y) - reach, bounds.minY - 0.01)
                            XCTAssertLessThanOrEqual(max(bar.end.y, bar.start.y) + reach, bounds.maxY + 0.01)
                        }
                    }
                }
            }
        }
    }

    func testSilenceLeavesAnEvenRingOfDots() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let bars = OrbitLayout.bars(spectrum: Array(repeating: 0, count: 24), in: bounds, count: 48)
        let geometry = OrbitLayout.geometry(in: bounds, count: 48)

        XCTAssertEqual(bars.count, 48)
        XCTAssertNotNil(geometry)
        for bar in bars {
            XCTAssertEqual(distance(bar.start, bar.end), 0, accuracy: 0.001)
            XCTAssertEqual(distance(bar.end, center), geometry?.startRadius ?? 0, accuracy: 0.001)
        }
        XCTAssertGreaterThan(geometry?.startRadius ?? 0, min(bounds.width, bounds.height) * 0.2)
    }

    func testLoudBandReachesFartherThanQuietBand() {
        var spectrum = Array(repeating: Float(0), count: 24)
        spectrum[0] = 1
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let bars = OrbitLayout.bars(spectrum: spectrum, in: bounds, count: 48)

        XCTAssertGreaterThan(distance(bars[0].end, center), distance(bars[10].end, center) + 10)
        XCTAssertLessThanOrEqual(distance(bars[0].end, center), OrbitLayout.geometry(in: bounds, count: 48)?.endRadius ?? 0 + 0.001)
    }

    func testMirroringReadsHalfTheBandsAndIsSymmetric() {
        XCTAssertEqual(OrbitLayout.bandCount(barCount: 48, mirrored: true), 24)
        XCTAssertEqual(OrbitLayout.bandCount(barCount: 48, mirrored: false), 48)
        XCTAssertEqual(OrbitLayout.bandCount(barCount: 8, mirrored: true), 4)
        XCTAssertEqual(OrbitLayout.bandCount(barCount: 0, mirrored: true), 0)

        let spectrum = (0..<12).map { Float($0) / 11 }
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let mirrored = OrbitLayout.bars(spectrum: spectrum, in: bounds, count: 24, mirrored: true)
        let plain = OrbitLayout.bars(spectrum: (0..<24).map { Float($0) / 23 }, in: bounds, count: 24, mirrored: false)

        for index in 0..<24 {
            XCTAssertEqual(
                distance(mirrored[index].end, center),
                distance(mirrored[23 - index].end, center),
                accuracy: 0.001
            )
            XCTAssertEqual(mirrored[index].end.x - center.x, -(mirrored[23 - index].end.x - center.x), accuracy: 0.001)
        }
        XCTAssertGreaterThan(distance(plain[23].end, center), distance(plain[0].end, center))
        XCTAssertLessThan(distance(mirrored[0].end, center), distance(mirrored[11].end, center), "low bands sit at the top")
    }

    func testAngularGapNarrowsBarsAndRadiiMoveTheRing() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let tight = OrbitLayout.geometry(in: bounds, count: 32, gapDegrees: 0)
        let airy = OrbitLayout.geometry(in: bounds, count: 32, gapDegrees: 6)
        let large = OrbitLayout.geometry(in: bounds, count: 32, innerRatio: 0.8, outerScale: 1)
        let small = OrbitLayout.geometry(in: bounds, count: 32, innerRatio: 0.4, outerScale: 0.6)

        XCTAssertGreaterThan(tight?.barWidth ?? 0, airy?.barWidth ?? 1)
        XCTAssertGreaterThan(large?.startRadius ?? 0, small?.startRadius ?? 1)
        XCTAssertGreaterThan(large?.endRadius ?? 0, small?.endRadius ?? 1)
    }

    func testInvalidInputsStaySafe() {
        XCTAssertTrue(OrbitLayout.bars(spectrum: [1], in: .zero, count: 8).isEmpty)
        XCTAssertTrue(OrbitLayout.bars(spectrum: [1], in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 80), count: 8).isEmpty)
        XCTAssertTrue(OrbitLayout.bars(spectrum: [1], in: CGRect(x: 0, y: 0, width: 80, height: 80), count: 0).isEmpty)

        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let bars = OrbitLayout.bars(
            spectrum: [.nan, .infinity, -1],
            in: bounds,
            count: 8,
            innerRatio: .nan,
            outerScale: .infinity,
            gapDegrees: .nan,
            amplitude: .nan
        )
        XCTAssertEqual(bars.count, 8)
        for bar in bars {
            assertInside(bar.end, bounds)
        }
    }

    func testDualBandSplitsLowAndHighIntoNestedRings() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        var spectrum = Array(repeating: Float(0), count: 24)
        spectrum[0] = 1
        spectrum[23] = 1
        let dual = OrbitLayout.dualBars(spectrum: spectrum, in: bounds, count: 48, mirrored: true)
        XCTAssertEqual(dual.inner.count, 48)
        XCTAssertEqual(dual.outer.count, 48)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let innerReach = dual.inner.map { distance($0.end, center) }.max() ?? 0
        let outerReach = dual.outer.map { distance($0.end, center) }.max() ?? 0
        XCTAssertGreaterThan(outerReach, innerReach)
    }

    func testPulseStrengthScalesAmplitudeAndZeroDisables() {
        let spectrum = Array(repeating: Float(0.8), count: 16)
        let base: CGFloat = 1
        XCTAssertEqual(OrbitLayout.pulsedAmplitude(base: base, spectrum: spectrum, strength: 0), base, accuracy: 0.000_1)
        let pulsed = OrbitLayout.pulsedAmplitude(base: base, spectrum: spectrum, strength: 0.35)
        XCTAssertGreaterThan(pulsed, base)
        XCTAssertLessThanOrEqual(pulsed, base * 1.35 + 0.001)
        // Strength above 0.35 clamps; mean energy 0.8 → 1 + 0.35 * 0.8 = 1.28
        XCTAssertEqual(OrbitLayout.pulsedAmplitude(base: base, spectrum: spectrum, strength: 9), base * 1.28, accuracy: 0.001)

        var bassHeavy = Array(repeating: Float(0.1), count: 16)
        for index in 0..<4 { bassHeavy[index] = 0.9 }
        var trebleHeavy = Array(repeating: Float(0.1), count: 16)
        for index in 12..<16 { trebleHeavy[index] = 0.9 }
        XCTAssertGreaterThan(
            OrbitLayout.pulsedAmplitude(base: base, spectrum: bassHeavy, strength: 0.3),
            OrbitLayout.pulsedAmplitude(base: base, spectrum: trebleHeavy, strength: 0.3)
        )
    }

    func testOrbitDynamicsAttackFasterThanTheyRelease() {
        let dynamics = OrbitPreferences.standard.dynamics
        XCTAssertLessThan(dynamics.attackSeconds, dynamics.releaseSeconds)
        let rising = SpectrumDynamics.step(state: SpectrumDynamicsState(), target: [1], dt: 0.033, settings: dynamics)
        let start = SpectrumDynamicsState(levels: [1], peaks: [1], peakAge: [0])
        let falling = SpectrumDynamics.step(state: start, target: [0], dt: 0.033, settings: dynamics)
        XCTAssertGreaterThan(rising.levels[0], 1 - falling.levels[0])
    }

    func testCoreRingBreathesWithLowEnergyAndSettlesInSilence() throws {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let geometry = try XCTUnwrap(OrbitLayout.geometry(in: bounds, count: 48))

        let silentRing = OrbitLayout.coreRingStyle(
            geometry: geometry,
            spectrum: Array(repeating: 0.8, count: 24),
            drawsLevels: false,
            baseOpacity: 0.9
        )
        let activeRing = OrbitLayout.coreRingStyle(
            geometry: geometry,
            spectrum: Array(repeating: 0.8, count: 24),
            drawsLevels: true,
            baseOpacity: 0.9
        )

        XCTAssertEqual(silentRing.lineWidth, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(silentRing.opacity, 0.9 * 0.22, accuracy: 0.000_1)
        XCTAssertGreaterThan(activeRing.lineWidth, silentRing.lineWidth)
        XCTAssertGreaterThan(activeRing.opacity, silentRing.opacity)
        XCTAssertEqual(activeRing.radius, geometry.startRadius, accuracy: 0.000_1)
    }

    private func assertInside(_ point: CGPoint, _ bounds: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(point.x, bounds.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(point.x, bounds.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(point.y, bounds.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(point.y, bounds.maxY, file: file, line: line)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
