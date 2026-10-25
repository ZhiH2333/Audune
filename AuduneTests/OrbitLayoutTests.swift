import CoreGraphics
import XCTest
@testable import Audune

final class OrbitLayoutTests: XCTestCase {
    func testTinyAndHugeSpokesStayInside() {
        let spectrum = (0..<16).map { Float($0) / 15 }
        for bounds in [
            CGRect(x: 0, y: 0, width: 8, height: 6),
            CGRect(x: 4, y: 8, width: 9_000, height: 4_000)
        ] {
            let spokes = OrbitLayout.spokes(spectrum: spectrum, in: bounds)
            XCTAssertEqual(spokes.count, AudioSnapshot.bandCount)
            for spoke in spokes {
                assertInside(spoke.start, bounds)
                assertInside(spoke.end, bounds)
                XCTAssertGreaterThanOrEqual(distance(spoke.start, spoke.end), 0)
            }
        }
    }

    func testSilenceUsesOneShortRadius() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let spokes = OrbitLayout.spokes(spectrum: Array(repeating: 0, count: 16), in: bounds)
        let radii = spokes.map { distance($0.end, center) }

        XCTAssertEqual(spokes.count, 16)
        XCTAssertEqual(radii.max() ?? 0, radii.min() ?? 1, accuracy: 0.001)
        XCTAssertGreaterThan(radii[0], 0)
    }

    func testLoudBandReachesFartherThanQuietBand() {
        var spectrum = Array(repeating: Float(0), count: 16)
        spectrum[0] = 1
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let spokes = OrbitLayout.spokes(spectrum: spectrum, in: bounds)

        XCTAssertGreaterThan(distance(spokes[0].end, center), distance(spokes[8].end, center) + 10)
    }

    func testThirtyTwoSpokesStayInside() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let spectrum = (0..<32).map { Float($0) / 31 }
        let spokes = OrbitLayout.spokes(spectrum: spectrum, in: bounds, count: 32)

        XCTAssertEqual(spokes.count, 32)
        for spoke in spokes {
            assertInside(spoke.start, bounds)
            assertInside(spoke.end, bounds)
        }
    }

    func testInvalidBoundsProduceNoSpokes() {
        XCTAssertTrue(OrbitLayout.spokes(spectrum: [1], in: .zero).isEmpty)
        XCTAssertTrue(OrbitLayout.spokes(spectrum: [1], in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 80)).isEmpty)
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
