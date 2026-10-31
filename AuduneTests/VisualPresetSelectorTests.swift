import AppKit
import XCTest
@testable import Audune

final class VisualPresetSelectorTests: XCTestCase {
    private let suite = "AuduneVisualPresetSelectorTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testStatusTextFollowsApplyAndEdits() throws {
        var library = VisualPresetCatalog.restoring(from: defaults)
        XCTAssertEqual(library.match(in: .standard, mode: .spectrum).statusText, "Unsaved settings")

        var prefs = try library.apply(VisualPresetCatalog.clean, to: .standard, in: defaults).get()
        XCTAssertEqual(library.match(in: prefs, mode: .spectrum).statusText, "Clean")
        prefs.appearance.opacity = 0.5
        XCTAssertEqual(library.match(in: prefs, mode: .spectrum).statusText, "Clean")
        prefs.spectrum.barGap = 0
        XCTAssertEqual(library.match(in: prefs, mode: .spectrum).statusText, "Clean (Modified)")

        var waveform = WaveformPreferences.standard
        waveform.density = 32
        waveform.style = .softFill
        let custom = try library.addCustom(name: "Night", mode: .waveform, waveform: waveform, to: defaults).get()
        let restored = try library.apply(custom, to: prefs, in: defaults).get()
        XCTAssertEqual(library.match(in: restored, mode: .waveform).statusText, "Night")
        XCTAssertEqual(library.match(in: restored, mode: .spectrum).statusText, "Clean (Modified)")
    }

    @MainActor
    func testControllerAppliesBuiltInsWithoutStartingCaptureOrChangingTheSettingsWindow() {
        let spike = ProcessTapSpike()
        let studio = StudioWindowController(spike: spike, defaults: defaults)
        defer { studio.shutdown() }
        let island = IslandWindowController(spike: spike, defaults: defaults, allowsOrderFront: false)
        defer { island.shutdown() }
        let settings = SettingsWindowController(studio: studio, island: island)
        defer { settings.shutdown() }

        for preset in VisualPresetCatalog.all {
            studio.model.prefs = .standard
            XCTAssertTrue(studio.applyVisualPreset(preset))
            let current = studio.currentPreferences()
            switch preset.mode {
            case .spectrum:
                XCTAssertEqual(current.spectrum, preset.spectrum)
                XCTAssertEqual(current.waveform, .standard)
                XCTAssertEqual(current.orbit, .standard)
            case .waveform:
                XCTAssertEqual(current.waveform, preset.waveform)
                XCTAssertEqual(current.spectrum, .standard)
                XCTAssertEqual(current.orbit, .standard)
            case .orbit:
                XCTAssertEqual(current.orbit, preset.orbit)
                XCTAssertEqual(current.spectrum, .standard)
                XCTAssertEqual(current.waveform, .standard)
            }
            XCTAssertEqual(current.appearance, .standard)
            XCTAssertEqual(current.mode, .spectrum)
            XCTAssertEqual(current.windowMode, .onTop)
            XCTAssertEqual(spike.phase, .idle)
        }

        XCTAssertTrue(settings.window.styleMask.contains(.titled))
        XCTAssertTrue(settings.window.styleMask.contains(.closable))
        XCTAssertTrue(settings.window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(settings.window.styleMask.contains(.resizable))
        XCTAssertEqual(settings.window.level, .normal)
        XCTAssertEqual(settings.window.collectionBehavior, [])
        XCTAssertTrue(settings.window.titlebarAppearsTransparent)
        XCTAssertEqual(settings.window.titleVisibility, .hidden)
        XCTAssertEqual(SettingsWindowController.initialSize, CGSize(width: 760, height: 600))
        XCTAssertEqual(SettingsWindowController.minimumSize, CGSize(width: 640, height: 480))
    }
}
