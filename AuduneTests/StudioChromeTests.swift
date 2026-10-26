import CoreGraphics
import XCTest
@testable import Audune

final class StudioChromeTests: XCTestCase {
    func testMissingExitKeepsChromeVisible() {
        XCTAssertTrue(visible(pointerInside: false, pointerDown: false, holdsChrome: false, now: 100, exitedAt: nil))
    }

    func testPointerInsideShowsChromeImmediately() {
        XCTAssertTrue(visible(pointerInside: true, pointerDown: false, holdsChrome: false, now: 80, exitedAt: 0))
    }

    func testExitKeepsChromeUntilTheDelayElapses() {
        let exit = 10.0
        XCTAssertTrue(visible(
            pointerInside: false,
            pointerDown: false,
            holdsChrome: false,
            now: exit + 0.399,
            exitedAt: exit
        ))
        XCTAssertFalse(visible(
            pointerInside: false,
            pointerDown: false,
            holdsChrome: false,
            now: exit + StudioChromeMotion.hideDelaySeconds,
            exitedAt: exit
        ))
    }

    func testPointerDownAndOpenSettingsHoldChrome() {
        XCTAssertTrue(visible(pointerInside: false, pointerDown: true, holdsChrome: false, now: 50, exitedAt: 0))
        XCTAssertTrue(visible(pointerInside: false, pointerDown: false, holdsChrome: true, now: 50, exitedAt: 0))
    }

    func testReduceMotionRemovesTheFade() {
        XCTAssertEqual(StudioChromeMotion.fadeSeconds(hiding: false, reduceMotion: false), StudioChromeMotion.revealSeconds)
        XCTAssertEqual(StudioChromeMotion.fadeSeconds(hiding: true, reduceMotion: false), StudioChromeMotion.hideSeconds)
        XCTAssertEqual(StudioChromeMotion.fadeSeconds(hiding: false, reduceMotion: true), 0)
        XCTAssertEqual(StudioChromeMotion.fadeSeconds(hiding: true, reduceMotion: true), 0)
        XCTAssertEqual(StudioChromeMotion.revealSeconds, 0.20, accuracy: 0.000_1)
        XCTAssertEqual(StudioChromeMotion.hideDelaySeconds, 3, accuracy: 0.000_1)
        XCTAssertEqual(StudioChromeMotion.hideSeconds, 0.25, accuracy: 0.000_1)
    }

    func testHideDelayAndFadeFollowTheWindowSettings() {
        XCTAssertTrue(StudioChrome.isVisible(
            pointerInside: false, pointerDown: false, holdsChrome: false, now: 11.5, exitedAt: 10, hideDelay: 2
        ))
        XCTAssertFalse(StudioChrome.isVisible(
            pointerInside: false, pointerDown: false, holdsChrome: false, now: 10.2, exitedAt: 10, hideDelay: 0.1
        ))
        XCTAssertFalse(StudioChrome.isVisible(
            pointerInside: false, pointerDown: false, holdsChrome: false, now: 10 + StudioChromeMotion.hideDelaySeconds, exitedAt: 10, hideDelay: .nan
        ))
        XCTAssertEqual(StudioChromeMotion.fadeSeconds(hiding: false, reduceMotion: false, animates: false), 0)
        XCTAssertEqual(StudioChromeMotion.fadeSeconds(hiding: true, reduceMotion: true, animates: true, followsReduceMotion: true), 0)
        XCTAssertEqual(
            StudioChromeMotion.fadeSeconds(hiding: true, reduceMotion: true, animates: true, followsReduceMotion: false),
            StudioChromeMotion.hideSeconds
        )
        XCTAssertEqual(
            StudioChromeMotion.fadeSeconds(hiding: false, reduceMotion: false, animates: true, followsReduceMotion: true),
            StudioChromeMotion.revealSeconds
        )
    }

    func testPointerNearTheEdgeStillCountsAsInside() {
        let frame = CGRect(x: 100, y: 80, width: 240, height: 160)
        XCTAssertTrue(StudioChrome.pointerIsInside(windowFrame: frame, cursor: CGPoint(x: 200, y: 140)))
        XCTAssertTrue(StudioChrome.pointerIsInside(windowFrame: frame, cursor: CGPoint(x: 96, y: 140)))
        XCTAssertFalse(StudioChrome.pointerIsInside(windowFrame: frame, cursor: CGPoint(x: 80, y: 140)))
        XCTAssertFalse(StudioChrome.pointerIsInside(windowFrame: frame, cursor: CGPoint(x: CGFloat.nan, y: 140)))
        XCTAssertFalse(StudioChrome.pointerIsInside(windowFrame: .zero, cursor: CGPoint(x: 1, y: 1)))
    }

