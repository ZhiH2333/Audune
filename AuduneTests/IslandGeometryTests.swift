import CoreGraphics
import XCTest
@testable import Audune

final class IslandGeometryTests: XCTestCase {
    private func notchedMacBookScreen(
        id: String = "display-1",
        name: String = "Built-in Liquid Retina XDR Display",
        origin: CGPoint = .zero,
        size: CGSize = CGSize(width: 1512, height: 982),
        notchWidth: CGFloat = 184,
        notchHeight: CGFloat = 32
    ) -> IslandScreenDescriptor {
        let frame = CGRect(origin: origin, size: size)
        let leftWidth = (size.width - notchWidth) / 2
        let rightWidth = size.width - leftWidth - notchWidth
        let topY = frame.maxY - notchHeight
        return IslandScreenDescriptor(
            id: id,
            localizedName: name,
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: size.width, height: size.height - notchHeight),
            safeAreaTop: notchHeight,
            auxiliaryTopLeft: CGRect(x: frame.minX, y: topY, width: leftWidth, height: notchHeight),
            auxiliaryTopRight: CGRect(x: frame.minX + leftWidth + notchWidth, y: topY, width: rightWidth, height: notchHeight),
            backingScaleFactor: 2
        )
    }

    private func externalNonNotchedScreen(
        id: String = "display-2",
        name: String = "Studio Display",
        origin: CGPoint = CGPoint(x: 1512, y: 0),
        size: CGSize = CGSize(width: 2560, height: 1440)
    ) -> IslandScreenDescriptor {
        let frame = CGRect(origin: origin, size: size)
        return IslandScreenDescriptor(
            id: id,
            localizedName: name,
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: size.width, height: size.height - 24),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            backingScaleFactor: 2
        )
    }

    func testValidNotchedDisplayDerivesAccurateNotchCompactAndExpandedFrames() throws {
        let screen = notchedMacBookScreen()
        let geometry = try IslandGeometry.analyze(screen: screen).get()

        XCTAssertEqual(geometry.screenID, "display-1")
        XCTAssertEqual(geometry.notchRect, CGRect(x: 664, y: 950, width: 184, height: 32))
        XCTAssertEqual(geometry.compactFrame.maxY, screen.frame.maxY)
        XCTAssertEqual(geometry.compactFrame.height, 32)
        XCTAssertEqual(geometry.compactFrame.midX, geometry.notchRect.midX, accuracy: 0.001)
        XCTAssertEqual(geometry.leftWingWidth, IslandGeometry.defaultCompactWingWidth, accuracy: 0.001)
        XCTAssertEqual(geometry.rightWingWidth, IslandGeometry.defaultCompactWingWidth, accuracy: 0.001)

        XCTAssertEqual(geometry.expandedFrame.maxY, screen.frame.maxY)
        XCTAssertEqual(geometry.expandedFrame.midX, geometry.notchRect.midX, accuracy: 0.001)
        XCTAssertTrue(geometry.expandedFrame.contains(geometry.compactFrame))
        XCTAssertTrue(screen.frame.contains(geometry.expandedFrame))
    }

    func testExpandedPlayerFrameIsLargeRegardlessOfNowPlayingSwitch() throws {
        let screen = notchedMacBookScreen() // notch ~184 pt, matching 14" class
        let geometry = try IslandGeometry.analyze(screen: screen).get()
        let withNowPlaying = geometry.expandedFrame(nowPlayingEnabled: true)
        let without = geometry.expandedFrame(nowPlayingEnabled: false)
        let player = geometry.expandedPlayerFrame()

        XCTAssertEqual(withNowPlaying, without)
        XCTAssertEqual(withNowPlaying, player)
        XCTAssertEqual(player.maxY, geometry.expandedFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(
            player.height,
            geometry.expandedFrame.height + IslandGeometry.nowPlayingExpandedExtraHeight,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(player.width, IslandGeometry.nowPlayingMinExpandedWidth - 0.5)
        XCTAssertGreaterThan(player.width, geometry.expandedFrame.width)
        let sides = geometry.expandedSideClearance(in: player)
        XCTAssertGreaterThanOrEqual(sides.left, IslandGeometry.nowPlayingMinSideClearance - 1)
        XCTAssertGreaterThanOrEqual(sides.right, IslandGeometry.nowPlayingMinSideClearance - 1)
        XCTAssertEqual(geometry.compactFrame, try IslandGeometry.analyze(screen: screen).get().compactFrame)
        XCTAssertTrue(player.contains(geometry.compactFrame))
        XCTAssertTrue(screen.frame.contains(player))
    }

    func testSafeAreaTopAloneWithoutAuxiliaryAreasIsRejected() {
        var screen = notchedMacBookScreen()
        screen.auxiliaryTopLeft = nil
        screen.auxiliaryTopRight = nil

        XCTAssertEqual(IslandGeometry.analyze(screen: screen), .failure(.invalidGeometry))

        var missingRight = notchedMacBookScreen()
        missingRight.auxiliaryTopRight = nil
        XCTAssertEqual(IslandGeometry.analyze(screen: missingRight), .failure(.invalidGeometry))
    }

    func testNonNotchedDisplayReportsNoNotch() {
        let external = externalNonNotchedScreen()
        XCTAssertEqual(IslandGeometry.analyze(screen: external), .failure(.noNotch))
    }

    func testOverlappingOffCenterOrOutOfBoundsAuxiliaryAreasAreRejected() {
        var overlapping = notchedMacBookScreen()
        overlapping.auxiliaryTopLeft = CGRect(x: 0, y: 950, width: 900, height: 32)
        overlapping.auxiliaryTopRight = CGRect(x: 800, y: 950, width: 712, height: 32)
        XCTAssertEqual(IslandGeometry.analyze(screen: overlapping), .failure(.invalidGeometry))

        var offCenter = notchedMacBookScreen()
        offCenter.auxiliaryTopLeft = CGRect(x: 0, y: 950, width: 200, height: 32)
        offCenter.auxiliaryTopRight = CGRect(x: 380, y: 950, width: 1132, height: 32)
        XCTAssertEqual(IslandGeometry.analyze(screen: offCenter), .failure(.invalidGeometry))

        var outOfBounds = notchedMacBookScreen()
        outOfBounds.auxiliaryTopRight = CGRect(x: 848, y: 950, width: 900, height: 32)
        XCTAssertEqual(IslandGeometry.analyze(screen: outOfBounds), .failure(.invalidGeometry))

        var detachedFromTop = notchedMacBookScreen()
        detachedFromTop.auxiliaryTopLeft = CGRect(x: 0, y: 900, width: 664, height: 32)
        XCTAssertEqual(IslandGeometry.analyze(screen: detachedFromTop), .failure(.invalidGeometry))
    }

    func testNonFiniteOrExtremeDimensionsAreRejected() {
        var nanScreen = notchedMacBookScreen()
        nanScreen.safeAreaTop = .nan
        XCTAssertEqual(IslandGeometry.analyze(screen: nanScreen), .failure(.invalidGeometry))

        var hugeSafeArea = notchedMacBookScreen()
        hugeSafeArea.safeAreaTop = 200
        XCTAssertEqual(IslandGeometry.analyze(screen: hugeSafeArea), .failure(.invalidGeometry))
    }

    func testMultiDisplaySelectionPrefersNotchedDisplayAndFallsBackSafely() {
        let external = externalNonNotchedScreen(id: "ext-1")
        let builtIn = notchedMacBookScreen(id: "builtin-1", origin: CGPoint(x: -1512, y: -200))
        let secondNotched = notchedMacBookScreen(id: "builtin-2", origin: CGPoint(x: 0, y: 1440), size: CGSize(width: 1728, height: 1117), notchWidth: 180, notchHeight: 38)

        let autoResolution = IslandGeometry.selectScreen(from: [external, builtIn], target: .automatic)
        XCTAssertEqual(autoResolution.geometry?.screenID, "builtin-1")
        if case .supported(_, let usedFallback) = autoResolution {
            XCTAssertFalse(usedFallback)
        } else {
            XCTFail("Expected supported screen")
        }

        let explicitMatch = IslandGeometry.selectScreen(from: [builtIn, secondNotched], target: .screenID("builtin-2"))
        XCTAssertEqual(explicitMatch.geometry?.screenID, "builtin-2")

        let fallbackWhenMissing = IslandGeometry.selectScreen(from: [external, builtIn], target: .screenID("disconnected-id"))
        XCTAssertEqual(fallbackWhenMissing.geometry?.screenID, "builtin-1")
        if case .supported(_, let usedFallback) = fallbackWhenMissing {
            XCTAssertTrue(usedFallback)
        } else {
            XCTFail("Expected fallback to remaining notched screen")
        }

        let noNotchAtAll = IslandGeometry.selectScreen(from: [external], target: .automatic)
        XCTAssertEqual(noNotchAtAll, .unsupported(.noNotch))

        let emptyScreens = IslandGeometry.selectScreen(from: [], target: .automatic)
        XCTAssertEqual(emptyScreens, .unsupported(.noScreens))
    }

    func testCompactBarsAreSymmetricAndNeverOverlapTheNotch() throws {
        let geometry = try IslandGeometry.analyze(screen: notchedMacBookScreen()).get()
        let levels: [Float] = [0.9, 0.7, 0.5, 0.3, 0.1]
        let bars = IslandGeometry.compactBars(
            levels: levels,
            notchRect: geometry.notchRect,
            compactFrame: geometry.compactFrame,
            barsPerSide: 5,
            amplitude: 1,
            drawsActiveBars: true
        )

        XCTAssertEqual(bars.left.count, 5)
        XCTAssertEqual(bars.right.count, 5)

        let localNotch = geometry.localNotchRect(in: geometry.compactFrame)
        let localBounds = CGRect(origin: .zero, size: geometry.compactFrame.size)

        for index in 0..<5 {
            let leftBar = bars.left[index]
            let rightBar = bars.right[index]
            XCTAssertTrue(localBounds.contains(leftBar))
            XCTAssertTrue(localBounds.contains(rightBar))
            XCTAssertFalse(leftBar.intersects(localNotch))
            XCTAssertFalse(rightBar.intersects(localNotch))
            XCTAssertEqual(leftBar.height, rightBar.height, accuracy: 0.001)
            XCTAssertEqual(leftBar.width, rightBar.width, accuracy: 0.001)
            let leftDistanceFromNotch = localNotch.minX - leftBar.maxX
            let rightDistanceFromNotch = rightBar.minX - localNotch.maxX
            XCTAssertEqual(leftDistanceFromNotch, rightDistanceFromNotch, accuracy: 0.001)
        }

        XCTAssertGreaterThan(bars.left[0].height, bars.left[4].height)
    }

    func testCompactBarsSettleToBaselineOnSilenceAndSanitizeNonFiniteInput() throws {
        let geometry = try IslandGeometry.analyze(screen: notchedMacBookScreen()).get()
        let silentBars = IslandGeometry.compactBars(
            levels: [.nan, .infinity, -1, 5, 0.8],
            notchRect: geometry.notchRect,
            compactFrame: geometry.compactFrame,
            barsPerSide: 5,
            amplitude: 1,
            drawsActiveBars: false
        )

        XCTAssertEqual(silentBars.left.count, 5)
        XCTAssertEqual(silentBars.right.count, 5)
        for bar in silentBars.left + silentBars.right {
            XCTAssertEqual(bar.height, 3, accuracy: 0.001)
        }

        let sanitizedActive = IslandGeometry.compactBars(
            levels: [.nan, .infinity, -3, 2, 0.5],
            notchRect: geometry.notchRect,
            compactFrame: geometry.compactFrame,
            barsPerSide: 5,
            amplitude: .nan,
            drawsActiveBars: true
        )
        XCTAssertEqual(sanitizedActive.left.count, 5)
        for bar in sanitizedActive.left + sanitizedActive.right {
            XCTAssertTrue(bar.origin.x.isFinite && bar.origin.y.isFinite)
            XCTAssertGreaterThanOrEqual(bar.height, 3)
            XCTAssertLessThanOrEqual(bar.height, geometry.compactFrame.height)
        }
    }
}
