#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class StudioWindowController: NSObject, NSWindowDelegate {
    private let spike: ProcessTapSpike
    let model = StudioModel()
    private let panel: NSPanel
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
        model.alwaysOnTop = StudioWindowStorage.alwaysOnTop()
        configurePanel()
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
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
        UserDefaults.standard.set(enabled, forKey: StudioWindowStorage.alwaysOnTopKey)
        applyLevel()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopDisplayTimer()
        return true
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true
        panel.title = "Audune Studio"
        panel.isOpaque = true
        panel.backgroundColor = NSColor(srgbRed: 24.0 / 255.0, green: 26.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)
        panel.minSize = StudioFrame.minimumSize
        panel.contentMinSize = StudioFrame.minimumSize
        applyLevel()
        let root = StudioContentView(
            spike: spike,
            model: model,
            setAlwaysOnTop: { [weak self] enabled in
                self?.setAlwaysOnTop(enabled)
            },
            close: { [weak self] in
                self?.hide()
            }
        )
        panel.contentView = NSHostingView(rootView: root)
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
