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
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 100)
        let quiet = WaveformPath.points(samples: [0.2, 0.2], in: bounds, amplitude: 1)
        let lifted = WaveformPath.points(samples: [0.2, 0.2], in: bounds, amplitude: WaveformPath.displayGain)
        XCTAssertGreaterThan(abs(lifted[0].y - bounds.midY), abs(quiet[0].y - bounds.midY) * 2)
        XCTAssertGreaterThan(abs(lifted[0].y - bounds.midY), 20)
        XCTAssertEqual(WaveformPath.centerline(in: .zero), [])
    }

    func testDensityKeepsRealSamplesAndNeverInventsMore() {
        let samples = sine(frequency: 3, amplitude: 0.6, count: 128)
        let half = WaveformPath.reduced(samples, to: 64)

        XCTAssertEqual(half.count, 64)
        XCTAssertEqual(WaveformPath.reduced(samples, to: 128), samples)
        XCTAssertEqual(WaveformPath.reduced(samples, to: 256), samples, "no upsampling")
        XCTAssertEqual(WaveformPath.reduced(Array(samples.prefix(40)), to: 64).count, 40)
        for (index, value) in half.enumerated() {
            XCTAssertTrue(samples[index * 2] == value || samples[index * 2 + 1] == value, "bucket \(index) is a real sample")
        }
        XCTAssertEqual(WaveformPath.reduced([.nan, 2, -3, .infinity], to: 2), [1, -1])
    }

    func testEdgesFadeToTheBaselineAndTheMiddleKeepsRealValues() {
        let steady = Array(repeating: Float(0.5), count: 64)
        let faded = WaveformPath.tapered(steady)

        XCTAssertEqual(faded.first ?? 1, 0, accuracy: 0.000_1)
        XCTAssertEqual(faded.last ?? 1, 0, accuracy: 0.000_1)
        XCTAssertEqual(faded[32], 0.5, accuracy: 0.000_1)
        XCTAssertTrue(faded.allSatisfy { $0 >= 0 && $0 <= 0.5 })
        XCTAssertEqual(WaveformPath.tapered([.nan, 1, .infinity]), [0, 1, 0])
    }

    func testPreparedSilenceIsAFlatBaselineAtEveryDensity() {
        for density in WaveformPath.densities {
            let prepared = WaveformPath.prepared(Array(repeating: 0, count: 128), density: density, smoothing: 0.5)
            let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
            let points = WaveformPath.points(samples: prepared, in: bounds, amplitude: WaveformPath.displayGain)

            XCTAssertEqual(prepared.count, density)
            XCTAssertTrue(points.allSatisfy { abs($0.y - bounds.midY) < 0.001 })
        }
        XCTAssertEqual(WaveformPath.prepared(Array(repeating: 0, count: 128), density: 7, smoothing: 0).count, 128)
    }

    func testCurveControlPointsStayInsideBounds() {
        let samples = sine(frequency: 5, amplitude: 1, count: 128)
        for bounds in [CGRect(x: 0, y: 0, width: 8, height: 4), CGRect(x: 10, y: 12, width: 900, height: 500)] {
            let points = WaveformPath.points(samples: samples, in: bounds, amplitude: 3)
            let segments = WaveformPath.segments(through: points, in: bounds)

            XCTAssertEqual(segments.count, points.count - 1)
            for segment in segments {
                for point in [segment.control1, segment.control2, segment.end] {
                    XCTAssertTrue(inside(point, bounds), "\(point) outside \(bounds)")
                }
            }
            for point in WaveformPath.mirrored(points, in: bounds) {
                XCTAssertTrue(inside(point, bounds))
            }
        }
        XCTAssertTrue(WaveformPath.segments(through: [.zero], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        XCTAssertTrue(WaveformPath.segments(through: [.zero, CGPoint(x: CGFloat.nan, y: 0)], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        XCTAssertTrue(WaveformPath.mirrored([.zero], in: .zero).isEmpty)
    }

    func testMirroredPointsReflectThroughTheMidline() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let mirrored = WaveformPath.mirrored([CGPoint(x: 10, y: 20), CGPoint(x: 20, y: 50)], in: bounds)

        XCTAssertEqual(mirrored, [CGPoint(x: 10, y: 80), CGPoint(x: 20, y: 50)])
    }

    private func inside(_ point: CGPoint, _ bounds: CGRect) -> Bool {
        point.x >= bounds.minX && point.x <= bounds.maxX && point.y >= bounds.minY && point.y <= bounds.maxY
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
