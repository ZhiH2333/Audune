#if os(macOS)
import Foundation

/// Applies `StartupPreferences` once per process after controllers exist and before Island presents.
@MainActor
final class StartupApplicator {
    private(set) var didApply = false
    private(set) var lastResolution: StartupResolution?

    /// Resolves prefs, applies mode/preset, then destination. Subsequent calls are no-ops.
    @discardableResult
    func applyOnce(
        preferences: StartupPreferences,
        studio: StudioWindowController,
        island: IslandWindowController,
        defaults: UserDefaults,
        builtIns: [VisualPreset] = VisualPresetCatalog.all
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

        switch resolution.islandPolicy {
        case .followExisting:
            break
        case .forceDisabled:
            island.setEnabled(false)
        case .forceEnabled:
            island.setEnabled(true)
        }

        island.activatePresentation()

        if resolution.studioShouldShow {
            studio.show()
        }

        return resolution
    }
}
#endif
