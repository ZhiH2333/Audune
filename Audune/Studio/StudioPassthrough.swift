#if os(macOS)
import AppKit
import SwiftUI

enum StudioResizeEdge: Equatable, Sendable {
    case minX
    case maxX
    case minY
    case maxY
}

struct StudioEdgeBand: Equatable, Sendable {
    var edge: StudioResizeEdge
    var frame: CGRect
}

#if DEBUG
struct StudioPassthroughInspection: Equatable {
    var visualIgnoresMouseEvents: Bool
    var interactionVisible: Bool
    var interactionFrame: CGRect
    var interactionIgnoresMouseEvents: Bool
    var interactionLevel: NSWindow.Level
    var interactionCollectionBehavior: NSWindow.CollectionBehavior
    var edgeFrames: [CGRect]
}
#endif

/// Screen-coordinate frames for the controls panel and the resize strips.
/// The visual window itself ignores mouse events while passthrough is on, so these frames are the only hit targets.
enum StudioPassthroughLayout {
    static func interactionFrame(visual: CGRect, contentSize: CGSize, padding: CGFloat = 8) -> CGRect {
        guard visual.isValidRect, contentSize.isValidSize else { return .zero }
        let pad = padding.isFinite && padding >= 0 ? padding : 0
        let width = min(contentSize.width, max(visual.width - pad * 2, 1))
        let height = min(contentSize.height, max(visual.height - pad * 2, 1))
        return CGRect(x: visual.midX - width / 2, y: visual.minY + pad, width: width, height: height)
    }

    static func edgeBands(in visual: CGRect, margin: CGFloat = 6) -> [StudioEdgeBand] {
        guard visual.isValidRect, margin.isFinite, margin > 0, visual.width > margin * 2, visual.height > margin * 2 else {
            return []
        }
        return [
            StudioEdgeBand(edge: .minX, frame: CGRect(x: visual.minX, y: visual.minY, width: margin, height: visual.height)),
            StudioEdgeBand(edge: .maxX, frame: CGRect(x: visual.maxX - margin, y: visual.minY, width: margin, height: visual.height)),
            StudioEdgeBand(edge: .minY, frame: CGRect(x: visual.minX, y: visual.minY, width: visual.width, height: margin)),
            StudioEdgeBand(edge: .maxY, frame: CGRect(x: visual.minX, y: visual.maxY - margin, width: visual.width, height: margin))
        ]
    }

    static func canvasCenterIsOpen(visual: CGRect, interaction: CGRect, edges: [CGRect]) -> Bool {
        let center = CGPoint(x: visual.midX, y: visual.midY)
        guard interaction.contains(center) == false else { return false }
        return edges.contains { $0.contains(center) } == false
    }
}

enum StudioWindowResize {
    static func frame(
        start: CGRect,
        startMouse: CGPoint,
        mouse: CGPoint,
        edge: StudioResizeEdge,
        minimum: CGSize,
        maximum: CGSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    ) -> CGRect {
        let values = [
            start.origin.x, start.origin.y, start.width, start.height,
            startMouse.x, startMouse.y, mouse.x, mouse.y,
            minimum.width, minimum.height, maximum.width, maximum.height
        ]
        guard values.allSatisfy(\.isFinite), start.isValidRect, minimum.isValidSize else { return start }
        let maxW = max(maximum.width, minimum.width)
        let maxH = max(maximum.height, minimum.height)
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        var frame = start
        switch edge {
        case .minX:
            frame.origin.x = start.origin.x + dx
            frame.size.width = start.width - dx
        case .maxX:
            frame.size.width = start.width + dx
        case .minY:
            frame.origin.y = start.origin.y + dy
            frame.size.height = start.height - dy
        case .maxY:
            frame.size.height = start.height + dy
        }
        if frame.width < minimum.width {
            if edge == .minX {
                frame.origin.x = start.maxX - minimum.width
            }
            frame.size.width = minimum.width
        } else if frame.width > maxW {
            if edge == .minX {
                frame.origin.x = start.maxX - maxW
            }
            frame.size.width = maxW
        }
        if frame.height < minimum.height {
            if edge == .minY {
                frame.origin.y = start.maxY - minimum.height
            }
            frame.size.height = minimum.height
        } else if frame.height > maxH {
            if edge == .minY {
                frame.origin.y = start.maxY - maxH
            }
            frame.size.height = maxH
        }
        return frame
    }

