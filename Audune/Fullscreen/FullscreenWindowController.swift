#if os(macOS)
import AppKit
import SwiftUI

/// Experimental Fullscreen ambient player. Never starts or stops Process Tap.
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
    private var saveTask: Task<Void, Never>?

    var reconcileNowPlayingListening: (() -> Void)?
    var openSettings: (() -> Void)?

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
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.borderless, .fullSizeContentView, .resizable],
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
        model.isPresented = true
        refreshNowPlayingSnapshot()
        reconcileNowPlayingListening?()
        startDisplayTimer()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrame(screen.frame, display: true)
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if panel.styleMask.contains(.fullScreen) == false {
            panel.toggleFullScreen(nil)
        }
    }

    func hide() {
        model.isPresented = false
        model.nowPlaying = .idle
        lyrics.reset()
        publishLyrics()
        stopDisplayTimer()
        if panel.styleMask.contains(.fullScreen) {
            panel.toggleFullScreen(nil)
        }
        panel.orderOut(nil)
        reconcileNowPlayingListening?()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func refreshNowPlayingSnapshot() {
        model.nowPlaying = wantsNowPlayingListening ? nowPlaying.snapshot : .idle
        refreshLyrics()
    }

    func shutdown() {
        guard didShutdown == false else { return }
        didShutdown = true
        saveTask?.cancel()
        saveTask = nil
        model.isPresented = false
        model.nowPlaying = .idle
        lyrics.reset()
        publishLyrics()
        stopDisplayTimer()
        panel.orderOut(nil)
        panel.delegate = nil
        reconcileNowPlayingListening?()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if model.isPresented == false {
            panel.orderOut(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        hide()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenPrimary, .managed]
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.title = String(localized: "Audune Fullscreen")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .black
        panel.hasShadow = false
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
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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
            networkEnabled: model.prefs.lyricsNetworkEnabled
        )
        publishLyrics()
    }

    private func publishLyrics() {
        model.lyricsStatus = lyrics.status
        model.lyricsLines = lyrics.lines
    }
}
#endif
