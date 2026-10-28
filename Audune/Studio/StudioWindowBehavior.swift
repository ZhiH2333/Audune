#if os(macOS)
import AppKit
import CoreGraphics
#if DEBUG
import os

/// Debug-only trace of the Studio grip drag. View it with
/// `log stream --predicate 'subsystem == "Audune" AND category == "StudioDrag"'`. No audio data is logged.
let studioDragLog = Logger(subsystem: "Audune", category: "StudioDrag")
#endif

/// Window level and Spaces membership are separate.
/// `fullScreenAuxiliary` alone hides a panel on ordinary desktops, so On Top pairs it with `canJoinAllSpaces`.
nonisolated enum StudioWindowBehavior {
    static let resizeMargin: CGFloat = 6
    static let controlSlop: CGFloat = 1

    static func level(for mode: StudioWindowMode) -> NSWindow.Level {
        switch mode {
        case .onDesktop:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        case .onTop:
            return .floating
        case .asWindow:
            return .normal
        }
    }

    static func isFloatingPanel(for mode: StudioWindowMode) -> Bool {
        mode == .onTop
    }

    static func collectionBehavior(for mode: StudioWindowMode) -> NSWindow.CollectionBehavior {
        switch mode {
        case .onDesktop:
            return [.canJoinAllSpaces]
        case .onTop:
            return [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .asWindow:
            return []
        }
    }
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
        controlSlop: CGFloat = StudioWindowBehavior.controlSlop,
        chromeVisible: Bool = true
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
        guard chromeVisible else { return .idle }
        if controlFrames.contains(where: { $0.insetBy(dx: -slop, dy: -slop).contains(point) }) {
            return .control
        }
        if gripFrames.contains(where: { $0.insetBy(dx: -slop, dy: -slop).contains(point) }) {
            return .drag
        }
        return .idle
    }

    /// SwiftUI frames use a top-left origin. A plain AppKit view uses a bottom-left origin,
    /// but `NSHostingView.isFlipped` is true, so its bounds already use the same top-left origin.
    /// Flipping again inside a flipped view mirrors every region to the other edge.
    static func appKitFrames(fromTopLeft frames: [CGRect], containerHeight: CGFloat, isFlipped: Bool = false) -> [CGRect] {
        guard containerHeight.isFinite, containerHeight > 0 else { return [] }
        return frames.compactMap { rect in
            guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.width > 0, rect.height > 0
            else { return nil }
            return CGRect(
                x: rect.origin.x,
                y: isFlipped ? rect.origin.y : containerHeight - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
        }
    }
}

final class StudioHitMap {
    var controlFramesTopLeft: [CGRect] = []
    var gripFramesTopLeft: [CGRect] = []
    /// Hidden controls keep their rectangles. Routing ignores them until this is true.
    var chromeVisible = true
    /// The Window setting that turns dragging off. The grip stays visible but does not move the window.
    var allowsDrag = true
    /// Keeps passthrough panels attached while the visual panel moves.
    var onWindowFrameChanged: (() -> Void)?
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
    static func apply(to window: NSWindow, startOrigin: CGPoint, startMouse: CGPoint, currentMouse: CGPoint) {
        window.setFrameOrigin(origin(startOrigin: startOrigin, startMouse: startMouse, currentMouse: currentMouse))
    }

    /// Moves a borderless panel from screen coordinates.
    /// `performDrag(with:)` is not used: on this panel it ends immediately and logs
    /// "Window move completed without beginning" without moving the window.
    @MainActor
    static func track(_ window: NSWindow, onMove: (() -> Void)? = nil) {
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        #if DEBUG
        studioDragLog.debug("drag begin mouse=\(startMouse.x, privacy: .public),\(startMouse.y, privacy: .public) origin=\(startOrigin.x, privacy: .public),\(startOrigin.y, privacy: .public)")
        defer {
            let end = window.frame.origin
            studioDragLog.debug("drag end origin=\(end.x, privacy: .public),\(end.y, privacy: .public)")
        }
        #endif
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        let monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            if event.type != .leftMouseUp, event.window === window || event.window == nil {
                apply(to: window, startOrigin: startOrigin, startMouse: startMouse, currentMouse: NSEvent.mouseLocation)
                onMove?()
            }
            return event
        }
        defer {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        while true {
            let next = window.nextEvent(
                matching: mask,
                until: Date(timeIntervalSinceNow: 1.0 / 60.0),
                inMode: .eventTracking,
                dequeue: true
            )
            if next?.type == .leftMouseUp {
                return
            }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                return
            }
            apply(to: window, startOrigin: startOrigin, startMouse: startMouse, currentMouse: NSEvent.mouseLocation)
            onMove?()
        }
    }
}

#if DEBUG
struct StudioWindowInspection: Equatable {
    var frame: NSRect
    var level: NSWindow.Level
    var isFloatingPanel: Bool
    var hidesOnDeactivate: Bool
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
#endif
