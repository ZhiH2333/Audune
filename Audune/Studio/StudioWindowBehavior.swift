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
}

nonisolated enum StudioDragRouting {
    static func route(
        point: CGPoint,
        bounds: CGRect,
        controlFrames: [CGRect],
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
        return .drag
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
}

struct StudioWindowInspection: Equatable {
    var collectionBehavior: NSWindow.CollectionBehavior
    var isMovable: Bool
    var isMovableByWindowBackground: Bool
    var isResizable: Bool
    var usesDragHostingView: Bool
}
#endif
