import CoreGraphics
import XCTest
@testable import Audune

final class StudioChromeTests: XCTestCase {
    func testCleanCanvasOffStaysVisible() {
        XCTAssertTrue(visible(cleanCanvas: false, pointerInside: false, pointerDown: false, holdsChrome: false, now: 100, exitedAt: 0))
    }

    func testPointerInsideShowsChromeImmediately() {
        XCTAssertTrue(visible(cleanCanvas: true, pointerInside: true, pointerDown: false, holdsChrome: false, now: 80, exitedAt: 0))
    }

    func testExitKeepsChromeUntilTheDelayElapses() {
        let exit = 10.0
        XCTAssertTrue(visible(
            cleanCanvas: true,
            pointerInside: false,
            pointerDown: false,
            holdsChrome: false,
            now: exit + 0.399,
            exitedAt: exit
        ))
        XCTAssertFalse(visible(
            cleanCanvas: true,
            pointerInside: false,
            pointerDown: false,
            holdsChrome: false,
            now: exit + StudioChromeMotion.hideDelaySeconds,
            exitedAt: exit
        ))
    }

    func testPointerDownAndOpenSettingsHoldChrome() {
        XCTAssertTrue(visible(cleanCanvas: true, pointerInside: false, pointerDown: true, holdsChrome: false, now: 50, exitedAt: 0))
        XCTAssertTrue(visible(cleanCanvas: true, pointerInside: false, pointerDown: false, holdsChrome: true, now: 50, exitedAt: 0))
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

    func testCanvasFrameStaysPutWhenChromeHides() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        let canvas = StudioChrome.canvasFrame(in: bounds)
        let chrome = StudioChrome.chromeFrame(in: bounds)

        XCTAssertEqual(canvas, bounds)
        XCTAssertEqual(StudioChrome.canvasFrame(in: bounds), canvas)
        XCTAssertTrue(bounds.contains(chrome))
        XCTAssertEqual(chrome.height, StudioChrome.barHeight)
        XCTAssertEqual(StudioChrome.canvasFrame(in: .zero), .zero)
    }

    private func visible(
        cleanCanvas: Bool,
        pointerInside: Bool,
        pointerDown: Bool,
        holdsChrome: Bool,
        now: TimeInterval,
        exitedAt: TimeInterval?
    ) -> Bool {
        StudioChrome.isVisible(
            cleanCanvas: cleanCanvas,
            pointerInside: pointerInside,
            pointerDown: pointerDown,
            holdsChrome: holdsChrome,
            now: now,
            exitedAt: exitedAt
        )
    }
}
