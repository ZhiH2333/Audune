#if os(macOS)
import AppKit
import CoreGraphics

/// Visible on every normal Space and beside full-screen apps.
/// `fullScreenAuxiliary` alone hides the panel on ordinary desktops.
nonisolated enum StudioWindowBehavior {
    static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    static let resizeMargin: CGFloat = 6
    static let controlSlop: CGFloat = 1
}

nonisolated enum StudioDragRoute: Equatable {
    case drag
    case control
    case resize
    case idle
}

nonisolated enum StudioDragRouting {
    static func route(
        point: CGPoint,
        bounds: CGRect,
        controlFrames: [CGRect],
        gripFrames: [CGRect] = [],
        edge: CGFloat = StudioWindowBehavior.resizeMargin,
        controlSlop: CGFloat = StudioWindowBehavior.controlSlop
    ) -> StudioDragRoute {
        guard bounds.width > edge * 2, bounds.height > edge * 2, point.x.isFinite, point.y.isFinite else {
            return .control
        }
        if point.x < bounds.minX + edge
            || point.y < bounds.minY + edge
            || point.x > bounds.maxX - edge
            || point.y > bounds.maxY - edge
        {
            return .resize
        }
        let slop = controlSlop.isFinite && controlSlop > 0 ? controlSlop : 0
        if controlFrames.contains(where: { $0.insetBy(dx: -slop, dy: -slop).contains(point) }) {
            return .control
        }
        if gripFrames.contains(where: { $0.insetBy(dx: -slop, dy: -slop).contains(point) }) {
            return .drag
        }
        return .idle
    }

    /// SwiftUI frames use a top-left origin. AppKit view bounds use a bottom-left origin.
    static func appKitFrames(fromTopLeft frames: [CGRect], containerHeight: CGFloat) -> [CGRect] {
        guard containerHeight.isFinite, containerHeight > 0 else { return [] }
        return frames.compactMap { rect in
            guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.width > 0, rect.height > 0
            else { return nil }
            return CGRect(
                x: rect.origin.x,
                y: containerHeight - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
        }
    }
}

final class StudioHitMap {
    var controlFramesTopLeft: [CGRect] = []
    var gripFramesTopLeft: [CGRect] = []
}

enum StudioWindowDrag {
    static func origin(startOrigin: CGPoint, startMouse: CGPoint, currentMouse: CGPoint) -> CGPoint {
        let values = [startOrigin.x, startOrigin.y, startMouse.x, startMouse.y, currentMouse.x, currentMouse.y]
        guard values.allSatisfy(\.isFinite) else { return startOrigin }
        return CGPoint(
            x: startOrigin.x + (currentMouse.x - startMouse.x),
            y: startOrigin.y + (currentMouse.y - startMouse.y)
        )
    }

    @MainActor
    static func track(_ window: NSWindow) {
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { return }
            if next.type == .leftMouseUp { return }
            window.setFrameOrigin(
                origin(startOrigin: startOrigin, startMouse: startMouse, currentMouse: NSEvent.mouseLocation)
            )
        }
    }
}

struct StudioWindowInspection: Equatable {
    var collectionBehavior: NSWindow.CollectionBehavior
    var isMovable: Bool
    var isMovableByWindowBackground: Bool
    var isResizable: Bool
    var usesDragHostingView: Bool
    var isOpaque: Bool
    var backgroundAlpha: CGFloat
    var hasShadow: Bool
    var ignoresMouseEvents: Bool
    var hostIsOpaque: Bool
}
#endif
