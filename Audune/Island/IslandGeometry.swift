#if os(macOS)
import AppKit
#endif
import CoreGraphics
import Foundation

nonisolated struct IslandScreenDescriptor: Equatable, Sendable, Identifiable {
    var id: String
    var localizedName: String
    var frame: CGRect
    var visibleFrame: CGRect
    var safeAreaTop: CGFloat
    var auxiliaryTopLeft: CGRect?
    var auxiliaryTopRight: CGRect?
    var backingScaleFactor: CGFloat

    #if os(macOS)
    static func from(_ screen: NSScreen, index: Int = 0) -> IslandScreenDescriptor {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let identifier = number.map { "display-\($0)" } ?? "display-index-\(index)"
        return IslandScreenDescriptor(
            id: identifier,
            localizedName: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            backingScaleFactor: screen.backingScaleFactor
        )
    }
    #endif
}

nonisolated enum IslandUnsupportedReason: String, Error, Equatable, Sendable {
    case noScreens
    case noNotch
    case invalidGeometry

    var userMessage: String {
        switch self {
        case .noScreens:
            return String(localized: "No active display is available.")
        case .noNotch:
            return String(localized: "No notched display detected. Notch Island is only shown on displays with a camera housing.")
        case .invalidGeometry:
            return String(localized: "The display reported incomplete or unsupported top safe-area geometry.")
        }
    }
}

nonisolated enum IslandTargetScreenMode: Equatable, Sendable {
    case automatic
    case screenID(String)

    init(storedID: String) {
        let trimmed = storedID.trimmingCharacters(in: .whitespacesAndNewlines)
        self = trimmed.isEmpty ? .automatic : .screenID(trimmed)
    }

    var storedID: String {
        switch self {
        case .automatic:
            return ""
        case .screenID(let id):
            return id
        }
    }
}

nonisolated struct IslandNotchGeometry: Equatable, Sendable {
    var screenID: String
    var screenName: String
    var screenFrame: CGRect
    /// Camera housing rect in AppKit bottom-left screen coordinates.
    var notchRect: CGRect
    /// Compact window frame in AppKit bottom-left screen coordinates.
    var compactFrame: CGRect
    /// Expanded window frame in AppKit bottom-left screen coordinates. Always contains `compactFrame`.
    var expandedFrame: CGRect

    /// Expanded/Pinned frame used for all Expanded sessions (same size whether Now Playing is on or off).
    /// Compact unchanged.
    func expandedPlayerFrame() -> CGRect {
        let proposedHeight = expandedFrame.height + IslandGeometry.nowPlayingExpandedExtraHeight
        let height = min(proposedHeight, screenFrame.height * 0.55, screenFrame.maxY - screenFrame.minY - 8)

        let maxUsableWidth = screenFrame.width - 32
        let desiredWidth = min(
            max(
                notchRect.width + IslandGeometry.nowPlayingExpandedWidthPadding,
                IslandGeometry.nowPlayingMinExpandedWidth,
                notchRect.width + IslandGeometry.nowPlayingMinSideClearance * 2
            ),
            min(IslandGeometry.nowPlayingMaxExpandedWidth, maxUsableWidth)
        )
        let width = max(desiredWidth, expandedFrame.width)

        var x = notchRect.midX - width / 2
        let minX = min(screenFrame.minX + 16, compactFrame.minX)
        let maxX = max(screenFrame.maxX - 16 - width, compactFrame.maxX - width)
        x = min(max(x, minX), maxX)

        let frame = CGRect(
            x: x,
            y: screenFrame.maxY - max(height, expandedFrame.height),
            width: width,
            height: max(height, expandedFrame.height)
        )
        guard screenFrame.contains(frame), frame.contains(compactFrame) else {
            return expandedFrame
        }
        return frame
    }

    /// Backward-compatible alias; `nowPlayingEnabled` no longer changes the frame.
    func expandedFrame(nowPlayingEnabled: Bool) -> CGRect {
        _ = nowPlayingEnabled
        return expandedPlayerFrame()
    }

    /// Clear content width to the left/right of the notch inside an Expanded window frame.
    func expandedSideClearance(in windowFrame: CGRect) -> (left: CGFloat, right: CGFloat) {
        let localNotch = localNotchRect(in: windowFrame)
        let left = max(0, localNotch.minX)
        let right = max(0, windowFrame.width - localNotch.maxX)
        return (left, right)
    }

    var leftWingWidth: CGFloat {
        max(0, notchRect.minX - compactFrame.minX)
    }

    var rightWingWidth: CGFloat {
        max(0, compactFrame.maxX - notchRect.maxX)
    }

    /// Notch rect converted into the local top-left coordinate space of `windowFrame`.
    func localNotchRect(in windowFrame: CGRect) -> CGRect {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return .zero }
        return CGRect(
            x: notchRect.minX - windowFrame.minX,
            y: windowFrame.maxY - notchRect.maxY,
            width: notchRect.width,
            height: notchRect.height
        )
    }
}

