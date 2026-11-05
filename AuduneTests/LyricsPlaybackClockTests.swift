import XCTest
@testable import Audune

final class LyricsPlaybackClockTests: XCTestCase {
    func testPlayingPositionProjectsFromMonotonicAnchorAndRate() {
        let anchor = PlaybackClockAnchor(elapsedSeconds: 30, monotonicUptime: 100, revision: 1)

        let position = LyricsPlaybackClock.position(
            anchor: anchor,
            isPlaying: true,
            playbackRate: 1.5,
            durationSeconds: 120,
            nowUptime: 104
        )

        XCTAssertEqual(position, 36, accuracy: 0.001)
    }

    func testPauseFreezesAndSeekUsesNewAnchorImmediately() {
        let anchor = PlaybackClockAnchor(elapsedSeconds: 30, monotonicUptime: 100, revision: 2)

        let paused = LyricsPlaybackClock.position(
            anchor: anchor,
            isPlaying: false,
            playbackRate: 0,
            durationSeconds: 120,
            nowUptime: 110
        )
        let afterSeek = LyricsPlaybackClock.position(
            anchor: PlaybackClockAnchor(elapsedSeconds: 70, monotonicUptime: 110, revision: 3),
            isPlaying: true,
            playbackRate: 1,
            durationSeconds: 120,
            nowUptime: 110
        )

        XCTAssertEqual(paused, 30)
        XCTAssertEqual(afterSeek, 70)
    }

    func testPositionClampsAtDurationAndHandlesInvalidValues() {
        let anchor = PlaybackClockAnchor(elapsedSeconds: 9, monotonicUptime: 1, revision: 1)
        let clamped = LyricsPlaybackClock.position(
            anchor: anchor,
            isPlaying: true,
            playbackRate: 4,
            durationSeconds: 10,
            nowUptime: 2
        )
        let invalid = LyricsPlaybackClock.position(
            anchor: PlaybackClockAnchor(elapsedSeconds: .nan, monotonicUptime: .nan, revision: 1),
            isPlaying: true,
            playbackRate: .infinity,
            durationSeconds: 0,
            nowUptime: .infinity
        )

        XCTAssertEqual(clamped, 10)
        XCTAssertEqual(invalid, 0)
    }

    func testProgressClampsAndHidesUnknownOrInvalidDuration() {
        XCTAssertEqual(LyricsPlaybackClock.progress(position: 25, duration: 100), 0.25)
        XCTAssertEqual(LyricsPlaybackClock.progress(position: -1, duration: 100), 0)
        XCTAssertEqual(LyricsPlaybackClock.progress(position: 120, duration: 100), 1)
        XCTAssertNil(LyricsPlaybackClock.progress(position: 10, duration: 0))
        XCTAssertNil(LyricsPlaybackClock.progress(position: 10, duration: .infinity))
        XCTAssertNil(LyricsPlaybackClock.progress(position: .nan, duration: 100))
    }

    func testActiveLineAndWordProgressUseSamePosition() {
        let lines = [
            LyricsLine(id: 0, startSeconds: 1, endSeconds: 2, text: "First", translation: nil, words: nil),
            LyricsLine(id: 1, startSeconds: 2, endSeconds: 4, text: "Second", translation: nil, words: nil)
        ]
        let word = LyricsWord(id: 0, text: "word", startSeconds: 2, durationSeconds: 2)

        XCTAssertNil(LyricsPlaybackClock.activeLineIndex(in: lines, at: 0.5))
        XCTAssertEqual(LyricsPlaybackClock.activeLineIndex(in: lines, at: 2.5), 1)
        XCTAssertEqual(LyricsPlaybackClock.wordProgress(for: word, at: 3), 0.5, accuracy: 0.001)
        XCTAssertEqual(LyricsPlaybackClock.wordProgress(for: word, at: 9), 1)
        XCTAssertEqual(LyricsPlaybackClock.wordProgress(for: word, at: 1), 0)
    }


    func testActiveLineHandlesIntroGapsAndUnsyncedLines() {
        let lines = [
            LyricsLine(id: 0, startSeconds: nil, endSeconds: nil, text: "Plain", translation: nil, words: nil),
            LyricsLine(id: 1, startSeconds: 5, endSeconds: 8, text: "First", translation: nil, words: nil),
            LyricsLine(id: 2, startSeconds: 12, endSeconds: 16, text: "Second", translation: nil, words: nil)
        ]

        XCTAssertNil(LyricsPlaybackClock.activeLineIndex(in: lines, at: 4.99))
        XCTAssertEqual(LyricsPlaybackClock.activeLineIndex(in: lines, at: 5), 1)
        XCTAssertEqual(LyricsPlaybackClock.activeLineIndex(in: lines, at: 9), 1)
        XCTAssertEqual(LyricsPlaybackClock.activeLineIndex(in: lines, at: 12), 2)
        XCTAssertEqual(LyricsPlaybackClock.activeLineIndex(in: lines, at: 60), 2)

        let unsynced = lines.map { line in
            LyricsLine(id: line.id, startSeconds: nil, endSeconds: nil, text: line.text)
        }
        XCTAssertNil(LyricsPlaybackClock.activeLineIndex(in: unsynced, at: 10))
        XCTAssertNil(LyricsPlaybackClock.activeLineIndex(in: lines, at: .nan))
    }

