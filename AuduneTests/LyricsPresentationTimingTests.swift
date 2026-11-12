import XCTest
@testable import Audune

final class LyricsPresentationTimingTests: XCTestCase {
    func testManualBrowsingOpacityKeepsFocusBrightAndDimsOtherLines() {
        XCTAssertEqual(
            LyricsPresentationTiming.manualBrowsingOpacity(isFocused: true),
            1
        )
        XCTAssertEqual(
            LyricsPresentationTiming.manualBrowsingOpacity(isFocused: false),
            0.30
        )
    }

    func testTranslationRevealFollowsPlaybackPosition() {
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 9.9),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 10.12),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 10.20),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 30),
            1,
            accuracy: 0.0001
        )
    }

    func testTranslationRevealFreezesWithPlaybackAndHandlesMissingTiming() {
        let frozen = LyricsPresentationTiming.translationOpacity(
            lineStartSeconds: 10,
            positionSeconds: 10.20
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(
                lineStartSeconds: 10,
                positionSeconds: 10.20
            ),
            frozen,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: nil, positionSeconds: 10),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: .nan, positionSeconds: 10),
            1,
            accuracy: 0.0001
        )
    }

    func testWordLiftEmphasisGlowAndStaggerFollowAppleMusicCurves() {
        // Continuous arch: zero at boundaries, negative peak at midpoint.
        XCTAssertEqual(LyricsPresentationTiming.wordLiftOffset(progress: 0, durationSeconds: 0.5), 0)
        XCTAssertEqual(LyricsPresentationTiming.wordLiftOffset(progress: 1, durationSeconds: 0.5), 0)
        let shortMidLift = LyricsPresentationTiming.wordLiftOffset(progress: 0.5, durationSeconds: 0.4)
        let sustainedMidLift = LyricsPresentationTiming.wordLiftOffset(progress: 0.5, durationSeconds: 1.2)
        XCTAssertLessThan(shortMidLift, -1.5)
        XCTAssertLessThan(sustainedMidLift, shortMidLift)
        XCTAssertEqual(
            LyricsPresentationTiming.wordLiftOffset(progress: 0.5, durationSeconds: 1.2, reduceMotion: true),
            0
        )

        // Sustained word scale blooms only for words >= 0.75 s and respects Reduce Motion.
        XCTAssertEqual(LyricsPresentationTiming.wordEmphasisScale(progress: 0.5, durationSeconds: 0.4), 1.0)
        XCTAssertGreaterThan(LyricsPresentationTiming.wordEmphasisScale(progress: 0.5, durationSeconds: 1.2), 1.02)
        XCTAssertEqual(
            LyricsPresentationTiming.wordEmphasisScale(progress: 0.5, durationSeconds: 1.2, reduceMotion: true),
            1.0
        )

        // Continuous glow envelope fades smoothly at boundaries instead of snapping at 1.0.
        XCTAssertEqual(LyricsPresentationTiming.wordGlowOpacity(progress: 0, durationSeconds: 0.8), 0)
        XCTAssertEqual(LyricsPresentationTiming.wordGlowOpacity(progress: 1, durationSeconds: 0.8), 0)
        XCTAssertGreaterThan(LyricsPresentationTiming.wordGlowOpacity(progress: 0.5, durationSeconds: 0.8), 0.5)

        // Cascading stagger delay and artwork play/pause spring scale.
        XCTAssertEqual(LyricsPresentationTiming.staggeredRowDelay(distance: 0), 0)
        XCTAssertEqual(LyricsPresentationTiming.staggeredRowDelay(distance: 3), 0.084, accuracy: 0.0001)
        XCTAssertEqual(LyricsPresentationTiming.staggeredRowDelay(distance: 20), 7 * 0.028, accuracy: 0.0001)
        XCTAssertEqual(LyricsPresentationTiming.staggeredRowDelay(distance: 3, reduceMotion: true), 0)

        XCTAssertEqual(LyricsPresentationTiming.artworkScale(isPlaying: true), 1.0)
        XCTAssertEqual(LyricsPresentationTiming.artworkScale(isPlaying: false), 0.86, accuracy: 0.0001)
        XCTAssertEqual(LyricsPresentationTiming.artworkScale(isPlaying: false, reduceMotion: true), 1.0)
    }

    func testDepthOfFieldOpacityAndBlurKeepViewportFilledAndCullOffscreenBlur() {
        // Focused active line is crisp and bright; interlude waiting dims slightly.
        XCTAssertEqual(
            LyricsPresentationTiming.rowOpacity(distance: 0, hasActiveLine: true, isPast: false),
            0.98,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.rowOpacity(distance: 0, hasActiveLine: true, isPast: false, isWaiting: true),
            0.58,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.rowBlurRadius(distance: 0, hasActiveLine: true, isPast: false),
            0
        )

        // Upcoming lines stay visible across a deep viewport wall (distances 1...7) and blur progressively.
        let upcoming1 = LyricsPresentationTiming.rowOpacity(distance: 1, hasActiveLine: true, isPast: false)
        let upcoming3 = LyricsPresentationTiming.rowOpacity(distance: 3, hasActiveLine: true, isPast: false)
        let upcoming6 = LyricsPresentationTiming.rowOpacity(distance: 6, hasActiveLine: true, isPast: false)
        XCTAssertGreaterThan(upcoming1, upcoming3)
        XCTAssertGreaterThan(upcoming3, 0.20)
        XCTAssertGreaterThan(upcoming6, 0.08)

        let blur1 = LyricsPresentationTiming.rowBlurRadius(distance: 1, hasActiveLine: true, isPast: false)
        let blur3 = LyricsPresentationTiming.rowBlurRadius(distance: 3, hasActiveLine: true, isPast: false)
        XCTAssertGreaterThan(blur1, 1.4)
        XCTAssertGreaterThan(blur3, blur1)

        // Past lines fade faster and blur slightly more than upcoming lines at the same distance.
        let past2 = LyricsPresentationTiming.rowOpacity(distance: 2, hasActiveLine: true, isPast: true)
        let upcoming2 = LyricsPresentationTiming.rowOpacity(distance: 2, hasActiveLine: true, isPast: false)
        XCTAssertLessThan(past2, upcoming2)
        XCTAssertGreaterThan(
            LyricsPresentationTiming.rowBlurRadius(distance: 2, hasActiveLine: true, isPast: true),
            LyricsPresentationTiming.rowBlurRadius(distance: 2, hasActiveLine: true, isPast: false)
        )

        // Invisible distant rows and hovered/manual rows skip Gaussian blur completely.
        XCTAssertEqual(
            LyricsPresentationTiming.rowBlurRadius(distance: 8, hasActiveLine: true, isPast: false),
            0
        )
        XCTAssertEqual(
            LyricsPresentationTiming.rowBlurRadius(distance: 5, hasActiveLine: true, isPast: true),
            0
        )
        XCTAssertEqual(
            LyricsPresentationTiming.rowBlurRadius(distance: 2, hasActiveLine: true, isPast: false, isHovered: true),
            0
        )
        XCTAssertEqual(
            LyricsPresentationTiming.rowBlurRadius(distance: 2, hasActiveLine: true, isPast: false, manualMode: true),
            0
        )
    }

    func testAnalyticUnderdampedSpringProducesStaggeredAccordionWave() {
        let initial: Double = 42.0
        let delayRow0 = LyricsPresentationTiming.staggeredRowDelay(distance: 0)
        let delayRow3 = LyricsPresentationTiming.staggeredRowDelay(distance: 3)

        // At t = 0.05s, row 0 is already advancing toward 0 while row 3 (delay 0.084s) still holds its initial offset.
        let disp0Early = LyricsPresentationTiming.underdampedSpringDisplacement(
            elapsed: 0.05,
            delay: delayRow0,
            initialOffset: initial
        )
        let disp3Early = LyricsPresentationTiming.underdampedSpringDisplacement(
            elapsed: 0.05,
            delay: delayRow3,
            initialOffset: initial
        )
        XCTAssertLessThan(disp0Early, initial)
        XCTAssertEqual(disp3Early, initial, accuracy: 0.0001)

        // Mid-transition, closer rows have traveled further than distant rows (wave spread).
        let disp0Mid = LyricsPresentationTiming.underdampedSpringDisplacement(
            elapsed: 0.16,
            delay: delayRow0,
            initialOffset: initial
        )
        let disp3Mid = LyricsPresentationTiming.underdampedSpringDisplacement(
            elapsed: 0.16,
            delay: delayRow3,
            initialOffset: initial
        )
        XCTAssertLessThan(disp0Mid, disp3Mid)

        // Settled after ~3.2x response.
        XCTAssertEqual(
            LyricsPresentationTiming.underdampedSpringDisplacement(
                elapsed: 1.8,
                delay: delayRow3,
                initialOffset: initial
            ),
            0
        )
    }
}
