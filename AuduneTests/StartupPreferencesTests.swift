import XCTest
@testable import Audune

final class StartupPreferencesTests: XCTestCase {
    private let suite = "AuduneStartupPreferencesTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testMissingKeysUseBackwardCompatibleDefaults() {
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertEqual(loaded, .standard)
        XCTAssertEqual(loaded.destination, .followExisting)
        XCTAssertEqual(loaded.visualMode, .keepCurrent)
        XCTAssertNil(loaded.presetID)
    }

    func testSaveAndLoadRoundTrip() {
        let stored = StartupPreferences(
            destination: .openStudioAndIsland,
            visualMode: .orbit,
            presetID: "builtin.orbit.halo"
        )
        stored.save(to: defaults)

        XCTAssertEqual(StartupPreferences.load(from: defaults), stored)
        XCTAssertEqual(defaults.string(forKey: StartupPreferenceKey.destination), "openStudioAndIsland")
        XCTAssertEqual(defaults.string(forKey: StartupPreferenceKey.visualMode), "orbit")
        XCTAssertEqual(defaults.string(forKey: StartupPreferenceKey.presetID), "builtin.orbit.halo")
    }

    func testUnknownRawValuesFallBackToDefaults() {
        defaults.set("restoreLastSession", forKey: StartupPreferenceKey.destination)
        defaults.set("magnet", forKey: StartupPreferenceKey.visualMode)
        defaults.set("  ", forKey: StartupPreferenceKey.presetID)

        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertEqual(loaded.destination, .followExisting)
        XCTAssertEqual(loaded.visualMode, .keepCurrent)
        XCTAssertNil(loaded.presetID)
    }

    func testClearingPresetIDRemovesTheKey() {
        var prefs = StartupPreferences.standard
        prefs.presetID = "builtin.spectrum.clean"
        prefs.save(to: defaults)
        XCTAssertNotNil(defaults.string(forKey: StartupPreferenceKey.presetID))

        prefs.presetID = nil
        prefs.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: StartupPreferenceKey.presetID))
    }

    func testResetWritesStandardValues() {
        StartupPreferences(
            destination: .menuBarOnly,
            visualMode: .waveform,
            presetID: "gone"
        ).save(to: defaults)
        StartupPreferences.reset(in: defaults)
        XCTAssertEqual(StartupPreferences.load(from: defaults), .standard)
    }

    func testResolveFollowExistingKeepsSurfacesUnchanged() {
        let resolution = StartupResolution.resolve(.standard, library: emptyLibrary())
        XCTAssertEqual(resolution.destination, .followExisting)
        XCTAssertNil(resolution.effectiveMode)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertFalse(resolution.presetIDWasInvalid)
        XCTAssertFalse(resolution.studioShouldShow)
        XCTAssertEqual(resolution.islandPolicy, .followExisting)
    }

    func testResolveMenuBarOnlyForcesIslandOff() {
        let prefs = StartupPreferences(destination: .menuBarOnly, visualMode: .keepCurrent, presetID: nil)
        let resolution = StartupResolution.resolve(prefs, library: emptyLibrary())
        XCTAssertFalse(resolution.studioShouldShow)
        XCTAssertEqual(resolution.islandPolicy, .forceDisabled)
    }

    func testResolveOpenStudioAndIsland() {
        let prefs = StartupPreferences(
            destination: .openStudioAndIsland,
            visualMode: .keepCurrent,
            presetID: nil
        )
        let resolution = StartupResolution.resolve(prefs, library: emptyLibrary())
        XCTAssertTrue(resolution.studioShouldShow)
        XCTAssertEqual(resolution.islandPolicy, .forceEnabled)
    }

    func testResolveExplicitModeWithoutPreset() {
        let prefs = StartupPreferences(destination: .openStudio, visualMode: .waveform, presetID: nil)
        let resolution = StartupResolution.resolve(prefs, library: emptyLibrary())
        XCTAssertEqual(resolution.effectiveMode, .waveform)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertTrue(resolution.studioShouldShow)
        XCTAssertEqual(resolution.islandPolicy, .followExisting)
    }

    func testResolvePresetInfersModeWhenKeepingCurrent() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            destination: .followExisting,
            visualMode: .keepCurrent,
            presetID: VisualPresetCatalog.dense.id
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertEqual(resolution.effectiveMode, .spectrum)
        XCTAssertEqual(resolution.presetToApply?.id, VisualPresetCatalog.dense.id)
        XCTAssertFalse(resolution.presetIDWasInvalid)
    }

    func testResolveMissingPresetSkipsWithoutChoosingAnother() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            destination: .openStudio,
            visualMode: .orbit,
            presetID: "custom-deleted-uuid"
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertEqual(resolution.effectiveMode, .orbit)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertTrue(resolution.presetIDWasInvalid)
    }

    func testResolveMismatchedPresetAndModeSkipsPreset() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            destination: .followExisting,
            visualMode: .orbit,
            presetID: VisualPresetCatalog.dense.id
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertEqual(resolution.effectiveMode, .orbit)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertFalse(resolution.presetIDWasInvalid)
    }

    func testResolveMatchingExplicitModeAppliesPreset() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            destination: .showIsland,
            visualMode: .spectrum,
            presetID: VisualPresetCatalog.clean.id
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertEqual(resolution.effectiveMode, .spectrum)
        XCTAssertEqual(resolution.presetToApply?.id, VisualPresetCatalog.clean.id)
        XCTAssertFalse(resolution.studioShouldShow)
        XCTAssertEqual(resolution.islandPolicy, .forceEnabled)
    }

    func testResolveDoesNotMutateUnrelatedDefaults() {
        var studio = StudioPreferences.standard
        studio.appearance.opacity = 0.77
        studio.window.width = 800
        studio.save(to: defaults)
        var island = IslandPreferences.standard
        island.compactBarCountPerSide = 6
        island.isEnabled = false
        island.save(to: defaults)

        let prefs = StartupPreferences(
            destination: .openStudio,
            visualMode: .waveform,
            presetID: VisualPresetCatalog.mirror.id
        )
        prefs.save(to: defaults)
        _ = StartupResolution.resolve(
            prefs,
            library: VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        )

        XCTAssertEqual(StudioPreferences.load(from: defaults).appearance.opacity, 0.77, accuracy: 0.000_1)
        XCTAssertEqual(StudioPreferences.load(from: defaults).window.width, 800, accuracy: 0.000_1)
        XCTAssertEqual(IslandPreferences.load(from: defaults).compactBarCountPerSide, 6)
        XCTAssertFalse(IslandPreferences.load(from: defaults).isEnabled)
        XCTAssertEqual(StudioPreferences.load(from: defaults).mode, .spectrum)
    }

    private func emptyLibrary() -> VisualPresetLibrary {
        VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
    }
}
