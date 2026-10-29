#if os(macOS)
import Foundation

/// Applies `StartupPreferences` once per process after controllers exist and before Island presents.
@MainActor
final class StartupApplicator {
    private(set) var didApply = false
    private(set) var lastResolution: StartupResolution?
    private(set) var didRequestAutoStartCapture = false

    /// Resolves prefs, applies mode/preset, then independent launch surfaces. Subsequent calls are no-ops.
    @discardableResult
    func applyOnce(
        preferences: StartupPreferences,
        studio: StudioWindowController,
        island: IslandWindowController,
        settings: SettingsWindowController,
        spike: ProcessTapSpike,
        defaults: UserDefaults,
        builtIns: [VisualPreset] = VisualPresetCatalog.all,
        captureAuthorization: any CaptureAuthorizationChecking = ScreenCaptureAuthorizationProbe()
    ) -> StartupResolution? {
        guard didApply == false else { return nil }
        didApply = true

        let library = VisualPresetLibrary.load(from: defaults, builtIns: builtIns)
        let resolution = StartupResolution.resolve(preferences, library: library)
        lastResolution = resolution

        if let mode = resolution.effectiveMode {
            studio.selectMode(mode)
            island.selectMode(mode)
        }

        if let preset = resolution.presetToApply {
            _ = studio.applyVisualPreset(preset)
            island.updateSharedVisuals(studio.currentPreferences())
        }

        // Do not rewrite `island.isEnabled`. Gate presentation for this process only.
        island.setAllowsLaunchPresentation(resolution.islandShouldPresent)
        island.activatePresentation()

        if resolution.studioShouldShow {
            studio.show()
        }

        if resolution.settingsShouldShow {
            settings.show()
        }

        // Optional capture is independent of window checkboxes and never prompts for permission.
        if resolution.autoStartCapture, captureAuthorization.isCaptureAlreadyAuthorized() {
            didRequestAutoStartCapture = true
            Task { await spike.start() }
        }

        return resolution
    }
}
#endif
