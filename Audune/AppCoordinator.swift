#if os(macOS)
import AppKit

/// Owns the single capture pipeline and every surface that reads it.
/// Release builds always create the menu bar item. Studio, Island, and Settings presentation follow
/// `StartupPreferences` (default: Studio/Settings hidden; Island follows saved enablement).
@MainActor
final class AppCoordinator {
    private let spike = ProcessTapSpike()
    private let studio: StudioWindowController
    private let island: IslandWindowController
    private let settings: SettingsWindowController
    private let menuBar: MenuBarController
    private let startupApplicator = StartupApplicator()
    #if DEBUG
    private let debugWindow: DebugWindowController
    #endif

    init() {
        let defaults = UserDefaults.standard
        let studio = StudioWindowController(spike: spike, defaults: defaults)
        let island = IslandWindowController(
            spike: spike,
            defaults: defaults,
            activateOnInit: false
        )
        let settings = SettingsWindowController(
            studio: studio,
            island: island
        )
        studio.openSettings = { settings.show() }
        island.openStudio = { studio.show() }
        island.openSettings = { settings.show(category: .island) }
        island.onCycleVisualPreset = { [weak studio, weak island] mode in
            guard let studio, let preset = studio.cycleVisualPreset(for: mode) else { return nil }
            island?.updateSharedVisuals(studio.currentPreferences())
            return preset
        }
        self.studio = studio
        self.island = island
        self.settings = settings

        #if DEBUG
        let debugWindow = DebugWindowController(spike: spike)
        self.debugWindow = debugWindow
        let openDebug: (() -> Void)? = { debugWindow.show() }
        #else
        let openDebug: (() -> Void)? = nil
        #endif
        menuBar = MenuBarController(
            spike: spike,
            openDebug: openDebug,
            toggleStudio: { studio.toggle() },
            toggleIsland: { island.toggleEnabled() },
            openSettings: { settings.show() },
            studioVisible: { studio.isVisible },
            islandEnabled: { island.isEffectivelyEnabled },
            islandSupported: { island.model.isSupported }
        )

        startupApplicator.applyOnce(
            preferences: StartupPreferences.load(from: defaults),
            studio: studio,
            island: island,
            settings: settings,
            spike: spike,
            defaults: defaults
        )
    }

    func shutdown() {
        spike.stop()
        menuBar.shutdown()
        studio.shutdown()
        island.shutdown()
        settings.shutdown()
        #if DEBUG
        debugWindow.shutdown()
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
#endif
