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
        XCTAssertEqual(StudioChromeMotion.hideDelaySeconds, 0.40, accuracy: 0.000_1)
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
            pointerInside: false, pointerDown: false, holdsChrome: false, now: 10.5, exitedAt: 10, hideDelay: .nan
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
