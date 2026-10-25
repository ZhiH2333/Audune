#if os(macOS)
import AppKit
import SwiftUI

/// A normal, resizable window. It does not use Studio's level or Spaces behavior,
/// and hiding Studio never closes it.
@MainActor
final class SettingsWindowController: NSObject {
    static let initialSize = CGSize(width: 760, height: 600)
    static let minimumSize = CGSize(width: 640, height: 480)
    static let frameAutosaveName = "AuduneSettings"

    let window: NSWindow

    init(studio: StudioWindowController) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Audune Settings"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = []
        window.hidesOnDeactivate = false
        window.contentMinSize = Self.minimumSize
        let host = NSHostingView(rootView: SettingsView(studio: studio))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(Self.initialSize)
        if window.setFrameAutosaveName(Self.frameAutosaveName) == false {
            window.center()
        }
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func shutdown() {
        window.orderOut(nil)
    }
}
#endif
