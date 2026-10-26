import CoreGraphics
import Foundation

nonisolated enum StudioChromeMotion {
    static let revealSeconds = 0.20
    static let hideDelaySeconds = 3.0
    static let hideSeconds = 0.25

    /// `reduceMotion` is the system setting. It only matters while `followsReduceMotion` is on.
    static func fadeSeconds(
        hiding: Bool,
        reduceMotion: Bool,
        animates: Bool = true,
        followsReduceMotion: Bool = true
    ) -> Double {
        guard animates else { return 0 }
        guard reduceMotion == false || followsReduceMotion == false else { return 0 }
        return hiding ? hideSeconds : revealSeconds
    }
}

nonisolated enum StudioChrome {
    static let barHeight: CGFloat = 36
    static let gripWidth: CGFloat = 28
    static let gripHeight: CGFloat = 22
    /// Keeps the controls up while the pointer is on the edge, moving toward them.
    static let pointerSlop: CGFloat = 8
    /// How close the pointer must be before the buttons fade in.
    static let controlProximity: CGFloat = 40
    /// Once the buttons are visible, they stay until the pointer is at least this far outside them.
    static let controlLeaveDistance: CGFloat = 120

    static func pointerKeepsControls(controlFrame: CGRect, cursor: CGPoint, controlsVisible: Bool) -> Bool {
        let margin = controlsVisible ? controlLeaveDistance : controlProximity
        return pointerIsInside(windowFrame: controlFrame, cursor: cursor, slop: margin)
    }

    static func pointerIsInside(windowFrame: CGRect, cursor: CGPoint, slop: CGFloat = pointerSlop) -> Bool {
        guard windowFrame.width.isFinite, windowFrame.height.isFinite, windowFrame.width > 0, windowFrame.height > 0,
              cursor.x.isFinite, cursor.y.isFinite
        else { return false }
        let margin = slop.isFinite && slop >= 0 ? slop : pointerSlop
        return windowFrame.insetBy(dx: -margin, dy: -margin).contains(cursor)
    }

    static func isVisible(
        pointerInside: Bool,
        pointerDown: Bool,
        holdsChrome: Bool,
        now: TimeInterval,
        exitedAt: TimeInterval?,
        hideDelay: TimeInterval = StudioChromeMotion.hideDelaySeconds,
        autoHides: Bool = true
    ) -> Bool {
        if autoHides == false { return true }
        if pointerInside || pointerDown || holdsChrome { return true }
        guard let exitedAt else { return true }
        let delay = hideDelay.isFinite ? max(hideDelay, 0) : StudioChromeMotion.hideDelaySeconds
        return now - exitedAt < delay
    }

    /// Size of the always-present summon target while the buttons are hidden.
    static func hiddenContentSize(region: StudioSummonRegion, visualWidth: CGFloat) -> CGSize {
        let grip = CGSize(width: gripWidth, height: gripHeight)
        switch region {
        case .grip:
            return grip
        case .bottomEdge:
            let width = visualWidth.isFinite ? max(visualWidth - 16, grip.width) : grip.width
            return CGSize(width: width, height: barHeight)
        }
    }

    static func canvasFrame(in bounds: CGRect) -> CGRect {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return .zero }
        return bounds
    }

    static func chromeFrame(in bounds: CGRect) -> CGRect {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return .zero }
        let height = min(barHeight, bounds.height)
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }
}

/// One hide countdown. `cancel` or a newer `arm` makes the previous token stale.
struct StudioChromeHide: Equatable {
    /// Hidden until the pointer comes close. A nil exit still means visible.
    static var concealed: StudioChromeHide {
        var value = StudioChromeHide()
        _ = value.arm(at: 0, autoHides: true, engaged: false)
        return value
    }

    private(set) var generation = 0
    private(set) var exitedAt: TimeInterval?

    mutating func arm(at now: TimeInterval, autoHides: Bool, engaged: Bool) -> Int? {
        generation += 1
        guard autoHides, engaged == false, now.isFinite else {
            exitedAt = nil
            return nil
        }
        exitedAt = now
        return generation
    }

    mutating func cancel() {
        generation += 1
        exitedAt = nil
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }
}
