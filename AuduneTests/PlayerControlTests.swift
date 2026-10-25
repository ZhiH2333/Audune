import XCTest
@testable import Audune

final class PlayerControlTests: XCTestCase {
    func testPlayerStateTextParsesPublicNamesAndCodes() {
        XCTAssertEqual(PlayerStateText.parse("playing"), .playing)
        XCTAssertEqual(PlayerStateText.parse("paused"), .paused)
        XCTAssertEqual(PlayerStateText.parse("stopped"), .stopped)
        XCTAssertEqual(PlayerStateText.parse("kPSP"), .playing)
        XCTAssertEqual(PlayerStateText.parse("kPSp"), .paused)
        XCTAssertEqual(PlayerStateText.parse("kPSS"), .stopped)
        XCTAssertEqual(PlayerStateText.parse("nope"), .unknown)
    }

    func testAppleEventFailuresStayDistinct() {
        XCTAssertEqual(AppleEventFailure.availability(status: AppleEventFailure.automationDenied), .automationDenied)
        XCTAssertEqual(AppleEventFailure.availability(status: AppleEventFailure.applicationNotRunning), .notRunning)
        XCTAssertEqual(AppleEventFailure.availability(status: -1), .failed("Apple Event -1"))
    }

    func testPlaybackButtonStaysDisabledWithoutAReadyTarget() {
        XCTAssertFalse(PlaybackButton.isEnabled(selection: "", availability: .ready, busy: false))
        XCTAssertFalse(PlaybackButton.isEnabled(selection: "music", availability: .notRunning, busy: false))
        XCTAssertFalse(PlaybackButton.isEnabled(selection: "music", availability: .automationDenied, busy: false))
        XCTAssertFalse(PlaybackButton.isEnabled(selection: "music", availability: .noSelection, busy: false))
        XCTAssertFalse(PlaybackButton.isEnabled(selection: "music", availability: .ready, busy: true))
        XCTAssertTrue(PlaybackButton.isEnabled(selection: "music", availability: .ready, busy: false))
        XCTAssertEqual(PlaybackButton.title(availability: .ready, state: .playing), "Pause")
        XCTAssertEqual(PlaybackButton.title(availability: .ready, state: .paused), "Play")
        XCTAssertEqual(PlaybackButton.title(availability: .automationDenied, state: .playing), "Denied")
        XCTAssertEqual(PlaybackButton.title(availability: .notRunning, state: .unknown), "Not running")
    }

    @MainActor
    func testMusicAvailabilityDoesNotRequireSendingACommand() {
        let music = MusicPlayerController()
        switch music.availability() {
        case .ready, .notRunning:
            break
        case .notInstalled, .noSelection, .automationDenied, .failed:
            XCTFail("Music.app should be installed")
        }
    }

    @MainActor
    func testSpotifyAvailabilityDoesNotRequireSendingACommand() {
        let spotify = SpotifyPlayerController()
        switch spotify.availability() {
        case .ready, .notRunning:
            break
        case .notInstalled, .noSelection, .automationDenied, .failed:
            XCTFail("Spotify.app should be installed")
        }
    }
}
