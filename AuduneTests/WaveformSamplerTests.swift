import CoreGraphics
import XCTest
@testable import Audune

final class WaveformSamplerTests: XCTestCase {
    func testSilenceIsZero() {
        let waveform = WaveformSampler.downsample(Array(repeating: 0, count: 1_024))

        XCTAssertEqual(waveform.count, AudioSnapshot.waveformCount)
        XCTAssertTrue(waveform.allSatisfy { $0 == 0 })
    }

    func testEmptyInputStaysFixedLength() {
        let waveform = WaveformSampler.downsample([])

        XCTAssertEqual(waveform.count, AudioSnapshot.waveformCount)
        XCTAssertTrue(waveform.allSatisfy { $0 == 0 })
    }

    func testSineCrossesZeroAndIsNotFlatRMS() {
        let samples = sine(frequency: 4, amplitude: 0.8, count: 1_024)
        let waveform = WaveformSampler.downsample(samples)
        let rms = rootMeanSquare(samples)

        XCTAssertEqual(waveform.count, 128)
        XCTAssertTrue(waveform.contains { $0 > 0.5 })
        XCTAssertTrue(waveform.contains { $0 < -0.5 })
        XCTAssertFalse(waveform.allSatisfy { abs($0 - rms) < 0.05 })
    }

    func testNonFiniteSamplesAreCleared() {
        var samples = Array(repeating: Float.nan, count: 16)
        samples[10] = .infinity
        samples[11] = -.infinity
        samples[12] = 0.4
        let waveform = WaveformSampler.downsample(samples, count: 2)

        XCTAssertEqual(waveform.count, 2)
        XCTAssertEqual(waveform[0], 0)
        XCTAssertEqual(waveform[1], 0.4, accuracy: 0.000_1)
    }

    func testOutOfRangeSamplesClamp() {
        let waveform = WaveformSampler.downsample([4, -5], count: 2)

        XCTAssertEqual(waveform, [1, -1])
    }

    func testLengthStaysStable() {
        XCTAssertEqual(WaveformSampler.downsample([0.2]).count, AudioSnapshot.waveformCount)
        XCTAssertEqual(WaveformSampler.downsample(Array(repeating: 0.2, count: 5_000)).count, AudioSnapshot.waveformCount)
    }

    func testPointsStayInsideTinyAndHugeBounds() {
        let samples = sine(frequency: 3, amplitude: 1, count: 128)
        for bounds in [
            CGRect(x: 0, y: 0, width: 8, height: 4),
            CGRect(x: 10, y: 12, width: 8_000, height: 5_000)
        ] {
            let points = WaveformPath.points(samples: samples, in: bounds)
            XCTAssertEqual(points.count, samples.count)
            for point in points {
                XCTAssertGreaterThanOrEqual(point.x, bounds.minX)
                XCTAssertLessThanOrEqual(point.x, bounds.maxX)
                XCTAssertGreaterThanOrEqual(point.y, bounds.minY)
                XCTAssertLessThanOrEqual(point.y, bounds.maxY)
            }
            XCTAssertEqual(points.first?.x ?? -1, bounds.minX, accuracy: 0.001)
            XCTAssertEqual(points.last?.x ?? -1, bounds.maxX, accuracy: 0.001)
        }
        XCTAssertTrue(WaveformPath.points(samples: [0.2], in: CGRect(x: 0, y: 0, width: 100, height: 40)).isEmpty)
        XCTAssertEqual(WaveformPath.centerline(in: .zero), [])
    }

    private func sine(frequency: Float, amplitude: Float, count: Int) -> [Float] {
        (0..<count).map { index in
            amplitude * sin(2 * Float.pi * frequency * Float(index) / Float(count))
        }
    }

    private func rootMeanSquare(_ samples: [Float]) -> Float {
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}
