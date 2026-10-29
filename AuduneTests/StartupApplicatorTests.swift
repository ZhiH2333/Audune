import AppKit
import CoreGraphics
import XCTest
@testable import Audune

@MainActor
final class StartupApplicatorTests: XCTestCase {
    private let suite = "AuduneStartupApplicatorTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    private func notchedScreen(
        id: String = "display-1",
        size: CGSize = CGSize(width: 1512, height: 982),
        notchWidth: CGFloat = 184,
        notchHeight: CGFloat = 32
    ) -> IslandScreenDescriptor {
        let frame = CGRect(origin: .zero, size: size)
        let leftWidth = (size.width - notchWidth) / 2
        let rightWidth = size.width - leftWidth - notchWidth
        let topY = frame.maxY - notchHeight
        return IslandScreenDescriptor(
            id: id,
            localizedName: "Built-in",
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: size.width, height: size.height - notchHeight),
            safeAreaTop: notchHeight,
            auxiliaryTopLeft: CGRect(x: 0, y: topY, width: leftWidth, height: notchHeight),
            auxiliaryTopRight: CGRect(x: leftWidth + notchWidth, y: topY, width: rightWidth, height: notchHeight),
            backingScaleFactor: 2
        )
    }

    private func nonNotchedScreen() -> IslandScreenDescriptor {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        return IslandScreenDescriptor(
            id: "external",
            localizedName: "External",
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1416),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            backingScaleFactor: 2
        )
    }

    private func makeControllers(
        screens: [IslandScreenDescriptor]
    ) -> (ProcessTapSpike, StudioWindowController, IslandWindowController, SettingsWindowController) {
        let spike = ProcessTapSpike()
        let studio = StudioWindowController(spike: spike, defaults: defaults)
        let island = IslandWindowController(
            spike: spike,
            defaults: defaults,
            screenProvider: { screens },
            allowsOrderFront: false,
            activateOnInit: false
        )
        let settings = SettingsWindowController(studio: studio, island: island)
        return (spike, studio, island, settings)
    }

    private func prefs(
        studio: Bool = false,
        island: Bool = true,
        settings: Bool = false,
        mode: StartupVisualMode = .keepCurrent,
        presetID: String? = nil
    ) -> StartupPreferences {
        StartupPreferences(
            openStudioAtLaunch: studio,
            showIslandAtLaunch: island,
            openSettingsAtLaunch: settings,
            visualMode: mode,
            presetID: presetID,
            autoStartCapture: false
        )
    }

    func testDefaultPreferencesMatchLegacyLaunchSurfaces() {
        IslandPreferences.standard.save(to: defaults)
        let screen = notchedScreen()
        let (spike, studio, island, settings) = makeControllers(screens: [screen])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        let applicator = StartupApplicator()
        let resolution = applicator.applyOnce(
            preferences: .standard,
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertEqual(resolution?.openStudioAtLaunch, false)
        XCTAssertEqual(resolution?.showIslandAtLaunch, true)
        XCTAssertFalse(studio.isVisible)
        XCTAssertFalse(settings.isVisible)
        XCTAssertTrue(island.isVisible)
        XCTAssertTrue(island.model.prefs.isEnabled)
        XCTAssertTrue(island.allowsLaunchPresentation)
        XCTAssertEqual(spike.phase, .idle)
        XCTAssertTrue(applicator.didApply)
    }

    func testAllSurfacesUncheckedLeavesMenuBarOnlyWithoutDisablingIsland() {
        IslandPreferences.standard.save(to: defaults)
        let (spike, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        let resolution = StartupApplicator().applyOnce(
            preferences: prefs(studio: false, island: false, settings: false),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertEqual(resolution?.islandShouldPresent, false)
        XCTAssertFalse(studio.isVisible)
        XCTAssertFalse(settings.isVisible)
        XCTAssertFalse(island.isVisible)
        XCTAssertTrue(island.model.prefs.isEnabled)
        XCTAssertFalse(island.allowsLaunchPresentation)
        XCTAssertFalse(island.isEffectivelyEnabled)
        XCTAssertEqual(spike.phase, .idle)
    }

    func testOpenSettingsAtLaunchShowsSettingsWindow() {
        IslandPreferences.standard.save(to: defaults)
        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: false, island: false, settings: true),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertFalse(studio.isVisible)
        XCTAssertTrue(settings.isVisible)
        XCTAssertFalse(island.isVisible)
        settings.shutdown()
    }

    func testOpenStudioShowsStudioAndLeavesIslandEnablement() {
        var islandPrefs = IslandPreferences.standard
        islandPrefs.isEnabled = false
        islandPrefs.save(to: defaults)
        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: true, island: true, settings: false),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertTrue(studio.isVisible)
        XCTAssertFalse(island.model.prefs.isEnabled)
        XCTAssertFalse(island.isVisible)
        studio.hide()
    }

    func testShowIslandDoesNotForceEnableWhenIslandDisabled() {
        var islandPrefs = IslandPreferences.standard
        islandPrefs.isEnabled = false
        islandPrefs.save(to: defaults)
        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: false, island: true, settings: false),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertFalse(studio.isVisible)
        XCTAssertFalse(island.model.prefs.isEnabled)
        XCTAssertTrue(island.allowsLaunchPresentation)
        XCTAssertFalse(island.isVisible)
    }

    func testShowIslandPresentsWhenEnabledOnSupportedScreen() {
        IslandPreferences.standard.save(to: defaults)
        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: false, island: true, settings: false),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertFalse(studio.isVisible)
        XCTAssertTrue(island.model.prefs.isEnabled)
        XCTAssertTrue(island.isVisible)
    }

    func testLaunchSuppressToggleRestoresIslandWithoutWritingDisable() {
        IslandPreferences.standard.save(to: defaults)
        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: false, island: false, settings: false),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )
        XCTAssertFalse(island.isVisible)
        XCTAssertTrue(island.model.prefs.isEnabled)

        island.toggleEnabled()
        XCTAssertTrue(island.allowsLaunchPresentation)
        XCTAssertTrue(island.model.prefs.isEnabled)
        XCTAssertTrue(island.isVisible)
    }

    func testOpenStudioAndIslandOnUnsupportedScreenStillOpensStudio() {
        IslandPreferences.standard.save(to: defaults)
        let (_, studio, island, settings) = makeControllers(screens: [nonNotchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: true, island: true, settings: false),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertTrue(studio.isVisible)
        XCTAssertTrue(island.model.prefs.isEnabled)
        XCTAssertFalse(island.model.isSupported)
        XCTAssertFalse(island.isVisible)
        studio.hide()
    }

    func testModeOverrideUpdatesStudioAndIslandBeforePresentation() {
        var studioPrefs = StudioPreferences.standard
        studioPrefs.mode = .spectrum
        studioPrefs.save(to: defaults)
        var islandPrefs = IslandPreferences.standard
        islandPrefs.mode = .spectrum
        islandPrefs.save(to: defaults)

        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: true, island: true, mode: .orbit),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertEqual(studio.model.prefs.mode, .orbit)
        XCTAssertEqual(island.model.prefs.mode, .orbit)
        XCTAssertEqual(StudioPreferences.load(from: defaults).mode, .orbit)
        XCTAssertEqual(IslandPreferences.load(from: defaults).mode, .orbit)
        studio.hide()
    }

    func testPresetApplyUsesExistingPathAndSetsMode() throws {
        StudioPreferences.standard.save(to: defaults)
        IslandPreferences.standard.save(to: defaults)
        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(presetID: VisualPresetCatalog.dense.id),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertEqual(studio.model.prefs.mode, .spectrum)
        XCTAssertEqual(island.model.prefs.mode, .spectrum)
        let expected = try XCTUnwrap(VisualPresetCatalog.dense.spectrum)
        XCTAssertEqual(studio.model.prefs.spectrum.barCount, expected.barCount)
        XCTAssertEqual(studio.model.prefs.spectrum.colorMode, expected.colorMode)
        XCTAssertEqual(island.model.spectrum.barCount, expected.barCount)
    }

    func testMissingPresetDoesNotBlockLaunchOrPickAReplacement() {
        var studioPrefs = StudioPreferences.standard
        studioPrefs.mode = .waveform
        studioPrefs.appearance.opacity = 0.81
        studioPrefs.waveform.amplitude = 0.42
        studioPrefs.save(to: defaults)
        var islandPrefs = IslandPreferences.standard
        islandPrefs.compactBarCountPerSide = 4
        islandPrefs.save(to: defaults)

        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(studio: true, island: true, mode: .orbit, presetID: "missing-custom-id"),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertEqual(studio.model.prefs.mode, .orbit)
        XCTAssertEqual(island.model.prefs.mode, .orbit)
        XCTAssertEqual(studio.model.prefs.appearance.opacity, 0.81, accuracy: 0.000_1)
        XCTAssertEqual(studio.model.prefs.waveform.amplitude, 0.42, accuracy: 0.000_1)
        XCTAssertEqual(island.model.prefs.compactBarCountPerSide, 4)
        studio.hide()
    }

    func testApplyOnceIsIdempotentAgainstLaterActivation() {
        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        let applicator = StartupApplicator()
        let first = applicator.applyOnce(
            preferences: prefs(studio: true, island: true, mode: .waveform),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )
        XCTAssertNotNil(first)
        XCTAssertTrue(studio.isVisible)
        XCTAssertEqual(studio.model.prefs.mode, .waveform)

        studio.hide()
        studio.selectMode(.orbit)
        island.selectMode(.orbit)
        island.setEnabled(false)

        let second = applicator.applyOnce(
            preferences: prefs(
                studio: true,
                island: true,
                mode: .spectrum,
                presetID: VisualPresetCatalog.dense.id
            ),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertNil(second)
        XCTAssertFalse(studio.isVisible)
        XCTAssertEqual(studio.model.prefs.mode, .orbit)
        XCTAssertEqual(island.model.prefs.mode, .orbit)
        XCTAssertFalse(island.model.prefs.isEnabled)
    }

    func testDeferredIslandActivationAvoidsPrematureVisibility() {
        IslandPreferences.standard.save(to: defaults)
        let spike = ProcessTapSpike()
        let island = IslandWindowController(
            spike: spike,
            defaults: defaults,
            screenProvider: { [self.notchedScreen()] },
            allowsOrderFront: false,
            activateOnInit: false
        )
        defer { island.shutdown() }

        XCTAssertFalse(island.model.isSupported)
        XCTAssertFalse(island.isVisible)

        island.activatePresentation()
        XCTAssertTrue(island.model.isSupported)
        XCTAssertTrue(island.isVisible)
    }

    func testPresetDoesNotMutateAppearanceWindowOrIslandChrome() {
        var studioPrefs = StudioPreferences.standard
        studioPrefs.appearance.opacity = 0.66
        studioPrefs.appearance.lineWidth = 2.25
        studioPrefs.spectrum.barCount = 16
        studioPrefs.save(to: defaults)
        var islandPrefs = IslandPreferences.standard
        islandPrefs.compactBarCountPerSide = 6
        islandPrefs.hoverToExpand = false
        islandPrefs.save(to: defaults)

        let (_, studio, island, settings) = makeControllers(screens: [notchedScreen()])
        defer {
            studio.shutdown()
            island.shutdown()
            settings.shutdown()
        }

        _ = StartupApplicator().applyOnce(
            preferences: prefs(presetID: VisualPresetCatalog.halo.id),
            studio: studio,
            island: island,
            settings: settings,
            defaults: defaults
        )

        XCTAssertEqual(studio.model.prefs.appearance.opacity, 0.66, accuracy: 0.000_1)
        XCTAssertEqual(studio.model.prefs.appearance.lineWidth, 2.25, accuracy: 0.000_1)
        // Orbit preset must not rewrite Spectrum payload or Island chrome.
        XCTAssertEqual(studio.model.prefs.spectrum.barCount, 16)
        XCTAssertEqual(island.model.prefs.compactBarCountPerSide, 6)
        XCTAssertFalse(island.model.prefs.hoverToExpand)
        XCTAssertEqual(studio.model.prefs.mode, .orbit)
    }
}
