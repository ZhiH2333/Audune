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

    func testSpectrumPresetApplyClearsHeldPeaksOnStudioAndIsland() throws {
        let spike = ProcessTapSpike()
        let studio = StudioWindowController(spike: spike, defaults: defaults)
        defer { studio.shutdown() }
        let island = IslandWindowController(spike: spike, defaults: defaults, allowsOrderFront: false)
        defer { island.shutdown() }

        studio.model.prefs.mode = .spectrum
        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.dynamic))
        island.updateSharedVisuals(studio.currentPreferences())
        XCTAssertTrue(studio.currentPreferences().spectrum.peakHold)

        let staleLevels = Array(repeating: Float(0.4), count: 32)
        let stalePeaks = Array(repeating: Float(1), count: 32)
        studio.seedSpectrumDynamicsForTests(levels: staleLevels, peaks: stalePeaks)
        island.seedExpandedSpectrumDynamicsForTests(levels: staleLevels, peaks: stalePeaks)
        XCTAssertEqual(studio.model.spectrumPeaks, stalePeaks)
        XCTAssertEqual(island.model.expandedPeaks, stalePeaks)

        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.dense))
        island.updateSharedVisuals(studio.currentPreferences())
        XCTAssertEqual(studio.currentPreferences().spectrum, VisualPresetCatalog.dense.spectrum)
        XCTAssertTrue(studio.model.spectrumPeaks.allSatisfy { $0 == 0 })
        XCTAssertTrue(island.model.expandedPeaks.allSatisfy { $0 == 0 })
        XCTAssertEqual(studio.model.studioSpectrum.count, 64)
        XCTAssertEqual(island.model.spectrum.barCount, 64)

        studio.seedSpectrumDynamicsForTests(levels: Array(repeating: 0.3, count: 64), peaks: Array(repeating: 0.9, count: 64))
        // Dense has peakHold off, so published peaks stay empty even if dynamics were seeded.
        XCTAssertTrue(studio.model.spectrumPeaks.isEmpty)

        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.clean))
        island.updateSharedVisuals(studio.currentPreferences())
        XCTAssertFalse(studio.currentPreferences().spectrum.peakHold)
        XCTAssertTrue(studio.model.spectrumPeaks.isEmpty)
        XCTAssertTrue(island.model.expandedPeaks.isEmpty)

        var customSpectrum = SpectrumPreferences.standard
        customSpectrum.amplitude = 2.4
        customSpectrum.sensitivity = 0.9
        customSpectrum.peakHold = true
        customSpectrum.peakHoldSeconds = 0.5
        customSpectrum.barCount = 48
        var library = VisualPresetCatalog.restoring(from: defaults)
        let custom = try library.addCustom(
            name: "Hot Peaks",
            mode: .spectrum,
            spectrum: customSpectrum,
            to: defaults
        ).get()

        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.dynamic))
        island.updateSharedVisuals(studio.currentPreferences())
        studio.seedSpectrumDynamicsForTests(levels: Array(repeating: 0.5, count: 32), peaks: Array(repeating: 1, count: 32))
        island.seedExpandedSpectrumDynamicsForTests(levels: Array(repeating: 0.5, count: 32), peaks: Array(repeating: 1, count: 32))

        XCTAssertTrue(studio.applyVisualPreset(custom))
        island.updateSharedVisuals(studio.currentPreferences())
        XCTAssertEqual(studio.currentPreferences().spectrum.amplitude, 2.4, accuracy: 0.000_1)
        XCTAssertEqual(studio.currentPreferences().spectrum.barCount, 48)
        XCTAssertTrue(studio.currentPreferences().spectrum.peakHold)
        XCTAssertTrue(studio.model.spectrumPeaks.allSatisfy { $0 == 0 })
        XCTAssertTrue(island.model.expandedPeaks.allSatisfy { $0 == 0 })
        XCTAssertEqual(spike.phase, .idle)

        // Waveform preset must not wipe spectrum peaks when spectrum prefs are unchanged.
        studio.seedSpectrumDynamicsForTests(
            levels: Array(repeating: 0.2, count: 48),
            peaks: Array(repeating: 0.8, count: 48)
        )
        let peaksBeforeWaveform = studio.model.spectrumPeaks
        XCTAssertEqual(peaksBeforeWaveform, Array(repeating: Float(0.8), count: 48))
        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.fineLine))
        XCTAssertEqual(studio.model.spectrumPeaks, peaksBeforeWaveform)
        XCTAssertEqual(studio.currentPreferences().spectrum.barCount, 48)
    }
}
