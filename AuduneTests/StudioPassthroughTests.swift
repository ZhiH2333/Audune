import AppKit
import CoreGraphics
import XCTest
@testable import Audune

final class StudioPassthroughTests: XCTestCase {
    func testInteractionFrameSitsOnTheBottomAndLeavesTheCanvasOpen() {
        let visual = CGRect(x: 100, y: 80, width: 640, height: 400)
        let controls = StudioPassthroughLayout.interactionFrame(visual: visual, contentSize: CGSize(width: 220, height: 36))
        let grip = StudioPassthroughLayout.interactionFrame(
            visual: visual,
            contentSize: CGSize(width: StudioChrome.gripWidth, height: StudioChrome.gripHeight)
        )
        let edges = StudioPassthroughLayout.edgeBands(in: visual).map(\.frame)

        XCTAssertTrue(visual.contains(controls))
        XCTAssertTrue(controls.contains(CGPoint(x: controls.midX, y: controls.midY)))
        XCTAssertFalse(controls.contains(CGPoint(x: visual.midX, y: visual.midY)))
        XCTAssertFalse(grip.contains(CGPoint(x: visual.midX, y: visual.midY)))
        XCTAssertFalse(grip.contains(CGPoint(x: controls.maxX - 4, y: controls.midY)))
        XCTAssertTrue(StudioPassthroughLayout.canvasCenterIsOpen(visual: visual, interaction: controls, edges: edges))
        XCTAssertTrue(StudioPassthroughLayout.canvasCenterIsOpen(visual: visual, interaction: grip, edges: edges))
        XCTAssertEqual(edges.count, 4)
        XCTAssertTrue(edges.contains { $0.minX == visual.minX && $0.width == 6 })
    }