    func testProximityStaysAroundTheControls() {
        let window = CGRect(x: 0, y: 0, width: 640, height: 400)
        let grip = CGRect(x: 306, y: 8, width: StudioChrome.gripWidth, height: StudioChrome.gripHeight)
        let center = CGPoint(x: window.midX, y: window.midY)
        let beside = CGPoint(x: grip.midX, y: grip.maxY + 24)
        XCTAssertTrue(window.contains(center))
        XCTAssertFalse(StudioChrome.pointerIsInside(windowFrame: grip, cursor: center, slop: StudioChrome.controlProximity))
        XCTAssertTrue(StudioChrome.pointerIsInside(windowFrame: grip, cursor: beside, slop: StudioChrome.controlProximity))
        XCTAssertFalse(StudioChrome.pointerIsInside(windowFrame: grip, cursor: beside))
        XCTAssertEqual(StudioChrome.controlProximity, 40)
        let stillNear = CGPoint(x: grip.midX, y: grip.maxY + 80)
        let gone = CGPoint(x: grip.midX, y: grip.maxY + 150)
        XCTAssertTrue(StudioChrome.pointerKeepsControls(controlFrame: grip, cursor: stillNear, controlsVisible: true))
        XCTAssertFalse(StudioChrome.pointerKeepsControls(controlFrame: grip, cursor: gone, controlsVisible: true))
        XCTAssertFalse(StudioChrome.pointerKeepsControls(controlFrame: grip, cursor: stillNear, controlsVisible: false))
        XCTAssertEqual(StudioChrome.controlLeaveDistance, 120)
    }

    func testCanvasFrameStaysPutWhenChromeHides() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        let canvas = StudioChrome.canvasFrame(in: bounds)
        let chrome = StudioChrome.chromeFrame(in: bounds)

        XCTAssertEqual(canvas, bounds)
        XCTAssertEqual(StudioChrome.canvasFrame(in: bounds), canvas)
        XCTAssertTrue(bounds.contains(chrome))
        XCTAssertEqual(chrome.height, StudioChrome.barHeight)
        XCTAssertEqual(StudioChrome.canvasFrame(in: .zero), .zero)
        XCTAssertEqual(StudioChrome.gripWidth, 28)
        XCTAssertEqual(StudioChrome.gripHeight, 22)
    }

    func testAutoHideOffKeepsChromeAfterTheDelay() {
        XCTAssertTrue(StudioChrome.isVisible(
            pointerInside: false,
            pointerDown: false,
            holdsChrome: false,
            now: 20,
            exitedAt: 10,
            hideDelay: 0.8,
            autoHides: false
        ))
    }

    func testReturningOrInteractingCancelsTheHide() {
        var hide = StudioChromeHide()
        let first = hide.arm(at: 10, autoHides: true, engaged: false)
        XCTAssertEqual(first, 1)
        XCTAssertTrue(StudioChrome.isVisible(
            pointerInside: true, pointerDown: false, holdsChrome: false, now: 12, exitedAt: hide.exitedAt
        ))
        hide.cancel()
        XCTAssertFalse(hide.isCurrent(first ?? 0))
        XCTAssertNil(hide.exitedAt)

        let held = hide.arm(at: 12, autoHides: true, engaged: true)
        XCTAssertNil(held)
        XCTAssertNil(hide.exitedAt)
        let armed = hide.arm(at: 12, autoHides: true, engaged: false)
        XCTAssertFalse(hide.isCurrent(first ?? 0))
        XCTAssertTrue(hide.isCurrent(armed ?? 0))
        XCTAssertFalse(StudioChrome.isVisible(
            pointerInside: false, pointerDown: false, holdsChrome: false, now: 12 + StudioChromeMotion.hideDelaySeconds, exitedAt: hide.exitedAt
        ))
        XCTAssertTrue(StudioChrome.isVisible(
            pointerInside: false, pointerDown: true, holdsChrome: false, now: 12.8, exitedAt: hide.exitedAt
        ))
        XCTAssertTrue(StudioChrome.isVisible(
            pointerInside: false, pointerDown: false, holdsChrome: true, now: 12.8, exitedAt: hide.exitedAt
        ))
        XCTAssertNil(hide.arm(at: 13, autoHides: false, engaged: false))
    }

    func testSummonRegionLeavesTheCanvasCenterOpen() {
        let visual = CGRect(x: 40, y: 40, width: 640, height: 400)
        let center = CGPoint(x: visual.midX, y: visual.midY)
        let bottom = StudioPassthroughLayout.interactionFrame(
            visual: visual,
            contentSize: StudioChrome.hiddenContentSize(region: .bottomEdge, visualWidth: visual.width)
        )
        let grip = StudioPassthroughLayout.interactionFrame(
            visual: visual,
            contentSize: StudioChrome.hiddenContentSize(region: .grip, visualWidth: visual.width)
        )
        XCTAssertFalse(bottom.contains(center))
        XCTAssertFalse(grip.contains(center))
        XCTAssertGreaterThan(bottom.width, grip.width)
        XCTAssertEqual(grip.width, StudioChrome.gripWidth, accuracy: 0.001)
        XCTAssertLessThan(bottom.height, visual.height / 2)
    }

    private func visible(
        pointerInside: Bool,
        pointerDown: Bool,
        holdsChrome: Bool,
        now: TimeInterval,
        exitedAt: TimeInterval?
    ) -> Bool {
        StudioChrome.isVisible(
            pointerInside: pointerInside,
            pointerDown: pointerDown,
            holdsChrome: holdsChrome,
            now: now,
            exitedAt: exitedAt
        )
    }
}
