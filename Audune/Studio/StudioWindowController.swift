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

    func resetPreferences() {
        StudioPreferences.reset()
        apply(StudioPreferences.standard)
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
            usesDragHostingView: panel.contentView is StudioHostingView<StudioContentView>
        )
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = StudioWindowBehavior.collectionBehavior
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true
        panel.title = "Audune Studio"
        panel.isOpaque = false
        panel.backgroundColor = .clear
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
            hitMap: hitMap
        )
        let host = StudioHostingView(rootView: root)
        host.hitMap = hitMap
        panel.contentView = host
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
        applyLevel()
    }

    private func currentPreferences() -> StudioPreferences {
        StudioPreferences(
            mode: model.mode,
            alwaysOnTop: model.alwaysOnTop,
            backgroundOpacity: model.backgroundOpacity,
            accent: model.accent
        )
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
    }
}
#endif
