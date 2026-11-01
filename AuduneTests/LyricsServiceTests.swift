import XCTest
@testable import Audune

@MainActor
final class LyricsServiceTests: XCTestCase {
    func testLRCParserReadsTimedLinesAndActiveIndex() {
        let raw = """
        [ti:Demo]
        [00:01.00]First line
        [00:05.50]Second line
        [01:00.00]Third line
        """
        let lines = LRCParser.parse(raw)
        XCTAssertEqual(lines.map(\.text), ["First line", "Second line", "Third line"])
        XCTAssertEqual(lines[0].timeSeconds, 1, accuracy: 0.001)
        XCTAssertEqual(lines[1].timeSeconds, 5.5, accuracy: 0.001)
        XCTAssertEqual(LRCParser.activeIndex(in: lines, at: 0.5), nil)
        XCTAssertEqual(LRCParser.activeIndex(in: lines, at: 1.0), 0)
        XCTAssertEqual(LRCParser.activeIndex(in: lines, at: 5.5), 1)
        XCTAssertEqual(LRCParser.activeIndex(in: lines, at: 90), 2)
    }

    func testNetworkDisabledPerformsZeroFetches() async {
        let fetcher = RecordingLyricsFetcher()
        fetcher.result = .success("[00:01.00]Hello")
        let service = LyricsService(fetcher: fetcher)
        var snapshot = NowPlayingSnapshot.idle
        snapshot.availability = .listening
        snapshot.title = "Song"
        snapshot.artist = "Artist"
        snapshot.lastUpdated = Date()

        service.sync(snapshot: snapshot, networkEnabled: false)
        XCTAssertEqual(service.status, .disabled)
        XCTAssertEqual(fetcher.queryCount, 0)
        XCTAssertTrue(service.lines.isEmpty)
    }

    func testNetworkEnabledFetchesAndCaches() async {
        let fetcher = RecordingLyricsFetcher()
        fetcher.result = .success("[00:01.00]Hello\n[00:02.00]World")
        let service = LyricsService(fetcher: fetcher)
        var snapshot = NowPlayingSnapshot.idle
        snapshot.availability = .listening
        snapshot.title = "Song"
        snapshot.artist = "Artist"
        snapshot.lastUpdated = Date()

        service.sync(snapshot: snapshot, networkEnabled: true)
        XCTAssertEqual(service.status, .loading)
        let deadline = Date().addingTimeInterval(2)
        while service.status == .loading, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(service.status, .ready)
        XCTAssertEqual(service.lines.map(\.text), ["Hello", "World"])
        XCTAssertEqual(fetcher.queryCount, 1)

        service.sync(snapshot: snapshot, networkEnabled: true)
        XCTAssertEqual(fetcher.queryCount, 1)
    }

    func testTrackChangeCancelsStaleResult() async {
        let fetcher = RecordingLyricsFetcher()
        fetcher.result = .success("[00:01.00]One")
        let service = LyricsService(fetcher: fetcher)
        var first = NowPlayingSnapshot.idle
        first.availability = .listening
        first.title = "A"
        first.artist = "X"
        first.lastUpdated = Date()
        service.sync(snapshot: first, networkEnabled: true)

        fetcher.result = .success("[00:01.00]Two")
        var second = first
        second.title = "B"
        service.sync(snapshot: second, networkEnabled: true)

        let deadline = Date().addingTimeInterval(2)
        while service.status == .loading, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(service.status, .ready)
        XCTAssertEqual(service.lines.first?.text, "Two")
        XCTAssertEqual(fetcher.queryCount, 2)
    }
}

@MainActor
private final class ReconcileFakeNowPlayingController: NowPlayingControlling {
    var onTrackReceived: ((NowPlayingTrackPayload?) -> Void)?
    var onListenerTerminated: (() -> Void)?
    func startListening() {}
    func stopListening() {}
    func togglePlayPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func setTime(seconds: Double) {}
}

@MainActor
final class NowPlayingListeningReconcileTests: XCTestCase {
    func testSharedServiceListensWhenEitherSurfaceWantsIt() {
        let fake = ReconcileFakeNowPlayingController()
        let service = NowPlayingService(controllerFactory: { fake })
        let suite = "AuduneNPReconcileTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let spike = ProcessTapSpike()
        let island = IslandWindowController(
            spike: spike,
            defaults: defaults,
            nowPlaying: service,
            screenProvider: { [] },
            allowsOrderFront: false,
            activateOnInit: false
        )
        let fullscreen = FullscreenWindowController(spike: spike, defaults: defaults, nowPlaying: service)

        let reconcile = {
            let shouldListen = island.wantsNowPlayingListening || fullscreen.wantsNowPlayingListening
            service.syncDesiredListening(shouldListen: shouldListen)
            island.refreshNowPlayingSnapshot()
            fullscreen.refreshNowPlayingSnapshot()
        }
        island.reconcileNowPlayingListening = reconcile
        fullscreen.reconcileNowPlayingListening = reconcile

        XCTAssertFalse(service.isListening)

        var islandPrefs = IslandPreferences.standard
        islandPrefs.isEnabled = true
        islandPrefs.nowPlayingEnabled = true
        island.model.prefs = islandPrefs
        // Unsupported geometry → island does not want listening.
        XCTAssertFalse(island.wantsNowPlayingListening)

        fullscreen.model.prefs.isEnabled = true
        fullscreen.model.isPresented = true
        reconcile()
        XCTAssertTrue(fullscreen.wantsNowPlayingListening)
        XCTAssertTrue(service.isListening)

        fullscreen.model.isPresented = false
        reconcile()
        XCTAssertFalse(service.isListening)

        island.shutdown()
        fullscreen.shutdown()
        defaults.removePersistentDomain(forName: suite)
    }
}
