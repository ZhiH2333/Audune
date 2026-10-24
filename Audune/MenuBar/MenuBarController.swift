#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let spike: ProcessTapSpike
    private let openDebug: () -> Void
    private let toggleStudio: () -> Void
    private let studioVisible: () -> Bool
    private let model = MenuBarModel()
    private let spectrumImage = MenuBarSpectrumImage()
    private let statusItem = NSStatusBar.system.statusItem(withLength: MenuBarSpectrumImage.pointSize.width)
    private let popover = NSPopover()
    private var timer: Timer?
    private var renderedState: MenuBarVisualState?
    private var renderedSequence: UInt64?
    private var lastReadingRefresh = ContinuousClock.now
    private var didShutdown = false

    init(
        spike: ProcessTapSpike,
        openDebug: @escaping () -> Void,
        toggleStudio: @escaping () -> Void,
        studioVisible: @escaping () -> Bool
    ) {
        self.spike = spike
        self.openDebug = openDebug
        self.toggleStudio = toggleStudio
        self.studioVisible = studioVisible
        super.init()
        let root = MenuBarPopoverView(
            model: model,
            start: { [weak self] in self?.startCapture() },
            stop: { [weak self] in self?.stopCapture() },
            toggleStudio: { [weak self] in self?.toggleStudioWindow() },
            openDebug: { [weak self] in self?.showDebugWindow() },
            quit: { NSApp.terminate(nil) }
        )
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: root)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        publish()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickFromTimer()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    func shutdown() {
        guard didShutdown == false else { return }
        didShutdown = true
        timer?.invalidate()
        timer = nil
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func startCapture() {
        Task { await spike.start() }
    }

    private func stopCapture() {
        spike.stop()
        publish()
    }

    private func showDebugWindow() {
        popover.performClose(nil)
        openDebug()
    }

    private func toggleStudioWindow() {
        popover.performClose(nil)
        toggleStudio()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        publish()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func handleTerminate() {
        shutdown()
    }

    private func tickFromTimer() {
        MainActor.assumeIsolated {
            tick()
        }
    }

    private func tick() {
        let now = ContinuousClock.now
        if now - lastReadingRefresh >= .milliseconds(250) {
            spike.refreshReading()
            lastReadingRefresh = now
        }
        publish()
    }

    private func publish() {
        let snapshot = spike.snapshots.load()
        let presentation = presentation(snapshot: snapshot)
        if model.title != presentation.title { model.title = presentation.title }
        if model.detail != presentation.detail { model.detail = presentation.detail }
        if model.statusText != presentation.statusText { model.statusText = presentation.statusText }
        if model.showDetail != presentation.showDetail { model.showDetail = presentation.showDetail }
        if model.startDisabled != presentation.startDisabled { model.startDisabled = presentation.startDisabled }
        if model.stopDisabled != presentation.stopDisabled { model.stopDisabled = presentation.stopDisabled }
        let studioOpen = studioVisible()
        if model.studioVisible != studioOpen { model.studioVisible = studioOpen }
        guard let button = statusItem.button else { return }
        let sequence = presentation.state == .receiving ? snapshot.sequence : nil
        if renderedState == presentation.state && renderedSequence == sequence { return }
        renderedState = presentation.state
        renderedSequence = sequence
        button.image = spectrumImage.render(state: presentation.state, spectrum: snapshot.spectrum)
        button.setAccessibilityLabel("Audune, \(presentation.title)")
    }

    private func presentation(snapshot: AudioSnapshot) -> Presentation {
        switch spike.phase {
        case .idle:
            return Presentation(state: .idle, title: "Not listening", detail: "", statusText: "", showDetail: false, startDisabled: false, stopDisabled: true)
        case .starting:
            return Presentation(state: .starting, title: "Starting", detail: "", statusText: "", showDetail: false, startDisabled: true, stopDisabled: false)
        case .failed:
            let detail = spike.failureText.isEmpty ? "Audio capture failed." : spike.failureText
            return Presentation(state: .failed, title: "Capture failed", detail: detail, statusText: spike.statusText, showDetail: true, startDisabled: false, stopDisabled: false)
        case .running:
            if snapshot.isSilent {
                return Presentation(state: .silent, title: "No audio", detail: "", statusText: "", showDetail: false, startDisabled: true, stopDisabled: false)
            }
            return Presentation(state: .receiving, title: "Listening", detail: "", statusText: "", showDetail: false, startDisabled: true, stopDisabled: false)
        }
    }
}

private struct Presentation: Equatable {
    var state: MenuBarVisualState
    var title: String
    var detail: String
    var statusText: String
    var showDetail: Bool
    var startDisabled: Bool
    var stopDisabled: Bool
}

struct MenuBarInstaller: View {
    @Bindable var spike: ProcessTapSpike
    @Environment(\.openWindow) private var openWindow
    @State private var controller: MenuBarController?
    @State private var studio: StudioWindowController?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard controller == nil else { return }
                let studio = StudioWindowController(spike: spike)
                self.studio = studio
                let openWindow = openWindow
                controller = MenuBarController(
                    spike: spike,
                    openDebug: {
                        openWindow(id: "debug")
                        NSApp.activate()
                    },
                    toggleStudio: { studio.toggle() },
                    studioVisible: { studio.isVisible }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                controller?.shutdown()
                studio?.shutdown()
            }
    }
}
#endif
