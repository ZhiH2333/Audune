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
    private var currentLyricsTrackKey: LyricsTrackKey?
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
            setActiveLyricsLineIndex(nil)
        }
        syncNowPlayingListening()
        if model.isFullScreen, model.fullScreenScene == .lyrics {
            refreshLyricsForCurrentTrack()
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

    func setFullScreenScene(_ scene: IslandFullScreenScene) {
        guard model.isFullScreen else { return }
        model.fullScreenScene = scene
        syncNowPlayingListening()
        if scene == .lyrics {
            refreshLyricsForCurrentTrack()
        } else {
            setActiveLyricsLineIndex(nil)
        }
    }

    func importLyricsFromFile() {
        updateLyricsPresentation()
        guard currentLyricsTrackKey != nil else {
            model.lyricsState = .metadataUnavailable
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "Import Lyrics")
        panel.message = String(localized: "Choose an LRC lyrics file for the current song.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importLyrics(at: url)
    }

    func importLyrics(at url: URL) {
        updateLyricsPresentation()
        guard let currentLyricsTrackKey else {
            model.lyricsState = .metadataUnavailable
            return
        }
        do {
            let document = try localLyricsStore().importLRC(at: url, for: currentLyricsTrackKey)
            model.lyricsState = .local(document)
            setActiveLyricsLineIndex(nil)
            updateLyricsLinePosition()
        } catch {
            model.lyricsState = .error(error.localizedDescription)
        }
    }

    func chooseLyricsCandidate(_ documentID: UUID) {
        updateLyricsPresentation()
        guard case .ambiguous(let documents) = model.lyricsState,
              let document = documents.first(where: { $0.id == documentID })
        else {
            return
        }
        model.lyricsState = .local(document)
        setActiveLyricsLineIndex(nil)
        updateLyricsLinePosition()
    }

    func deleteLyrics(_ documentID: UUID) {
        updateLyricsPresentation()
        let isCurrentDocument: Bool
        switch model.lyricsState {
        case .local(let document):
            isCurrentDocument = document.id == documentID
        case .ambiguous(let documents):
            isCurrentDocument = documents.contains(where: { $0.id == documentID })
        case .noTrack, .nowPlayingUnavailable, .metadataUnavailable, .onlineUnavailable, .error:
            isCurrentDocument = false
        }
        guard isCurrentDocument else { return }
        do {
            try localLyricsStore().delete(documentID: documentID)
            if let currentLyricsTrackKey {
                resolveLyrics(for: currentLyricsTrackKey)
            } else {
                model.lyricsState = .noTrack
            }
            updateLyricsLinePosition()
        } catch {
            model.lyricsState = .error(error.localizedDescription)
        }
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
        applyCollectionBehavior()
        evaluateScreensAndApply(animated: false)
        refreshVisuals()
        syncNowPlayingListening()
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

    private func refreshLyricsForCurrentTrack() {
        currentLyricsTrackKey = nil
        updateLyricsPresentation()
    }

    private func updateLyricsPresentation() {
        let snapshot = nowPlaying.snapshot
        guard snapshot.availability != .unavailable else {
            currentLyricsTrackKey = nil
            model.lyricsState = .nowPlayingUnavailable
            setActiveLyricsLineIndex(nil)
            model.lyricsPositionSeconds = 0
            return
        }
        guard let trackKey = lyricsTrackKey(from: snapshot) else {
            currentLyricsTrackKey = nil
            model.lyricsState = snapshot.hasTrack ? .metadataUnavailable : .noTrack
            setActiveLyricsLineIndex(nil)
            model.lyricsPositionSeconds = 0
            return
        }

        if currentLyricsTrackKey != trackKey {
            currentLyricsTrackKey = trackKey
            model.lyricsTrackRevision &+= 1
            setActiveLyricsLineIndex(nil)
            resolveLyrics(for: trackKey)
        }
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

    private func resolveLyrics(for trackKey: LyricsTrackKey) {
        do {
            switch try localLyricsStore().resolve(trackKey: trackKey) {
            case .local(let document):
                model.lyricsState = .local(document)
            case .ambiguous(let documents):
                model.lyricsState = .ambiguous(documents)
            case .onlineUnavailable:
                model.lyricsState = .onlineUnavailable
            }
        } catch {
            model.lyricsState = .error(error.localizedDescription)
        }
    }

    private func updateLyricsLinePosition() {
        guard case .local(let document) = model.lyricsState else {
            setActiveLyricsLineIndex(nil)
            model.lyricsPositionSeconds = 0
            return
        }
        let snapshot = nowPlaying.snapshot
        let position = LyricsPlaybackClock.position(
            anchor: snapshot.playbackClockAnchor,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            durationSeconds: snapshot.durationSeconds,
            nowUptime: ProcessInfo.processInfo.systemUptime
        )
        model.lyricsPositionSeconds = position
        setActiveLyricsLineIndex(LyricsPlaybackClock.activeLineIndex(
            in: document.lines,
            at: position
        ))
    }

    private func setActiveLyricsLineIndex(_ index: Int?) {
        guard model.activeLyricsLineIndex != index else { return }
        model.activeLyricsLineIndex = index
        model.activeLyricsLineChangedAtUptime = ProcessInfo.processInfo.systemUptime
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
            seekNowPlaying: { [weak self] seconds in
                self?.nowPlaying.seek(to: seconds)
            },
            selectFullScreenScene: { [weak self] scene in
                self?.setFullScreenScene(scene)
            },
            importLyrics: { [weak self] in
                self?.importLyricsFromFile()
            },
            chooseLyricsCandidate: { [weak self] documentID in
                self?.chooseLyricsCandidate(documentID)
            },
            deleteLyrics: { [weak self] documentID in
                self?.deleteLyrics(documentID)
            }
        )
        let host = IslandHostingView(rootView: root)
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
            model.isFullScreen = false
            model.fullScreenScene = .visualizer
            setActiveLyricsLineIndex(nil)
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

        if allowsOrderFront && panel.isVisible == false {
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

    private func updateKeyMonitor(active: Bool) {
        if active {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    MainActor.assumeIsolated {
                        self?.escapeExpandedPresentation()
                    }
                    return nil
                }
                return event
            }
        } else if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
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
