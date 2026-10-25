#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class StudioWindowController: NSObject, NSWindowDelegate {
    private let spike: ProcessTapSpike
    let model = StudioModel()
    private let panel: NSPanel
    private let hitMap = StudioHitMap()
    private var interactionPanel: NSPanel?
    private var interactionHost: StudioInteractionHostingView<StudioInteractionRoot>?
    private var edgePanels: [StudioEdgePanel] = []
    private var interactionContentSize = CGSize(width: StudioChrome.gripWidth, height: StudioChrome.gripHeight)
    private var timer: Timer?
    private var playbackTimer: Timer?
    private let players: [any PlayerControlling] = [MusicPlayerController(), SpotifyPlayerController()]
    /// Set by the owner of the Settings window. Studio never owns that window.
    var openSettings: (() -> Void)?
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var pointerMonitor: Any?
    private var smoothedStudio: [Float] = []
    private var smoothedWave: [Float] = []
    private var didShutdown = false
    private var saveTask: Task<Void, Never>?
    private var settingsWindowVisible = false
    private var permissionCache: [String: AutomationPermission] = [:]
    private var permissionChecks: Set<String> = []
    private var spectrumState = SpectrumDynamicsState()
    private var lastTick: ContinuousClock.Instant?
    private let defaults: UserDefaults

    init(spike: ProcessTapSpike, defaults: UserDefaults = .standard) {
        self.spike = spike
        self.defaults = defaults
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: StudioFrame.defaultSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        apply(StudioPreferences.load(from: defaults))
        configurePanel()
    }

    var isVisible: Bool { panel.isVisible }

    var playerChoices: [PlayerChoice] {
        players.map { PlayerChoice(id: $0.id, title: $0.displayName) }
    }

    func show() {
        clampOntoVisibleScreen()
        applyWindowMode()
        refreshPointerInside()
        panel.orderFrontRegardless()
        model.isShown = true
        startDisplayTimer()
        updatePlaybackTimer()
        syncPassthroughWindows()
    }

    func hide() {
        stopDisplayTimer()
        orderOutPassthroughWindows()
        panel.orderOut(nil)
        model.isShown = false
        clearInteractionState()
        updatePlaybackTimer()
    }

    /// The Settings window reports when it opens or closes, so Playback status can refresh while it is open.
    func setSettingsWindowVisible(_ visible: Bool) {
        settingsWindowVisible = visible
        updatePlaybackTimer()
    }

    /// Status is polled only while Studio is visible, or while Settings is open on the Playback page.
    func updatePlaybackTimer() {
        let needed = panel.isVisible || (settingsWindowVisible && model.settingsCategory == .playback)
        if needed {
            startPlaybackTimer()
        } else {
            stopPlaybackTimer()
        }
    }

    func refreshPlaybackNow() {
        refreshPlayback()
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
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
        stopPlaybackTimer()
        orderOutPassthroughWindows()
        panel.orderOut(nil)
        model.isShown = false
        clearInteractionState()
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

    /// Asks macOS for Automation access to the selected player. This is the only place that can show the prompt.
    /// The call may wait for the user, so it runs off the main thread.
    func requestPlayerAccess() {
        guard model.playbackRequesting == false, let player = selectedPlayer() else { return }
        let id = player.id
        let bundleIdentifier = player.bundleIdentifier
        model.playbackRequesting = true
        Task { @MainActor [weak self] in
            let result = await Task.detached {
                AutomationPermissionCheck.determine(bundleIdentifier: bundleIdentifier, askUserIfNeeded: true)
            }.value
            guard let self else { return }
            self.model.playbackRequesting = false
            self.permissionCache[id] = result
            self.refreshPlayback()
        }
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func setWindowMode(_ mode: StudioWindowMode) {
        model.prefs.windowMode = mode
        savePreferences()
        applyWindowMode()
    }

    func savePreferences() {
        saveTask?.cancel()
        saveTask = nil
        currentPreferences().save(to: defaults)
    }

    /// Slider drags call this on every tick; the write happens once the value settles.
    func preferencesDidChange() {
        applyWindowPreferences()
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard Task.isCancelled == false else { return }
            self?.savePreferences()
        }
    }

    func setSpectrumBarCount(_ count: Int) {
        model.prefs.spectrum.barCount = StudioPreferences.normalizedBarCount(count)
        savePreferences()
        refreshStudioSpectrum(dt: 0)
    }

    func setOrbitBarCount(_ count: Int) {
        model.prefs.orbit.barCount = StudioPreferences.normalizedBarCount(count)
        savePreferences()
        refreshStudioSpectrum(dt: 0)
    }

    @discardableResult
    func applyVisualPreset(_ preset: VisualPreset) -> Bool {
        var library = VisualPresetCatalog.restoring(from: defaults)
        switch library.apply(preset, to: model.prefs, in: defaults) {
        case .success(let updated):
            model.prefs = updated
            savePreferences()
            refreshStudioSpectrum(dt: 0)
            refreshWaveform()
            return true
        case .failure:
            return false
        }
    }

    func saveCurrentVisualPreset(name: String, mode: StudioVisualMode) -> Result<VisualPreset, VisualPresetEditError> {
        var library = VisualPresetCatalog.restoring(from: defaults)
        let saved: Result<VisualPreset, VisualPresetEditError>
        switch mode {
        case .spectrum:
            saved = library.addCustom(name: name, mode: mode, spectrum: model.prefs.spectrum, to: defaults)
        case .waveform:
            saved = library.addCustom(name: name, mode: mode, waveform: model.prefs.waveform, to: defaults)
        case .orbit:
            saved = library.addCustom(name: name, mode: mode, orbit: model.prefs.orbit, to: defaults)
        }
        guard case .success(let preset) = saved else { return saved }
        switch library.setAppliedID(preset.id, for: mode, in: defaults) {
        case .success:
            return .success(preset)
        case .failure(let error):
            return .failure(error)
        }
    }

    func duplicateVisualPreset(id: String) -> Result<VisualPreset, VisualPresetEditError> {
        var library = VisualPresetCatalog.restoring(from: defaults)
        return library.duplicate(id: id, to: defaults)
    }

    func renameVisualPreset(id: String, to name: String) -> Result<Void, VisualPresetEditError> {
        var library = VisualPresetCatalog.restoring(from: defaults)
        return library.rename(id: id, to: name, in: defaults)
    }

    func deleteVisualPreset(id: String) -> Result<Void, VisualPresetEditError> {
        var library = VisualPresetCatalog.restoring(from: defaults)
        return library.delete(id: id, in: defaults)
    }

    func clearAppliedVisualPreset(for mode: StudioVisualMode) {
        var library = VisualPresetCatalog.restoring(from: defaults)
        _ = library.setAppliedID(nil, for: mode, in: defaults)
    }

    func clearAppliedVisualPresets() {
        StudioVisualMode.allCases.forEach { clearAppliedVisualPreset(for: $0) }
    }

    @discardableResult
    func resetVisualPresetLibrary() -> Bool {
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        return library.resetLibrary(in: defaults)
    }

    func setChromeVisible(_ visible: Bool) {
        panel.hasShadow = false
        model.chromeVisible = visible
        applyHiddenInteractionSizeIfNeeded()
        syncPassthroughWindows()
    }

    func resetPreferences() {
        StudioPreferences.reset(in: defaults)
        smoothedStudio = []
        smoothedWave = []
        spectrumState = SpectrumDynamicsState()
        apply(StudioPreferences.standard)
        refreshStudioSpectrum(dt: 0)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopDisplayTimer()
        return true
    }

    var allowsDragForTests: Bool { hitMap.allowsDrag }

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
        panel.ignoresMouseEvents = true
        panel.minSize = StudioFrame.minimumSize
        panel.contentMinSize = StudioFrame.minimumSize
        let root = StudioContentView(
            spike: spike,
            model: model,
            savePreferences: { [weak self] in
                self?.savePreferences()
            },
            openSettings: { [weak self] in
                self?.openSettings?()
            },
            setChromeVisible: { [weak self] visible in
                self?.setChromeVisible(visible)
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
        hitMap.onWindowFrameChanged = { [weak self] in
            self?.syncPassthroughWindows()
        }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.ownsEventWindow(event.window) else { return }
                self.model.pointerDown = event.type == .leftMouseDown
            }
            return event
        }
        if model.prefs.window.restorePosition == false {
            NSWindow.removeFrame(usingName: StudioWindowStorage.frameAutosaveName)
        }
        if panel.setFrameAutosaveName(StudioWindowStorage.frameAutosaveName) == false || model.prefs.window.restorePosition == false {
            panel.center()
        }
        applyWindowPreferences()
        installMenuTracking()
        clampOntoVisibleScreen()
        applyWindowMode()
        let storedPlayer = UserDefaults.standard.string(forKey: PlayerSelectionKey.selected) ?? ""
        model.playerID = players.contains(where: { $0.id == storedPlayer }) ? storedPlayer : ""
        if let player = selectedPlayer() {
            let gate = effectiveAvailability(of: player)
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

    /// Applies drag and resize permissions right away. The window mode has its own path.
    func applyWindowPreferences() {
        let window = model.prefs.window
        hitMap.allowsDrag = window.allowsDrag
        if window.allowsResize {
            panel.styleMask.insert(.resizable)
        } else {
            panel.styleMask.remove(.resizable)
        }
        syncPassthroughWindows()
    }

    /// Back to the default size, centered on the screen the window is on.
    func resetWindowFrame() {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(origin: .zero, size: StudioFrame.defaultSize)
        panel.setFrame(StudioFrame.centeredDefault(in: visible), display: panel.isVisible)
        clampOntoVisibleScreen()
        syncPassthroughWindows()
    }

    private func applyWindowMode() {
        let frame = panel.frame
        let visible = panel.isVisible
        panel.isFloatingPanel = StudioWindowBehavior.isFloatingPanel(for: model.prefs.windowMode)
        panel.level = StudioWindowBehavior.level(for: model.prefs.windowMode)
        panel.collectionBehavior = StudioWindowBehavior.collectionBehavior(for: model.prefs.windowMode)
        panel.hidesOnDeactivate = false
        if panel.frame != frame {
            panel.setFrame(frame, display: visible)
        }
        if visible {
            panel.orderFrontRegardless()
        }
        syncPassthroughWindows()
    }

    private func apply(_ preferences: StudioPreferences) {
        model.prefs = preferences
        let count = preferences.spectrum.barCount
        if model.studioSpectrum.count != count {
            model.studioSpectrum = Array(repeating: 0, count: count)
        }
        applyWindowMode()
        applyWindowPreferences()
    }

    func currentPreferences() -> StudioPreferences {
        model.prefs
    }

    private func refreshPointerInside() {
        let frame = interactionPanel?.frame ?? .zero
        let inside = StudioChrome.pointerIsInside(windowFrame: frame, cursor: NSEvent.mouseLocation)
        if model.pointerInside != inside {
            model.pointerInside = inside
        }
    }

    private func refreshStudioSpectrum(dt: Double) {
        let prefs = model.prefs
        switch prefs.mode {
        case .spectrum:
            let levels = SpectrumBands.levels(
                binMagnitudes: model.snapshot.binMagnitudes,
                sampleRate: model.snapshot.sampleRate,
                count: prefs.spectrum.barCount,
                layout: prefs.spectrum.layout
            )
            spectrumState = SpectrumDynamics.step(
                state: spectrumState,
                target: levels,
                dt: dt,
                settings: prefs.spectrum.dynamics
            )
            model.studioSpectrum = spectrumState.levels
            model.spectrumPeaks = prefs.spectrum.peakHold ? spectrumState.peaks : []
        case .orbit:
            let count = prefs.orbit.bandCount
            let levels = SpectrumBands.levels(
                binMagnitudes: model.snapshot.binMagnitudes,
                sampleRate: model.snapshot.sampleRate,
                count: count
            )
            smoothedStudio = SpectrumBands.displayMix(
                current: smoothedStudio,
                toward: levels,
                count: count,
                smoothing: Float(prefs.orbit.smoothing)
            )
            model.studioSpectrum = smoothedStudio
            model.spectrumPeaks = []
        case .waveform:
            break
        }
    }

    private func selectedPlayer() -> (any PlayerControlling)? {
        players.first { $0.id == model.playerID }
    }

    private func startPlaybackTimer() {
        guard playbackTimer == nil else { return }
        refreshPlayback()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
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
        let gate = effectiveAvailability(of: player)
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

    /// Installed and running first, then the cached Automation permission. Nothing here can block the main thread.
    /// A missing or not-yet-granted permission starts a background check without a prompt.
    private func effectiveAvailability(of player: any PlayerControlling) -> PlayerAvailability {
        let base = player.availability()
        guard base == .ready else {
            permissionCache[player.id] = nil
            return base
        }
        let cached = permissionCache[player.id]
        if cached != .granted {
            checkPermission(of: player)
        }
        return cached?.availability ?? .checking
    }

    private func checkPermission(of player: any PlayerControlling) {
        let id = player.id
        let bundleIdentifier = player.bundleIdentifier
        guard permissionChecks.contains(id) == false else { return }
        permissionChecks.insert(id)
        Task { @MainActor [weak self] in
            let result = await Task.detached {
                AutomationPermissionCheck.determine(bundleIdentifier: bundleIdentifier, askUserIfNeeded: false)
            }.value
            guard let self else { return }
            self.permissionChecks.remove(id)
            let changed = self.permissionCache[id] != result
            self.permissionCache[id] = result
            if changed, self.selectedPlayer()?.id == id {
                self.refreshPlayback()
            }
        }
    }

    private func applyPlayback(_ result: PlayerCommandResult) {
        switch result {
        case .state(let state):
            model.playbackAvailability = .ready
            model.playbackState = state
            model.playbackDetail = ""
        case .unavailable(let availability):
            if availability == .automationDenied || availability == .automationNotRequested, let id = selectedPlayer()?.id {
                permissionCache[id] = availability == .automationDenied ? .denied : .notRequested
            }
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
        case .checking:
            return "Checking Automation access\u{2026}"
        case .automationNotRequested:
            return "Audune has not been allowed to control this player yet. Use Request Access in Settings > Playback."
        case .automationDenied:
            return "Automation was denied. Allow Audune in System Settings > Privacy & Security > Automation."
        case .failed(let message):
            return message
        }
    }

    private func refreshWaveform() {
        guard model.prefs.mode == .waveform else { return }
        smoothedWave = WaveformPath.mix(
            current: smoothedWave,
            toward: model.snapshot.waveform,
            smoothing: Float(model.prefs.waveform.smoothing)
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
        syncPassthroughWindows()
    }

    private func startDisplayTimer() {
        guard timer == nil else { return }
        lastTick = nil
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
        let now = ContinuousClock.now
        let dt = lastTick.map { Double((now - $0).components.seconds) + Double((now - $0).components.attoseconds) / 1e18 } ?? 0
        lastTick = now
        model.snapshot = spike.snapshots.load()
        refreshPointerInside()
        refreshStudioSpectrum(dt: dt)
        refreshWaveform()
    }

    func placeForTests(_ frame: CGRect) {
        panel.setFrame(frame, display: false)
        syncPassthroughWindows()
    }

    func inspectWindowNumberForTests() -> Int {
        panel.windowNumber
    }

    func inspectInteractionWindowNumberForTests() -> Int {
        interactionPanel?.windowNumber ?? 0
    }

    func stackAboveForTests() {
        panel.orderFrontRegardless()
        edgePanels.forEach { $0.orderFrontRegardless() }
        interactionPanel?.orderFrontRegardless()
    }

    func setLevelForTests(_ level: NSWindow.Level) {
        panel.level = level
        interactionPanel?.level = level
        edgePanels.forEach { $0.level = level }
    }

    func inspectPassthroughForTests() -> StudioPassthroughInspection {
        StudioPassthroughInspection(
            visualIgnoresMouseEvents: panel.ignoresMouseEvents,
            interactionVisible: interactionPanel?.isVisible ?? false,
            interactionFrame: interactionPanel?.frame ?? .zero,
            interactionIgnoresMouseEvents: interactionPanel?.ignoresMouseEvents ?? false,
            interactionLevel: interactionPanel?.level ?? panel.level,
            interactionCollectionBehavior: interactionPanel?.collectionBehavior ?? [],
            edgeFrames: edgePanels.map(\.frame)
        )
    }

    private func ownsEventWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window === panel || window === interactionPanel { return true }
        return edgePanels.contains { $0 === window }
    }

    private var passthroughSyncDepth = 0
    private var passthroughSyncAgain = false

    private func noteInteractionSize(_ size: CGSize) {
        guard model.chromeVisible else { return }
        guard size.width.isFinite, size.height.isFinite, size.width > 1, size.height > 1 else { return }
        guard abs(size.width - interactionContentSize.width) > 0.5 || abs(size.height - interactionContentSize.height) > 0.5 else { return }
        interactionContentSize = size
        syncPassthroughWindows()
    }

    private func syncPassthroughWindows() {
        guard didShutdown == false else { return }
        if passthroughSyncDepth > 0 {
            passthroughSyncAgain = true
            return
        }
        passthroughSyncDepth = 1
        var passes = 0
        repeat {
            passthroughSyncAgain = false
            performPassthroughSync()
            passes += 1
        } while passthroughSyncAgain && passes < 3
        passthroughSyncDepth = 0
    }

    private func performPassthroughSync() {
        panel.ignoresMouseEvents = true
        applyHiddenInteractionSizeIfNeeded()
        let interaction = ensureInteractionPanel()
        matchVisualBehavior(interaction)
        let frame = StudioPassthroughLayout.interactionFrame(visual: panel.frame, contentSize: interactionContentSize)
        if interaction.frame.equalTo(frame) == false {
            interaction.setFrame(frame, display: false)
        }
        if panel.isVisible {
            if interaction.isVisible == false {
                interaction.orderFrontRegardless()
            }
        } else {
            interaction.orderOut(nil)
        }
        syncEdgePanels()
    }

    private func syncEdgePanels() {
        let bands = model.prefs.window.allowsResize
            ? StudioPassthroughLayout.edgeBands(in: panel.frame, margin: StudioWindowBehavior.resizeMargin)
            : []
        if bands.isEmpty {
            edgePanels.forEach { $0.orderOut(nil) }
            return
        }
        if edgePanels.count != bands.count {
            edgePanels.forEach { $0.orderOut(nil) }
            edgePanels = bands.map { makeEdgePanel($0.edge) }
        }
        for (edgePanel, band) in zip(edgePanels, bands) {
            edgePanel.edge = band.edge
            matchVisualBehavior(edgePanel)
            if edgePanel.frame.equalTo(band.frame) == false {
                edgePanel.setFrame(band.frame, display: false)
            }
            if panel.isVisible {
                if edgePanel.isVisible == false {
                    edgePanel.orderFrontRegardless()
                }
            } else {
                edgePanel.orderOut(nil)
            }
        }
        if panel.isVisible, let interactionPanel, interactionPanel.isVisible == false {
            interactionPanel.orderFrontRegardless()
        }
    }

    private func ensureInteractionPanel() -> NSPanel {
        if let interactionPanel { return interactionPanel }
        let interaction = makeAuxiliaryPanel()
        interaction.title = "Audune Studio Controls"
        let root = StudioInteractionRoot(
            spike: spike,
            model: model,
            savePreferences: { [weak self] in self?.savePreferences() },
            openSettings: { [weak self] in self?.openSettings?() },
            togglePlayback: { [weak self] in self?.togglePlayback() },
            drag: { [weak self] in self?.dragVisualPanel() },
            summon: { [weak self] in self?.model.pointerInside = true },
            onContentSize: { [weak self] size in self?.noteInteractionSize(size) }
        )
        let host = StudioInteractionHostingView(rootView: root)
        host.onPointerInside = { [weak self] inside in
            self?.model.pointerInside = inside
        }
        interaction.contentView = host
        interactionHost = host
        interactionPanel = interaction
        return interaction
    }

    private func makeEdgePanel(_ edge: StudioResizeEdge) -> StudioEdgePanel {
        let edgePanel = StudioEdgePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureAuxiliary(edgePanel)
        edgePanel.edge = edge
        edgePanel.title = "Audune Studio Resize"
        let view = StudioEdgeView()
        view.onMouseDown = { [weak self, weak edgePanel] in
            guard let self, let edgePanel else { return }
            self.model.pointerDown = true
            StudioWindowResize.track(
                window: self.panel,
                eventWindow: edgePanel,
                edge: edgePanel.edge,
                minimum: StudioFrame.minimumSize
            ) { [weak self] in
                self?.syncPassthroughWindows()
            }
            self.model.pointerDown = false
        }
        edgePanel.contentView = view
        return edgePanel
    }

    private func makeAuxiliaryPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureAuxiliary(panel)
        return panel
    }

    private func configureAuxiliary(_ panel: NSPanel) {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isExcludedFromWindowsMenu = true
        panel.becomesKeyOnlyIfNeeded = false
    }

    private func matchVisualBehavior(_ window: NSPanel) {
        window.isFloatingPanel = panel.isFloatingPanel
        window.level = panel.level
        window.collectionBehavior = panel.collectionBehavior
        window.hidesOnDeactivate = false
    }

    private func dragVisualPanel() {
        model.pointerDown = true
        StudioWindowDrag.track(panel) { [weak self] in
            self?.syncPassthroughWindows()
        }
        model.pointerDown = false
    }

    private func orderOutPassthroughWindows() {
        interactionPanel?.orderOut(nil)
        edgePanels.forEach { $0.orderOut(nil) }
    }

    private func applyHiddenInteractionSizeIfNeeded() {
        guard model.chromeVisible == false else { return }
        interactionContentSize = StudioChrome.hiddenContentSize(
            region: model.prefs.window.summonRegion,
            visualWidth: panel.frame.width
        )
    }

    private func clearInteractionState() {
        model.pointerInside = false
        model.pointerDown = false
        model.menuTracking = false
    }

    private func installMenuTracking() {
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.menuTracking = true
            }
        })
        menuObservers.append(center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.menuTracking = false
            }
        })
    }
}
#endif
