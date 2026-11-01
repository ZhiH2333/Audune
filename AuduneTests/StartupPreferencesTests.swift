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
        XCTAssertFalse(loaded.openStudioAtLaunch)
        XCTAssertTrue(loaded.showIslandAtLaunch)
        XCTAssertFalse(loaded.openSettingsAtLaunch)
        XCTAssertEqual(loaded.visualMode, .keepCurrent)
        XCTAssertNil(loaded.presetID)
        XCTAssertFalse(loaded.autoStartCapture)
    }

    func testSaveAndLoadRoundTrip() {
        let stored = StartupPreferences(
            openStudioAtLaunch: true,
            showIslandAtLaunch: true,
            openSettingsAtLaunch: true,
            visualMode: .orbit,
            presetID: "builtin.orbit.halo",
            autoStartCapture: true
        )
        stored.save(to: defaults)

        XCTAssertEqual(StartupPreferences.load(from: defaults), stored)
        XCTAssertTrue(defaults.bool(forKey: StartupPreferenceKey.openStudioAtLaunch))
        XCTAssertTrue(defaults.bool(forKey: StartupPreferenceKey.showIslandAtLaunch))
        XCTAssertTrue(defaults.bool(forKey: StartupPreferenceKey.openSettingsAtLaunch))
        XCTAssertEqual(defaults.string(forKey: StartupPreferenceKey.visualMode), "orbit")
        XCTAssertEqual(defaults.string(forKey: StartupPreferenceKey.presetID), "builtin.orbit.halo")
        XCTAssertTrue(defaults.bool(forKey: StartupPreferenceKey.autoStartCapture))
        XCTAssertNil(defaults.object(forKey: StartupPreferenceKey.legacyDestination))
    }

    func testIndependentSurfaceBooleansPersistSeparately() {
        let stored = StartupPreferences(
            openStudioAtLaunch: true,
            showIslandAtLaunch: false,
            openSettingsAtLaunch: true,
            visualMode: .keepCurrent,
            presetID: nil,
            autoStartCapture: false
        )
        stored.save(to: defaults)
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertTrue(loaded.openStudioAtLaunch)
        XCTAssertFalse(loaded.showIslandAtLaunch)
        XCTAssertTrue(loaded.openSettingsAtLaunch)
    }

    func testAllSurfacesUncheckedPersists() {
        let stored = StartupPreferences(
            openStudioAtLaunch: false,
            showIslandAtLaunch: false,
            openSettingsAtLaunch: false,
            visualMode: .keepCurrent,
            presetID: nil,
            autoStartCapture: false
        )
        stored.save(to: defaults)
        XCTAssertEqual(StartupPreferences.load(from: defaults), stored)
    }

    func testUnknownVisualModeFallsBackToDefault() {
        defaults.set(true, forKey: StartupPreferenceKey.openStudioAtLaunch)
        defaults.set(false, forKey: StartupPreferenceKey.showIslandAtLaunch)
        defaults.set(false, forKey: StartupPreferenceKey.openSettingsAtLaunch)
        defaults.set("magnet", forKey: StartupPreferenceKey.visualMode)
        defaults.set("  ", forKey: StartupPreferenceKey.presetID)

        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertTrue(loaded.openStudioAtLaunch)
        XCTAssertFalse(loaded.showIslandAtLaunch)
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
            openStudioAtLaunch: true,
            showIslandAtLaunch: false,
            openSettingsAtLaunch: true,
            visualMode: .waveform,
            presetID: "gone",
            autoStartCapture: true
        ).save(to: defaults)
        StartupPreferences.reset(in: defaults)
        XCTAssertEqual(StartupPreferences.load(from: defaults), .standard)
    }

    func testLegacyDestinationFollowExistingMigrates() {
        defaults.set("followExisting", forKey: StartupPreferenceKey.legacyDestination)
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertEqual(loaded, .standard)
        XCTAssertTrue(defaults.bool(forKey: StartupPreferenceKey.showIslandAtLaunch))
        XCTAssertNil(defaults.object(forKey: StartupPreferenceKey.legacyDestination))
    }

    func testLegacyDestinationMenuBarOnlyMigrates() {
        defaults.set("menuBarOnly", forKey: StartupPreferenceKey.legacyDestination)
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertFalse(loaded.openStudioAtLaunch)
        XCTAssertFalse(loaded.showIslandAtLaunch)
        XCTAssertFalse(loaded.openSettingsAtLaunch)
        XCTAssertNil(defaults.object(forKey: StartupPreferenceKey.legacyDestination))
    }

    func testLegacyDestinationOpenStudioMigrates() {
        defaults.set("openStudio", forKey: StartupPreferenceKey.legacyDestination)
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertTrue(loaded.openStudioAtLaunch)
        XCTAssertTrue(loaded.showIslandAtLaunch)
        XCTAssertFalse(loaded.openSettingsAtLaunch)
    }

    func testLegacyDestinationShowIslandMigrates() {
        defaults.set("showIsland", forKey: StartupPreferenceKey.legacyDestination)
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertFalse(loaded.openStudioAtLaunch)
        XCTAssertTrue(loaded.showIslandAtLaunch)
        XCTAssertFalse(loaded.openSettingsAtLaunch)
    }

    func testLegacyDestinationOpenStudioAndIslandMigrates() {
        defaults.set("openStudioAndIsland", forKey: StartupPreferenceKey.legacyDestination)
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertTrue(loaded.openStudioAtLaunch)
        XCTAssertTrue(loaded.showIslandAtLaunch)
        XCTAssertFalse(loaded.openSettingsAtLaunch)
    }

    func testUnknownLegacyDestinationFallsBackWithoutMigratingKeys() {
        defaults.set("restoreLastSession", forKey: StartupPreferenceKey.legacyDestination)
        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertEqual(loaded, .standard)
        XCTAssertEqual(defaults.string(forKey: StartupPreferenceKey.legacyDestination), "restoreLastSession")
        XCTAssertNil(defaults.object(forKey: StartupPreferenceKey.openStudioAtLaunch))
    }

    func testSurfaceKeysTakePrecedenceOverLegacyDestination() {
        defaults.set(true, forKey: StartupPreferenceKey.openStudioAtLaunch)
        defaults.set(false, forKey: StartupPreferenceKey.showIslandAtLaunch)
        defaults.set(true, forKey: StartupPreferenceKey.openSettingsAtLaunch)
        defaults.set("menuBarOnly", forKey: StartupPreferenceKey.legacyDestination)

        let loaded = StartupPreferences.load(from: defaults)
        XCTAssertTrue(loaded.openStudioAtLaunch)
        XCTAssertFalse(loaded.showIslandAtLaunch)
        XCTAssertTrue(loaded.openSettingsAtLaunch)
    }

    func testResolveStandardKeepsSurfacesUnchanged() {
        let resolution = StartupResolution.resolve(.standard, library: emptyLibrary())
        XCTAssertFalse(resolution.studioShouldShow)
        XCTAssertTrue(resolution.islandShouldPresent)
        XCTAssertFalse(resolution.settingsShouldShow)
        XCTAssertNil(resolution.effectiveMode)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertFalse(resolution.presetIDWasInvalid)
        XCTAssertFalse(resolution.autoStartCapture)
    }

    func testResolveAllSurfacesUnchecked() {
        let prefs = StartupPreferences(
            openStudioAtLaunch: false,
            showIslandAtLaunch: false,
            openSettingsAtLaunch: false,
            visualMode: .keepCurrent,
            presetID: nil,
            autoStartCapture: false
        )
        let resolution = StartupResolution.resolve(prefs, library: emptyLibrary())
        XCTAssertFalse(resolution.studioShouldShow)
        XCTAssertFalse(resolution.islandShouldPresent)
        XCTAssertFalse(resolution.settingsShouldShow)
    }

    func testResolveIndependentSurfaceCombination() {
        let prefs = StartupPreferences(
            openStudioAtLaunch: true,
            showIslandAtLaunch: false,
            openSettingsAtLaunch: true,
            visualMode: .keepCurrent,
            presetID: nil,
            autoStartCapture: false
        )
        let resolution = StartupResolution.resolve(prefs, library: emptyLibrary())
        XCTAssertTrue(resolution.studioShouldShow)
        XCTAssertFalse(resolution.islandShouldPresent)
        XCTAssertTrue(resolution.settingsShouldShow)
    }

    func testResolveExplicitModeWithoutPreset() {
        let prefs = StartupPreferences(
            openStudioAtLaunch: true,
            showIslandAtLaunch: true,
            openSettingsAtLaunch: false,
            visualMode: .waveform,
            presetID: nil,
            autoStartCapture: false
        )
        let resolution = StartupResolution.resolve(prefs, library: emptyLibrary())
        XCTAssertEqual(resolution.effectiveMode, .waveform)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertTrue(resolution.studioShouldShow)
        XCTAssertTrue(resolution.islandShouldPresent)
    }

    func testResolveKeepCurrentAppliesPresetWithoutSwitchingMode() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            openStudioAtLaunch: false,
            showIslandAtLaunch: true,
            openSettingsAtLaunch: false,
            visualMode: .keepCurrent,
            presetID: VisualPresetCatalog.dense.id,
            autoStartCapture: false
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertNil(resolution.effectiveMode)
        XCTAssertEqual(resolution.presetToApply?.id, VisualPresetCatalog.dense.id)
        XCTAssertFalse(resolution.presetIDWasInvalid)
    }

    func testResolveMissingPresetSkipsWithoutChoosingAnother() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            openStudioAtLaunch: true,
            showIslandAtLaunch: true,
            openSettingsAtLaunch: false,
            visualMode: .orbit,
            presetID: "custom-deleted-uuid",
            autoStartCapture: false
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertEqual(resolution.effectiveMode, .orbit)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertTrue(resolution.presetIDWasInvalid)
    }

    func testResolveMismatchedPresetAndModeSkipsPreset() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            openStudioAtLaunch: false,
            showIslandAtLaunch: true,
            openSettingsAtLaunch: false,
            visualMode: .orbit,
            presetID: VisualPresetCatalog.dense.id,
            autoStartCapture: false
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertEqual(resolution.effectiveMode, .orbit)
        XCTAssertNil(resolution.presetToApply)
        XCTAssertFalse(resolution.presetIDWasInvalid)
    }

    func testResolveMatchingExplicitModeAppliesPreset() {
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let prefs = StartupPreferences(
            openStudioAtLaunch: false,
            showIslandAtLaunch: true,
            openSettingsAtLaunch: false,
            visualMode: .spectrum,
            presetID: VisualPresetCatalog.clean.id,
            autoStartCapture: false
        )
        let resolution = StartupResolution.resolve(prefs, library: library)
        XCTAssertEqual(resolution.effectiveMode, .spectrum)
        XCTAssertEqual(resolution.presetToApply?.id, VisualPresetCatalog.clean.id)
        XCTAssertFalse(resolution.studioShouldShow)
        XCTAssertTrue(resolution.islandShouldPresent)
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
            openStudioAtLaunch: true,
            showIslandAtLaunch: true,
            openSettingsAtLaunch: false,
            visualMode: .waveform,
            presetID: VisualPresetCatalog.mirror.id,
            autoStartCapture: false
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
