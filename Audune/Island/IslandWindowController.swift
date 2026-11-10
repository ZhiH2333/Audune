#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

#if DEBUG
struct IslandWindowInspection: Equatable {
    var frame: NSRect
    var isVisible: Bool
    var state: IslandPresentationState
    var level: NSWindow.Level
    var isFloatingPanel: Bool
    var hidesOnDeactivate: Bool
    var collectionBehavior: NSWindow.CollectionBehavior
    var isMovable: Bool
    var isMovableByWindowBackground: Bool
    var isFullScreen: Bool
    var isOpaque: Bool
    var backgroundAlpha: CGFloat
    var hasShadow: Bool
    var ignoresMouseEvents: Bool
    var hostIsOpaque: Bool
    var isTimerRunning: Bool
    var unsupportedReason: IslandUnsupportedReason?
}
#endif

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    private var pointerTracking: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearLayerBackground()
    }

    override func layout() {
        super.layout()
        clearLayerBackground()
    }

    private func clearLayerBackground() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking {
            removeTrackingArea(pointerTracking)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandWindowController: NSObject, NSWindowDelegate {
    private let spike: ProcessTapSpike
    private let defaults: UserDefaults
    private let screenProvider: () -> [IslandScreenDescriptor]
    private let allowsOrderFront: Bool
    private let haptics: any IslandHapticPerforming
    private let makeLyricsStore: () throws -> LocalLyricsStore
    private let makeLyricsProvider: () -> any OnlineLyricsProviding
    private var hapticToken = 0
    let model = IslandModel()
    /// Tests may inject a private instance.
    let nowPlaying: NowPlayingService
    private let panel: NSPanel
    private var stateContext = IslandStateContext(state: .compact)
    private var timer: Timer?
    private var collapseTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?
    private var timingGeneration = 0
    private var saveTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var pointerMonitor: Any?
    private var keyMonitor: Any?
    private var smoothedCompact: [Float] = []
    private var smoothedExpanded: [Float] = []
    private var smoothedWaveform: [Float] = []
    private var spectrumState = SpectrumDynamicsState()
    private var lastTick: ContinuousClock.Instant?
    private var didShutdown = false
    private var lyricsRuntimeDemand: UUID?
    private var lyricsStore: LocalLyricsStore?
    private var lyricsManager: LyricsManager?
    private var currentLyricsTrackKey: LyricsTrackKey?
    private var lyricsFilePanelOpen = false
    /// Bumps when a new panel frame animation starts so stale completion handlers cannot flip chrome early.
    private var frameAnimationGeneration = 0
    /// Session-only gate for startup checkboxes. Does not persist into `IslandPreferences`.
    private(set) var allowsLaunchPresentation = true

    var openStudio: (() -> Void)?
    var openSettings: (() -> Void)?

    /// True when this surface alone needs the MediaRemote listener.
    var wantsNowPlayingListening: Bool {
        didShutdown == false
            && isEffectivelyEnabled
            && model.isSupported
            && model.prefs.nowPlayingEnabled
    }

    static func systemScreens() -> [IslandScreenDescriptor] {
        NSScreen.screens.enumerated().map { index, screen in
            IslandScreenDescriptor.from(screen, index: index)
        }
    }

    nonisolated static func collectionBehavior(showsInFullScreen: Bool) -> NSWindow.CollectionBehavior {
        if showsInFullScreen {
            return [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        }
        return [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    init(
        spike: ProcessTapSpike,
        defaults: UserDefaults = .standard,
        nowPlaying: NowPlayingService? = nil,
        lyricsStoreFactory: (() throws -> LocalLyricsStore)? = nil,
        lyricsProviderFactory: (() -> any OnlineLyricsProviding)? = nil,
        screenProvider: @escaping () -> [IslandScreenDescriptor] = IslandWindowController.systemScreens,
        allowsOrderFront: Bool = true,
        /// When false, load prefs and configure the panel but defer screen evaluation until
        /// `activatePresentation()` so startup surfaces can run before the first orderFront.
        activateOnInit: Bool = true,
        haptics: any IslandHapticPerforming = SystemIslandHaptics()
    ) {
        self.spike = spike
        self.defaults = defaults
        self.nowPlaying = nowPlaying ?? NowPlayingService()
        self.makeLyricsStore = lyricsStoreFactory ?? { try LocalLyricsStore.applicationStore() }
        self.makeLyricsProvider = lyricsProviderFactory ?? {
            LyricsRoutingController.shared.makeProvider()
        }
        self.screenProvider = screenProvider
        self.allowsOrderFront = allowsOrderFront
        self.haptics = haptics
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 252, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        model.prefs = IslandPreferences.load(from: defaults)
        updateSharedVisuals(StudioPreferences.load(from: defaults))
        model.compactLevels = Array(repeating: 0, count: model.prefs.compactBarCountPerSide)
        configurePanel()
        if activateOnInit {
            evaluateScreensAndApply(animated: false)
        }
    }

    /// Runs geometry evaluation and presents or hides the Island according to current prefs.
    func activatePresentation() {
        evaluateScreensAndApply(animated: false)
    }

    /// Startup-only presentation gate. Does not write `island.isEnabled`.
    func setAllowsLaunchPresentation(_ allowed: Bool) {
        allowsLaunchPresentation = allowed
    }

    /// True when the Island enable preference and the launch presentation gate both allow showing.
    var isEffectivelyEnabled: Bool {
        model.prefs.isEnabled && allowsLaunchPresentation
    }

    var isVisible: Bool {
        return panel.isVisible || (allowsOrderFront == false && model.state.isVisible && model.isSupported)
    }

    func shutdown() {
        guard didShutdown == false else { return }
        didShutdown = true
        timingGeneration += 1
        hapticToken += 1
        collapseTask?.cancel()
        collapseTask = nil
        expandTask?.cancel()
        expandTask = nil
        saveTask?.cancel()
        saveTask = nil
        lyricsManager?.deactivate()
        lyricsManager = nil
        model.nowPlaying = .idle
        model.isFullScreen = false
        lyricsRuntimeDemand = nil
        nowPlaying.stop()
        stopDisplayTimer()
        updateKeyMonitor(active: false)
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
        panel.orderOut(nil)
        stateContext = IslandStateContext(state: .disabled)
        model.state = .disabled
    }

    func updateSharedVisuals(_ preferences: StudioPreferences) {
        if preferences.spectrum != model.spectrum {
            // Spectrum preset replace must clear held peaks that used the old layout.
            spectrumState = SpectrumDynamicsState()
            model.expandedPeaks = []
        }
        if preferences.orbit.bandCount != model.orbit.bandCount {
            smoothedExpanded = []
        }
        model.appearance = preferences.appearance
        model.spectrum = preferences.spectrum
        model.waveform = preferences.waveform
        model.orbit = preferences.orbit
        refreshVisuals()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            allowsLaunchPresentation = true
        }
        model.prefs.isEnabled = enabled
        savePreferences()
        evaluateScreensAndApply(animated: true)
    }

    func toggleEnabled() {
        // Launch checkbox may suppress presentation without clearing the saved enable switch.
        if allowsLaunchPresentation == false && model.prefs.isEnabled {
            allowsLaunchPresentation = true
            evaluateScreensAndApply(animated: true)
            return
        }
        setEnabled(model.prefs.isEnabled == false)
    }

    func selectMode(_ mode: StudioVisualMode) {
        model.prefs.mode = mode
        savePreferences()
        refreshVisuals()
    }

    func setCompactBarCountPerSide(_ count: Int) {
        let normalized = IslandPreferences.compactBarCounts.contains(count)
            ? count
            : IslandPreferences.standard.compactBarCountPerSide
        model.prefs.compactBarCountPerSide = normalized
        savePreferences()
        refreshVisuals()
    }

    func setTargetScreenID(_ id: String) {
        model.prefs.targetScreenID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        savePreferences()
        evaluateScreensAndApply(animated: false)
    }

    func expand() {
        applyEvent(.expandRequested, animated: true)
    }

    func collapse() {
        applyEvent(.collapseRequested, animated: true)
    }

    func toggleFullScreenView() {
        guard stateContext.state.isExpandedOrPinned, let geometry = model.geometry else { return }
        model.isFullScreen.toggle()
        stateContext.exitedAt = nil
        if model.isFullScreen {
            collapseTask?.cancel()
            collapseTask = nil
        } else {
            model.fullScreenScene = .visualizer
            lyricsManager?.deactivate()
            setActiveLyricsLineIndex(nil)
        }
        syncNowPlayingListening()
        if model.isFullScreen, model.fullScreenScene == .lyrics {
            refreshLyricsForCurrentTrack()
        }
        if timer != nil {
            startDisplayTimer()
        }
        updatePanelFrame(
            model.isFullScreen ? geometry.screenFrame : geometry.expandedPlayerFrame(),
            expanding: model.isFullScreen,
            targetExpandedChrome: true,
            animated: allowsOrderFront,
            hapticPattern: nil,
            hapticToken: hapticToken
        )
    }

    func openFullScreenLyrics() {
        guard stateContext.state.isExpandedOrPinned,
              let geometry = model.geometry,
              model.prefs.lyricsEnabled
        else { return }
        model.isFullScreen = true
        model.fullScreenScene = .lyrics
        stateContext.exitedAt = nil
        collapseTask?.cancel()
        collapseTask = nil
        syncNowPlayingListening()
        refreshLyricsForCurrentTrack()
        if timer != nil {
            startDisplayTimer()
        }
        updatePanelFrame(
            geometry.screenFrame,
            expanding: true,
            targetExpandedChrome: true,
            animated: allowsOrderFront,
            hapticPattern: nil,
            hapticToken: hapticToken
        )
    }

    func setFullScreenScene(_ scene: IslandFullScreenScene) {
        guard model.isFullScreen else { return }
        guard scene != .lyrics || model.prefs.lyricsEnabled else { return }
        model.fullScreenScene = scene
        syncNowPlayingListening()
        if scene == .lyrics {
            refreshLyricsForCurrentTrack()
        } else {
            lyricsManager?.deactivate()
            setActiveLyricsLineIndex(nil)
        }
        if timer != nil {
            startDisplayTimer()
        }
    }

    func importLyricsFromFile() {
        updateLyricsPresentation()
        guard currentLyricsTrackKey != nil else {
            model.lyricsState = .metadataUnavailable
            return
        }
        guard lyricsFilePanelOpen == false else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "Import Lyrics")
        panel.message = String(localized: "Choose an LRC lyrics file for the current song.")

        lyricsFilePanelOpen = true
        panel.orderOut(nil)
        updateKeyMonitor(active: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.lyricsFilePanelOpen = false
            guard self.didShutdown == false else { return }
            self.updateKeyMonitor(active: self.stateContext.state.isExpandedOrPinned)
            if self.allowsOrderFront,
               self.isEffectivelyEnabled,
               self.stateContext.state.isVisible,
               self.model.isSupported
            {
                self.panel.orderFrontRegardless()
            }
            guard response == .OK, let url = panel.url else { return }
            Task { [weak self] in
                await self?.importLyrics(at: url)
            }
        }
    }

    func importLyrics(at url: URL) async {
        updateLyricsPresentation()
        guard let currentLyricsTrackKey else {
            model.lyricsState = .metadataUnavailable
            return
        }
        do {
            let manager = try resolvedLyricsManager()
            _ = try await manager.importLocal(url: url, for: currentLyricsTrackKey)
            setActiveLyricsLineIndex(nil)
            updateLyricsLinePosition()
        } catch {
            model.lyricsState = .importError(importErrorMessage(error))
        }
    }

    private func importErrorMessage(_ error: Error) -> String {
        guard let importError = error as? LyricsImportError else {
            return error.localizedDescription
        }
        switch importError {
        case .noTimedLines:
            return String(localized: "This LRC file has no timed lyric lines.")
        case .invalidEncoding:
            return String(localized: "This lyrics file uses an unsupported text encoding.")
        case .emptyFile:
            return String(localized: "This lyrics file is empty.")
        case .unreadableFile:
            return String(localized: "Audune could not read this lyrics file.")
        case .storageUnavailable:
            return String(localized: "Audune could not save imported lyrics.")
        case .documentNotFound:
            return String(localized: "The saved lyrics entry could not be found.")
        }
    }

    func chooseLyricsCandidate(_ documentID: UUID) {
        updateLyricsPresentation()
        guard case .ambiguous(let documents) = model.lyricsState,
              let document = documents.first(where: { $0.id == documentID })
        else {
            return
        }
        try? resolvedLyricsManager().selectCandidate(document)
        setActiveLyricsLineIndex(nil)
        updateLyricsLinePosition()
    }

    func deleteLyrics(_ documentID: UUID) {
        updateLyricsPresentation()
        let isCurrentDocument: Bool
        switch model.lyricsState {
        case .local(let document), .found(let document):
            isCurrentDocument = document.id == documentID
        case .ambiguous(let documents):
            isCurrentDocument = documents.contains(where: { $0.id == documentID })
        default:
            isCurrentDocument = false
        }
        guard isCurrentDocument else { return }
        do {
            try resolvedLyricsManager().deleteLocalDocument(documentID)
            updateLyricsLinePosition()
        } catch {
            model.lyricsState = .error(error.localizedDescription)
        }
    }

    func setLyricsOffset(_ seconds: Double) {
        model.prefs.lyricsOffsetSeconds = seconds
        preferencesDidChange()
    }

    func setAutomaticOnlineLyricsEnabled(_ enabled: Bool) {
        model.prefs.automaticOnlineLyricsEnabled = enabled
        savePreferences()
        lyricsManager?.updateAutomaticOnlineEnabled(enabled)
    }

    func setLyricsEnabled(_ enabled: Bool) {
        model.prefs.lyricsEnabled = enabled
        if enabled == false, model.fullScreenScene == .lyrics {
            setFullScreenScene(.visualizer)
        } else {
            syncNowPlayingListening()
        }
        savePreferences()
    }

    private func escapeExpandedPresentation() {
        if model.isFullScreen {
            toggleFullScreenView()
        } else {
            applyEvent(.escapePressed, animated: true)
        }
    }

    func togglePin() {
        applyEvent(.togglePin(at: Date().timeIntervalSinceReferenceDate), animated: true)
    }

    func preferencesDidChange() {
        model.prefs = model.prefs.normalized()
        if model.prefs.lyricsEnabled == false, model.fullScreenScene == .lyrics {
            model.fullScreenScene = .visualizer
            lyricsManager?.deactivate()
            setActiveLyricsLineIndex(nil)
        }
        applyCollectionBehavior()
        evaluateScreensAndApply(animated: false)
        refreshVisuals()
        syncNowPlayingListening()
        updateLyricsLinePosition()
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard Task.isCancelled == false else { return }
            self?.savePreferences()
        }
    }

    func setNowPlayingEnabled(_ enabled: Bool) {
        model.prefs.nowPlayingEnabled = enabled
        savePreferences()
        syncNowPlayingListening()
        // Expanded size no longer depends on Now Playing; only listening/chrome change.
        if let geometry = model.geometry, stateContext.state.isExpandedOrPinned {
            let target = model.isFullScreen ? geometry.screenFrame : geometry.expandedPlayerFrame()
            updatePanelFrame(
                target,
                expanding: false,
                collapsing: false,
                targetExpandedChrome: true,
                animated: false,
                hapticPattern: nil,
                hapticToken: hapticToken
            )
        }
    }

    func savePreferences() {
        saveTask?.cancel()
        saveTask = nil
        model.prefs = model.prefs.normalized()
        model.prefs.save(to: defaults)
    }

    func resetPreferences() {
        IslandPreferences.reset(in: defaults)
        smoothedCompact = []
        smoothedExpanded = []
        smoothedWaveform = []
        model.prefs = IslandPreferences.standard
        applyCollectionBehavior()
        evaluateScreensAndApply(animated: false)
        refreshVisuals()
        syncNowPlayingListening()
    }

    func evaluateScreensAndApply(animated: Bool = false) {
        guard didShutdown == false else { return }
        timingGeneration += 1
        collapseTask?.cancel()
        collapseTask = nil
        expandTask?.cancel()
        expandTask = nil
        let screens = screenProvider()
        model.availableScreens = screens
        let resolution = IslandGeometry.selectScreen(from: screens, target: model.prefs.targetScreenMode)
        switch resolution {
        case .supported(let geometry, let usedFallback):
            model.geometry = geometry
            model.unsupportedReason = nil
            model.usedFallbackScreen = usedFallback
        case .unsupported(let reason):
            model.geometry = nil
            model.unsupportedReason = reason
            model.usedFallbackScreen = false
        }
        applyCollectionBehavior()
        if stateContext.expandArmedAt != nil {
            applyEvent(.hoverTimingCancelled, animated: false)
        }
        applyEvent(
            .availabilityChanged(isEnabled: isEffectivelyEnabled, isSupported: model.isSupported),
            animated: animated
        )
        syncNowPlayingListening()
        rearmHoverIfPointerStillInside()
    }

    private func syncNowPlayingListening() {
        syncLyricsRuntimeDemand()
        nowPlaying.syncDesiredListening(shouldListen: wantsNowPlayingListening)
        refreshNowPlayingSnapshot()
    }

    private func syncLyricsRuntimeDemand() {
        let shouldListenForLyrics = didShutdown == false
            && model.isFullScreen
            && model.fullScreenScene == .lyrics
            && model.prefs.lyricsEnabled
            && isEffectivelyEnabled
            && model.isSupported
        if shouldListenForLyrics, lyricsRuntimeDemand == nil {
            lyricsRuntimeDemand = nowPlaying.acquireRuntimeDemand()
        } else if shouldListenForLyrics == false, let lyricsRuntimeDemand {
            nowPlaying.releaseRuntimeDemand(lyricsRuntimeDemand)
            self.lyricsRuntimeDemand = nil
        }
    }

    func refreshNowPlayingSnapshot() {
        model.nowPlaying = wantsNowPlayingListening || lyricsRuntimeDemand != nil
            ? nowPlaying.snapshot
            : .idle
        if model.isFullScreen, model.fullScreenScene == .lyrics {
            updateLyricsPresentation()
        }
    }

    private func localLyricsStore() throws -> LocalLyricsStore {
        if let lyricsStore { return lyricsStore }
        let store = try makeLyricsStore()
        lyricsStore = store
        return store
    }

    private func resolvedLyricsManager() throws -> LyricsManager {
        if let lyricsManager { return lyricsManager }
        let manager = LyricsManager(
            store: try localLyricsStore(),
            provider: makeLyricsProvider(),
            automaticOnlineEnabled: model.prefs.automaticOnlineLyricsEnabled
        )
        manager.onStateChange = { [weak self] in
            self?.applyLyricsManagerState()
        }
        lyricsManager = manager
        return manager
    }

    private func applyLyricsManagerState() {
        guard let lyricsManager else { return }
        if model.lyricsState != lyricsManager.state {
            model.lyricsState = lyricsManager.state
            setActiveLyricsLineIndex(nil)
        }
        updateLyricsLinePosition()
    }

    private func refreshLyricsForCurrentTrack() {
        currentLyricsTrackKey = nil
        updateLyricsPresentation()
    }

    /// Rebuilds the online provider after the user changes Auto/Manual routing.
    func applyLyricsRoutingSelection(_ selection: LyricsRoutingSelection) {
        LyricsRoutingController.shared.apply(selection)
        lyricsManager?.deactivate()
        lyricsManager = nil
        refreshLyricsForCurrentTrack()
    }

    private func updateLyricsPresentation() {
        let snapshot = nowPlaying.snapshot
        guard snapshot.availability != .unavailable else {
            currentLyricsTrackKey = nil
            lyricsManager?.deactivate()
            model.lyricsState = .nowPlayingUnavailable
            setActiveLyricsLineIndex(nil)
            model.lyricsPositionSeconds = 0
            model.lyricsDisplayPositionSeconds = 0
            return
        }
        guard let trackKey = lyricsTrackKey(from: snapshot) else {
            currentLyricsTrackKey = nil
            lyricsManager?.deactivate()
            model.lyricsState = snapshot.hasTrack ? .metadataUnavailable : .noTrack
            setActiveLyricsLineIndex(nil)
            model.lyricsPositionSeconds = 0
            model.lyricsDisplayPositionSeconds = 0
            return
        }

        if currentLyricsTrackKey != trackKey {
            currentLyricsTrackKey = trackKey
            model.lyricsTrackRevision &+= 1
            setActiveLyricsLineIndex(nil)
        }
        beginLyricsLookup(for: trackKey)
        updateLyricsLinePosition()
    }

    private func lyricsTrackKey(from snapshot: NowPlayingSnapshot) -> LyricsTrackKey? {
        guard snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return nil
        }
        return LyricsTrackKey(
            isrc: nil,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album.isEmpty ? nil : snapshot.album,
            durationSeconds: snapshot.durationSeconds > 0 ? snapshot.durationSeconds : nil
        )
    }

    private func beginLyricsLookup(for trackKey: LyricsTrackKey) {
        do {
            try resolvedLyricsManager().activate(
                trackKey: trackKey,
                automaticOnlineEnabled: model.prefs.automaticOnlineLyricsEnabled
            )
        } catch {
            model.lyricsState = .error(error.localizedDescription)
        }
    }

    private func updateLyricsLinePosition() {
        let snapshot = nowPlaying.snapshot
        let position = LyricsPlaybackClock.position(
            anchor: snapshot.playbackClockAnchor,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            durationSeconds: snapshot.durationSeconds,
            nowUptime: ProcessInfo.processInfo.systemUptime
        )
        let displayPosition = LyricsPlaybackClock.presentationPosition(
            position,
            offsetSeconds: model.prefs.lyricsOffsetSeconds
        )
        model.lyricsPositionSeconds = position
        model.lyricsDisplayPositionSeconds = displayPosition
        guard let document = model.lyricsState.document else {
            setActiveLyricsLineIndex(nil)
            return
        }
        setActiveLyricsLineIndex(LyricsPlaybackClock.activeLineIndex(
            in: document.lines,
            at: displayPosition
        ))
    }

    private func setActiveLyricsLineIndex(_ index: Int?) {
        model.activeLyricsLineIndex = index
    }

    #if DEBUG
    // MARK: Test Entry Points

    func simulatePointerEntered(at timestamp: TimeInterval = 0) {
        applyEvent(.pointerEntered(hoverToExpand: model.prefs.hoverToExpand, at: timestamp), animated: false)
    }

    func simulateExpandTimerFired(now: TimeInterval) {
        applyEvent(.expandTimerFired(now: now), animated: false)
    }

    func simulatePointerExited(at timestamp: TimeInterval) {
        applyEvent(.pointerExited(at: timestamp), animated: false)
    }

    func simulateCollapseTimerFired(now: TimeInterval) {
        applyEvent(.collapseTimerFired(now: now), animated: false)
    }

    func simulateEscapePressed() {
        escapeExpandedPresentation()
    }

    func inspectWindowForTests() -> IslandWindowInspection {
        IslandWindowInspection(
            frame: panel.frame,
            isVisible: isVisible,
            state: model.state,
            level: panel.level,
            isFloatingPanel: panel.isFloatingPanel,
            hidesOnDeactivate: panel.hidesOnDeactivate,
            collectionBehavior: panel.collectionBehavior,
            isMovable: panel.isMovable,
            isMovableByWindowBackground: panel.isMovableByWindowBackground,
            isFullScreen: model.isFullScreen,
            isOpaque: panel.isOpaque,
            backgroundAlpha: panel.backgroundColor?.alphaComponent ?? 1,
            hasShadow: panel.hasShadow,
            ignoresMouseEvents: panel.ignoresMouseEvents,
            hostIsOpaque: (panel.contentView as? IslandHostingView<IslandContentView>)?.isOpaque ?? true,
            isTimerRunning: timer != nil,
            unsupportedReason: model.unsupportedReason
        )
    }

    /// Seeds expanded spectrum dynamics so shared-visual peak reset can be asserted in tests.
    func seedExpandedSpectrumDynamicsForTests(levels: [Float], peaks: [Float]) {
        let count = max(levels.count, peaks.count)
        spectrumState = SpectrumDynamicsState(
            levels: levels,
            peaks: peaks,
            peakAge: Array(repeating: 0.5, count: count)
        )
        model.expandedSpectrum = levels
        model.expandedPeaks = model.spectrum.peakHold ? peaks : []
    }
    #endif

    // MARK: Private Setup & Event Handling

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.title = "Audune Notch Island"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        applyCollectionBehavior()

        let root = IslandContentView(
            spike: spike,
            model: model,
            selectMode: { [weak self] mode in
                self?.selectMode(mode)
            },
            togglePin: { [weak self] in
                self?.togglePin()
            },
            expand: { [weak self] in
                self?.expand()
            },
            collapse: { [weak self] in
                self?.collapse()
            },
            toggleFullScreen: { [weak self] in
                self?.toggleFullScreenView()
            },
            openStudio: { [weak self] in
                self?.openStudio?()
            },
            openSettings: { [weak self] in
                self?.openSettings?()
            },
            toggleNowPlaying: { [weak self] in
                self?.nowPlaying.togglePlayPause()
            },
            previousTrack: { [weak self] in
                self?.nowPlaying.previousTrack()
            },
            nextTrack: { [weak self] in
                self?.nowPlaying.nextTrack()
            },
            setLyricsOffset: { [weak self] seconds in
                self?.setLyricsOffset(seconds)
            },
            seekNowPlaying: { [weak self] seconds in
                self?.nowPlaying.seek(to: seconds)
            },
            selectFullScreenScene: { [weak self] scene in
                self?.setFullScreenScene(scene)
            },
            openFullScreenLyrics: { [weak self] in
                self?.openFullScreenLyrics()
            },
            importLyrics: { [weak self] in
                self?.importLyricsFromFile()
            },
            chooseLyricsCandidate: { [weak self] documentID in
                self?.chooseLyricsCandidate(documentID)
            },
            deleteLyrics: { [weak self] documentID in
                self?.deleteLyrics(documentID)
            },
            retryLyrics: { [weak self] in
                self?.lyricsManager?.retry()
            },
            selectLyricsRouting: { [weak self] selection in
                self?.applyLyricsRoutingSelection(selection)
            }
        )
        let host = IslandHostingView(rootView: root)
        // The panel frame is owned by IslandWindowController. Prevent AppKit's hosting
        // view from resizing the borderless panel when a scene reports a larger ideal size.
        host.sizingOptions = []
        host.onPointerEntered = { [weak self] in
            self?.handleLivePointerEntered()
        }
        host.onPointerExited = { [weak self] in
            self?.handleLivePointerExited()
        }
        panel.contentView = host

        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return }
                let now = Date().timeIntervalSinceReferenceDate
                self.applyEvent(.pointerDownChanged(event.type == .leftMouseDown, at: now), animated: true)
            }
            return event
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateScreensAndApply(animated: false)
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateScreensAndApply(animated: false)
            }
        }
    }

    private func applyCollectionBehavior() {
        panel.collectionBehavior = Self.collectionBehavior(showsInFullScreen: model.prefs.showsInFullScreen)
    }

    private func handleLivePointerEntered() {
        applyEvent(
            .pointerEntered(hoverToExpand: model.prefs.hoverToExpand, at: Date().timeIntervalSinceReferenceDate),
            animated: true
        )
    }

    private func handleLivePointerExited() {
        // When the window resizes from Compact to Expanded, AppKit can rebuild tracking areas and
        // deliver a transient mouseExited while the pointer is still inside the expanded frame.
        if IslandStateMachine.pointerIsInside(windowFrame: panel.frame, cursor: NSEvent.mouseLocation) {
            return
        }
        applyEvent(.pointerExited(at: Date().timeIntervalSinceReferenceDate), animated: true)
    }

    private func applyEvent(_ event: IslandEvent, animated: Bool) {
        guard didShutdown == false else { return }
        let previousState = stateContext.state
        stateContext = IslandStateMachine.reduce(
            context: stateContext,
            event: event,
            collapseDelay: model.prefs.collapseDelaySeconds,
            expandDelay: model.prefs.expandDelaySeconds
        )
        model.state = stateContext.state
        if stateContext.state.isExpandedOrPinned == false {
            let wasFullScreen = model.isFullScreen
            model.isFullScreen = false
            model.fullScreenScene = .visualizer
            lyricsManager?.deactivate()
            setActiveLyricsLineIndex(nil)
            if wasFullScreen {
                // Collapsing the Island tears down the fullscreen surface, so the
                // Lyrics runtime demand must be released with it.
                syncNowPlayingListening()
            }
        }
        model.pointerInside = stateContext.pointerInside
        model.pointerDown = stateContext.pointerDown
        model.hoverArmed = stateContext.state == .compact && stateContext.expandArmedAt != nil

        scheduleCollapseTimerIfNeeded()
        scheduleExpandTimerIfNeeded()

        guard stateContext.state != .disabled, let geometry = model.geometry else {
            frameAnimationGeneration += 1
            model.showsExpandedChrome = false
            stopDisplayTimer()
            updateKeyMonitor(active: false)
            panel.orderOut(nil)
            return
        }

        let targetFrame: NSRect
        if stateContext.state.isExpandedOrPinned {
            targetFrame = model.isFullScreen ? geometry.screenFrame : geometry.expandedPlayerFrame()
        } else {
            targetFrame = geometry.compactFrame
        }
        let expanding = stateContext.state.isExpandedOrPinned && previousState == .compact
        let collapsing = stateContext.state == .compact && previousState.isExpandedOrPinned
        let shouldAnimate = animated && (expanding || collapsing) && allowsOrderFront
        let hapticPattern = IslandHapticCue.pattern(
            from: previousState,
            to: stateContext.state,
            strength: model.prefs.hapticStrength
        )
        if hapticPattern != nil {
            hapticToken += 1
        }
        updatePanelFrame(
            targetFrame,
            expanding: expanding,
            collapsing: collapsing,
            targetExpandedChrome: stateContext.state.isExpandedOrPinned,
            animated: shouldAnimate,
            hapticPattern: hapticPattern,
            hapticToken: hapticToken
        )

        if allowsOrderFront && lyricsFilePanelOpen == false && panel.isVisible == false {
            panel.orderFrontRegardless()
        }
        startDisplayTimer()
        updateKeyMonitor(active: stateContext.state.isExpandedOrPinned)
    }

    private func scheduleCollapseTimerIfNeeded() {
        collapseTask?.cancel()
        collapseTask = nil
        guard stateContext.state == .expanded,
              model.isFullScreen == false,
              stateContext.pointerInside == false,
              stateContext.pointerDown == false,
              let exitedAt = stateContext.exitedAt
        else {
            return
        }
        let delay = model.prefs.collapseDelaySeconds
        let generation = timingGeneration
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard Task.isCancelled == false, let self, self.timingGeneration == generation else { return }
            if self.allowsOrderFront,
               IslandStateMachine.pointerIsInside(windowFrame: self.panel.frame, cursor: NSEvent.mouseLocation)
            {
                self.applyEvent(
                    .pointerEntered(
                        hoverToExpand: self.model.prefs.hoverToExpand,
                        at: Date().timeIntervalSinceReferenceDate
                    ),
                    animated: true
                )
                return
            }
            self.applyEvent(.collapseTimerFired(now: exitedAt + delay), animated: true)
        }
    }

    private func scheduleExpandTimerIfNeeded() {
        expandTask?.cancel()
        expandTask = nil
        guard stateContext.state == .compact,
              stateContext.pointerInside,
              stateContext.pointerDown == false,
              let armedAt = stateContext.expandArmedAt
        else {
            return
        }
        let delay = model.prefs.expandDelaySeconds
        let generation = timingGeneration
        expandTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard Task.isCancelled == false, let self, self.timingGeneration == generation else { return }
            if self.allowsOrderFront,
               IslandStateMachine.pointerIsInside(windowFrame: self.panel.frame, cursor: NSEvent.mouseLocation) == false
            {
                self.applyEvent(.pointerExited(at: Date().timeIntervalSinceReferenceDate), animated: true)
                return
            }
            self.applyEvent(.expandTimerFired(now: armedAt + delay), animated: true)
        }
    }

    private func rearmHoverIfPointerStillInside() {
        guard allowsOrderFront,
              stateContext.state == .compact,
              model.prefs.hoverToExpand,
              IslandStateMachine.pointerIsInside(windowFrame: panel.frame, cursor: NSEvent.mouseLocation)
        else {
            return
        }
        applyEvent(
            .pointerEntered(hoverToExpand: true, at: Date().timeIntervalSinceReferenceDate),
            animated: true
        )
    }

    private func updatePanelFrame(
        _ targetFrame: CGRect,
        expanding: Bool,
        collapsing: Bool = false,
        targetExpandedChrome: Bool,
        animated: Bool,
        hapticPattern: NSHapticFeedbackManager.FeedbackPattern?,
        hapticToken token: Int
    ) {
        frameAnimationGeneration += 1
        let generation = frameAnimationGeneration

        guard panel.frame != targetFrame else {
            model.showsExpandedChrome = targetExpandedChrome
            performHaptic(hapticPattern, token: token)
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var duration = animated
            ? IslandMotion.transitionSeconds(
                expanding: expanding,
                reduceMotion: reduceMotion,
                followsReduceMotion: model.prefs.followsReduceMotion,
                speed: model.prefs.animationSpeed
            )
            : 0
        // Now Playing expands much wider; only expand gets extra settle time. Collapse stays snappy.
        if duration > 0, model.prefs.nowPlayingEnabled, expanding {
            duration *= 1.25
        }

        if expanding || collapsing == false {
            model.showsExpandedChrome = targetExpandedChrome
        }
        // Collapsing: keep Expanded chrome until the frame finishes shrinking.

        if duration > 0 {
            let pace = IslandMotion.framePace(expanding: expanding, duration: duration)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = Self.timingFunction(for: pace)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: panel.isVisible)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.frameAnimationGeneration == generation else { return }
                    self.model.showsExpandedChrome = targetExpandedChrome
                    self.performHaptic(hapticPattern, token: token)
                }
            }
        } else {
            model.showsExpandedChrome = targetExpandedChrome
            panel.setFrame(targetFrame, display: panel.isVisible)
            performHaptic(hapticPattern, token: token)
        }
    }

    private static func timingFunction(for pace: IslandFramePace) -> CAMediaTimingFunction {
        switch pace {
        case .immediate, .collapseSettle:
            return CAMediaTimingFunction(name: .easeIn)
        case .expandSettle:
            let points = IslandMotion.expandSettleControlPoints
            return CAMediaTimingFunction(controlPoints: points.0, points.1, points.2, points.3)
        }
    }

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern?, token: Int) {
        guard let pattern, token == hapticToken, stateContext.state == .expanded, didShutdown == false else { return }
        haptics.perform(pattern)
    }

    @discardableResult
    func handleKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []) -> Bool {
        if keyCode == 53 {
            escapeExpandedPresentation()
            return true
        }
        guard model.isFullScreen, lyricsFilePanelOpen == false else { return false }
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch keyCode {
        case 49 where flags.isEmpty:
            // Space: Play / Pause
            guard model.nowPlaying.hasTrack, model.nowPlaying.availability == .listening else {
                return false
            }
            nowPlaying.togglePlayPause()
            refreshNowPlayingSnapshot()
            return true
        case 123 where flags.subtracting([.numericPad, .function]).isEmpty:
            // Left arrow: Seek -5s
            guard model.nowPlaying.seekSupported,
                  model.nowPlaying.durationSeconds.isFinite,
                  model.nowPlaying.durationSeconds > 0
            else { return false }
            nowPlaying.seek(to: max(0, model.lyricsPositionSeconds - 5))
            refreshNowPlayingSnapshot()
            return true
        case 124 where flags.subtracting([.numericPad, .function]).isEmpty:
            // Right arrow: Seek +5s
            guard model.nowPlaying.seekSupported,
                  model.nowPlaying.durationSeconds.isFinite,
                  model.nowPlaying.durationSeconds > 0
            else { return false }
            nowPlaying.seek(to: min(model.nowPlaying.durationSeconds, model.lyricsPositionSeconds + 5))
            refreshNowPlayingSnapshot()
            return true
        case 37 where flags == .command:
            // Command+L: Toggle Visualizer / Lyrics scene
            guard model.prefs.lyricsEnabled else { return false }
            setFullScreenScene(model.fullScreenScene == .lyrics ? .visualizer : .lyrics)
            return true
        default:
            return false
        }
    }

    private func updateKeyMonitor(active: Bool) {
        if active {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    self?.handleKeyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags) ?? false
                }
                return handled ? nil : event
            }
        } else if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private var desiredTimerInterval: TimeInterval {
        model.isFullScreen && model.fullScreenScene == .lyrics ? (1.0 / 60.0) : (1.0 / 30.0)
    }

    private func startDisplayTimer() {
        let interval = desiredTimerInterval
        if let existing = timer {
            guard abs(existing.timeInterval - interval) > 0.000_5 else { return }
            existing.invalidate()
            self.timer = nil
        }
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
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
        if model.prefs.nowPlayingEnabled || lyricsRuntimeDemand != nil {
            model.nowPlaying = nowPlaying.snapshot
        }
        if model.isFullScreen, model.fullScreenScene == .lyrics {
            updateLyricsPresentation()
        }
        if allowsOrderFront,
           stateContext.state == .expanded,
           stateContext.pointerInside,
           stateContext.pointerDown == false,
           IslandStateMachine.pointerIsInside(windowFrame: panel.frame, cursor: NSEvent.mouseLocation) == false
        {
            applyEvent(.pointerExited(at: Date().timeIntervalSinceReferenceDate), animated: true)
        }
        refreshVisuals(dt: dt)
    }

    private func refreshVisuals(dt: Double = 0) {
        let snapshot = model.snapshot
        let silent = snapshot.isSilent
        let compactCount = model.prefs.compactBarCountPerSide
        let compactLive = SpectrumBands.levels(
            binMagnitudes: snapshot.binMagnitudes,
            sampleRate: snapshot.sampleRate,
            count: compactCount
        )
        let compactTarget = silent ? Array(repeating: Float(0), count: compactCount) : compactLive
        smoothedCompact = SpectrumBands.displayMix(
            current: smoothedCompact,
            toward: compactTarget,
            count: compactCount,
            smoothing: 0.25,
            dt: dt
        )
        model.compactLevels = smoothedCompact

        guard model.state.isExpandedOrPinned else { return }
        switch model.prefs.mode {
        case .spectrum:
            let live = SpectrumBands.levels(
                binMagnitudes: snapshot.binMagnitudes,
                sampleRate: snapshot.sampleRate,
                count: model.spectrum.barCount,
                layout: model.spectrum.layout
            )
            let target = silent ? Array(repeating: Float(0), count: live.count) : live
            spectrumState = SpectrumDynamics.step(
                state: spectrumState,
                target: target,
                dt: dt,
                settings: model.spectrum.dynamics
            )
            model.expandedSpectrum = spectrumState.levels
            model.expandedPeaks = model.spectrum.peakHold ? spectrumState.peaks : []

        case .orbit:
            let count = model.orbit.bandCount
            let live = SpectrumBands.levels(
                binMagnitudes: snapshot.binMagnitudes,
                sampleRate: snapshot.sampleRate,
                count: count
            )
            let target = silent ? Array(repeating: Float(0), count: count) : live
            smoothedExpanded = SpectrumBands.displayMix(
                current: smoothedExpanded,
                toward: target,
                count: count,
                smoothing: Float(model.orbit.smoothing),
                dt: dt
            )
            model.expandedSpectrum = smoothedExpanded
            model.expandedPeaks = []

        case .waveform:
            let live = snapshot.waveform
            let target = silent ? Array(repeating: Float(0), count: live.count) : live
            smoothedWaveform = WaveformPath.mix(
                current: smoothedWaveform,
                toward: target,
                smoothing: Float(model.waveform.smoothing),
                dt: dt
            )
            model.expandedWaveform = smoothedWaveform
            model.expandedPeaks = []
        }
    }
}
#endif
