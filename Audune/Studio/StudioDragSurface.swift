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

struct StudioGripFramesKey: PreferenceKey {
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

    func studioGripRegion() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StudioGripFramesKey.self,
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
        let height = content.bounds.height
        return StudioDragRouting.route(
            point: point,
            bounds: content.bounds,
            controlFrames: StudioDragRouting.appKitFrames(fromTopLeft: hitMap.controlFramesTopLeft, containerHeight: height, isFlipped: content.isFlipped),
            gripFrames: StudioDragRouting.appKitFrames(fromTopLeft: hitMap.allowsDrag ? hitMap.gripFramesTopLeft : [], containerHeight: height, isFlipped: content.isFlipped),
            chromeVisible: hitMap.chromeVisible
        )
    }
}

final class StudioHostingView<Content: View>: NSHostingView<Content> {
    var hitMap = StudioHitMap()
    var onPointerInside: ((Bool) -> Void)?
    private var pointerTracking: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearLayerBackground()
    }

    override func layout() {
        super.layout()
        clearLayerBackground()
    }

    private func clearLayerBackground() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking {
            removeTrackingArea(pointerTracking)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerInside?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let window else {
            onPointerInside?(false)
            return
        }
        onPointerInside?(StudioChrome.pointerIsInside(windowFrame: window.frame, cursor: NSEvent.mouseLocation))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        switch currentRoute(local) {
        case .resize:
            return nil
        case .idle, .drag:
            return self
        case .control:
            return super.hitTest(point) ?? self
        }
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard currentRoute(local) == .drag, let window else {
            super.mouseDown(with: event)
            return
        }
        StudioWindowDrag.track(window)
    }

    func currentRoute(_ point: CGPoint) -> StudioDragRoute {
        let height = bounds.height
        return StudioDragRouting.route(
            point: point,
            bounds: bounds,
            controlFrames: StudioDragRouting.appKitFrames(fromTopLeft: hitMap.controlFramesTopLeft, containerHeight: height, isFlipped: isFlipped),
            gripFrames: StudioDragRouting.appKitFrames(fromTopLeft: hitMap.allowsDrag ? hitMap.gripFramesTopLeft : [], containerHeight: height, isFlipped: isFlipped),
            chromeVisible: hitMap.chromeVisible
        )
    }
}
#endif
