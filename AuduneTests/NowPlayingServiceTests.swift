import AppKit
import XCTest
@testable import Audune

@MainActor
private final class FakeNowPlayingController: NowPlayingControlling {
    var onTrackReceived: ((NowPlayingTrackPayload?) -> Void)?
    var onListenerTerminated: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var seekCalls: [Double] = []
    private(set) var toggleCount = 0

    func startListening() {
        startCount += 1
    }

    func stopListening() {
        stopCount += 1
    }

    func togglePlayPause() {
        toggleCount += 1
    }

    func nextTrack() {}
    func previousTrack() {}

    func setTime(seconds: Double) {
        seekCalls.append(seconds)
    }

    func emit(_ payload: NowPlayingTrackPayload?) {
        onTrackReceived?(payload)
    }

    func emitTerminated() {
        onListenerTerminated?()
    }
}

@MainActor
final class NowPlayingServiceTests: XCTestCase {
    func testStartStopLifecycleAndEmptyState() {
        let fake = FakeNowPlayingController()
        let service = NowPlayingService(controllerFactory: { fake })

        service.syncDesiredListening(shouldListen: true)
        XCTAssertTrue(service.isListening)
        XCTAssertEqual(fake.startCount, 1)
        XCTAssertEqual(service.snapshot.availability, .listening)

        fake.emit(nil)
        XCTAssertEqual(service.snapshot.availability, .empty)
        XCTAssertFalse(service.snapshot.hasTrack)

        service.syncDesiredListening(shouldListen: false)
        XCTAssertFalse(service.isListening)
        XCTAssertEqual(fake.stopCount, 1)
        XCTAssertEqual(service.snapshot.availability, .idle)
    }

    func testTrackMappingAndUnavailableOnTerminate() {
        let fake = FakeNowPlayingController()
        let service = NowPlayingService(controllerFactory: { fake })
        service.startIfNeeded()

        fake.emit(
            NowPlayingTrackPayload(
                title: "Song",
                artist: "Artist",
                album: "Album",
                isPlaying: true,
                elapsedSeconds: 12,
                durationSeconds: 100,
                playbackRate: 1,
                bundleIdentifier: "com.example.player",
                artwork: nil,
                timestamp: Date()
            )
        )

        XCTAssertEqual(service.snapshot.availability, .listening)
        XCTAssertEqual(service.snapshot.title, "Song")
        XCTAssertEqual(service.snapshot.artist, "Artist")
        XCTAssertTrue(service.snapshot.isPlaying)
        XCTAssertTrue(service.snapshot.seekSupported)

        fake.emitTerminated()
        XCTAssertFalse(service.isListening)
        XCTAssertEqual(service.snapshot.availability, .unavailable)
        XCTAssertEqual(service.snapshot.title, "")
    }

    func testSeekUnsupportedFallbackAfterIgnoredSeek() async throws {
        let fake = FakeNowPlayingController()
        let service = NowPlayingService(controllerFactory: { fake })
        service.startIfNeeded()

        let stamp = Date()
        fake.emit(
            NowPlayingTrackPayload(
                title: "Track",
                artist: "A",
                album: "",
                isPlaying: true,
                elapsedSeconds: 10,
                durationSeconds: 200,
                playbackRate: 1,
                bundleIdentifier: "com.spotify.client",
                artwork: nil,
                timestamp: stamp
            )
        )

        service.seek(to: 80)
        XCTAssertEqual(fake.seekCalls, [80])
        XCTAssertEqual(service.snapshot.elapsedSeconds, 80, accuracy: 0.001)

        // Pending seek is evaluated only after 0.45s.
        try await Task.sleep(for: .milliseconds(500))
        fake.emit(
            NowPlayingTrackPayload(
                title: "Track",
                artist: "A",
                album: "",
                isPlaying: true,
                elapsedSeconds: 10.2,
                durationSeconds: 200,
                playbackRate: 1,
                bundleIdentifier: "com.spotify.client",
                artwork: nil,
                timestamp: Date()
            )
        )

        XCTAssertFalse(service.snapshot.seekSupported)

        service.seek(to: 120)
        XCTAssertEqual(fake.seekCalls, [80], "Further seeks must not call MediaRemote once unsupported")
    }

    func testDisplayElapsedAdvancesWhilePlaying() {
        var snapshot = NowPlayingSnapshot.idle
        snapshot.isPlaying = true
        snapshot.elapsedSeconds = 10
        snapshot.durationSeconds = 100
        snapshot.playbackRate = 1
        snapshot.lastUpdated = Date().addingTimeInterval(-2)
        let displayed = snapshot.displayElapsed(at: Date())
        XCTAssertEqual(displayed, 12, accuracy: 0.25)
    }

    func testRejectsNoisyBackwardElapsedJumpOnSameTrack() {
        let fake = FakeNowPlayingController()
        let service = NowPlayingService(controllerFactory: { fake })
        service.startIfNeeded()

        let t0 = Date()
        fake.emit(
            NowPlayingTrackPayload(
                title: "天気の子",
                artist: "STRlighT",
                album: "",
                isPlaying: true,
                elapsedSeconds: 140,
                durationSeconds: 231,
                playbackRate: 1,
                bundleIdentifier: "com.spotify.client",
                artwork: nil,
                timestamp: t0
            )
        )
        let before = service.snapshot.displayElapsed(at: t0.addingTimeInterval(3))
        XCTAssertEqual(before, 143, accuracy: 0.2)

        // Stale MediaRemote sample reporting ~0:41 while local clock is ~2:23.
        fake.emit(
            NowPlayingTrackPayload(
                title: "天気の子",
                artist: "STRlighT",
                album: "",
                isPlaying: true,
                elapsedSeconds: 41,
                durationSeconds: 231,
                playbackRate: 1,
                bundleIdentifier: "com.spotify.client",
                artwork: nil,
                timestamp: t0.addingTimeInterval(3)
            )
        )

        let after = service.snapshot.displayElapsed(at: t0.addingTimeInterval(3))
        XCTAssertEqual(after, before, accuracy: 0.35)
        XCTAssertGreaterThan(after, 100)
    }
}
