#if os(macOS)
import AppKit
import SwiftUI

enum StudioCoordinateSpace {
    static let name = "AuduneStudio"
}

struct StudioControlFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func studioControlRegion() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StudioControlFramesKey.self,
                    value: [proxy.frame(in: .named(StudioCoordinateSpace.name))]
                )
            }
        }
    }
}

struct StudioDragSurface: NSViewRepresentable {
    var hitMap: StudioHitMap

    func makeNSView(context: Context) -> StudioDragView {
        let view = StudioDragView()
        view.hitMap = hitMap
        return view
    }

    func updateNSView(_ view: StudioDragView, context: Context) {
        view.hitMap = hitMap
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: StudioDragView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class StudioDragView: NSView {
    var hitMap = StudioHitMap()

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        guard let content = window?.contentView else { return self }
        return route(localPointInSelf: local, content: content) == .drag ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, let content = window?.contentView else {
            super.mouseDown(with: event)
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        guard route(localPointInSelf: local, content: content) == .drag else {
            super.mouseDown(with: event)
            return
        }
        guard let window else { return }
        StudioWindowDrag.track(window)
    }

    private func route(localPointInSelf local: CGPoint, content: NSView) -> StudioDragRoute {
        let point = content.convert(local, from: self)
        let frames = StudioDragRouting.appKitFrames(
            fromTopLeft: hitMap.controlFramesTopLeft,
            containerHeight: content.bounds.height
        )
        return StudioDragRouting.route(point: point, bounds: content.bounds, controlFrames: frames)
    }
}

final class StudioHostingView<Content: View>: NSHostingView<Content> {
    var hitMap = StudioHitMap()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        let route = currentRoute(local)
        if route == .resize {
            return nil
        }
        let hit = super.hitTest(point)
        if let hit, hit !== self, containsControl(hit) {
            return hit
        }
        if route == .drag {
            return dragView(containing: local) ?? self
        }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard event.type == .leftMouseDown, currentRoute(local) == .drag else {
            super.mouseDown(with: event)
            return
        }
        guard let window else { return }
        StudioWindowDrag.track(window)
    }

    private func currentRoute(_ point: CGPoint) -> StudioDragRoute {
        let frames = StudioDragRouting.appKitFrames(
            fromTopLeft: hitMap.controlFramesTopLeft,
            containerHeight: bounds.height
        )
        return StudioDragRouting.route(point: point, bounds: bounds, controlFrames: frames)
    }

    private func containsControl(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current, candidate !== self {
            if candidate is NSControl {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    private func dragView(containing point: NSPoint) -> StudioDragView? {
        func walk(_ view: NSView) -> StudioDragView? {
            for subview in view.subviews.reversed() {
                let local = subview.convert(point, from: self)
                guard subview.bounds.contains(local) else { continue }
                if let drag = subview as? StudioDragView {
                    return drag
                }
                if let found = walk(subview) {
                    return found
                }
            }
            return nil
        }
        return walk(self)
    }
}
#endif
