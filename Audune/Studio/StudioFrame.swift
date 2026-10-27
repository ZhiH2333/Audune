import CoreGraphics
import Foundation

/// Saved Studio frames are in points. Empty screen lists use `fallback`.
nonisolated enum StudioFrame {
    /// Absolute floor for chrome usability. User prefs cannot go below this.
    static let absoluteMinimum = CGSize(width: 360, height: 240)
    /// Preferred default minimum when prefs are absent. Matches `absoluteMinimum`.
    static let minimumSize = absoluteMinimum
    static let defaultSize = CGSize(width: 640, height: 400)
    /// Default user-facing maximum when prefs are absent.
    static let defaultMaximumSize = CGSize(width: 1600, height: 1000)

    /// Resolves user min/max against the absolute floor and optional screen bounds.
    /// When `max < min` after clamping, max is raised to min (stable, predictable).
    static func effectiveLimits(
        minWidth: Double,
        minHeight: Double,
        maxWidth: Double,
        maxHeight: Double,
        screen: CGSize? = nil
    ) -> (minimum: CGSize, maximum: CGSize) {
        let floorW = absoluteMinimum.width
        let floorH = absoluteMinimum.height
        var minW = finiteOr(minWidth, floorW)
        var minH = finiteOr(minHeight, floorH)
        var maxW = finiteOr(maxWidth, defaultMaximumSize.width)
        var maxH = finiteOr(maxHeight, defaultMaximumSize.height)

        minW = max(minW, floorW)
        minH = max(minH, floorH)
        maxW = max(maxW, minW)
        maxH = max(maxH, minH)

        if let screen, screen.width.isFinite, screen.height.isFinite, screen.width > 0, screen.height > 0 {
            let screenMaxW = max(screen.width, floorW)
            let screenMaxH = max(screen.height, floorH)
            maxW = min(maxW, screenMaxW)
            maxH = min(maxH, screenMaxH)
            minW = min(minW, maxW)
            minH = min(minH, maxH)
        }

        return (
            minimum: CGSize(width: minW, height: minH),
            maximum: CGSize(width: maxW, height: maxH)
        )
    }

    /// Clamps a frame into `[minimum, maximum]` while keeping the chosen edge anchored when possible.
    static func constrain(_ frame: CGRect, minimum: CGSize, maximum: CGSize) -> CGRect {
        let values = [
            frame.origin.x, frame.origin.y, frame.width, frame.height,
            minimum.width, minimum.height, maximum.width, maximum.height
        ]
        guard values.allSatisfy(\.isFinite),
              frame.width > 0 || frame.height > 0,
              minimum.width.isFinite, minimum.height.isFinite,
              maximum.width.isFinite, maximum.height.isFinite
        else { return frame }

        let minW = max(minimum.width, 1)
        let minH = max(minimum.height, 1)
        let maxW = max(maximum.width, minW)
        let maxH = max(maximum.height, minH)

        var result = frame
        if result.width < minW {
            result.size.width = minW
        } else if result.width > maxW {
            result.size.width = maxW
        }
        if result.height < minH {
            result.size.height = minH
        } else if result.height > maxH {
            result.size.height = maxH
        }
        return result
    }

    /// The default size centered in `visible`. Falls back to the minimum size on tiny or invalid areas.
    static func centeredDefault(in visible: CGRect) -> CGRect {
        guard visible.width.isFinite, visible.height.isFinite, visible.width > 0, visible.height > 0 else {
            return CGRect(origin: .zero, size: defaultSize)
        }
        let width = min(max(defaultSize.width, minimumSize.width), visible.width)
        let height = min(max(defaultSize.height, minimumSize.height), visible.height)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    static func clamped(
        _ frame: CGRect,
        to visibleFrames: [CGRect],
        fallback: CGRect,
        minimum: CGSize = minimumSize,
        maximum: CGSize? = nil
    ) -> CGRect {
        let home = visibleFrames.first { $0.intersects(frame) && $0.width > 0 && $0.height > 0 }
            ?? visibleFrames.first { $0.width > 0 && $0.height > 0 }
            ?? fallback
        let bounds = home.width > 0 && home.height > 0
            ? home
            : CGRect(origin: .zero, size: absoluteMinimum)
        // Tiny screens/fallbacks may be smaller than the absolute floor; never exceed bounds.
        let minW = min(max(minimum.width, 1), bounds.width)
        let minH = min(max(minimum.height, 1), bounds.height)
        let preferredMaxW = maximum?.width ?? bounds.width
        let preferredMaxH = maximum?.height ?? bounds.height
        let maxW = min(max(preferredMaxW, minW), bounds.width)
        let maxH = min(max(preferredMaxH, minH), bounds.height)
        let width = min(max(frame.width, minW), maxW)
        let height = min(max(frame.height, minH), maxH)
        var origin = frame.origin
        if origin.x < bounds.minX { origin.x = bounds.minX }
        if origin.y < bounds.minY { origin.y = bounds.minY }
        if origin.x + width > bounds.maxX { origin.x = bounds.maxX - width }
        if origin.y + height > bounds.maxY { origin.y = bounds.maxY - height }
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private static func finiteOr(_ value: Double, _ fallback: CGFloat) -> CGFloat {
        guard value.isFinite else { return fallback }
        return CGFloat(value)
    }
}

nonisolated enum StudioWindowStorage {
    static let frameAutosaveName = "AuduneStudio"
}
