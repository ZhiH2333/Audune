import CoreGraphics
import Foundation

nonisolated enum StudioChromeMotion {
    static let revealSeconds = 0.20
    static let hideDelaySeconds = 0.40
    static let hideSeconds = 0.25

    static func fadeSeconds(hiding: Bool, reduceMotion: Bool) -> Double {
        guard reduceMotion == false else { return 0 }
        return hiding ? hideSeconds : revealSeconds
    }
}

nonisolated enum StudioChrome {
    static let barHeight: CGFloat = 36
    static let gripWidth: CGFloat = 28
    static let gripHeight: CGFloat = 22
    /// Keeps the controls up while the pointer is on the edge, moving toward them.
    static let pointerSlop: CGFloat = 8

    static func pointerIsInside(windowFrame: CGRect, cursor: CGPoint) -> Bool {
        guard windowFrame.width.isFinite, windowFrame.height.isFinite, windowFrame.width > 0, windowFrame.height > 0,
              cursor.x.isFinite, cursor.y.isFinite
        else { return false }
        return windowFrame.insetBy(dx: -pointerSlop, dy: -pointerSlop).contains(cursor)
    }

    static func isVisible(
        pointerInside: Bool,
        pointerDown: Bool,
        holdsChrome: Bool,
        now: TimeInterval,
        exitedAt: TimeInterval?
    ) -> Bool {
        if pointerInside || pointerDown || holdsChrome { return true }
        guard let exitedAt else { return true }
        return now - exitedAt < StudioChromeMotion.hideDelaySeconds
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