nonisolated enum IslandScreenResolution: Equatable, Sendable {
    case supported(IslandNotchGeometry, usedFallbackScreen: Bool)
    case unsupported(IslandUnsupportedReason)

    var geometry: IslandNotchGeometry? {
        if case .supported(let geometry, _) = self {
            return geometry
        }
        return nil
    }

    var unsupportedReason: IslandUnsupportedReason? {
        if case .unsupported(let reason) = self {
            return reason
        }
        return nil
    }
}

nonisolated struct IslandCompactBars: Equatable, Sendable {
    var left: [CGRect]
    var right: [CGRect]
}

/// Pure screen-geometry detector and layout calculator for Notch Island.
/// Requires both a valid top safe-area inset and valid left/right auxiliary menu-bar areas.
nonisolated enum IslandGeometry {
    static let minSafeAreaTop: CGFloat = 16
    static let maxSafeAreaTop: CGFloat = 64
    static let minAuxiliaryWidth: CGFloat = 48
    static let minAuxiliaryHeight: CGFloat = 16
    static let topEdgeTolerance: CGFloat = 2
    static let minNotchWidth: CGFloat = 100
    static let maxNotchWidth: CGFloat = 360
    static let maxNotchWidthRatio: CGFloat = 0.45
    static let maxCenterOffset: CGFloat = 16
    static let defaultCompactWingWidth: CGFloat = 34
    static let minCompactWingWidth: CGFloat = 20
    static let minMenuBarClearance: CGFloat = 32
    static let defaultExpandedWidthPadding: CGFloat = 148
    static let minExpandedWidth: CGFloat = 320
    static let maxExpandedWidth: CGFloat = 420
    static let defaultExpandedHeight: CGFloat = 132
    /// Extra Expanded/Pinned height for the unified player-sized Island (independent of Now Playing on/off).
    static let nowPlayingExpandedExtraHeight: CGFloat = 72
    /// Physical notch is ~185–220 pt (14"/16" MacBook). Expanded needs wide wings
    /// so Pin/Settings sit clear of the camera housing (~160+ pt per side).
    static let nowPlayingExpandedWidthPadding: CGFloat = 340
    static let nowPlayingMinExpandedWidth: CGFloat = 520
    static let nowPlayingMaxExpandedWidth: CGFloat = 580
    /// Minimum clear width on each side of the notch for Expanded chrome.
    static let nowPlayingMinSideClearance: CGFloat = 150
    static let compactBarCounts = [4, 5, 6]

    static func analyze(screen: IslandScreenDescriptor) -> Result<IslandNotchGeometry, IslandUnsupportedReason> {
        guard isValidRect(screen.frame), screen.frame.width >= 320, screen.frame.height >= 200,
              screen.safeAreaTop.isFinite
        else {
            return .failure(.invalidGeometry)
        }

        if screen.safeAreaTop <= 0 {
            if screen.auxiliaryTopLeft == nil && screen.auxiliaryTopRight == nil {
                return .failure(.noNotch)
            }
            return .failure(.invalidGeometry)
        }

        guard screen.safeAreaTop >= minSafeAreaTop, screen.safeAreaTop <= maxSafeAreaTop else {
            return .failure(.invalidGeometry)
        }

        guard let left = screen.auxiliaryTopLeft,
              let right = screen.auxiliaryTopRight,
              isValidRect(left),
              isValidRect(right)
        else {
            return .failure(.invalidGeometry)
        }

        guard left.width >= minAuxiliaryWidth,
              right.width >= minAuxiliaryWidth,
              left.height >= minAuxiliaryHeight,
              right.height >= minAuxiliaryHeight
        else {
            return .failure(.invalidGeometry)
        }

        let bounds = screen.frame.insetBy(dx: -0.5, dy: -0.5)
        guard bounds.contains(left), bounds.contains(right) else {
            return .failure(.invalidGeometry)
        }

        guard abs(left.maxY - screen.frame.maxY) <= topEdgeTolerance,
              abs(right.maxY - screen.frame.maxY) <= topEdgeTolerance,
              left.maxX < right.minX
        else {
            return .failure(.invalidGeometry)
        }

        let notchMinX = left.maxX
        let notchMaxX = right.minX
        let notchWidth = notchMaxX - notchMinX
        let maxAllowedNotchWidth = min(maxNotchWidth, screen.frame.width * maxNotchWidthRatio)
        guard notchWidth >= minNotchWidth, notchWidth <= maxAllowedNotchWidth else {
            return .failure(.invalidGeometry)
        }

        let notchMidX = (notchMinX + notchMaxX) / 2
        guard abs(notchMidX - screen.frame.midX) <= maxCenterOffset else {
            return .failure(.invalidGeometry)
        }

        let notchHeight = max(screen.safeAreaTop, min(left.height, right.height))
        guard notchHeight >= minSafeAreaTop, notchHeight <= maxSafeAreaTop else {
            return .failure(.invalidGeometry)
        }

        let notchRect = CGRect(
            x: notchMinX,
            y: screen.frame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        guard screen.frame.contains(notchRect) else {
            return .failure(.invalidGeometry)
        }

        let availableLeftWing = left.width - minMenuBarClearance
        let availableRightWing = right.width - minMenuBarClearance
        let availableWing = min(availableLeftWing, availableRightWing)
        guard availableWing >= minCompactWingWidth else {
            return .failure(.invalidGeometry)
        }
        let wingWidth = min(defaultCompactWingWidth, availableWing)
        let compactFrame = CGRect(
            x: notchRect.minX - wingWidth,
            y: screen.frame.maxY - notchHeight,
            width: notchRect.width + wingWidth * 2,
            height: notchHeight
        )
        guard screen.frame.contains(compactFrame),
              compactFrame.minX >= left.minX,
              compactFrame.maxX <= right.maxX
        else {
            return .failure(.invalidGeometry)
        }

        let maxUsableWidth = screen.frame.width - 32
        let desiredExpandedWidth = min(
            max(notchRect.width + defaultExpandedWidthPadding, minExpandedWidth, compactFrame.width + 40),
            min(maxExpandedWidth, maxUsableWidth)
        )
        let expandedHeight = min(
            max(defaultExpandedHeight, notchHeight + 72),
            screen.frame.height * 0.5
        )
        guard desiredExpandedWidth >= compactFrame.width, expandedHeight >= compactFrame.height else {
            return .failure(.invalidGeometry)
        }

        var expandedX = notchRect.midX - desiredExpandedWidth / 2
        let minExpandedX = min(screen.frame.minX + 16, compactFrame.minX)
        let maxExpandedX = max(screen.frame.maxX - 16 - desiredExpandedWidth, compactFrame.maxX - desiredExpandedWidth)
        expandedX = min(max(expandedX, minExpandedX), maxExpandedX)

        let expandedFrame = CGRect(
            x: expandedX,
            y: screen.frame.maxY - expandedHeight,
            width: desiredExpandedWidth,
            height: expandedHeight
        )
        guard screen.frame.contains(expandedFrame), expandedFrame.contains(compactFrame) else {
            return .failure(.invalidGeometry)
        }

        return .success(
            IslandNotchGeometry(
                screenID: screen.id,
                screenName: screen.localizedName,
                screenFrame: screen.frame,
                notchRect: notchRect,
                compactFrame: compactFrame,
                expandedFrame: expandedFrame
            )
        )
    }

    static func selectScreen(
        from screens: [IslandScreenDescriptor],
        target: IslandTargetScreenMode = .automatic
    ) -> IslandScreenResolution {
        guard screens.isEmpty == false else {
            return .unsupported(.noScreens)
        }

        var validGeometries: [IslandNotchGeometry] = []
        var sawInvalidGeometry = false

        for screen in screens {
            switch analyze(screen: screen) {
            case .success(let geometry):
                validGeometries.append(geometry)
            case .failure(let reason):
                if reason == .invalidGeometry {
                    sawInvalidGeometry = true
                }
            }
        }

        switch target {
        case .automatic:
            if let first = validGeometries.first {
                return .supported(first, usedFallbackScreen: false)
            }
            return .unsupported(sawInvalidGeometry ? .invalidGeometry : .noNotch)

        case .screenID(let requestedID):
            if let match = validGeometries.first(where: { $0.screenID == requestedID }) {
                return .supported(match, usedFallbackScreen: false)
            }
            if let fallback = validGeometries.first {
                return .supported(fallback, usedFallbackScreen: true)
            }
            return .unsupported(sawInvalidGeometry ? .invalidGeometry : .noNotch)
        }
    }

    /// Computes symmetric compact spectrum bars inside a top-left local `compactBounds`.
    /// Bars sit inside the left and right wings and never overlap the physical notch area.
    static func compactBars(
        levels: [Float],
        notchRect: CGRect,
        compactFrame: CGRect,
        barsPerSide requestedCount: Int = 5,
        amplitude: CGFloat = 1,
        drawsActiveBars: Bool = true
    ) -> IslandCompactBars {
        let bounds = CGRect(origin: .zero, size: compactFrame.size)
        guard isValidRect(bounds), isValidRect(notchRect), isValidRect(compactFrame),
              compactFrame.contains(notchRect)
        else {
            return IslandCompactBars(left: [], right: [])
        }

        let count = min(max(requestedCount, 3), 8)
        let localNotchMinX = notchRect.minX - compactFrame.minX
        let localNotchMaxX = localNotchMinX + notchRect.width
        let leftWingWidth = localNotchMinX
        let rightWingWidth = bounds.width - localNotchMaxX
        let outerInset: CGFloat = 7
        let innerInset: CGFloat = 5
        let verticalInset: CGFloat = 6
        let gap: CGFloat = 2

        let leftDrawableWidth = leftWingWidth - outerInset - innerInset
        let rightDrawableWidth = rightWingWidth - outerInset - innerInset
        let maxBarHeight = bounds.height - verticalInset * 2
        guard leftDrawableWidth > CGFloat(count) * 1.5,
              rightDrawableWidth > CGFloat(count) * 1.5,
              maxBarHeight >= 3
        else {
            return IslandCompactBars(left: [], right: [])
        }

        let leftBarWidth = (leftDrawableWidth - gap * CGFloat(count - 1)) / CGFloat(count)
        let rightBarWidth = (rightDrawableWidth - gap * CGFloat(count - 1)) / CGFloat(count)
        guard leftBarWidth > 0.5, rightBarWidth > 0.5 else {
            return IslandCompactBars(left: [], right: [])
        }

        let safeGain = amplitude.isFinite ? max(amplitude, 0) : 1
        let restingHeight = min(3, maxBarHeight)
        let centerY = bounds.midY

        var leftBars: [CGRect] = []
        var rightBars: [CGRect] = []
        leftBars.reserveCapacity(count)
        rightBars.reserveCapacity(count)

        for index in 0..<count {
            let raw = index < levels.count ? levels[index] : 0
            let level = (drawsActiveBars && raw.isFinite) ? min(max(CGFloat(raw) * safeGain, 0), 1) : 0
            let height = min(maxBarHeight, max(restingHeight, restingHeight + (maxBarHeight - restingHeight) * level))

            // Index 0 sits closest to the notch (low frequency); higher indices move outward toward the wing tip.
            let leftX = localNotchMinX - innerInset - leftBarWidth - CGFloat(index) * (leftBarWidth + gap)
            let rightX = localNotchMaxX + innerInset + CGFloat(index) * (rightBarWidth + gap)
            let y = centerY - height / 2

            let leftRect = CGRect(x: leftX, y: y, width: leftBarWidth, height: height)
            let rightRect = CGRect(x: rightX, y: y, width: rightBarWidth, height: height)

            guard isValidRect(leftRect), isValidRect(rightRect),
                  leftRect.minX >= 0, leftRect.maxX <= localNotchMinX,
                  rightRect.minX >= localNotchMaxX, rightRect.maxX <= bounds.width,
                  bounds.contains(leftRect), bounds.contains(rightRect)
            else {
                return IslandCompactBars(left: [], right: [])
            }

            leftBars.append(leftRect)
            rightBars.append(rightRect)
        }

        return IslandCompactBars(left: leftBars, right: rightBars)
    }

    private static func isValidRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }
}
