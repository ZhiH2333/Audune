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
    private let studio: StudioWindowController
    let island: IslandWindowController
    let fullscreen: FullscreenWindowController?
    private let ownsIsland: Bool
    private let ownsFullscreen: Bool

    init(
        studio: StudioWindowController,
        island: IslandWindowController? = nil,
        fullscreen: FullscreenWindowController? = nil
    ) {
        self.studio = studio
        if let island {
            self.island = island
            self.ownsIsland = false
        } else {
            self.island = IslandWindowController(spike: ProcessTapSpike(), allowsOrderFront: false)
            self.ownsIsland = true
        }
        if let fullscreen {
            self.fullscreen = fullscreen
            self.ownsFullscreen = false
        } else {
            self.fullscreen = nil
            self.ownsFullscreen = false
        }
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = String(localized: "Audune Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = []
        window.hidesOnDeactivate = false
        window.contentMinSize = Self.minimumSize
        let host = NSHostingView(
            rootView: SettingsView(studio: studio, island: self.island, fullscreen: self.fullscreen)
        )
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(Self.initialSize)
        if window.setFrameAutosaveName(Self.frameAutosaveName) == false {
            window.center()
        }
    }

    var isVisible: Bool { window.isVisible }

    func show(category: SettingsCategory? = nil) {
        if let category {
            studio.model.settingsCategory = category
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func shutdown() {
        window.orderOut(nil)
        if ownsIsland {
            island.shutdown()
        }
        if ownsFullscreen {
            fullscreen?.shutdown()
        }
    }
}
#endif
