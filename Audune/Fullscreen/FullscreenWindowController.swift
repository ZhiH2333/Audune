#if os(macOS)
import AppKit
import SwiftUI

/// Experimental Zen player window. Never starts or stops Process Tap.
@MainActor
final class FullscreenWindowController: NSObject, NSWindowDelegate {
    private let spike: ProcessTapSpike
    private let defaults: UserDefaults
    let nowPlaying: NowPlayingService
    let model = FullscreenModel()
    let lyrics = LyricsService()
    private let panel: NSPanel
    private var timer: Timer?
    private var didShutdown = false
    private var isClosingForFullscreenExit = false
    private var saveTask: Task<Void, Never>?

    var reconcileNowPlayingListening: (() -> Void)?
    var openSettings: (() -> Void)?
    var setIslandFullscreenPresentationActive: ((Bool) -> Void)?

    var wantsNowPlayingListening: Bool {
        didShutdown == false && model.isPresented && model.prefs.isEnabled
    }

    var isVisible: Bool { panel.isVisible && model.isPresented }

    init(
        spike: ProcessTapSpike,
        defaults: UserDefaults = .standard,
        nowPlaying: NowPlayingService
    ) {
        self.spike = spike
        self.defaults = defaults
        self.nowPlaying = nowPlaying
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        model.prefs = FullscreenPreferences.load(from: defaults)
        updateSharedVisuals(StudioPreferences.load(from: defaults))
        configurePanel()
    }

    func updateSharedVisuals(_ preferences: StudioPreferences) {
        model.appearance = preferences.appearance
        model.spectrum = preferences.spectrum
        model.waveform = preferences.waveform
        model.orbit = preferences.orbit
        model.mode = preferences.mode
    }

    func setEnabled(_ enabled: Bool) {
        model.prefs.isEnabled = enabled
        savePreferences()
        if enabled == false {
            hide()
        }
        reconcileNowPlayingListening?()
    }

    func setLyricsNetworkEnabled(_ enabled: Bool) {
        model.prefs.lyricsNetworkEnabled = enabled
        savePreferences()
        refreshLyrics()
    }

    func preferencesDidChange() {
        model.prefs = model.prefs.normalized()
        scheduleSavePreferences()
        if model.prefs.isEnabled == false {
            hide()
        }
        reconcileNowPlayingListening?()
        refreshLyrics()
    }

    func savePreferences() {
        saveTask?.cancel()
        saveTask = nil
        model.prefs = model.prefs.normalized()
        model.prefs.save(to: defaults)
    }

    func show() {
        guard didShutdown == false else { return }
        guard model.prefs.isEnabled else { return }
        guard isClosingForFullscreenExit == false else { return }
        model.isPresented = true
        model.snapshot = spike.snapshots.load()
        refreshNowPlayingSnapshot()
        reconcileNowPlayingListening?()
        if panel.styleMask.contains(.fullScreen) == false,
           let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            let width = min(visibleFrame.width, min(1180, max(640, visibleFrame.width * 0.88)))
            let height = min(visibleFrame.height, min(820, max(500, visibleFrame.height * 0.86)))
            panel.setFrame(
                NSRect(
                    x: visibleFrame.midX - width / 2,
                    y: visibleFrame.midY - height / 2,
                    width: width,
                    height: height
                ),
                display: false
            )
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        startDisplayTimer()
    }

    func hide() {
        guard model.isPresented, isClosingForFullscreenExit == false else { return }
        isClosingForFullscreenExit = true
        stopDisplayTimer()
        if panel.styleMask.contains(.fullScreen) {
            panel.toggleFullScreen(nil)
        } else {
            finishHide()
        }
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func refreshNowPlayingSnapshot() {
        let latest = isClosingForFullscreenExit
            ? model.nowPlaying
            : (wantsNowPlayingListening ? nowPlaying.snapshot : .idle)
        let trackChanged = latest.trackIdentity != model.nowPlaying.trackIdentity
        let statusChanged = latest.availability != model.nowPlaying.availability
        let playingChanged = latest.isPlaying != model.nowPlaying.isPlaying
        let elapsedDelta = abs(latest.elapsedSeconds - model.nowPlaying.elapsedSeconds)

        if trackChanged || statusChanged || playingChanged || elapsedDelta > 0.20 || model.nowPlaying.hasTrack != latest.hasTrack {
            model.nowPlaying = latest
        }

        if trackChanged || (model.lyricsStatus == .idle && latest.hasTrack) {
            refreshLyrics()
        }
    }

    func shutdown() {
        guard didShutdown == false else { return }
        didShutdown = true
        isClosingForFullscreenExit = false
        saveTask?.cancel()
        saveTask = nil
        model.isPresented = false
        model.nowPlaying = .idle
        lyrics.reset()
        publishLyrics()
        stopDisplayTimer()
        panel.orderOut(nil)
        panel.delegate = nil
        setIslandFullscreenPresentationActive?(false)
        reconcileNowPlayingListening?()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if isClosingForFullscreenExit {
            finishHide()
        } else {
            setIslandFullscreenPresentationActive?(false)
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard model.isPresented, isClosingForFullscreenExit == false else { return }
        setIslandFullscreenPresentationActive?(true)
        startDisplayTimer()
    }

    func windowWillClose(_ notification: Notification) {
        hide()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.managed]
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.title = String(localized: "Zen")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isOpaque = true
        let root = FullscreenContentView(
            model: model,
            spike: spike,
            togglePlayPause: { [weak self] in self?.nowPlaying.togglePlayPause() },
            previousTrack: { [weak self] in self?.nowPlaying.previousTrack() },
            nextTrack: { [weak self] in self?.nowPlaying.nextTrack() },
            seek: { [weak self] seconds in self?.nowPlaying.seek(to: seconds) },
            close: { [weak self] in self?.hide() },
            openSettings: { [weak self] in self?.openSettings?() }
        )
        panel.contentView = NSHostingView(rootView: root)
    }

    private func scheduleSavePreferences() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard Task.isCancelled == false else { return }
            self?.savePreferences()
        }
    }

    private func startDisplayTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopDisplayTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard model.isPresented else { return }
        model.snapshot = spike.snapshots.load()
        refreshNowPlayingSnapshot()
    }

    private func refreshLyrics() {
        guard model.isPresented else {
            lyrics.reset()
            publishLyrics()
            return
        }
        lyrics.sync(
            snapshot: model.nowPlaying,
            networkEnabled: model.prefs.lyricsNetworkEnabled,
            sourceSelection: model.prefs.lyricsSource
        )
        publishLyrics()
    }

    private func finishHide() {
        guard isClosingForFullscreenExit else { return }
        isClosingForFullscreenExit = false
        model.isPresented = false
        model.nowPlaying = .idle
        lyrics.reset()
        publishLyrics()
        stopDisplayTimer()
        panel.orderOut(nil)
        setIslandFullscreenPresentationActive?(false)
        reconcileNowPlayingListening?()
    }

    private func publishLyrics() {
        if model.lyricsStatus != lyrics.status {
            model.lyricsStatus = lyrics.status
        }
        if model.lyricsLines != lyrics.lines {
            model.lyricsLines = lyrics.lines
        }
        let label = lyrics.sourceID?.displayName ?? ""
        if model.lyricsSourceLabel != label {
            model.lyricsSourceLabel = label
        }
    }
}
#endif
