#if os(macOS)
import AppKit

/// Owns the single capture pipeline and every surface that reads it.
/// Release builds always create the menu bar item. Studio, Island, and Settings presentation follow
/// `StartupPreferences` (default: Studio/Settings hidden; Island follows saved enablement).
@MainActor
final class AppCoordinator {
    private let spike = ProcessTapSpike()
    private let nowPlaying: NowPlayingService
    private let studio: StudioWindowController
    private let island: IslandWindowController
    private let fullscreen: FullscreenWindowController
    private let settings: SettingsWindowController
    private let menuBar: MenuBarController
    private let startupApplicator = StartupApplicator()
    #if DEBUG
    private let debugWindow: DebugWindowController
    #endif

    init() {
        let defaults = UserDefaults.standard
        let nowPlaying = NowPlayingService()
        let studio = StudioWindowController(spike: spike, defaults: defaults)
        let island = IslandWindowController(
            spike: spike,
            defaults: defaults,
            nowPlaying: nowPlaying,
            activateOnInit: false
        )
        let fullscreen = FullscreenWindowController(
            spike: spike,
            defaults: defaults,
            nowPlaying: nowPlaying
        )
        let settings = SettingsWindowController(
            studio: studio,
            island: island,
            fullscreen: fullscreen
        )
        studio.openSettings = { settings.show() }
        island.openStudio = { studio.show() }
        island.openSettings = { settings.show(category: .island) }
        island.openFullscreen = {
            if fullscreen.model.prefs.isEnabled {
                fullscreen.show()
            } else {
                settings.show(category: .fullscreen)
            }
        }
        fullscreen.openSettings = { settings.show(category: .fullscreen) }
        self.nowPlaying = nowPlaying
        self.studio = studio
        self.island = island
        self.fullscreen = fullscreen
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
            openFullscreen: { fullscreen.toggle() },
            studioVisible: { studio.isVisible },
            islandEnabled: { island.isEffectivelyEnabled },
            islandSupported: { island.model.isSupported },
            fullscreenEnabled: { fullscreen.model.prefs.isEnabled }
        )

        let reconcile: () -> Void = { [weak self] in
            self?.reconcileNowPlayingListening()
        }
        island.reconcileNowPlayingListening = reconcile
        fullscreen.reconcileNowPlayingListening = reconcile

        startupApplicator.applyOnce(
            preferences: StartupPreferences.load(from: defaults),
            studio: studio,
            island: island,
            settings: settings,
            spike: spike,
            defaults: defaults
        )
    }

    func reconcileNowPlayingListening() {
        let shouldListen = island.wantsNowPlayingListening || fullscreen.wantsNowPlayingListening
        nowPlaying.syncDesiredListening(shouldListen: shouldListen)
        island.refreshNowPlayingSnapshot()
        fullscreen.refreshNowPlayingSnapshot()
    }

    func shutdown() {
        spike.stop()
        menuBar.shutdown()
        studio.shutdown()
        island.shutdown()
        fullscreen.shutdown()
        nowPlaying.stop()
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
