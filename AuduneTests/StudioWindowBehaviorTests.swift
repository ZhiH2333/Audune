import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Audune

private struct GripFixture: View {
    var hitMap: StudioHitMap

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            Color.red
                .frame(width: StudioChrome.gripWidth, height: StudioChrome.gripHeight)
                .studioGripRegion()
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: StudioCoordinateSpace.name)
        .onPreferenceChange(StudioGripFramesKey.self) { frames in
            hitMap.gripFramesTopLeft = frames
        }
    }
}

final class StudioWindowBehaviorTests: XCTestCase {
    func testWindowModesUseSeparateLevelAndSpaceBehavior() {
        XCTAssertEqual(
            StudioWindowBehavior.level(for: .onDesktop).rawValue,
            Int(CGWindowLevelForKey(.desktopIconWindow))
        )
        XCTAssertEqual(StudioWindowBehavior.level(for: .onTop), .floating)
        XCTAssertEqual(StudioWindowBehavior.level(for: .asWindow), .normal)
        XCTAssertFalse(StudioWindowBehavior.isFloatingPanel(for: .onDesktop))
        XCTAssertTrue(StudioWindowBehavior.isFloatingPanel(for: .onTop))
        XCTAssertFalse(StudioWindowBehavior.isFloatingPanel(for: .asWindow))
        XCTAssertEqual(StudioWindowBehavior.collectionBehavior(for: .onDesktop), [.canJoinAllSpaces])
        XCTAssertEqual(StudioWindowBehavior.collectionBehavior(for: .onTop), [.canJoinAllSpaces, .fullScreenAuxiliary])
        XCTAssertEqual(StudioWindowBehavior.collectionBehavior(for: .asWindow), [])
        for mode in StudioWindowMode.allCases {
            let behavior = StudioWindowBehavior.collectionBehavior(for: mode)
            XCTAssertFalse(behavior.contains(.fullScreenPrimary))
            XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        }
    }

    func testGripDragsAndCanvasOrControlDoesNot() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        let control = CGRect(x: 16, y: 300, width: 80, height: 28)
        let grip = CGRect(x: 200, y: 360, width: 28, height: 22)

