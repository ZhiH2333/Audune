import CoreGraphics
import XCTest
@testable import Audune

final class IslandStateMachineTests: XCTestCase {
    func testHoverArmsCompactUntilTheExpandDelayElapses() {
        var ctx = IslandStateContext(state: .compact)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true, at: 10), expandDelay: 0.35)

        XCTAssertEqual(ctx.state, .compact)
        XCTAssertTrue(ctx.pointerInside)
        XCTAssertEqual(ctx.expandArmedAt, 10)
        XCTAssertNil(ctx.exitedAt)

        ctx = IslandStateMachine.reduce(context: ctx, event: .expandTimerFired(now: 10.34), expandDelay: 0.35)
        XCTAssertEqual(ctx.state, .compact)
        XCTAssertEqual(ctx.expandArmedAt, 10)

        ctx = IslandStateMachine.reduce(context: ctx, event: .expandTimerFired(now: 10.35), expandDelay: 0.35)
        XCTAssertEqual(ctx.state, .expanded)
        XCTAssertNil(ctx.expandArmedAt)
        XCTAssertTrue(ctx.pointerInside)
    }

    func testLeavingDuringTheExpandDelayCancelsAndReentryRestartsIt() {
        var ctx = IslandStateContext(state: .compact)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true, at: 10), expandDelay: 0.35)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerExited(at: 10.1), expandDelay: 0.35)
        XCTAssertEqual(ctx.state, .compact)
        XCTAssertNil(ctx.expandArmedAt)

        ctx = IslandStateMachine.reduce(context: ctx, event: .expandTimerFired(now: 10.5), expandDelay: 0.35)
        XCTAssertEqual(ctx.state, .compact)

        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true, at: 12), expandDelay: 0.35)
        XCTAssertEqual(ctx.expandArmedAt, 12)
        ctx = IslandStateMachine.reduce(context: ctx, event: .expandTimerFired(now: 12.2), expandDelay: 0.35)
        XCTAssertEqual(ctx.state, .compact)
        ctx = IslandStateMachine.reduce(context: ctx, event: .expandTimerFired(now: 12.35), expandDelay: 0.35)
        XCTAssertEqual(ctx.state, .expanded)
    }

    func testExpandDelayDoesNotChangeCollapseDelay() {
        var ctx = IslandStateContext(state: .expanded, pointerInside: true)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerExited(at: 4), collapseDelay: 0.9, expandDelay: 0.1)
        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 4.2), collapseDelay: 0.9, expandDelay: 0.1)
        XCTAssertEqual(ctx.state, .expanded)

        ctx = IslandStateMachine.reduce(context: ctx, event: .collapseTimerFired(now: 4.9), collapseDelay: 0.9, expandDelay: 0.1)
        XCTAssertEqual(ctx.state, .compact)
        XCTAssertNil(ctx.expandArmedAt)
    }

    func testPinEscapeAndDisableDropAPendingExpand() {
        var armed = IslandStateContext(state: .compact, expandArmedAt: 3, pointerInside: true)
        armed = IslandStateMachine.reduce(context: armed, event: .togglePin(at: 3.1))
        XCTAssertEqual(armed.state, .pinned)
        XCTAssertNil(armed.expandArmedAt)
        armed = IslandStateMachine.reduce(context: armed, event: .expandTimerFired(now: 4))
        XCTAssertEqual(armed.state, .pinned)

        var escaping = IslandStateContext(state: .compact, expandArmedAt: 3, pointerInside: true)
        escaping = IslandStateMachine.reduce(context: escaping, event: .escapePressed)
        XCTAssertEqual(escaping.state, .compact)
        XCTAssertNil(escaping.expandArmedAt)
        escaping = IslandStateMachine.reduce(context: escaping, event: .expandTimerFired(now: 4))
        XCTAssertEqual(escaping.state, .compact)

        var disabled = IslandStateContext(state: .compact, expandArmedAt: 3, pointerInside: true)
        disabled = IslandStateMachine.reduce(context: disabled, event: .availabilityChanged(isEnabled: false, isSupported: true))
        XCTAssertEqual(disabled.state, .disabled)
        XCTAssertNil(disabled.expandArmedAt)
        disabled = IslandStateMachine.reduce(context: disabled, event: .expandTimerFired(now: 20))
        XCTAssertEqual(disabled.state, .disabled)

        var cancelled = IslandStateContext(state: .expanded, expandArmedAt: 8, pointerInside: true)
        cancelled = IslandStateMachine.reduce(context: cancelled, event: .hoverTimingCancelled)
        XCTAssertEqual(cancelled.state, .expanded)
        XCTAssertNil(cancelled.expandArmedAt)
    }

    func testHoverDoesNotExpandWhenHoverToExpandIsOffButExplicitExpandStillWorks() {
        var ctx = IslandStateContext(state: .compact)
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: false, at: 1))
        XCTAssertEqual(ctx.state, .compact)
        XCTAssertTrue(ctx.pointerInside)
        XCTAssertNil(ctx.expandArmedAt)

        ctx = IslandStateMachine.reduce(context: ctx, event: .expandTimerFired(now: 2))
        XCTAssertEqual(ctx.state, .compact)

        ctx = IslandStateMachine.reduce(context: ctx, event: .expandRequested)
        XCTAssertEqual(ctx.state, .expanded)
        XCTAssertNil(ctx.expandArmedAt)
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
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true, at: 10.3), collapseDelay: 0.35)
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
        ctx = IslandStateMachine.reduce(context: ctx, event: .pointerEntered(hoverToExpand: true, at: 1))
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
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: false, reduceMotion: false), 0.12, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: true, followsReduceMotion: true), 0)
        XCTAssertEqual(
            IslandMotion.transitionSeconds(expanding: true, reduceMotion: true, followsReduceMotion: false),
            0.20,
            accuracy: 0.000_1
        )
        XCTAssertEqual(IslandMotion.prefeedbackSeconds(expandDelay: 0.35, reduceMotion: false), 0.12, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.prefeedbackSeconds(expandDelay: 0.1, reduceMotion: false), 0.1, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.prefeedbackSeconds(expandDelay: 0.35, reduceMotion: true, followsReduceMotion: true), 0)
        XCTAssertEqual(IslandMotion.prefeedbackScale(hoverArmed: true, reduceMotion: false), IslandMotion.armedContentScale)
        XCTAssertEqual(IslandMotion.prefeedbackScale(hoverArmed: true, reduceMotion: true), 1)
        XCTAssertEqual(IslandMotion.prefeedbackScale(hoverArmed: false, reduceMotion: false), 1)

        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: false, speed: 1), 0.20, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: false, reduceMotion: false, speed: 1), 0.12, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: false, speed: 2), 0.10, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: false, reduceMotion: false, speed: 0.5), 0.24, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: false, speed: .nan), 0.20, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: false, speed: 9), 0.10, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: false, reduceMotion: true, followsReduceMotion: true, speed: 0.5), 0)
        XCTAssertEqual(IslandMotion.transitionSeconds(expanding: true, reduceMotion: true, followsReduceMotion: false, speed: 2), 0.10, accuracy: 0.000_1)
        XCTAssertEqual(IslandMotion.framePace(expanding: true, duration: 0), .immediate)
        XCTAssertEqual(IslandMotion.framePace(expanding: true, duration: 0.2), .expandSettle)
        XCTAssertEqual(IslandMotion.framePace(expanding: false, duration: 0.12), .collapseSettle)
        let points = IslandMotion.expandSettleControlPoints
        for value in [points.0, points.1, points.2, points.3] {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    func testHapticCueFiresOnlyForCompactToExpanded() {
        XCTAssertEqual(IslandHapticStrength.light.feedbackPattern, .alignment)
        XCTAssertEqual(IslandHapticStrength.medium.feedbackPattern, .generic)
        XCTAssertEqual(IslandHapticStrength.strong.feedbackPattern, .levelChange)
        XCTAssertNil(IslandHapticStrength.off.feedbackPattern)

        XCTAssertEqual(IslandHapticCue.pattern(from: .compact, to: .expanded, strength: .light), .alignment)
        XCTAssertEqual(IslandHapticCue.pattern(from: .compact, to: .expanded, strength: .medium), .generic)
        XCTAssertEqual(IslandHapticCue.pattern(from: .compact, to: .expanded, strength: .strong), .levelChange)
        XCTAssertNil(IslandHapticCue.pattern(from: .compact, to: .expanded, strength: .off))
        XCTAssertNil(IslandHapticCue.pattern(from: .compact, to: .pinned, strength: .strong))
        XCTAssertNil(IslandHapticCue.pattern(from: .expanded, to: .expanded, strength: .strong))
        XCTAssertNil(IslandHapticCue.pattern(from: .expanded, to: .compact, strength: .medium))
        XCTAssertNil(IslandHapticCue.pattern(from: .pinned, to: .expanded, strength: .light))
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

        activeSnapshot.isSilent = true
        model.snapshot = activeSnapshot
        model.compactLevels = [0.4, 0.2, 0.1, 0.05]
        XCTAssertTrue(model.drawsActiveVisuals(phase: .running), "silent but still settling")
        model.compactLevels = [0, 0, 0, 0]
        XCTAssertFalse(model.drawsActiveVisuals(phase: .running), "settled silent baseline")

        let shape = IslandShape(bottomRadius: IslandChrome.expandedBottomRadius)
        let rect = CGRect(x: 0, y: 0, width: 320, height: 132)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(path.boundingRect))
        XCTAssertTrue(IslandShape(bottomRadius: IslandChrome.expandedBottomRadius).path(in: .zero).isEmpty)
        XCTAssertGreaterThan(IslandChrome.expandedBottomRadius, IslandChrome.compactBottomRadius)
    }
}
