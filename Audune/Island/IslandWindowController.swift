#if os(macOS)
import AppKit
import SwiftUI

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
    var isOpaque: Bool
    var backgroundAlpha: CGFloat
    var hasShadow: Bool
    var ignoresMouseEvents: Bool
    var hostIsOpaque: Bool
    var isTimerRunning: Bool
    var unsupportedReason: IslandUnsupportedReason?
}

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
    private var hapticToken = 0
    let model = IslandModel()
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

    var openStudio: (() -> Void)?
    var openSettings: (() -> Void)?

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
        screenProvider: @escaping () -> [IslandScreenDescriptor] = IslandWindowController.systemScreens,
        allowsOrderFront: Bool = true,
        haptics: any IslandHapticPerforming = SystemIslandHaptics()
    ) {
        self.spike = spike
        self.defaults = defaults
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
        evaluateScreensAndApply(animated: false)
    }

    var isVisible: Bool {
        panel.isVisible || (allowsOrderFront == false && model.state.isVisible && model.isSupported)
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
        model.prefs.isEnabled = enabled
        savePreferences()
        evaluateScreensAndApply(animated: true)
    }

    func toggleEnabled() {
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

    func togglePin() {
        applyEvent(.togglePin(at: Date().timeIntervalSinceReferenceDate), animated: true)
    }

    func preferencesDidChange() {
        model.prefs = model.prefs.normalized()
        applyCollectionBehavior()
        evaluateScreensAndApply(animated: false)
        refreshVisuals()
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard Task.isCancelled == false else { return }
            self?.savePreferences()
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
            .availabilityChanged(isEnabled: model.prefs.isEnabled, isSupported: model.isSupported),
            animated: animated
        )
        rearmHoverIfPointerStillInside()
    }

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
        applyEvent(.escapePressed, animated: false)
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
            openStudio: { [weak self] in
                self?.openStudio?()
            },
            openSettings: { [weak self] in
                self?.openSettings?()
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
        model.pointerInside = stateContext.pointerInside
        model.pointerDown = stateContext.pointerDown
        model.hoverArmed = stateContext.state == .compact && stateContext.expandArmedAt != nil

        scheduleCollapseTimerIfNeeded()
        scheduleExpandTimerIfNeeded()

        guard stateContext.state != .disabled, let geometry = model.geometry else {
            stopDisplayTimer()
            updateKeyMonitor(active: false)
            panel.orderOut(nil)
            return
        }

        let targetFrame = stateContext.state.isExpandedOrPinned ? geometry.expandedFrame : geometry.compactFrame
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
        animated: Bool,
        hapticPattern: NSHapticFeedbackManager.FeedbackPattern?,
        hapticToken token: Int
    ) {
        guard panel.frame != targetFrame else {
            performHaptic(hapticPattern, token: token)
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = animated
            ? IslandMotion.transitionSeconds(
                expanding: expanding,
                reduceMotion: reduceMotion,
                followsReduceMotion: model.prefs.followsReduceMotion,
                speed: model.prefs.animationSpeed
            )
            : 0
        if duration > 0 {
            let pace = IslandMotion.framePace(expanding: expanding, duration: duration)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = Self.timingFunction(for: pace)
                panel.animator().setFrame(targetFrame, display: panel.isVisible)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.performHaptic(hapticPattern, token: token)
                }
            }
        } else {
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
                        self?.applyEvent(.escapePressed, animated: true)
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
