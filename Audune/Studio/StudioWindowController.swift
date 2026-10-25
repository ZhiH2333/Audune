#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class StudioWindowController: NSObject, NSWindowDelegate {
    private let spike: ProcessTapSpike
    let model = StudioModel()
    private let panel: NSPanel
    private let hitMap = StudioHitMap()
    private var timer: Timer?
    private var playbackTimer: Timer?
    private let players: [any PlayerControlling] = [MusicPlayerController(), SpotifyPlayerController()]
    private var screenObserver: NSObjectProtocol?
    private var pointerMonitor: Any?
    private var smoothedStudio: [Float] = []
    private var smoothedWave: [Float] = []
    private var didShutdown = false

    init(spike: ProcessTapSpike) {
        self.spike = spike
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: StudioFrame.defaultSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        apply(StudioPreferences.load())
        configurePanel()
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        clampOntoVisibleScreen()
        applyWindowMode()
        refreshPointerInside()
        panel.orderFrontRegardless()
        startDisplayTimer()
        startPlaybackTimer()
    }

    func hide() {
        stopDisplayTimer()
        stopPlaybackTimer()
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func shutdown() {
        guard didShutdown == false else { return }
        didShutdown = true
        stopDisplayTimer()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
        stopPlaybackTimer()
        panel.orderOut(nil)
    }

    func setPlayerID(_ id: String) {
        let stored = id.isEmpty || players.contains(where: { $0.id == id }) ? id : ""
        model.playerID = stored
        UserDefaults.standard.set(stored, forKey: PlayerSelectionKey.selected)
        model.playbackState = .unknown
        if stored.isEmpty {
            model.playbackAvailability = .noSelection
            model.playbackDetail = "Choose a player"
            model.playbackBusy = false
            return
        }
        refreshPlayback()
    }

    func togglePlayback() {
        guard model.playbackBusy == false, let player = selectedPlayer() else { return }
        model.playbackBusy = true
        let result = player.togglePlayPause()
        applyPlayback(result)
        model.playbackBusy = false
    }

    func setWindowMode(_ mode: StudioWindowMode) {
        model.windowMode = mode
        savePreferences()
        applyWindowMode()
    }

    func savePreferences() {
        currentPreferences().save()
    }

    func setBarCount(_ count: Int) {
        let normalized = StudioPreferences.normalizedBarCount(count)
        if model.barCount != normalized {
            smoothedStudio = []
        }
        model.barCount = normalized
        savePreferences()
        refreshStudioSpectrum()
    }

    func setChromeVisible(_ visible: Bool) {
        panel.hasShadow = false
    }

    func resetPreferences() {
        StudioPreferences.reset()
        smoothedStudio = []
        smoothedWave = []
        apply(StudioPreferences.standard)
        refreshStudioSpectrum()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopDisplayTimer()
        return true
    }

    func inspectWindowForTests() -> StudioWindowInspection {
        StudioWindowInspection(
            frame: panel.frame,
            level: panel.level,
            isFloatingPanel: panel.isFloatingPanel,
            hidesOnDeactivate: panel.hidesOnDeactivate,
            collectionBehavior: panel.collectionBehavior,
            isMovable: panel.isMovable,
            isMovableByWindowBackground: panel.isMovableByWindowBackground,
            isResizable: panel.styleMask.contains(.resizable),
            usesDragHostingView: panel.contentView is StudioHostingView<StudioContentView>,
            isOpaque: panel.isOpaque,
            backgroundAlpha: panel.backgroundColor?.alphaComponent ?? 1,
            hasShadow: panel.hasShadow,
            ignoresMouseEvents: panel.ignoresMouseEvents,
            hostIsOpaque: (panel.contentView as? StudioHostingView<StudioContentView>)?.isOpaque ?? true
        )
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = false
        panel.title = "Audune Studio"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.minSize = StudioFrame.minimumSize
        panel.contentMinSize = StudioFrame.minimumSize
        let root = StudioContentView(
            spike: spike,
            model: model,
            setWindowMode: { [weak self] mode in
                self?.setWindowMode(mode)
            },
            savePreferences: { [weak self] in
                self?.savePreferences()
            },
            resetPreferences: { [weak self] in
                self?.resetPreferences()
            },
            close: { [weak self] in
                self?.hide()
            },
            setBarCount: { [weak self] count in
                self?.setBarCount(count)
            },
            setChromeVisible: { [weak self] visible in
                self?.setChromeVisible(visible)
            },
            playerChoices: players.map { PlayerChoice(id: $0.id, title: $0.displayName) },
            setPlayerID: { [weak self] id in
                self?.setPlayerID(id)
            },
            togglePlayback: { [weak self] in
                self?.togglePlayback()
            },
            hitMap: hitMap
        )
        let host = StudioHostingView(rootView: root)
        host.hitMap = hitMap
        host.onPointerInside = { [weak self] inside in
            self?.model.pointerInside = inside
        }
        panel.contentView = host
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return }
                self.model.pointerDown = event.type == .leftMouseDown
            }
            return event
        }
        if panel.setFrameAutosaveName(StudioWindowStorage.frameAutosaveName) == false {
            panel.center()
        }
        clampOntoVisibleScreen()
        applyWindowMode()
        let storedPlayer = UserDefaults.standard.string(forKey: PlayerSelectionKey.selected) ?? ""
        model.playerID = players.contains(where: { $0.id == storedPlayer }) ? storedPlayer : ""
        if let player = selectedPlayer() {
            let gate = player.availability()
            model.playbackAvailability = gate
            model.playbackDetail = playbackDetail(gate)
        } else {
            model.playbackAvailability = .noSelection
            model.playbackDetail = "Choose a player"
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clampOntoVisibleScreen()
            }
        }
    }

    private func applyWindowMode() {
        let frame = panel.frame
        let visible = panel.isVisible
        panel.isFloatingPanel = StudioWindowBehavior.isFloatingPanel(for: model.windowMode)
        panel.level = StudioWindowBehavior.level(for: model.windowMode)
        panel.collectionBehavior = StudioWindowBehavior.collectionBehavior(for: model.windowMode)
        panel.hidesOnDeactivate = false
        if panel.frame != frame {
            panel.setFrame(frame, display: visible)
        }
        if visible {
            panel.orderFrontRegardless()
        }
    }

    private func apply(_ preferences: StudioPreferences) {
        model.mode = preferences.mode
        model.windowMode = preferences.windowMode
        model.backgroundOpacity = preferences.backgroundOpacity
        model.accent = preferences.accent
        model.barCount = preferences.barCount
        model.lineWidth = preferences.lineWidth
        model.amplitude = preferences.amplitude
        model.smoothing = preferences.smoothing
        model.barGap = preferences.barGap
        model.cornerRadius = preferences.cornerRadius
        model.spectrumStroke = preferences.spectrumStroke
        model.orbitInner = preferences.orbitInner
        if model.studioSpectrum.count != preferences.barCount {
            model.studioSpectrum = Array(repeating: 0, count: preferences.barCount)
        }
        applyWindowMode()
    }

    private func currentPreferences() -> StudioPreferences {
        StudioPreferences(
            mode: model.mode,
            windowMode: model.windowMode,
            backgroundOpacity: model.backgroundOpacity,
            accent: model.accent,
            barCount: model.barCount,
            lineWidth: model.lineWidth,
            amplitude: model.amplitude,
            smoothing: model.smoothing,
            barGap: model.barGap,
            cornerRadius: model.cornerRadius,
            spectrumStroke: model.spectrumStroke,
            orbitInner: model.orbitInner
        )
    }

    private func refreshPointerInside() {
        let inside = StudioChrome.pointerIsInside(windowFrame: panel.frame, cursor: NSEvent.mouseLocation)
        if model.pointerInside != inside {
            model.pointerInside = inside
        }
    }

    private func refreshStudioSpectrum() {
        let count = model.barCount
        let levels = SpectrumBands.levels(
            binMagnitudes: model.snapshot.binMagnitudes,
            sampleRate: model.snapshot.sampleRate,
            count: count
        )
        smoothedStudio = SpectrumBands.displayMix(
            current: smoothedStudio,
            toward: levels,
            count: count,
            smoothing: Float(model.smoothing)
        )
        model.studioSpectrum = smoothedStudio
    }

    private func selectedPlayer() -> (any PlayerControlling)? {
        players.first { $0.id == model.playerID }
    }

    private func startPlaybackTimer() {
        guard playbackTimer == nil else { return }
        refreshPlayback()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPlayback()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func refreshPlayback() {
        guard model.playbackBusy == false else { return }
        guard let player = selectedPlayer() else {
            model.playbackAvailability = .noSelection
            model.playbackState = .unknown
            model.playbackDetail = "Choose a player"
            return
        }
        let gate = player.availability()
        guard gate == .ready else {
            model.playbackAvailability = gate
            model.playbackState = .unknown
            model.playbackDetail = playbackDetail(gate)
            return
        }
        model.playbackBusy = true
        let result = player.playbackState()
        applyPlayback(result)
        model.playbackBusy = false
    }

    private func applyPlayback(_ result: PlayerCommandResult) {
        switch result {
        case .state(let state):
            model.playbackAvailability = .ready
            model.playbackState = state
            model.playbackDetail = ""
        case .unavailable(let availability):
            model.playbackAvailability = availability
            model.playbackState = .unknown
            model.playbackDetail = playbackDetail(availability)
        case .failed(let message):
            model.playbackAvailability = .failed(message)
            model.playbackState = .unknown
            model.playbackDetail = message
        }
    }

    private func playbackDetail(_ availability: PlayerAvailability) -> String {
        switch availability {
        case .noSelection:
            return "Choose a player"
        case .ready:
            return ""
        case .notInstalled:
            return "The selected player is not installed."
        case .notRunning:
            return "The selected player is not running."
        case .automationDenied:
            return "Automation was denied. Allow Audune in System Settings > Privacy & Security > Automation."
        case .failed(let message):
            return message
        }
    }

    private func refreshWaveform() {
        smoothedWave = WaveformPath.mix(
            current: smoothedWave,
            toward: model.snapshot.waveform,
            smoothing: Float(model.smoothing)
        )
        model.displayWaveform = smoothedWave
    }

    private func clampOntoVisibleScreen() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let fallback = NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: StudioFrame.defaultSize)
        let clamped = StudioFrame.clamped(panel.frame, to: screens, fallback: fallback)
        if clamped != panel.frame {
            panel.setFrame(clamped, display: panel.isVisible)
        }
    }

    private func startDisplayTimer() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickFromTimer()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopDisplayTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tickFromTimer() {
        MainActor.assumeIsolated {
            tick()
        }
    }

    private func tick() {
        model.snapshot = spike.snapshots.load()
        refreshPointerInside()
        refreshStudioSpectrum()
        refreshWaveform()
    }
}
#endif
