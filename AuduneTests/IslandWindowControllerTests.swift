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