    func testInterludeRequiresLongGapAndStaysInsideIt() {
        let lines = [
            LyricsLine(id: 0, startSeconds: 2, endSeconds: 5, text: "First", translation: nil, words: nil),
            LyricsLine(id: 1, startSeconds: 9, endSeconds: 12, text: "Second", translation: nil, words: nil)
        ]

        XCTAssertFalse(LyricsPlaybackClock.isInterlude(in: lines, activeIndex: nil, at: 7))
        XCTAssertFalse(LyricsPlaybackClock.isInterlude(in: lines, activeIndex: 0, at: 5.5))
        XCTAssertTrue(LyricsPlaybackClock.isInterlude(in: lines, activeIndex: 0, at: 7))
        XCTAssertTrue(LyricsPlaybackClock.isInterlude(in: lines, activeIndex: 0, at: 8.5))
        XCTAssertFalse(LyricsPlaybackClock.isInterlude(in: lines, activeIndex: 0, at: 8.9))
        XCTAssertFalse(LyricsPlaybackClock.isInterlude(in: lines, activeIndex: 0, at: .nan))

        let shortGap = [
            LyricsLine(id: 0, startSeconds: 2, endSeconds: 5, text: "First", translation: nil, words: nil),
            LyricsLine(id: 1, startSeconds: 7, endSeconds: 9, text: "Second", translation: nil, words: nil)
        ]
        XCTAssertFalse(LyricsPlaybackClock.isInterlude(in: shortGap, activeIndex: 0, at: 6))
    }

    func testWordProgressDoesNotInventTiming() {
        let zeroDuration = LyricsWord(id: 0, text: "word", startSeconds: 4, durationSeconds: 0)
        let invalidStart = LyricsWord(id: 1, text: "word", startSeconds: .nan, durationSeconds: 2)

        XCTAssertEqual(LyricsPlaybackClock.wordProgress(for: zeroDuration, at: 4), 0)
        XCTAssertEqual(LyricsPlaybackClock.wordProgress(for: invalidStart, at: 5), 0)
    }

    func testTranslationWaitsThenFadesInAfterLineFocus() {
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(sinceLineFocus: 0.1),
            0
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(sinceLineFocus: 0.2),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(sinceLineFocus: 0.3),
            1
        )
    }

    func testLyricsTrackKeyIsIndependentOfPlaybackAppIdentity() {
        let appleMusic = LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: "Album",
            durationSeconds: 180
        )
        let spotify = LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: "Album",
            durationSeconds: 180
        )

        XCTAssertEqual(appleMusic, spotify)
    }

    func testPresentationOffsetShiftsLyricsWithoutMovingPlaybackClock() {
        XCTAssertEqual(
            LyricsPlaybackClock.presentationPosition(30, offsetSeconds: 0.5),
            29.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.presentationPosition(30, offsetSeconds: -0.5),
            30.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.presentationPosition(0.2, offsetSeconds: 2),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.presentationPosition(12, offsetSeconds: .nan),
            12,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.presentationPosition(.nan, offsetSeconds: 1),
            0,
            accuracy: 0.001
        )
    }

    func testPlaybackPositionIsTheInverseOfPresentationOffset() {
        XCTAssertEqual(
            LyricsPlaybackClock.playbackPosition(forPresentationTime: 29.5, offsetSeconds: 0.5),
            30,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.playbackPosition(forPresentationTime: 30.5, offsetSeconds: -0.5),
            30,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.playbackPosition(forPresentationTime: 5, offsetSeconds: -2),
            3,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.playbackPosition(forPresentationTime: 12, offsetSeconds: .nan),
            12,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsPlaybackClock.playbackPosition(forPresentationTime: .nan, offsetSeconds: 1),
            0,
            accuracy: 0.001
        )
    }

    func testCanSeekRequiresPlayerSupportAndFiniteLineTimestamp() {
        let timedLine = LyricsLine(
            id: 0,
            startSeconds: 12,
            endSeconds: 15,
            text: "Timed",
            translation: nil,
            words: nil
        )
        let untimedLine = LyricsLine(
            id: 1,
            startSeconds: nil,
            endSeconds: nil,
            text: "Untimed",
            translation: nil,
            words: nil
        )
        let invalidLine = LyricsLine(
            id: 2,
            startSeconds: .infinity,
            endSeconds: nil,
            text: "Invalid",
            translation: nil,
            words: nil
        )
        let negativeLine = LyricsLine(
            id: 3,
            startSeconds: -1,
            endSeconds: nil,
            text: "Invalid",
            translation: nil,
            words: nil
        )

        XCTAssertTrue(LyricsPlaybackClock.canSeek(to: timedLine, isSeekSupported: true))
        XCTAssertFalse(LyricsPlaybackClock.canSeek(to: timedLine, isSeekSupported: false))
        XCTAssertFalse(LyricsPlaybackClock.canSeek(to: untimedLine, isSeekSupported: true))
        XCTAssertFalse(LyricsPlaybackClock.canSeek(to: invalidLine, isSeekSupported: true))
        XCTAssertFalse(LyricsPlaybackClock.canSeek(to: negativeLine, isSeekSupported: true))
    }
}
