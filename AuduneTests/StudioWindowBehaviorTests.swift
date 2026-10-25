import AppKit
import CoreGraphics
import XCTest
@testable import Audune

final class StudioWindowBehaviorTests: XCTestCase {
    func testCollectionBehaviorJoinsSpacesAndFullScreenApps() {
        let behavior = StudioWindowBehavior.collectionBehavior

        XCTAssertEqual(behavior, [.canJoinAllSpaces, .fullScreenAuxiliary])
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.fullScreenPrimary))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
    }

    func testCanvasPointDragsAndControlPointDoesNot() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        let control = CGRect(x: 16, y: 300, width: 80, height: 28)

        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 320, y: 120), bounds: bounds, controlFrames: [control]),
            .drag
        )
        XCTAssertEqual(
            StudioDragRouting.route(point: CGPoint(x: 40, y: 310), bounds: bounds, controlFrames: [control]),
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
            .drag
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
    func testConfiguredPanelUsesApprovedWindowBehavior() {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        let inspection = controller.inspectWindowForTests()

        XCTAssertEqual(inspection.collectionBehavior, StudioWindowBehavior.collectionBehavior)
        XCTAssertTrue(inspection.isMovable)
        XCTAssertFalse(inspection.isMovableByWindowBackground)
        XCTAssertTrue(inspection.isResizable)
        XCTAssertTrue(inspection.usesDragHostingView)
        XCTAssertFalse(inspection.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(inspection.collectionBehavior.contains(.moveToActiveSpace))
    }

    @MainActor
    func testBarCountAndCleanCanvasDoNotStartCapture() {
        let spike = ProcessTapSpike()
        let controller = StudioWindowController(spike: spike)
        defer { controller.shutdown() }

        controller.setBarCount(64)
        controller.setCleanCanvas(true)

        XCTAssertEqual(spike.phase, .idle)
        XCTAssertEqual(controller.model.barCount, 64)
        XCTAssertEqual(controller.model.studioSpectrum.count, 64)
        XCTAssertTrue(controller.model.cleanCanvas)
        XCTAssertEqual(controller.inspectWindowForTests().collectionBehavior, StudioWindowBehavior.collectionBehavior)

        controller.setBarCount(3)
        XCTAssertEqual(controller.model.barCount, 16)
        XCTAssertEqual(spike.phase, .idle)
    }
}