    func testResizeKeepsTheMinimumAndTheAnchoredEdge() {
        let start = CGRect(x: 10, y: 20, width: 400, height: 300)
        let shrunk = StudioWindowResize.frame(
            start: start,
            startMouse: CGPoint(x: 10, y: 20),
            mouse: CGPoint(x: 80, y: 40),
            edge: .minX,
            minimum: StudioFrame.minimumSize
        )
        XCTAssertEqual(shrunk.maxX, start.maxX, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(shrunk.width, StudioFrame.minimumSize.width)

        let grown = StudioWindowResize.frame(
            start: start,
            startMouse: CGPoint(x: 0, y: 0),
            mouse: CGPoint(x: 30, y: -10),
            edge: .maxY,
            minimum: StudioFrame.minimumSize
        )
        XCTAssertEqual(grown.origin.x, start.origin.x, accuracy: 0.001)
        XCTAssertEqual(grown.height, 290, accuracy: 0.001)
        XCTAssertEqual(
            StudioWindowResize.frame(
                start: start,
                startMouse: CGPoint(x: CGFloat.nan, y: 0),
                mouse: CGPoint(x: 1, y: 1),
                edge: .maxX,
                minimum: StudioFrame.minimumSize
            ),
            start
        )
    }

    func testResizeHonorsMaximumAndAnchoredEdge() {
        let start = CGRect(x: 10, y: 20, width: 400, height: 300)
        let maximum = CGSize(width: 500, height: 360)
        let grown = StudioWindowResize.frame(
            start: start,
            startMouse: CGPoint(x: 410, y: 20),
            mouse: CGPoint(x: 900, y: 20),
            edge: .maxX,
            minimum: StudioFrame.minimumSize,
            maximum: maximum
        )
        XCTAssertEqual(grown.width, 500, accuracy: 0.001)
        XCTAssertEqual(grown.origin.x, start.origin.x, accuracy: 0.001)

        let fromMinX = StudioWindowResize.frame(
            start: start,
            startMouse: CGPoint(x: 10, y: 20),
            mouse: CGPoint(x: -400, y: 20),
            edge: .minX,
            minimum: StudioFrame.minimumSize,
            maximum: maximum
        )
        XCTAssertEqual(fromMinX.width, 500, accuracy: 0.001)
        XCTAssertEqual(fromMinX.maxX, start.maxX, accuracy: 0.001)
    }

    func testMissingPassthroughPreferenceStaysOff() {
        let defaults = UserDefaults(suiteName: "AudunePassthroughDefaults")!
        defaults.removePersistentDomain(forName: "AudunePassthroughDefaults")
        let loaded = StudioPreferences.load(from: defaults)
        XCTAssertTrue(loaded.window.passesMouseThrough)
        var changed = loaded
        changed.window.passesMouseThrough = true
        changed.save(to: defaults)
        XCTAssertTrue(StudioPreferences.load(from: defaults).window.passesMouseThrough)
        defaults.removePersistentDomain(forName: "AudunePassthroughDefaults")
    }

    @MainActor
    func testPassthroughOffKeepsTheSinglePanel() {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        let inspection = controller.inspectPassthroughForTests()
        XCTAssertTrue(inspection.visualIgnoresMouseEvents)
        XCTAssertFalse(inspection.interactionVisible)
        XCTAssertTrue(controller.inspectWindowForTests().ignoresMouseEvents)
    }

    @MainActor
    func testPassthroughUsesASeparateControlPanelAndLeavesTheCanvasOpen() throws {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        let visual = CGRect(x: 180, y: 160, width: 640, height: 400)
        controller.model.prefs.window.passesMouseThrough = true
        controller.model.chromeVisible = true
        controller.placeForTests(visual)
        controller.applyWindowPreferences()

        let inspection = controller.inspectPassthroughForTests()
        XCTAssertTrue(inspection.visualIgnoresMouseEvents)
        XCTAssertFalse(inspection.interactionIgnoresMouseEvents)
        XCTAssertEqual(inspection.interactionLevel, controller.inspectWindowForTests().level)
        XCTAssertEqual(inspection.interactionCollectionBehavior, controller.inspectWindowForTests().collectionBehavior)
        XCTAssertFalse(inspection.interactionFrame.contains(CGPoint(x: visual.midX, y: visual.midY)))
        XCTAssertEqual(inspection.edgeFrames.count, 4)
        XCTAssertTrue(StudioPassthroughLayout.canvasCenterIsOpen(
            visual: visual,
            interaction: inspection.interactionFrame,
            edges: inspection.edgeFrames
        ))

        controller.setChromeVisible(false)
        let hidden = controller.inspectPassthroughForTests()
        XCTAssertFalse(hidden.interactionFrame.contains(CGPoint(x: visual.midX, y: visual.midY)))
        XCTAssertLessThanOrEqual(hidden.interactionFrame.width, StudioChrome.gripWidth + 24)
        XCTAssertLessThanOrEqual(hidden.interactionFrame.height, StudioChrome.gripHeight + 24)

        controller.hide()
        XCTAssertFalse(controller.inspectPassthroughForTests().interactionVisible)
        XCTAssertFalse(controller.isVisible)

        controller.model.prefs.window.passesMouseThrough = false
        for mode in [StudioWindowMode.asWindow, .onDesktop, .onTop] {
            controller.setWindowMode(mode)
            controller.show()
            let restored = controller.inspectPassthroughForTests()
            let current = controller.inspectWindowForTests().frame
            XCTAssertTrue(restored.visualIgnoresMouseEvents)
            XCTAssertEqual(restored.interactionLevel, StudioWindowBehavior.level(for: mode))
            XCTAssertFalse(restored.interactionFrame.contains(CGPoint(x: current.midX, y: current.midY)))
            XCTAssertTrue(StudioPassthroughLayout.canvasCenterIsOpen(
                visual: controller.inspectWindowForTests().frame,
                interaction: restored.interactionFrame,
                edges: restored.edgeFrames
            ))
        }
    }

    @MainActor
    func testCanvasPointResolvesToTheWindowUnderTheVisualPanel() throws {
        let controller = StudioWindowController(spike: ProcessTapSpike())
        defer { controller.shutdown() }
        controller.model.prefs.window.passesMouseThrough = true
        controller.model.chromeVisible = false
        controller.applyWindowPreferences()
        controller.show()
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visual = CGRect(
            x: visible.midX - 320,
            y: visible.midY - 200,
            width: min(640, visible.width),
            height: min(400, visible.height)
        )
        controller.placeForTests(visual)

        let probe = NSWindow(
            contentRect: visual,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { probe.orderOut(nil) }
        probe.isReleasedWhenClosed = false
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        probe.level = level
        probe.collectionBehavior = [.canJoinAllSpaces]
        probe.ignoresMouseEvents = false
        probe.contentView = NSView(frame: NSRect(origin: .zero, size: visual.size))
        probe.orderFrontRegardless()
        controller.setLevelForTests(level)
        controller.stackAboveForTests()

        let center = CGPoint(x: visual.midX, y: visual.midY)
        var below = 0
        var hits: [Int] = []
        for _ in 0..<24 {
            let number = NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: below)
            if number == 0 || hits.contains(number) { break }
            hits.append(number)
            below = number
        }
        if hits.isEmpty {
            throw XCTSkip("The window server did not resolve a window at the canvas center.")
        }
        let interaction = controller.inspectPassthroughForTests()
        XCTAssertFalse(interaction.interactionFrame.contains(center), "\(interaction.interactionFrame)")
        let visualNumber = controller.inspectWindowNumberForTests()
        let interactionNumber = controller.inspectInteractionWindowNumberForTests()
        XCTAssertFalse(hits.contains(visualNumber), "The visual panel was still a click target: \(hits)")
        XCTAssertFalse(hits.contains(interactionNumber), "The control panel covered the canvas: \(hits)")
        let lowerWindows = NSApp.windows.filter {
            $0.frame.contains(center) && $0.windowNumber != visualNumber && $0.windowNumber != interactionNumber && $0.ignoresMouseEvents == false
        }
        XCTAssertTrue(
            hits.contains(probe.windowNumber) || lowerWindows.contains { hits.contains($0.windowNumber) },
            "No lower window received the canvas point. hits \(hits) lower \(lowerWindows.map { "\($0.windowNumber) \($0.title)" })"
        )
    }
}
