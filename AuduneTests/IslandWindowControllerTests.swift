import AppKit
import CoreGraphics
import XCTest
@testable import Audune

final class RecordingIslandHaptics: IslandHapticPerforming {
    var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []

    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        patterns.append(pattern)
    }
}

final class SilentIslandHaptics: IslandHapticPerforming {
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {}
}

@MainActor
private final class FakeIslandNowPlayingController: NowPlayingControlling {
    var onTrackReceived: ((NowPlayingTrackPayload?) -> Void)?
    var onListenerTerminated: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startListening() { startCount += 1 }
    func stopListening() { stopCount += 1 }
    func togglePlayPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func setTime(seconds: Double) {}

    func emit(_ payload: NowPlayingTrackPayload?) {
        onTrackReceived?(payload)
    }
}

final class IslandWindowControllerTests: XCTestCase {
    private let suite = "AuduneIslandWindowControllerTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    private func notchedScreen(
        id: String = "display-1",
        origin: CGPoint = .zero,
        size: CGSize = CGSize(width: 1512, height: 982),
        notchWidth: CGFloat = 184,
        notchHeight: CGFloat = 32
    ) -> IslandScreenDescriptor {
        let frame = CGRect(origin: origin, size: size)
        let leftWidth = (size.width - notchWidth) / 2
        let rightWidth = size.width - leftWidth - notchWidth
        let topY = frame.maxY - notchHeight
        return IslandScreenDescriptor(
            id: id,
            localizedName: "Built-in Liquid Retina XDR Display",
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: size.width, height: size.height - notchHeight),
            safeAreaTop: notchHeight,
            auxiliaryTopLeft: CGRect(x: frame.minX, y: topY, width: leftWidth, height: notchHeight),
            auxiliaryTopRight: CGRect(x: frame.minX + leftWidth + notchWidth, y: topY, width: rightWidth, height: notchHeight),
            backingScaleFactor: 2
        )
    }

    private func nonNotchedScreen(id: String = "display-external") -> IslandScreenDescriptor {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        return IslandScreenDescriptor(
            id: id,
            localizedName: "External Display",
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1416),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            backingScaleFactor: 2
        )
    }

    @MainActor
    func testConfiguredPanelUsesTransparentStatusBarFlagsAndCompactFrameOnNotchedScreen() throws {
        let screen = notchedScreen()
        let expectedGeometry = try IslandGeometry.analyze(screen: screen).get()
        let spike = ProcessTapSpike()
        let controller = IslandWindowController(
            spike: spike,
            defaults: defaults,
            screenProvider: { [screen] },
            allowsOrderFront: false
        )
        defer { controller.shutdown() }

        let inspection = controller.inspectWindowForTests()
        XCTAssertEqual(inspection.state, .compact)
        XCTAssertTrue(inspection.isVisible)
        XCTAssertEqual(inspection.frame, expectedGeometry.compactFrame)
        XCTAssertEqual(inspection.level, .statusBar)
        XCTAssertTrue(inspection.isFloatingPanel)
        XCTAssertFalse(inspection.hidesOnDeactivate)
        XCTAssertEqual(inspection.collectionBehavior, [.canJoinAllSpaces, .stationary, .ignoresCycle])
        XCTAssertFalse(inspection.isMovable)
        XCTAssertFalse(inspection.isMovableByWindowBackground)
        XCTAssertFalse(inspection.isOpaque)
        XCTAssertEqual(inspection.backgroundAlpha, 0)
        XCTAssertFalse(inspection.hasShadow)
        XCTAssertFalse(inspection.ignoresMouseEvents)
        XCTAssertFalse(inspection.hostIsOpaque)
        XCTAssertTrue(inspection.isTimerRunning)
        XCTAssertNil(inspection.unsupportedReason)
        XCTAssertEqual(spike.phase, .idle)
    }

    @MainActor
    func testHoverExpandPinAndEscapeUpdateWindowFrameWithoutStartingAudioCapture() throws {
        let screen = notchedScreen()
        let expectedGeometry = try IslandGeometry.analyze(screen: screen).get()
        let spike = ProcessTapSpike()
        let controller = IslandWindowController(
            spike: spike,
            defaults: defaults,
            screenProvider: { [screen] },
            allowsOrderFront: false
        )
        defer { controller.shutdown() }

        let compactFrame = controller.inspectWindowForTests().frame
        controller.simulatePointerEntered(at: 10)
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)
        XCTAssertEqual(controller.inspectWindowForTests().frame, compactFrame)
        XCTAssertEqual(compactFrame, expectedGeometry.compactFrame)
        XCTAssertTrue(controller.model.hoverArmed)

        controller.simulateExpandTimerFired(now: 10.20)
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)
        XCTAssertEqual(controller.inspectWindowForTests().frame, expectedGeometry.compactFrame)

        controller.simulateExpandTimerFired(now: 10.35)
        XCTAssertEqual(controller.inspectWindowForTests().state, .expanded)
        XCTAssertEqual(controller.inspectWindowForTests().frame, expectedGeometry.expandedPlayerFrame())
        XCTAssertFalse(controller.model.hoverArmed)

        controller.togglePin()
        XCTAssertEqual(controller.inspectWindowForTests().state, .pinned)
        controller.simulatePointerExited(at: 10.0)
        controller.simulateCollapseTimerFired(now: 50.0)
        XCTAssertEqual(controller.inspectWindowForTests().state, .pinned)
        XCTAssertEqual(controller.inspectWindowForTests().frame, expectedGeometry.expandedPlayerFrame())

        controller.simulateEscapePressed()
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)
        XCTAssertEqual(controller.inspectWindowForTests().frame, expectedGeometry.compactFrame)
        XCTAssertEqual(spike.phase, .idle)
    }

    @MainActor
    func testFullScreenViewFillsSelectedDisplayAndEscapeReturnsToExpandedIsland() throws {
        let screen = notchedScreen(origin: CGPoint(x: -1512, y: 120))
        let geometry = try IslandGeometry.analyze(screen: screen).get()
        let spike = ProcessTapSpike()
        let controller = IslandWindowController(
            spike: spike,
            defaults: defaults,
            screenProvider: { [screen] },
            allowsOrderFront: false
        )
        defer { controller.shutdown() }

        controller.expand()
        controller.toggleFullScreenView()
        XCTAssertTrue(controller.inspectWindowForTests().isFullScreen)
        XCTAssertEqual(controller.inspectWindowForTests().frame, geometry.screenFrame)
        XCTAssertEqual(controller.inspectWindowForTests().state, .expanded)
        XCTAssertEqual(spike.phase, .idle)

        controller.simulateEscapePressed()
        XCTAssertFalse(controller.inspectWindowForTests().isFullScreen)
        XCTAssertEqual(controller.inspectWindowForTests().frame, geometry.expandedPlayerFrame())
        XCTAssertEqual(controller.inspectWindowForTests().state, .expanded)

        controller.simulateEscapePressed()
        XCTAssertEqual(controller.inspectWindowForTests().frame, geometry.compactFrame)
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)
        XCTAssertEqual(spike.phase, .idle)
    }

    @MainActor
    func testLyricsSceneUsesTemporaryNowPlayingDemandWithoutChangingSavedPreference() {
        let screen = notchedScreen()
        let spike = ProcessTapSpike()
        let fake = FakeIslandNowPlayingController()
        let service = NowPlayingService(controllerFactory: { fake })
        let controller = IslandWindowController(
            spike: spike,
            defaults: defaults,
            nowPlaying: service,
            screenProvider: { [screen] },
            allowsOrderFront: false
        )
        defer { controller.shutdown() }

        controller.expand()
        controller.toggleFullScreenView()
        controller.selectMode(.orbit)
        controller.setFullScreenScene(.lyrics)

        XCTAssertTrue(service.isListening)
        XCTAssertEqual(fake.startCount, 1)
        XCTAssertEqual(controller.model.prefs.mode, .orbit)
        XCTAssertFalse(controller.model.prefs.nowPlayingEnabled)
        XCTAssertFalse(defaults.bool(forKey: IslandPreferenceKey.nowPlayingEnabled))

        controller.setNowPlayingEnabled(true)
        controller.setFullScreenScene(.visualizer)
        XCTAssertTrue(service.isListening)
        XCTAssertEqual(controller.model.prefs.mode, .orbit)
        XCTAssertTrue(controller.model.prefs.nowPlayingEnabled)
        XCTAssertTrue(defaults.bool(forKey: IslandPreferenceKey.nowPlayingEnabled))

        controller.setNowPlayingEnabled(false)
        XCTAssertFalse(service.isListening)
        XCTAssertEqual(fake.stopCount, 1)

        controller.setFullScreenScene(.lyrics)
        XCTAssertTrue(service.isListening)
        controller.toggleFullScreenView()
        XCTAssertFalse(service.isListening)
        XCTAssertFalse(controller.model.prefs.nowPlayingEnabled)
        XCTAssertEqual(fake.startCount, 2)
        XCTAssertEqual(fake.stopCount, 2)

        controller.toggleFullScreenView()
        controller.setFullScreenScene(.lyrics)
        XCTAssertTrue(service.isListening)
        controller.setEnabled(false)
        XCTAssertFalse(service.isListening)
        XCTAssertFalse(controller.model.isFullScreen)
        XCTAssertEqual(controller.model.fullScreenScene, .visualizer)
        XCTAssertEqual(fake.startCount, 3)
        XCTAssertEqual(fake.stopCount, 3)
    }

    @MainActor
    func testLyricsSceneImportsMatchesAcrossPlayersAndDeletesTheCurrentDocument() throws {
        let screen = notchedScreen()
        let spike = ProcessTapSpike()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuduneLyricsControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("song.lrc")
        try Data("[00:01.00]First line\n[00:03.00]Second line".utf8).write(to: sourceURL)

        let fake = FakeIslandNowPlayingController()
        let service = NowPlayingService(controllerFactory: { fake })
        let storeURL = directory.appendingPathComponent("lyrics.json")
        let controller = IslandWindowController(
            spike: spike,
            defaults: defaults,
            nowPlaying: service,
            lyricsStoreFactory: { LocalLyricsStore(fileURL: storeURL) },
            screenProvider: { [screen] },
            allowsOrderFront: false
        )
        defer { controller.shutdown() }

        controller.expand()
        controller.toggleFullScreenView()
        controller.setFullScreenScene(.lyrics)
        let timestamp = Date()
        fake.emit(
            NowPlayingTrackPayload(
                title: "Song",
                artist: "Artist",
                album: "Album",
                isPlaying: true,
                elapsedSeconds: 1.2,
                durationSeconds: 180,
                playbackRate: 1,
                bundleIdentifier: "com.example.player.one",
                artwork: nil,
                timestamp: timestamp
            )
        )
        controller.refreshNowPlayingSnapshot()
        XCTAssertEqual(controller.model.lyricsState, .onlineUnavailable)
        let initialTrackRevision = controller.model.lyricsTrackRevision

        controller.importLyrics(at: sourceURL)
        guard case .local(let document) = controller.model.lyricsState else {
            return XCTFail("Expected imported local lyrics")
        }
        XCTAssertEqual(controller.model.activeLyricsLineIndex, 0)

        service.seek(to: 3.2)
        controller.refreshNowPlayingSnapshot()
        XCTAssertEqual(controller.model.activeLyricsLineIndex, 1)

        fake.emit(
            NowPlayingTrackPayload(
                title: "Song",
                artist: "Artist",
                album: "Album",
                isPlaying: true,
                elapsedSeconds: 1.2,
                durationSeconds: 180,
                playbackRate: 1,
                bundleIdentifier: "com.example.player.two",
                artwork: nil,
                timestamp: Date()
            )
        )
        controller.refreshNowPlayingSnapshot()
        guard case .local(let matchedDocument) = controller.model.lyricsState else {
            return XCTFail("Expected the saved lyrics to match across players")
        }
        XCTAssertEqual(matchedDocument.id, document.id)
        XCTAssertEqual(controller.model.lyricsTrackRevision, initialTrackRevision)

        fake.emit(
            NowPlayingTrackPayload(
                title: "Another Song",
                artist: "Another Artist",
                album: "Another Album",
                isPlaying: true,
                elapsedSeconds: 0,
                durationSeconds: 200,
                playbackRate: 1,
                bundleIdentifier: "com.example.player.two",
                artwork: nil,
                timestamp: Date()
            )
        )
        controller.refreshNowPlayingSnapshot()
        XCTAssertEqual(controller.model.lyricsState, .onlineUnavailable)
        XCTAssertGreaterThan(controller.model.lyricsTrackRevision, initialTrackRevision)
        XCTAssertEqual(controller.model.lyricsPositionSeconds, 0)
        controller.deleteLyrics(document.id)
        XCTAssertEqual(
            try LocalLyricsStore(fileURL: storeURL).resolve(
                trackKey: LyricsTrackKey(
                    isrc: nil,
                    title: "Song",
                    artist: "Artist",
                    album: "Album",
                    durationSeconds: 180
                )
            ),
            .local(document)
        )

        fake.emit(
            NowPlayingTrackPayload(
                title: "Song",
                artist: "Artist",
                album: "Album",
                isPlaying: true,
                elapsedSeconds: 1.2,
                durationSeconds: 180,
                playbackRate: 1,
                bundleIdentifier: "com.example.player.three",
                artwork: nil,
                timestamp: Date()
            )
        )
        controller.refreshNowPlayingSnapshot()
        controller.deleteLyrics(document.id)
        XCTAssertEqual(controller.model.lyricsState, .onlineUnavailable)
    }

    @MainActor
    func testNonNotchedScreenCleanlyDisablesIslandAndStopsTimer() {
        let external = nonNotchedScreen()
        let spike = ProcessTapSpike()
        let controller = IslandWindowController(
            spike: spike,
            defaults: defaults,
            screenProvider: { [external] },
            allowsOrderFront: false
        )
        defer { controller.shutdown() }

        let inspection = controller.inspectWindowForTests()
        XCTAssertEqual(inspection.state, .disabled)
        XCTAssertFalse(inspection.isVisible)
        XCTAssertFalse(inspection.isTimerRunning)
        XCTAssertEqual(inspection.unsupportedReason, .noNotch)
        XCTAssertEqual(spike.phase, .idle)
    }

    @MainActor
    func testDisablingAndScreenChangesRecalculateStateAndFrameCleanly() throws {
        let firstScreen = notchedScreen(id: "builtin-1", origin: .zero)
        let movedScreen = notchedScreen(id: "builtin-1", origin: CGPoint(x: 300, y: 120))
        let movedGeometry = try IslandGeometry.analyze(screen: movedScreen).get()
        var activeScreens = [firstScreen]

        let spike = ProcessTapSpike()
        let controller = IslandWindowController(
            spike: spike,
            defaults: defaults,
            screenProvider: { activeScreens },
            allowsOrderFront: false
        )
        defer { controller.shutdown() }

        activeScreens = [movedScreen]
        controller.evaluateScreensAndApply(animated: false)
        XCTAssertEqual(controller.inspectWindowForTests().frame, movedGeometry.compactFrame)

        controller.setEnabled(false)
        XCTAssertEqual(controller.inspectWindowForTests().state, .disabled)
        XCTAssertFalse(controller.inspectWindowForTests().isVisible)
        XCTAssertFalse(controller.inspectWindowForTests().isTimerRunning)

        controller.setEnabled(true)
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)
        XCTAssertTrue(controller.inspectWindowForTests().isVisible)
        XCTAssertTrue(controller.inspectWindowForTests().isTimerRunning)

        controller.simulatePointerEntered(at: 5)
        XCTAssertTrue(controller.model.hoverArmed)
        controller.evaluateScreensAndApply(animated: false)
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)
        XCTAssertFalse(controller.model.hoverArmed)
        XCTAssertEqual(controller.inspectWindowForTests().frame, movedGeometry.compactFrame)
        controller.simulateExpandTimerFired(now: 5.35)
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)

        controller.simulatePointerEntered(at: 8)
        controller.simulateEscapePressed()
        controller.simulateExpandTimerFired(now: 9)
        XCTAssertEqual(controller.inspectWindowForTests().state, .compact)
        XCTAssertFalse(controller.model.hoverArmed)

        controller.simulatePointerEntered(at: 11)
        controller.togglePin()
        controller.simulateExpandTimerFired(now: 12)
        XCTAssertEqual(controller.inspectWindowForTests().state, .pinned)
        XCTAssertEqual(controller.inspectWindowForTests().frame, movedGeometry.expandedPlayerFrame())
        controller.simulateEscapePressed()

        let haptics = RecordingIslandHaptics()
        let hapticController = IslandWindowController(
            spike: ProcessTapSpike(),
            defaults: defaults,
            screenProvider: { [movedScreen] },
            allowsOrderFront: false,
            haptics: haptics
        )
        defer { hapticController.shutdown() }
        hapticController.model.prefs.hapticStrength = .medium
        hapticController.simulatePointerEntered(at: 1)
        hapticController.simulatePointerExited(at: 1.1)
        hapticController.simulateExpandTimerFired(now: 2)
        XCTAssertTrue(hapticController.model.hoverArmed == false)
        XCTAssertEqual(hapticController.inspectWindowForTests().state, .compact)
        XCTAssertTrue(haptics.patterns.isEmpty)

        hapticController.simulatePointerEntered(at: 3)
        hapticController.simulateExpandTimerFired(now: 3.35)
        XCTAssertEqual(haptics.patterns, [.generic])
        hapticController.simulatePointerEntered(at: 4)
        XCTAssertEqual(haptics.patterns, [.generic])
        hapticController.togglePin()
        XCTAssertEqual(hapticController.inspectWindowForTests().state, .pinned)
        XCTAssertEqual(haptics.patterns, [.generic])

        hapticController.simulateEscapePressed()
        hapticController.model.prefs.hapticStrength = .off
        hapticController.expand()
        XCTAssertEqual(hapticController.inspectWindowForTests().state, .expanded)
        XCTAssertTrue(haptics.patterns.isEmpty == false)
        XCTAssertEqual(haptics.patterns.count, 1)

        hapticController.collapse()
        hapticController.togglePin()
        XCTAssertEqual(hapticController.inspectWindowForTests().state, .pinned)
        XCTAssertEqual(haptics.patterns.count, 1)

        controller.selectMode(.waveform)
        controller.selectMode(.orbit)
        controller.setCompactBarCountPerSide(6)
        XCTAssertEqual(controller.model.prefs.mode, .orbit)
        XCTAssertEqual(controller.model.prefs.compactBarCountPerSide, 6)
        XCTAssertEqual(spike.phase, .idle)
    }

    @MainActor
    func testSilentHapticsDoNotChangeTheExpandedTransition() throws {
        let screen = notchedScreen()
        let controller = IslandWindowController(
            spike: ProcessTapSpike(),
            defaults: defaults,
            screenProvider: { [screen] },
            allowsOrderFront: false,
            haptics: SilentIslandHaptics()
        )
        defer { controller.shutdown() }
        controller.model.prefs.hapticStrength = .strong
        controller.expand()
        XCTAssertEqual(controller.inspectWindowForTests().state, .expanded)
        XCTAssertEqual(controller.inspectWindowForTests().frame, try IslandGeometry.analyze(screen: screen).get().expandedPlayerFrame())
    }
}
