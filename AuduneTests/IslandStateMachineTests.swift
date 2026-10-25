import CoreGraphics
import XCTest
@testable import Audune

final class IslandStateMachineTests: XCTestCase {
    func testHoverExpandsFromCompactWhenEnabled() {
        var ctx = IslandStateContext(state: .compact)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true))

        XCTAssertEqual(ctx.state, .expanded)
        XCTAssertTrue(ctx.pointerInside)
        XCTAssertNil(ctx.exitedAt)
    }

    func testHoverDoesNotExpandWhenHoverToExpandIsOffButExplicitExpandStillWorks() {
        var ctx = IslandStateContext(state: .compact)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: false))
        XCTAssertEqual(ctx.state, .compact)
        XCTAssertTrue(ctx.pointerInside)

        ctx = IslandStateMachine.reduce(context: ctx, event: .expandRequested)
        XCTAssertEqual(ctx.state, .expanded)
    }

    func testDelayedCollapseWaitsForDelayAndCancelsOnReentry() {
        var ctx = IslandStateContext(state: .expanded, pointerInside: true)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerExited(at: 10.0), collapseDelay: 0.35)

        XCTAssertEqual(ctx.state, .expanded)
        XCTAssertFalse(ctx.pointerInside)
        XCTAssertEqual(ctx.exitedAt, 10.0)

        // Firing before the delay elapses keeps the island expanded.
        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 10.20), collapseDelay: 0.35)
        XCTAssertEqual(ctx.state, .expanded)

        // Re-entering before the delay elapses cancels the pending collapse.
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true), collapseDelay: 0.35)
        XCTAssertEqual(ctx.state, .expanded)
        XCTAssertTrue(ctx.pointerInside)
        XCTAssertNil(ctx.exitedAt)

        // Exiting again and waiting the full delay collapses to compact.
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerExited(at: 20.0), collapseDelay: 0.35)
        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 20.36), collapseDelay: 0.35)
        XCTAssertEqual(ctx.state, .compact)
        XCTAssertNil(ctx.exitedAt)
    }

    func testPinnedStateResistsPointerExitAndUnpinRestoresDelayedCollapse() {
        var ctx = IslandStateContext(state: .expanded, pointerInside: true)
        ctx = IslandStateMachine.reduce(context: ctx, event: .togglePin(at: 5.0))
        XCTAssertEqual(ctx.state, .pinned)
        XCTAssertNil(ctx.exitedAt)

        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerExited(at: 6.0))
        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 100.0))
        XCTAssertEqual(ctx.state, .pinned)
        XCTAssertNil(ctx.exitedAt)

        // Unpinning while pointer is outside returns to expanded and starts the collapse timer.
        ctx = IslandStateMachine.reduce(context: ctx, event: .togglePin(at: 50.0), collapseDelay: 0.4)
        XCTAssertEqual(ctx.state, .expanded)
        XCTAssertEqual(ctx.exitedAt, 50.0)

        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 50.45), collapseDelay: 0.4)
        XCTAssertEqual(ctx.state, .compact)
    }

    func testEscapeAndCollapseRequestImmediatelyReturnToCompactEvenFromPinned() {
        var ctx = IslandStateContext(state: .pinned, pointerInside: true)
        ctx = IslandStateMachine.reduce(context: ctx, event: .escapePressed)
        XCTAssertEqual(ctx.state, .compact)
        XCTAssertNil(ctx.exitedAt)

        var expanded = IslandStateContext(state: .expanded, pointerInside: true)
        expanded = IslandStateMachine.reduce(context: expanded, event: .collapseRequested)
        XCTAssertEqual(expanded.state, .compact)
    }

    func testPointerDownHoldsExpandedUntilMouseUp() {
        var ctx = IslandStateContext(state: .expanded, pointerInside: true)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerDownChanged(true, at: 10.0))
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerExited(at: 11.0))
        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 20.0), collapseDelay: 0.35)
        XCTAssertEqual(ctx.state, .expanded)
        XCTAssertNil(ctx.exitedAt)

        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerDownChanged(false, at: 21.0))
        XCTAssertEqual(ctx.exitedAt, 21.0)
        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 21.4), collapseDelay: 0.35)
        XCTAssertEqual(ctx.state, .compact)
    }

    func testAvailabilityChangesTransitionCleanlyBetweenDisabledAndCompact() {
        var ctx = IslandStateContext(state: .pinned, pointerInside: true, pointerDown: true)
        ctx = IslandStateMachine.reduce(context: ctx, event: .availabilityChanged(isEnabled: false, isSupported: true))
        XCTAssertEqual(ctx.state, .disabled)
        XCTAssertFalse(ctx.pointerInside)
        XCTAssertFalse(ctx.pointerDown)
        XCTAssertNil(ctx.exitedAt)

        // Events while disabled do not change state.
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true))
        XCTAssertEqual(ctx.state, .disabled)

        // Re-enabling on a supported screen starts in compact.
        ctx = IslandStateMachine.reduce(context: ctx, event: .availabilityChanged(isEnabled: true, isSupported: true))
        XCTAssertEqual(ctx.state, .compact)
    }

    func testPointerSlopAndReduceMotionDurations() {
        let frame = CGRect(x: 500, y: 950, width: 252, height: 32)
        XCTAssertTrue(IslandStateMachine.pointerIsInside(windowFrame: frame, cursor: CGPoint(x: 495, y: 960)))
        XCTAssertFalse(IslandStateMachine.pointerIsInside(windowFrame: frame, cursor: CGPoint(x: 480, y: 960)))
        XCTAssertFalse(IslandStateMachine.pointerIsInside(windowFrame: .zero, cursor: CGPoint(x: 0, y: 0)))

        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: false), 0.20, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: false, reduceMotion: false), 0.18, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: true, followsReduceMotion: true), 0)
        XCTAssertEqual(
            IslandMotion.transitionSeconds(expanding: true, reduceMotion: true, followsReduceMotion: false),
            0.20,
            accuracy: 0.000_1
        )
    }

    @MainActor
    func testIslandModelStatusAndShapeBoundsStaySafe() {
        let model = IslandModel()
        XCTAssertFalse(model.isSupported)
        XCTAssertEqual(model.captureLabel(phase: .idle), "Not listening")
        XCTAssertEqual(model.captureLabel(phase: .running), "No audio")
        XCTAssertFalse(model.drawsActiveVisuals(phase: .running))

        var activeSnapshot = AudioSnapshot.zero
        activeSnapshot.isSilent = false
        model.snapshot = activeSnapshot
        XCTAssertEqual(model.captureLabel(phase: .running), "Listening")
        XCTAssertTrue(model.drawsActiveVisuals(phase: .running))
        XCTAssertFalse(model.drawsActiveVisuals(phase: .idle))

        let shape = IslandShape(bottomRadius: 16)
        let rect = CGRect(x: 0, y: 0, width: 320, height: 132)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(path.boundingRect))
        XCTAssertTrue(IslandShape(bottomRadius: 16).path(in: .zero).isEmpty)
    }
}
