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
        let lifted = WaveformPath.points(
            samples: [0.2, 0.2],
            in: bounds,
            amplitude: WaveformPath.canvasAmplitude(visualAmplitude: 1)
        )
        XCTAssertGreaterThan(abs(lifted[0].y - bounds.midY), abs(quiet[0].y - bounds.midY))
        XCTAssertLessThan(abs(lifted[0].y - bounds.midY), 40)
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
            let points = WaveformPath.points(
                samples: prepared,
                in: bounds,
                amplitude: WaveformPath.canvasAmplitude(visualAmplitude: 1)
            )

            XCTAssertEqual(prepared.count, density)
            XCTAssertTrue(points.allSatisfy { abs($0.y - bounds.midY) < 0.001 })
        }
        XCTAssertEqual(WaveformPath.prepared(Array(repeating: 0, count: 128), density: 7, smoothing: 0).count, 128)
    }

    func testDefaultVisualAmplitudeIsCalmerThanLegacyBoost() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let sample: [Float] = [0.5, 0.5]
        let legacy = WaveformPath.points(samples: sample, in: bounds, amplitude: 3)
        let redesigned = WaveformPath.points(
            samples: sample,
            in: bounds,
            amplitude: WaveformPath.canvasAmplitude(visualAmplitude: WaveformPreferences.standard.amplitude),
            verticalRange: WaveformPath.clampedVerticalRange(CGFloat(WaveformPreferences.standard.verticalRange))
        )
        let legacySwing = abs(legacy[0].y - bounds.midY)
        let redesignSwing = abs(redesigned[0].y - bounds.midY)
        XCTAssertGreaterThan(legacySwing, redesignSwing * 1.5)
        XCTAssertLessThan(redesignSwing, bounds.height * 0.45)
        XCTAssertGreaterThan(redesignSwing, 5)
    }

    func testVerticalRangeCapsPeakToPeakAndAmplitudeCannotBypassIt() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let samples: [Float] = [1, -1, 1, -1]
        let range: CGFloat = 0.5
        let quiet = WaveformPath.points(
            samples: samples,
            in: bounds,
            amplitude: WaveformPath.canvasAmplitude(visualAmplitude: 0.2),
            verticalRange: range
        )
        let loud = WaveformPath.points(
            samples: samples,
            in: bounds,
            amplitude: WaveformPath.canvasAmplitude(visualAmplitude: 2),
            verticalRange: range
        )
        let ceiling = bounds.height * range / 2
        for point in quiet + loud {
            XCTAssertLessThanOrEqual(abs(point.y - bounds.midY), ceiling + 0.001)
        }
        let quietSwing = quiet.map { abs($0.y - bounds.midY) }.max() ?? 0
        let loudSwing = loud.map { abs($0.y - bounds.midY) }.max() ?? 0
        XCTAssertGreaterThan(loudSwing, quietSwing)
        XCTAssertEqual(loudSwing, ceiling, accuracy: 0.001)
        XCTAssertEqual(WaveformPath.clampedVerticalRange(0.1), 0.3, accuracy: 0.000_1)
        XCTAssertEqual(WaveformPath.clampedVerticalRange(1.5), 1, accuracy: 0.000_1)
    }

    func testDrawMetricsInsetKeepsStrokeInsideCanvas() throws {
        let canvas = CGRect(x: 0, y: 0, width: 200, height: 100)
        for lineWidth: CGFloat in [0.5, 1.25, 4] {
            let metrics = try XCTUnwrap(
                WaveformPath.drawMetrics(in: canvas, verticalRange: 1, lineWidth: lineWidth)
            )
            XCTAssertEqual(metrics.strokeInset, lineWidth / 2 + 0.5, accuracy: 0.000_1)
            XCTAssertTrue(metrics.safeBounds.minX >= canvas.minX + metrics.strokeInset - 0.001)
            XCTAssertTrue(metrics.safeBounds.maxX <= canvas.maxX - metrics.strokeInset + 0.001)
            XCTAssertTrue(metrics.safeBounds.minY >= canvas.minY + metrics.strokeInset - 0.001)
            XCTAssertTrue(metrics.safeBounds.maxY <= canvas.maxY - metrics.strokeInset + 0.001)
            // No inner hard band: safeBounds is the full drawable area after stroke inset.
            XCTAssertEqual(metrics.safeBounds.width, canvas.width - 2 * metrics.strokeInset, accuracy: 0.001)
            XCTAssertEqual(metrics.safeBounds.height, canvas.height - 2 * metrics.strokeInset, accuracy: 0.001)
            XCTAssertEqual(metrics.verticalRange, 1, accuracy: 0.000_1)
        }
        XCTAssertNil(WaveformPath.drawMetrics(in: .zero, verticalRange: 0.7, lineWidth: 2))
        XCTAssertNil(WaveformPath.drawMetrics(
            in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10),
            verticalRange: 0.7,
            lineWidth: 1
        ))
    }

    func testVerticalRangeScalesExcursionWithoutShrinkingSafeBounds() throws {
        let canvas = CGRect(x: 0, y: 0, width: 320, height: 180)
        let low = try XCTUnwrap(WaveformPath.drawMetrics(in: canvas, verticalRange: 0.3, lineWidth: 2))
        let mid = try XCTUnwrap(WaveformPath.drawMetrics(in: canvas, verticalRange: 0.7, lineWidth: 2))
        let high = try XCTUnwrap(WaveformPath.drawMetrics(in: canvas, verticalRange: 1, lineWidth: 2))
        XCTAssertEqual(low.safeBounds, mid.safeBounds)
        XCTAssertEqual(mid.safeBounds, high.safeBounds)
        XCTAssertEqual(low.verticalRange, 0.3, accuracy: 0.000_1)
        XCTAssertEqual(mid.verticalRange, 0.7, accuracy: 0.000_1)
        XCTAssertEqual(high.verticalRange, 1, accuracy: 0.000_1)

        let samples: [Float] = [1, -1, 1, -1]
        let lowPts = WaveformPath.plottedPoints(
            samples: samples, metrics: low, visualAmplitude: 2, density: 4, smoothing: 0
        )
        let highPts = WaveformPath.plottedPoints(
            samples: samples, metrics: high, visualAmplitude: 2, density: 4, smoothing: 0
        )
        let lowSwing = lowPts.map { abs($0.y - low.safeBounds.midY) }.max() ?? 0
        let highSwing = highPts.map { abs($0.y - high.safeBounds.midY) }.max() ?? 0
        XCTAssertEqual(lowSwing, low.safeBounds.height / 2 * 0.3, accuracy: 0.001)
        XCTAssertEqual(highSwing, high.safeBounds.height / 2, accuracy: 0.001)
        XCTAssertLessThan(lowSwing, highSwing)
        // Full range reaches the safe edge — no mid-canvas hard ceiling.
        XCTAssertEqual(highSwing + high.strokeInset, canvas.height / 2, accuracy: 0.001)
    }

    func testEveryWaveformStyleSharesTheSameSafeAnchors() throws {
        let canvas = CGRect(x: 0, y: 0, width: 240, height: 120)
        let metrics = try XCTUnwrap(
            WaveformPath.drawMetrics(in: canvas, verticalRange: 0.7, lineWidth: 3)
        )
        let samples = sine(frequency: 4, amplitude: 1, count: 128)
        let points = WaveformPath.plottedPoints(
            samples: samples,
            metrics: metrics,
            visualAmplitude: 2,
            density: 64,
            smoothing: 0.5
        )
        XCTAssertEqual(points.count, 64)
        for style in WaveformStyle.allCases {
            let anchors = WaveformPath.styleAnchors(points: points, in: metrics.safeBounds, style: style)
            XCTAssertFalse(anchors.isEmpty, "\(style)")
            for point in anchors {
                XCTAssertTrue(inside(point, metrics.safeBounds), "\(style) \(point)")
            }
            let segments = WaveformPath.segments(through: Array(anchors.prefix(points.count)), in: metrics.safeBounds)
            for segment in segments {
                for point in [segment.control1, segment.control2, segment.end] {
                    XCTAssertTrue(inside(point, metrics.safeBounds), "\(style) segment")
                }
            }
        }
        let lineAnchors = WaveformPath.styleAnchors(points: points, in: metrics.safeBounds, style: .line)
        let softAnchors = WaveformPath.styleAnchors(points: points, in: metrics.safeBounds, style: .softFill)
        let mirrorAnchors = WaveformPath.styleAnchors(points: points, in: metrics.safeBounds, style: .mirror)
        XCTAssertEqual(lineAnchors, points)
        XCTAssertEqual(softAnchors, mirrorAnchors)
        XCTAssertEqual(softAnchors.count, points.count * 2)
    }

    func testDrawMetricsFollowLatestCanvasSize() throws {
        let tall = try XCTUnwrap(
            WaveformPath.drawMetrics(
                in: CGRect(x: 0, y: 0, width: 100, height: 200),
                verticalRange: 0.7,
                lineWidth: 1
            )
        )
        let wide = try XCTUnwrap(
            WaveformPath.drawMetrics(
                in: CGRect(x: 0, y: 0, width: 400, height: 80),
                verticalRange: 0.7,
                lineWidth: 1
            )
        )
        XCTAssertEqual(tall.canvas.height, 200, accuracy: 0.001)
        XCTAssertEqual(wide.canvas.width, 400, accuracy: 0.001)
        XCTAssertGreaterThan(tall.safeBounds.height, wide.safeBounds.height)
        XCTAssertGreaterThan(wide.safeBounds.width, tall.safeBounds.width)
    }

    func testSafePlotGeometryContainsPointsSegmentsAndMirror() throws {
        let samples = sine(frequency: 7, amplitude: 1, count: 128)
        for size in [
            CGSize(width: 8, height: 4),
            CGSize(width: 40, height: 12),
            CGSize(width: 900, height: 500)
        ] {
            let canvas = CGRect(origin: .zero, size: size)
            let metrics = try XCTUnwrap(
                WaveformPath.drawMetrics(in: canvas, verticalRange: 1, lineWidth: 4)
            )
            let points = WaveformPath.plottedPoints(
                samples: samples,
                metrics: metrics,
                visualAmplitude: 2,
                density: 64,
                smoothing: 0
            )
            XCTAssertFalse(points.isEmpty)
            for point in points {
                XCTAssertTrue(inside(point, metrics.safeBounds), "\(point) outside safe \(metrics.safeBounds)")
            }
            for segment in WaveformPath.segments(through: points, in: metrics.safeBounds) {
                for point in [segment.control1, segment.control2, segment.end] {
                    XCTAssertTrue(inside(point, metrics.safeBounds))
                }
            }
            for point in WaveformPath.mirrored(points, in: metrics.safeBounds) {
                XCTAssertTrue(inside(point, metrics.safeBounds))
            }
            let strokeReach = metrics.strokeInset
            for point in points {
                XCTAssertGreaterThanOrEqual(point.y - strokeReach, canvas.minY - 0.001)
                XCTAssertLessThanOrEqual(point.y + strokeReach, canvas.maxY + 0.001)
                XCTAssertGreaterThanOrEqual(point.x - strokeReach, canvas.minX - 0.001)
                XCTAssertLessThanOrEqual(point.x + strokeReach, canvas.maxX + 0.001)
            }
        }
    }

    func testMixDependsOnElapsedTimeNotFrameCount() {
        let start = Array(repeating: Float(0), count: 8)
        let target = Array(repeating: Float(1), count: 8)
        var manySmall = start
        for _ in 0..<10 {
            manySmall = WaveformPath.mix(current: manySmall, toward: target, smoothing: 0.4, dt: 0.01)
        }
        var fewLarge = start
        for _ in 0..<2 {
            fewLarge = WaveformPath.mix(current: fewLarge, toward: target, smoothing: 0.4, dt: 0.05)
        }
        for index in 0..<8 {
            XCTAssertEqual(manySmall[index], fewLarge[index], accuracy: 0.08)
        }
        let silent = WaveformPath.mix(current: target, toward: start, smoothing: 0.4, dt: 0.2)
        XCTAssertTrue(silent.allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite })
        XCTAssertLessThan(silent[0], 0.5)
    }

    func testVisualAmplitudeDoesNotMutateSourceSamples() {
        var source: [Float] = [0.2, -0.3, 0.4]
        let before = source
        _ = WaveformPath.points(
            samples: source,
            in: CGRect(x: 0, y: 0, width: 100, height: 40),
            amplitude: WaveformPath.canvasAmplitude(visualAmplitude: 2)
        )
        XCTAssertEqual(source, before)
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

    func testZeroCrossingTriggerStabilizesPhaseOffsetSines() {
        let count = 1_024
        let frequency: Float = 8
        let waveA: [Float] = (0..<count).map { i in
            0.8 * sin(2 * Float.pi * frequency * Float(i) / Float(count) - 0.9)
        }
        let waveB: [Float] = (0..<count).map { i in
            0.8 * sin(2 * Float.pi * frequency * Float(i) / Float(count) - 1.7)
        }
        let offsetA = WaveformSampler.risingZeroCrossingOffset(in: waveA, maxSearch: count / 4)
        let offsetB = WaveformSampler.risingZeroCrossingOffset(in: waveB, maxSearch: count / 4)
        XCTAssertNotNil(offsetA)
        XCTAssertNotNil(offsetB)
        XCTAssertNotEqual(offsetA, offsetB)

        let sampledA = WaveformSampler.downsample(waveA, count: 64)
        let sampledB = WaveformSampler.downsample(waveB, count: 64)
        // Both triggered windows begin at a rising zero-crossing so their leading buckets are positive and aligned.
        XCTAssertGreaterThan(sampledA[1], 0)
        XCTAssertGreaterThan(sampledB[1], 0)
        for index in 0..<16 {
            XCTAssertEqual(sampledA[index], sampledB[index], accuracy: 0.12)
        }
    }

    func testEchoMixTrailsBehindPrimaryMixAndHorizontalFadeStaysBounded() {
        let start = Array(repeating: Float(0), count: 8)
        let target = Array(repeating: Float(1), count: 8)
        let primary = WaveformPath.mix(current: start, toward: target, smoothing: 0.4, dt: 0.05)
        let echo = WaveformPath.echoMix(current: start, toward: target, smoothing: 0.4, dt: 0.05)

        XCTAssertEqual(echo.count, 8)
        XCTAssertGreaterThan(echo[0], 0)
        XCTAssertLessThan(echo[0], primary[0], "echo trace must lag behind the primary waveform")

        let fade = WaveformPath.horizontalFadeOpacities(baseOpacity: 0.8)
        XCTAssertEqual(fade.center, 0.8, accuracy: 0.000_1)
        XCTAssertLessThan(fade.edge, fade.center * 0.3)
        XCTAssertGreaterThan(fade.edge, 0)
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