    @MainActor
    static func track(
        window: NSWindow,
        eventWindow: NSWindow,
        edge: StudioResizeEdge,
        minimum: CGSize,
        maximum: CGSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        onMove: (() -> Void)? = nil
    ) {
        let startMouse = NSEvent.mouseLocation
        let startFrame = window.frame
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        while true {
            let next = eventWindow.nextEvent(
                matching: mask,
                until: Date(timeIntervalSinceNow: 1.0 / 60.0),
                inMode: .eventTracking,
                dequeue: true
            )
            let resized = frame(
                start: startFrame,
                startMouse: startMouse,
                mouse: NSEvent.mouseLocation,
                edge: edge,
                minimum: minimum,
                maximum: maximum
            )
            window.setFrame(resized, display: window.isVisible)
            onMove?()
            if next?.type == .leftMouseUp || NSEvent.pressedMouseButtons & 1 == 0 {
                return
            }
        }
    }
}

final class StudioEdgePanel: NSPanel {
    var edge: StudioResizeEdge = .minX
}

final class StudioEdgeView: NSView {
    var onMouseDown: (() -> Void)?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

final class StudioInteractionHostingView<Content: View>: NSHostingView<Content> {
    var onPointerInside: ((Bool) -> Void)?
    private var pointerTracking: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
        onPointerInside?(StudioChrome.pointerIsInside(
            windowFrame: window.frame,
            cursor: NSEvent.mouseLocation,
            slop: StudioChrome.controlLeaveDistance
        ))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct StudioPassthroughGrip: NSViewRepresentable {
    var chromeVisible: Bool
    var allowsDrag: Bool
    var onDrag: () -> Void
    var onSummon: () -> Void

    func makeNSView(context: Context) -> StudioPassthroughGripView {
        let view = StudioPassthroughGripView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: StudioPassthroughGripView, context: Context) {
        view.chromeVisible = chromeVisible
        view.allowsDrag = allowsDrag
        view.onDrag = onDrag
        view.onSummon = onSummon
    }
}

final class StudioPassthroughGripView: NSView {
    var chromeVisible = false
    var allowsDrag = true
    var onDrag: () -> Void = {}
    var onSummon: () -> Void = {}

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if allowsDrag {
            onDrag()
        } else {
            onSummon()
        }
    }
}

struct StudioInteractionRoot: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: StudioModel
    var savePreferences: () -> Void
    var openSettings: () -> Void
    var togglePlayback: () -> Void
    var drag: () -> Void
    var summon: () -> Void
    var onContentSize: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                StudioPassthroughGrip(
                    chromeVisible: model.chromeVisible,
                    allowsDrag: model.prefs.window.allowsDrag,
                    onDrag: drag,
                    onSummon: summon
                )
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .allowsHitTesting(false)
            }
            .frame(width: StudioChrome.gripWidth, height: StudioChrome.gripHeight)
            .accessibilityLabel("Drag Studio")
            if model.chromeVisible {
                revealedButtons
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Color(red: 0.96, green: 0.94, blue: 0.90))
        .animation(buttonFade, value: model.chromeVisible)
        .fixedSize()
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onContentSize(proxy.size) }
                    .onChange(of: proxy.size) { _, newSize in
                        onContentSize(newSize)
                    }
            }
        }
    }

    private var revealedButtons: some View {
        HStack(spacing: 4) {
            if spike.phase == .failed {
                Text(spike.userFailureSummary)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .frame(width: 160, alignment: .leading)
            }
            StudioControlButton(
                title: PlaybackButton.title(availability: model.playbackAvailability, state: model.playbackState),
                symbol: PlaybackButton.symbol(availability: model.playbackAvailability, state: model.playbackState),
                disabled: PlaybackButton.isEnabled(
                    selection: model.playerID,
                    availability: model.playbackAvailability,
                    busy: model.playbackBusy
                ) == false,
                accessibilityLabel: String(localized: "Play or pause"),
                accessibilityValue: model.playbackDetail,
                action: togglePlayback
            )
            ForEach(StudioVisualMode.allCases) { mode in
                StudioControlButton(
                    title: mode.title,
                    symbol: mode.symbol,
                    selected: model.prefs.mode == mode
                ) {
                    model.prefs.mode = mode
                    savePreferences()
                }
            }
            StudioControlButton(title: String(localized: "Settings"), symbol: "gearshape", action: openSettings)
        }
    }

    private var buttonFade: Animation? {
        let duration = StudioChromeMotion.fadeSeconds(
            hiding: model.chromeVisible == false,
            reduceMotion: reduceMotion,
            animates: model.prefs.window.animatesChrome,
            followsReduceMotion: model.prefs.window.followsReduceMotion
        )
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }
}

private extension CGRect {
    var isValidRect: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

private extension CGSize {
    var isValidSize: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}
#endif
