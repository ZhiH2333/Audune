import XCTest
@testable import Audune

final class VisualPresetApplyTests: XCTestCase {
    private let suite = "AuduneVisualPresetApplyTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testBuiltInsDifferFromEachOtherAndFromTheFactorySettings() throws {
        let catalog = VisualPresetCatalog.all
        XCTAssertEqual(catalog.count, 9)
        XCTAssertEqual(Set(catalog.map(\.id)).count, 9)
        XCTAssertTrue(catalog.allSatisfy { $0.kind == .builtIn && $0.hasMatchingPayload() })

        let clean = try XCTUnwrap(VisualPresetCatalog.clean.spectrum)
        let dense = try XCTUnwrap(VisualPresetCatalog.dense.spectrum)
        let dynamic = try XCTUnwrap(VisualPresetCatalog.dynamic.spectrum)
        XCTAssertEqual(clean.barCount, 24)
        XCTAssertEqual(clean.barGap, 4)
        XCTAssertEqual(clean.cornerRadius, 3)
        XCTAssertEqual(clean.smoothing, 0.55)
        XCTAssertEqual(clean.attackMs, 50)
        XCTAssertEqual(clean.releaseMs, 420)
        XCTAssertEqual(clean.amplitude, 0.85)
        XCTAssertFalse(clean.peakHold)
        XCTAssertEqual(dense.barCount, 64)
        XCTAssertEqual(dense.barGap, 0.5)
        XCTAssertEqual(dense.minHz, 30)
        XCTAssertEqual(dense.maxHz, 18_000)
        XCTAssertEqual(dense.sensitivity, 0.65)
        XCTAssertEqual(clean.colorMode, .solid)
        XCTAssertEqual(dense.colorMode, .frequency)
        XCTAssertTrue(dynamic.peakHold)
        XCTAssertEqual(dynamic.peakHoldSeconds, 0.4)
        XCTAssertTrue(dynamic.stroke)
        XCTAssertEqual(dynamic.attackMs, 8)
        XCTAssertEqual(dynamic.amplitude, 1.8)
        XCTAssertEqual(dynamic.colorMode, .amplitude)
        XCTAssertNotEqual(clean, dense)
        XCTAssertNotEqual(dense, dynamic)
        XCTAssertNotEqual(clean, dynamic)
        XCTAssertNotEqual(clean, .standard)
        XCTAssertNotEqual(dense, .standard)
        XCTAssertNotEqual(dynamic, .standard)

        let fine = try XCTUnwrap(VisualPresetCatalog.fineLine.waveform)
        let soft = try XCTUnwrap(VisualPresetCatalog.softFill.waveform)
        let mirror = try XCTUnwrap(VisualPresetCatalog.mirror.waveform)
        XCTAssertEqual(fine.style, .line)
        XCTAssertEqual(fine.lineWidth, 0.75)
        XCTAssertEqual(fine.density, 128)
        XCTAssertEqual(fine.amplitude, 0.45, accuracy: 0.000_1)
        XCTAssertEqual(fine.verticalRange, 0.65, accuracy: 0.000_1)
        XCTAssertEqual(soft.style, .softFill)
        XCTAssertEqual(soft.lineWidth, 1.5)
        XCTAssertEqual(soft.smoothing, 0.55, accuracy: 0.000_1)
        XCTAssertEqual(soft.fillStrength, 0.4, accuracy: 0.000_1)
        XCTAssertEqual(soft.verticalRange, 0.75, accuracy: 0.000_1)
        XCTAssertEqual(mirror.style, .mirror)
        XCTAssertEqual(mirror.density, 64)
        XCTAssertEqual(mirror.amplitude, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(mirror.verticalRange, 0.7, accuracy: 0.000_1)
        XCTAssertNil(fine.customColor)
        XCTAssertNil(soft.customColor)
        XCTAssertNil(mirror.customColor)
        XCTAssertNotEqual(fine, soft)
        XCTAssertNotEqual(soft, mirror)
        XCTAssertNotEqual(fine, .standard)
        XCTAssertNotEqual(mirror, .standard)

        let compact = try XCTUnwrap(VisualPresetCatalog.compact.orbit)
        let halo = try XCTUnwrap(VisualPresetCatalog.halo.orbit)
        let ring = try XCTUnwrap(VisualPresetCatalog.denseRing.orbit)
        XCTAssertEqual(compact.barCount, 24)
        XCTAssertEqual(compact.inner, 0.72)
        XCTAssertEqual(compact.outerScale, 0.7)
        XCTAssertEqual(halo.barCount, 32)
        XCTAssertTrue(halo.stroke)
        XCTAssertEqual(halo.lineWidth, 1)
        XCTAssertEqual(halo.outerScale, 0.98)
        XCTAssertEqual(halo.layerMode, .dualBand)
        XCTAssertEqual(halo.pulseStrength, 0.12, accuracy: 0.000_1)
        XCTAssertEqual(ring.barCount, 64)
        XCTAssertFalse(ring.mirrored)
        XCTAssertEqual(ring.gapDegrees, 0.5)
        XCTAssertEqual(ring.amplitude, 1.3)
        XCTAssertEqual(ring.pulseStrength, 0.2, accuracy: 0.000_1)
        XCTAssertEqual(compact.layerMode, .single)
        XCTAssertNotEqual(compact, halo)
        XCTAssertNotEqual(halo, ring)
        XCTAssertNotEqual(compact, .standard)
        XCTAssertNotEqual(ring, .standard)
    }

