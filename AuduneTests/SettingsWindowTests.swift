import AppKit
import XCTest
@testable import Audune

/// Checks window configuration only. Whether the window appears and stays independent of Studio
/// on a real desktop is recorded in `docs/MANUAL_TESTS.md`.
final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testSettingsWindowIsAnOrdinaryResizableWindow() {
        let studio = StudioWindowController(spike: ProcessTapSpike())
        defer { studio.shutdown() }
        let settings = SettingsWindowController(studio: studio)
        let window = settings.window
        defer { settings.shutdown() }

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(window.collectionBehavior, [])
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.contentMinSize, SettingsWindowController.minimumSize)
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.width, SettingsWindowController.minimumSize.width)
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.height, SettingsWindowController.minimumSize.height)
    }

    @MainActor
    func testSettingsDoesNotInheritStudioWindowMode() {
        let studio = StudioWindowController(spike: ProcessTapSpike())
        defer { studio.shutdown() }
        let settings = SettingsWindowController(studio: studio)
        defer { settings.shutdown() }

        for mode in StudioWindowMode.allCases {
            studio.setWindowMode(mode)
            XCTAssertEqual(settings.window.level, .normal)
            XCTAssertEqual(settings.window.collectionBehavior, [])
        }
        studio.setWindowMode(.onTop)
    }

    @MainActor
    func testHidingStudioKeepsTheSettingsWindowObject() {
        let studio = StudioWindowController(spike: ProcessTapSpike())
        defer { studio.shutdown() }
        let settings = SettingsWindowController(studio: studio)
        defer { settings.shutdown() }
        let window = settings.window

        studio.hide()

        XCTAssertTrue(settings.window === window)
        XCTAssertFalse(studio.model.isShown)
    }

    @MainActor
    func testSettingsCategoriesMatchTheApprovedSidebar() {
        XCTAssertEqual(
            SettingsCategory.allCases.map(\.title),
            ["Startup", "Appearance", "Layout", "Spectrum", "Waveform", "Orbit", "Window", "Notch Island"]
        )
        XCTAssertEqual(SettingsWindowController.initialSize, CGSize(width: 760, height: 600))
    }

    @MainActor
    func testShowingSpecificCategorySelectsNotchIslandWithoutChangingWindowLevel() {
        let spike = ProcessTapSpike()
        let studio = StudioWindowController(spike: spike)
        defer { studio.shutdown() }
        let island = IslandWindowController(spike: spike, allowsOrderFront: false)
        defer { island.shutdown() }
        let settings = SettingsWindowController(studio: studio, island: island)
        defer { settings.shutdown() }

        studio.model.settingsCategory = .island
        XCTAssertEqual(studio.model.settingsCategory, .island)
        XCTAssertEqual(settings.window.level, .normal)
        XCTAssertEqual(spike.phase, .idle)
    }
}
