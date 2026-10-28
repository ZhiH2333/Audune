#if os(macOS)
import AppKit

/// Owns the single capture pipeline and every surface that reads it.
/// Release builds start with only the menu bar item; no window is created until the user opens one.
@MainActor
final class AppCoordinator {
    private let spike = ProcessTapSpike()
    private let studio: StudioWindowController
    private let island: IslandWindowController
    private let settings: SettingsWindowController
    private let menuBar: MenuBarController
    #if DEBUG
    private let debugWindow: DebugWindowController
    #endif

    init() {
        let studio = StudioWindowController(spike: spike)
        let island = IslandWindowController(spike: spike)
        let settings = SettingsWindowController(studio: studio, island: island)
        studio.openSettings = { settings.show() }
        island.openStudio = { studio.show() }
        island.openSettings = { settings.show(category: .island) }
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
            islandEnabled: { island.model.prefs.isEnabled },
            islandSupported: { island.model.isSupported }
        )
        #if DEBUG
        debugWindow.show()
        #endif
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
