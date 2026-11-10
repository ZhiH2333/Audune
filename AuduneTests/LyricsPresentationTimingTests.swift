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
}
