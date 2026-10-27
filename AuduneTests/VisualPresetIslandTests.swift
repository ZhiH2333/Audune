import XCTest
@testable import Audune

@MainActor
final class VisualPresetIslandTests: XCTestCase {
    private let suite = "AuduneVisualPresetIslandTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testStudioAndIslandReadTheSameModeSettings() {
        var stored = StudioPreferences.standard
        stored.spectrum = VisualPresetCatalog.dense.spectrum ?? .standard
        stored.appearance.opacity = 0.61
        stored.save(to: defaults)

        let spike = ProcessTapSpike()
        let studio = StudioWindowController(spike: spike, defaults: defaults)
        defer { studio.shutdown() }
        let island = IslandWindowController(spike: spike, defaults: defaults, allowsOrderFront: false)
        defer { island.shutdown() }

        XCTAssertEqual(island.model.spectrum, studio.currentPreferences().spectrum)
        XCTAssertEqual(island.model.waveform, studio.currentPreferences().waveform)
        XCTAssertEqual(island.model.orbit, studio.currentPreferences().orbit)
        XCTAssertEqual(island.model.appearance.opacity, 0.61, accuracy: 0.000_1)
        XCTAssertEqual(spike.phase, .idle)

        let studioMode = studio.currentPreferences().mode
        let islandMode = island.model.prefs.mode
        let compactBars = island.model.prefs.compactBarCountPerSide
        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.dense))
        island.updateSharedVisuals(studio.currentPreferences())

        XCTAssertEqual(island.model.spectrum, studio.currentPreferences().spectrum)
        XCTAssertEqual(island.model.spectrum.barCount, 64)
        XCTAssertEqual(island.model.spectrum.colorMode, .frequency)
        XCTAssertEqual(studio.currentPreferences().mode, studioMode)
        XCTAssertEqual(island.model.prefs.mode, islandMode)
        XCTAssertEqual(island.model.prefs.compactBarCountPerSide, compactBars)
        XCTAssertEqual(island.model.waveform, .standard)
        XCTAssertEqual(spike.phase, .idle)

        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.fineLine))
        island.updateSharedVisuals(studio.currentPreferences())
        XCTAssertEqual(island.model.waveform, VisualPresetCatalog.fineLine.waveform)
        XCTAssertEqual(island.model.waveform.style, .line)
        XCTAssertEqual(island.model.waveform.amplitude, 0.45, accuracy: 0.000_1)
        XCTAssertEqual(island.model.spectrum, VisualPresetCatalog.dense.spectrum)
        XCTAssertEqual(studio.currentPreferences().orbit, .standard)
        XCTAssertEqual(island.model.orbit, .standard)

        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.halo))
        island.updateSharedVisuals(studio.currentPreferences())
        XCTAssertEqual(island.model.orbit.layerMode, .dualBand)
        XCTAssertEqual(island.model.orbit.pulseStrength, 0.12, accuracy: 0.000_1)
        XCTAssertEqual(studio.currentPreferences().mode, studioMode)
        XCTAssertEqual(island.model.prefs.mode, islandMode)
        XCTAssertEqual(spike.phase, .idle)
    }
}
