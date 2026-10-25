import CoreGraphics
import Foundation

/// Saved Studio frames are in points. Empty screen lists use `fallback`.
nonisolated enum StudioFrame {
    static let minimumSize = CGSize(width: 360, height: 240)
    static let defaultSize = CGSize(width: 640, height: 400)

    /// The default size centered in `visible`. Falls back to the minimum size on tiny or invalid areas.
    static func centeredDefault(in visible: CGRect) -> CGRect {
        guard visible.width.isFinite, visible.height.isFinite, visible.width > 0, visible.height > 0 else {
            return CGRect(origin: .zero, size: defaultSize)
        }
        let width = min(max(defaultSize.width, minimumSize.width), visible.width)
        let height = min(max(defaultSize.height, minimumSize.height), visible.height)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    static func clamped(_ frame: CGRect, to visibleFrames: [CGRect], fallback: CGRect) -> CGRect {
        let home = visibleFrames.first { $0.intersects(frame) && $0.width > 0 && $0.height > 0 }
            ?? visibleFrames.first { $0.width > 0 && $0.height > 0 }
            ?? fallback
        let bounds = home.width > 0 && home.height > 0
            ? home
            : CGRect(origin: .zero, size: minimumSize)
        let width = min(max(frame.width, minimumSize.width), bounds.width)
        let height = min(max(frame.height, minimumSize.height), bounds.height)
        var origin = frame.origin
        if origin.x < bounds.minX { origin.x = bounds.minX }
        if origin.y < bounds.minY { origin.y = bounds.minY }
        if origin.x + width > bounds.maxX { origin.x = bounds.maxX - width }
        if origin.y + height > bounds.maxY { origin.y = bounds.maxY - height }
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
}

nonisolated enum StudioWindowStorage {
    static let frameAutosaveName = "AuduneStudio"
}
