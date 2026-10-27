import CoreGraphics
import XCTest
@testable import Audune

final class StudioFrameTests: XCTestCase {
    func testVisibleFrameStaysPut() {
        let frame = CGRect(x: 100, y: 80, width: 640, height: 400)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(StudioFrame.clamped(frame, to: [screen], fallback: screen), frame)
    }

    func testPartialOverlapClampsIntoThatScreen() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = CGRect(x: -20, y: 100, width: 400, height: 300)
        let result = StudioFrame.clamped(frame, to: [screen], fallback: .zero)

        XCTAssertEqual(result, CGRect(x: 0, y: 100, width: 400, height: 300))
        XCTAssertTrue(screen.contains(result))
    }

    func testDisconnectedFrameMovesOntoPrimary() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 5000, y: 4000, width: 200, height: 120)
        let result = StudioFrame.clamped(frame, to: [primary, secondary], fallback: secondary)

        XCTAssertTrue(primary.contains(result))
        XCTAssertGreaterThanOrEqual(result.width, StudioFrame.minimumSize.width)
        XCTAssertGreaterThanOrEqual(result.height, StudioFrame.minimumSize.height)
        XCTAssertFalse(secondary.contains(result))
    }

    func testNegativeOriginWithoutIntersectionUsesFallback() {
        let fallback = CGRect(x: 10, y: 20, width: 1000, height: 800)
        let frame = CGRect(x: -1800, y: -900, width: 50, height: 40)
        let result = StudioFrame.clamped(frame, to: [], fallback: fallback)

        XCTAssertTrue(fallback.contains(result))
        XCTAssertEqual(result.size, StudioFrame.minimumSize)
        XCTAssertEqual(result.origin, fallback.origin)
    }

    func testOversizedFrameShrinksToVisibleBounds() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 4000, y: 3000, width: 5000, height: 4000)
        let result = StudioFrame.clamped(frame, to: [screen], fallback: .zero)

        XCTAssertEqual(result, screen)
    }

    func testTinyFallbackWinsOverMinimumSize() {
        let fallback = CGRect(x: 0, y: 0, width: 200, height: 100)
        let result = StudioFrame.clamped(
            CGRect(x: -10, y: -10, width: 10, height: 10),
            to: [],
            fallback: fallback
        )

        XCTAssertEqual(result, fallback)
    }

    func testEffectiveLimitsRespectAbsoluteFloorAndRaiseMaxToMin() {
        let raised = StudioFrame.effectiveLimits(
            minWidth: 700,
            minHeight: 500,
            maxWidth: 640,
            maxHeight: 400
        )
        XCTAssertEqual(raised.minimum.width, 700, accuracy: 0.001)
        XCTAssertEqual(raised.minimum.height, 500, accuracy: 0.001)
        XCTAssertEqual(raised.maximum.width, 700, accuracy: 0.001)
        XCTAssertEqual(raised.maximum.height, 500, accuracy: 0.001)

        let floored = StudioFrame.effectiveLimits(
            minWidth: 100,
            minHeight: 50,
            maxWidth: 2000,
            maxHeight: 1500
        )
        XCTAssertEqual(floored.minimum, StudioFrame.absoluteMinimum)
        XCTAssertEqual(floored.maximum.width, 2000, accuracy: 0.001)
        XCTAssertEqual(floored.maximum.height, 1500, accuracy: 0.001)
    }

    func testEffectiveLimitsCapToScreen() {
        let limits = StudioFrame.effectiveLimits(
            minWidth: 360,
            minHeight: 240,
            maxWidth: 3000,
            maxHeight: 2000,
            screen: CGSize(width: 1280, height: 800)
        )
        XCTAssertEqual(limits.maximum.width, 1280, accuracy: 0.001)
        XCTAssertEqual(limits.maximum.height, 800, accuracy: 0.001)
    }

    func testClampedHonorsUserMaximum() {
        let screen = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let frame = CGRect(x: 10, y: 10, width: 1800, height: 1100)
        let result = StudioFrame.clamped(
            frame,
            to: [screen],
            fallback: screen,
            minimum: CGSize(width: 360, height: 240),
            maximum: CGSize(width: 900, height: 600)
        )
        XCTAssertEqual(result.width, 900, accuracy: 0.001)
        XCTAssertEqual(result.height, 600, accuracy: 0.001)
        XCTAssertTrue(screen.contains(result))
    }

    func testConstrainShrinksOversizedFrame() {
        let frame = CGRect(x: 40, y: 50, width: 2000, height: 1400)
        let next = StudioFrame.constrain(
            frame,
            minimum: CGSize(width: 360, height: 240),
            maximum: CGSize(width: 800, height: 500)
        )
        XCTAssertEqual(next.size, CGSize(width: 800, height: 500))
        XCTAssertEqual(next.origin, frame.origin)
    }
}
