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
    private var screenObserver: NSObjectProtocol?
    private var pointerMonitor: Any?
    private var smoothedStudio: [Float] = []
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
        panel.collectionBehavior = StudioWindowBehavior.collectionBehavior
        clampOntoVisibleScreen()
        applyLevel()
        refreshPointerInside()
        panel.orderFrontRegardless()
        startDisplayTimer()
    }

    func hide() {
        stopDisplayTimer()
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
        panel.orderOut(nil)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        model.alwaysOnTop = enabled
        savePreferences()
        applyLevel()
    }

    func savePreferences() {
        currentPreferences().save()
    }

    func setCleanCanvas(_ enabled: Bool) {
        model.cleanCanvas = enabled
        savePreferences()
        if enabled == false {
            setChromeVisible(true)
        }
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
        apply(StudioPreferences.standard)
        refreshStudioSpectrum()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopDisplayTimer()
        return true
    }

    func inspectWindowForTests() -> StudioWindowInspection {
        StudioWindowInspection(
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
        panel.collectionBehavior = StudioWindowBehavior.collectionBehavior
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = false
        panel.title = "Audune Studio"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.minSize = StudioFrame.minimumSize
        panel.contentMinSize = StudioFrame.minimumSize
        applyLevel()
        let root = StudioContentView(
            spike: spike,
            model: model,
            setAlwaysOnTop: { [weak self] enabled in
                self?.setAlwaysOnTop(enabled)
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
            setCleanCanvas: { [weak self] enabled in
                self?.setCleanCanvas(enabled)
            },
            setBarCount: { [weak self] count in
                self?.setBarCount(count)
            },
            setChromeVisible: { [weak self] visible in
                self?.setChromeVisible(visible)
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

    private func applyLevel() {
        panel.level = model.alwaysOnTop ? .floating : .normal
    }

    private func apply(_ preferences: StudioPreferences) {
        model.mode = preferences.mode
        model.alwaysOnTop = preferences.alwaysOnTop
        model.backgroundOpacity = preferences.backgroundOpacity
        model.accent = preferences.accent
        model.cleanCanvas = preferences.cleanCanvas
        model.barCount = preferences.barCount
        if model.studioSpectrum.count != preferences.barCount {
            model.studioSpectrum = Array(repeating: 0, count: preferences.barCount)
        }
        applyLevel()
        if preferences.cleanCanvas == false {
            setChromeVisible(true)
        }
    }

    private func currentPreferences() -> StudioPreferences {
        StudioPreferences(
            mode: model.mode,
            alwaysOnTop: model.alwaysOnTop,
            backgroundOpacity: model.backgroundOpacity,
            accent: model.accent,
            cleanCanvas: model.cleanCanvas,
            barCount: model.barCount
        )
    }

    private func refreshPointerInside() {
        model.pointerInside = panel.frame.contains(NSEvent.mouseLocation)
    }

    private func refreshStudioSpectrum() {
        let count = model.barCount
        let levels = SpectrumBands.levels(
            binMagnitudes: model.snapshot.binMagnitudes,
            sampleRate: model.snapshot.sampleRate,
            count: count
        )
        smoothedStudio = SpectrumBands.smooth(current: smoothedStudio, toward: levels, count: count)
        model.studioSpectrum = smoothedStudio
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
        refreshStudioSpectrum()
    }
}
#endif
