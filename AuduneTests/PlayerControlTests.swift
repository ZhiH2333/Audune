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
        XCTAssertEqual(AppleEventFailure.availability(status: AppleEventFailure.wouldRequireConsent), .automationNotRequested)
        XCTAssertEqual(AppleEventFailure.availability(status: AppleEventFailure.timedOut), .failed("The player did not answer in time."))
    }

    func testAutomationPermissionStatusCodesMapToDistinctStates() {
        XCTAssertEqual(AutomationPermission.from(status: 0), .granted)
        XCTAssertEqual(AutomationPermission.from(status: -1744), .notRequested)
        XCTAssertEqual(AutomationPermission.from(status: -1743), .denied)
        XCTAssertEqual(AutomationPermission.from(status: -600), .targetNotRunning)
        XCTAssertEqual(AutomationPermission.from(status: -50), .failed(-50))
        XCTAssertEqual(AutomationPermission.granted.availability, .ready)
        XCTAssertEqual(AutomationPermission.notRequested.availability, .automationNotRequested)
        XCTAssertEqual(AutomationPermission.denied.availability, .automationDenied)
        XCTAssertEqual(AutomationPermission.targetNotRunning.availability, .notRunning)
    }

    func testOnlyAGrantedPermissionEnablesPlayback() {
        for availability in [PlayerAvailability.checking, .automationNotRequested, .automationDenied, .notRunning, .notInstalled] {
            XCTAssertFalse(PlaybackButton.isEnabled(selection: "music", availability: availability, busy: false))
        }
        XCTAssertEqual(PlaybackButton.title(availability: .automationNotRequested, state: .unknown), "Needs access")
        XCTAssertEqual(PlaybackButton.title(availability: .checking, state: .unknown), "Checking")
    }

    func testAppBundleExplainsAudioCaptureAndAppleEventsAndNothingElse() {
        let info = Bundle(for: MusicPlayerController.self).infoDictionary ?? [:]

        XCTAssertFalse((info["NSAudioCaptureUsageDescription"] as? String ?? "").isEmpty)
        XCTAssertFalse((info["NSAppleEventsUsageDescription"] as? String ?? "").isEmpty)
        XCTAssertNil(info["NSMicrophoneUsageDescription"], "Audune never asks for the microphone")
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
        case .notInstalled, .noSelection, .checking, .automationNotRequested, .automationDenied, .failed:
            XCTFail("Music.app should be installed")
        }
    }

    @MainActor
    func testSpotifyAvailabilityDoesNotRequireSendingACommand() {
        let spotify = SpotifyPlayerController()
        switch spotify.availability() {
        case .ready, .notRunning:
            break
        case .notInstalled, .noSelection, .checking, .automationNotRequested, .automationDenied, .failed:
            XCTFail("Spotify.app should be installed")
        }
    }
}