    func testApplyingOneModeLeavesTheOthersUntouched() throws {
        var library = VisualPresetCatalog.restoring(from: defaults)
        var prefs = StudioPreferences.standard
        prefs.mode = .waveform
        prefs.windowMode = .onDesktop
        prefs.appearance.opacity = 0.4
        prefs.waveform.density = 32
        prefs.orbit.barCount = 16

        let spectrum = try library.apply(VisualPresetCatalog.dense, to: prefs, in: defaults).get()
        XCTAssertEqual(spectrum.spectrum, VisualPresetCatalog.dense.spectrum)
        XCTAssertEqual(spectrum.waveform.density, 32)
        XCTAssertEqual(spectrum.orbit.barCount, 16)
        XCTAssertEqual(spectrum.appearance.opacity, 0.4)
        XCTAssertEqual(spectrum.windowMode, .onDesktop)
        XCTAssertEqual(spectrum.mode, .waveform)
        XCTAssertEqual(library.appliedID(for: .spectrum), VisualPresetCatalog.dense.id)
        XCTAssertNil(library.appliedID(for: .waveform))

        let waveform = try library.apply(VisualPresetCatalog.fineLine, to: spectrum, in: defaults).get()
        XCTAssertEqual(waveform.waveform, VisualPresetCatalog.fineLine.waveform)
        XCTAssertEqual(waveform.spectrum, VisualPresetCatalog.dense.spectrum)
        XCTAssertEqual(waveform.orbit.barCount, 16)
        XCTAssertEqual(waveform.appearance.opacity, 0.4)

        let orbit = try library.apply(VisualPresetCatalog.halo, to: waveform, in: defaults).get()
        XCTAssertEqual(orbit.orbit, VisualPresetCatalog.halo.orbit)
        XCTAssertEqual(orbit.spectrum, VisualPresetCatalog.dense.spectrum)
        XCTAssertEqual(orbit.waveform, VisualPresetCatalog.fineLine.waveform)
        XCTAssertEqual(orbit.mode, .waveform)
        XCTAssertEqual(VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all).appliedID(for: .orbit), VisualPresetCatalog.halo.id)
    }

    func testCustomSnapshotRestoresAndEditsMarkOnlyThatMode() throws {
        var library = VisualPresetCatalog.restoring(from: defaults)
        var saved = WaveformPreferences.standard
        saved.style = .line
        saved.density = 128
        saved.lineWidth = 3
        saved.customColor = StudioColor(red: 0.2, green: 0.3, blue: 0.4)
        let custom = try library.addCustom(name: "Mine", mode: .waveform, waveform: saved, to: defaults).get()

        var prefs = StudioPreferences.standard
        prefs.waveform = .standard
        prefs.spectrum.barCount = 64
        let restored = try library.apply(custom, to: prefs, in: defaults).get()
        XCTAssertEqual(restored.waveform, saved.clamped())
        XCTAssertEqual(restored.spectrum.barCount, 64)
        XCTAssertEqual(restored.orbit, .standard)
        XCTAssertEqual(library.match(in: restored, mode: .waveform), .applied(custom))

        var drifted = restored
        drifted.appearance.color = StudioAccent.sea.color
        drifted.appearance.opacity = 0.55
        XCTAssertEqual(library.match(in: drifted, mode: .waveform), .applied(custom))
        drifted.waveform.amplitude = 2
        XCTAssertEqual(library.match(in: drifted, mode: .waveform), .modified(custom))
    }

    func testDuplicateCopiesABuiltInWithoutChangingIt() throws {
        var library = VisualPresetCatalog.restoring(from: defaults)
        let original = VisualPresetCatalog.clean
        let copy = try library.duplicate(id: original.id, to: defaults).get()
        let again = try library.duplicate(id: original.id, to: defaults).get()

        XCTAssertEqual(VisualPresetCatalog.clean, original)
        XCTAssertEqual(library.builtIns.first { $0.id == original.id }, original)
        XCTAssertEqual(copy.kind, .custom)
        XCTAssertEqual(copy.name, "Clean Copy")
        XCTAssertEqual(copy.spectrum, original.spectrum)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(again.name, "Clean Copy 2")
        XCTAssertNotEqual(again.id, copy.id)
        switch library.rename(id: original.id, to: "Renamed", in: defaults) {
        case .failure(let error):
            XCTAssertEqual(error, .builtInLocked)
        case .success:
            XCTFail("built-in rename should be rejected")
        }
    }

    func testApplyUsesTheStoredSnapshotAndLeavesCorruptDataAlone() throws {
        var library = VisualPresetCatalog.restoring(from: defaults)
        var forged = VisualPresetCatalog.clean
        forged.spectrum?.barCount = 64
        let applied = try library.apply(forged, to: .standard, in: defaults).get()
        XCTAssertEqual(applied.spectrum.barCount, 24)

        forged.id = "missing"
        switch library.apply(forged, to: .standard, in: defaults) {
        case .failure(let error):
            XCTAssertEqual(error, .notFound)
        case .success:
            XCTFail("expected a missing preset to be rejected")
        }

        let corrupt = Data("not json".utf8)
        defaults.set(corrupt, forKey: StudioPreferenceKey.visualPresets)
        var locked = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let dynamic = try locked.apply(VisualPresetCatalog.dynamic, to: .standard, in: defaults).get()
        XCTAssertTrue(dynamic.spectrum.peakHold)
        XCTAssertEqual(dynamic.waveform, .standard)
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), corrupt)
        XCTAssertEqual(locked.match(in: dynamic, mode: .spectrum), .applied(VisualPresetCatalog.dynamic))
        XCTAssertEqual(locked.match(in: .standard, mode: .orbit), .unsaved)
    }

    @MainActor
    func testCycleVisualPresetRotatesThroughBuiltInsAndCustomPresets() throws {
        let controller = StudioWindowController(spike: ProcessTapSpike(), defaults: defaults)
        defer { controller.shutdown() }
        controller.model.prefs.mode = .spectrum

        // Unsaved starts with the first built-in (Clean), then Dense, then Dynamic, then wraps back to Clean.
        let first = try XCTUnwrap(controller.cycleVisualPreset())
        XCTAssertEqual(first.id, VisualPresetCatalog.clean.id)
        XCTAssertEqual(controller.currentPreferences().spectrum, VisualPresetCatalog.clean.spectrum)

        let second = try XCTUnwrap(controller.cycleVisualPreset())
        XCTAssertEqual(second.id, VisualPresetCatalog.dense.id)
        XCTAssertEqual(controller.currentPreferences().spectrum, VisualPresetCatalog.dense.spectrum)

        let third = try XCTUnwrap(controller.cycleVisualPreset())
        XCTAssertEqual(third.id, VisualPresetCatalog.dynamic.id)
        XCTAssertEqual(controller.currentPreferences().spectrum, VisualPresetCatalog.dynamic.spectrum)

        // Add a custom preset and confirm rotation includes it before wrapping around.
        controller.model.prefs.spectrum.barCount = 16
        let custom = try controller.saveCurrentVisualPreset(name: "Sixteen", mode: .spectrum).get()
        // After saving custom, it is currently applied, so cycling wraps back to Clean.
        let wrapped = try XCTUnwrap(controller.cycleVisualPreset())
        XCTAssertEqual(wrapped.id, VisualPresetCatalog.clean.id)
        _ = controller.cycleVisualPreset() // Dense
        _ = controller.cycleVisualPreset() // Dynamic
        let fourth = try XCTUnwrap(controller.cycleVisualPreset())
        XCTAssertEqual(fourth.id, custom.id)
        XCTAssertEqual(controller.activePresetButtonTitle(), "Sixteen")
    }
}