        XCTAssertEqual(
            StudioDragRouting.route(
                point: CGPoint(x: 320, y: 120),
                bounds: bounds,
                controlFrames: [control],
                gripFrames: [grip]
            ),
            .idle
        )
        XCTAssertEqual(
            StudioDragRouting.route(
                point: CGPoint(x: 210, y: 370),
                bounds: bounds,
                controlFrames: [control],
                gripFrames: [grip]
            ),
            .drag
        )
        XCTAssertEqual(
            StudioDragRouting.route(
                point: CGPoint(x: 40, y: 310),
                bounds: bounds,
                controlFrames: [control],
                gripFrames: [grip]
            ),
            .control
        )
    }

    func testControlSlopDoesNotTurnNearbyCanvasIntoAControl() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        let control = CGRect(x: 16, y: 300, width: 80, height: 28)

        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 15.5, y: 310), bounds: bounds, controlFrames: [control]),
            .control
        )
        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 10, y: 310), bounds: bounds, controlFrames: [control]),
            .idle
        )
    }

    func testEdgesResizeEvenWhenAControlCoversThem() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        let control = CGRect(x: 0, y: 0, width: 80, height: 80)

        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 2, y: 40), bounds: bounds, controlFrames: [control]),
            .resize
        )
        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 637, y: 200), bounds: bounds, controlFrames: []),
            .resize
        )
        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 200, y: 2), bounds: bounds, controlFrames: []),
            .resize
        )
        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 200, y: 398), bounds: bounds, controlFrames: []),
            .resize
        )
    }

    func testUnsafePointsDoNotDrag() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)

        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: CGFloat.nan, y: 20), bounds: bounds, controlFrames: []),
            .control
        )
        XCTAssertEqual(
            StudioDragRouting.route(
                point: CGPoint(x: 20, y: 20),
                bounds: CGRect(x: 0, y: 0, width: 8, height: 8),
                controlFrames: []
            ),
            .control
        )
    }

    func testSwiftUIFramesConvertToAppKitBottomLeft() {
        let frames = StudioDragRouting.appKitFrames(
            fromTopLeft: [CGRect(x: 16, y: 16, width: 80, height: 28)],
            containerHeight: 400
        )

        XCTAssertEqual(frames, [CGRect(x: 16, y: 356, width: 80, height: 28)])
        XCTAssertEqual(
            StudioDragRouting.appKitFrames(
                fromTopLeft: [CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)],
                containerHeight: 400
            ),
            []
        )
        XCTAssertEqual(
            StudioDragRouting.appKitFrames(
                fromTopLeft: [CGRect(x: 0, y: 0, width: 10, height: 10)],
                containerHeight: 0
            ),
            []
        )
    }

    func testFlippedContainerKeepsSwiftUIFramesUnchanged() {
        let frames = StudioDragRouting.appKitFrames(
            fromTopLeft: [CGRect(x: 16, y: 16, width: 80, height: 28)],
            containerHeight: 400,
            isFlipped: true
        )

        XCTAssertEqual(frames, [CGRect(x: 16, y: 16, width: 80, height: 28)])
    }

    /// Uses a real `NSHostingView` in an offscreen window. This checks coordinates only; it is not a real drag.
    @MainActor
    func testHostingViewRoutesTheBottomGripInItsOwnCoordinates() throws {
        let hitMap = StudioHitMap()
        let host = StudioHostingView(rootView: GripFixture(hitMap: hitMap))
        host.hitMap = hitMap
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let deadline = Date(timeIntervalSinceNow: 2)
        while hitMap.gripFramesTopLeft.isEmpty, Date() < deadline {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        let grip = try XCTUnwrap(hitMap.gripFramesTopLeft.first)

        XCTAssertTrue(host.isFlipped, "NSHostingView uses a top-left origin")
        XCTAssertEqual(grip.midY, 381, accuracy: 1)
        XCTAssertEqual(host.currentRoute(CGPoint(x: grip.midX, y: grip.midY)), .drag)
        XCTAssertEqual(host.currentRoute(CGPoint(x: grip.midX, y: 400 - grip.midY)), .idle)
        XCTAssertEqual(host.currentRoute(CGPoint(x: 320, y: 2)), .resize)
        XCTAssertEqual(host.currentRoute(CGPoint(x: 320, y: 200)), .idle)
    }

    func testHiddenChromeKeepsTheGripFromDragging() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        let grip = CGRect(x: 200, y: 360, width: 28, height: 22)
        let point = CGPoint(x: 210, y: 370)

        XCTAssertEqual(
            StudioDragRouting.route(point: point, bounds: bounds, controlFrames: [], gripFrames: [grip], chromeVisible: false),
            .idle
        )
        XCTAssertEqual(
            StudioDragRouting.route(point: point, bounds: bounds, controlFrames: [], gripFrames: [grip], chromeVisible: true),
            .drag
        )
    }

    func testScreenDeltaMovesWindowOrigin() {
        XCTAssertEqual(
            StudioWindowDrag.origin(
                startOrigin: CGPoint(x: 100, y: 200),
                startMouse: CGPoint(x: 10, y: 20),
                currentMouse: CGPoint(x: 40, y: 5)
            ),
            CGPoint(x: 130, y: 185)
        )
    }

    func testNonFiniteDragKeepsTheStartOrigin() {
        XCTAssertEqual(
            StudioWindowDrag.origin(
                startOrigin: CGPoint(x: 12, y: 18),
                startMouse: CGPoint(x: CGFloat.nan, y: 4),
                currentMouse: CGPoint(x: 8, y: 9)
            ),
            CGPoint(x: 12, y: 18)
        )
    }

    @MainActor
    func testApplyingScreenDeltaChangesPanelOrigin() {
        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 90, width: 200, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        StudioWindowDrag.apply(
            to: panel,
            startOrigin: panel.frame.origin,
            startMouse: CGPoint(x: 0, y: 0),
            currentMouse: CGPoint(x: 15, y: -8)
        )

        XCTAssertEqual(panel.frame.origin.x, 95, accuracy: 0.001)
        XCTAssertEqual(panel.frame.origin.y, 82, accuracy: 0.001)
    }

    @MainActor
    func testConfiguredPanelUsesApprovedWindowBehavior() {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        let inspection = controller.inspectWindowForTests()

        XCTAssertEqual(inspection.level, .floating)
        XCTAssertTrue(inspection.isFloatingPanel)
        XCTAssertFalse(inspection.hidesOnDeactivate)
        XCTAssertEqual(inspection.collectionBehavior, StudioWindowBehavior.collectionBehavior(for: .onTop))
        XCTAssertTrue(inspection.isMovable)
        XCTAssertFalse(inspection.isMovableByWindowBackground)
        XCTAssertTrue(inspection.isResizable)
        XCTAssertTrue(inspection.usesDragHostingView)
        XCTAssertFalse(inspection.isOpaque)
        XCTAssertEqual(inspection.backgroundAlpha, 0)
        XCTAssertFalse(inspection.hasShadow)
        XCTAssertTrue(inspection.ignoresMouseEvents)
        XCTAssertFalse(inspection.hostIsOpaque)
        controller.setChromeVisible(true)
        XCTAssertFalse(controller.inspectWindowForTests().hasShadow)
        controller.setChromeVisible(false)
        XCTAssertFalse(controller.inspectWindowForTests().hasShadow)
        XCTAssertFalse(inspection.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(inspection.collectionBehavior.contains(.moveToActiveSpace))
    }

    @MainActor
    func testWindowModeSwitchKeepsFrameAndVisibilityFlags() {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        let before = controller.inspectWindowForTests()

        controller.setWindowMode(.onDesktop)
        var inspection = controller.inspectWindowForTests()
        XCTAssertEqual(inspection.frame, before.frame)
        XCTAssertEqual(inspection.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertFalse(inspection.isFloatingPanel)
        XCTAssertFalse(inspection.hidesOnDeactivate)
        XCTAssertEqual(inspection.collectionBehavior, [.canJoinAllSpaces])
        XCTAssertTrue(inspection.ignoresMouseEvents)

        controller.setWindowMode(.asWindow)
        inspection = controller.inspectWindowForTests()
        XCTAssertEqual(inspection.frame, before.frame)
        XCTAssertEqual(inspection.level, .normal)
        XCTAssertFalse(inspection.isFloatingPanel)
        XCTAssertEqual(inspection.collectionBehavior, [])
        XCTAssertTrue(inspection.ignoresMouseEvents)

        controller.setWindowMode(.onTop)
        inspection = controller.inspectWindowForTests()
        XCTAssertEqual(inspection.frame, before.frame)
        XCTAssertEqual(inspection.level, .floating)
        XCTAssertTrue(inspection.isFloatingPanel)
        XCTAssertEqual(inspection.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary])
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor
    func testWindowSettingsToggleResizeAndDragWithoutMovingTheWindow() {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        let before = controller.inspectWindowForTests()

        controller.model.prefs.window.allowsResize = false
        controller.model.prefs.window.allowsDrag = false
        controller.applyWindowPreferences()
        let locked = controller.inspectWindowForTests()
        XCTAssertFalse(locked.isResizable)
        XCTAssertEqual(locked.frame, before.frame)
        XCTAssertEqual(locked.level, before.level)
        XCTAssertTrue(locked.ignoresMouseEvents)
        XCTAssertFalse(controller.allowsDragForTests)

        controller.model.prefs.window.allowsResize = true
        controller.model.prefs.window.allowsDrag = true
        controller.applyWindowPreferences()
        XCTAssertTrue(controller.inspectWindowForTests().isResizable)
        XCTAssertTrue(controller.allowsDragForTests)
    }

    @MainActor
    func testPreferredWindowSizeAppliesAndStaysWithinInternalLimits() {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }

        controller.model.prefs.window.width = 800
        controller.model.prefs.window.height = 500
        controller.applyWindowPreferences()
        let sized = controller.inspectWindowForTests().frame
        XCTAssertEqual(sized.width, 800, accuracy: 1)
        XCTAssertEqual(sized.height, 500, accuracy: 1)
        XCTAssertEqual(controller.model.prefs.window.width, 800, accuracy: 0.000_1)
        XCTAssertEqual(controller.model.prefs.window.height, 500, accuracy: 0.000_1)

        controller.model.prefs.window.width = 100
        controller.model.prefs.window.height = 50
        controller.applyWindowPreferences()
        let floored = controller.inspectWindowForTests().frame
        XCTAssertGreaterThanOrEqual(floored.width, StudioFrame.absoluteMinimum.width - 0.5)
        XCTAssertGreaterThanOrEqual(floored.height, StudioFrame.absoluteMinimum.height - 0.5)
        XCTAssertEqual(controller.model.prefs.window.width, Double(floored.width), accuracy: 0.5)
        XCTAssertEqual(controller.model.prefs.window.height, Double(floored.height), accuracy: 0.5)

        controller.model.prefs.window.width = 9_000
        controller.model.prefs.window.height = 9_000
        controller.applyWindowPreferences()
        let capped = controller.inspectWindowForTests().frame
        XCTAssertLessThanOrEqual(capped.width, StudioFrame.defaultMaximumSize.width + 0.5)
        XCTAssertLessThanOrEqual(capped.height, StudioFrame.defaultMaximumSize.height + 0.5)
        XCTAssertEqual(controller.model.prefs.window.width, Double(capped.width), accuracy: 0.5)
        XCTAssertEqual(controller.model.prefs.window.height, Double(capped.height), accuracy: 0.5)

        controller.resetWindowFrame()
        let reset = controller.inspectWindowForTests().frame
        XCTAssertEqual(reset.width, StudioFrame.defaultSize.width, accuracy: 1)
        XCTAssertEqual(reset.height, StudioFrame.defaultSize.height, accuracy: 1)
        XCTAssertEqual(controller.model.prefs.window.width, Double(StudioFrame.defaultSize.width), accuracy: 0.5)
        XCTAssertEqual(controller.model.prefs.window.height, Double(StudioFrame.defaultSize.height), accuracy: 0.5)
    }

    @MainActor
    func testMenuTrackingAndHideClearTransientState() {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        controller.model.pointerInside = true
        controller.model.pointerDown = true
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        XCTAssertTrue(controller.model.menuTracking)
        controller.hide()
        XCTAssertFalse(controller.model.menuTracking)
        XCTAssertFalse(controller.model.pointerInside)
        XCTAssertFalse(controller.model.pointerDown)
        XCTAssertFalse(controller.inspectPassthroughForTests().interactionVisible)
    }

    func testCenteredDefaultFrameStaysInsideTheVisibleArea() {
        let visible = CGRect(x: 100, y: 50, width: 1_440, height: 800)
        let frame = StudioFrame.centeredDefault(in: visible)

        XCTAssertEqual(frame.size, StudioFrame.defaultSize)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.001)

        let tiny = StudioFrame.centeredDefault(in: CGRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertLessThanOrEqual(tiny.width, 300)
        XCTAssertLessThanOrEqual(tiny.height, 200)
        XCTAssertEqual(StudioFrame.centeredDefault(in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 5)).size, StudioFrame.defaultSize)
    }

    @MainActor
    func testBarCountAndChromeDoNotStartCapture() {
        let spike = ProcessTapSpike()
        let controller = StudioWindowController(spike: spike)
        defer { controller.shutdown() }

        controller.model.prefs.mode = .spectrum
        controller.setSpectrumBarCount(64)
        controller.setChromeVisible(false)

        XCTAssertEqual(spike.phase, .idle)
        XCTAssertEqual(controller.model.prefs.spectrum.barCount, 64)
        XCTAssertEqual(controller.model.studioSpectrum.count, 64)
        XCTAssertFalse(controller.inspectWindowForTests().hasShadow)
        XCTAssertTrue(controller.inspectWindowForTests().ignoresMouseEvents)
        XCTAssertEqual(controller.inspectWindowForTests().collectionBehavior, StudioWindowBehavior.collectionBehavior(for: .onTop))

        controller.setSpectrumBarCount(3)
        XCTAssertEqual(controller.model.prefs.spectrum.barCount, 32)
        XCTAssertEqual(spike.phase, .idle)
    }
}
