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
}
