#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class MenuBarModel {
    var title = String(localized: "Not listening")
    var detail = ""
    var statusText = ""
    var showDetail = false
    var startDisabled = false
    var stopDisabled = true
    var studioVisible = false
    var islandEnabled = true
    var islandSupported = false
    var fullscreenEnabled = false
}

struct MenuBarPopoverView: View {
    @Bindable var model: MenuBarModel
    var start: () -> Void
    var stop: () -> Void
    var toggleStudio: () -> Void
    var toggleIsland: () -> Void = {}
    var openSettings: () -> Void
    var openFullscreen: () -> Void = {}
    var openAbout: () -> Void = {}
    var openDebug: (() -> Void)?
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.title)
                .font(.headline)
            if model.showDetail {
                Text(model.detail)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                if model.statusText.isEmpty == false {
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: 8) {
                PopoverButton(title: "Start", symbol: "play.fill", action: start)
                    .disabled(model.startDisabled)
                PopoverButton(title: "Stop", symbol: "stop.fill", action: stop)
                    .disabled(model.stopDisabled)
            }
            PopoverButton(title: studioTitle, symbol: "macwindow", leading: true, action: toggleStudio)
            PopoverButton(title: islandTitle, symbol: "rectangle.topthird.inset.filled", leading: true, action: toggleIsland)
                .disabled(model.islandSupported == false)
            PopoverButton(title: "Fullscreen Player", symbol: "arrow.up.left.and.arrow.down.right", leading: true, action: openFullscreen)
                .disabled(model.fullscreenEnabled == false)
            PopoverButton(title: "Settings\u{2026}", symbol: "gearshape", leading: true, action: openSettings)
                .keyboardShortcut(",")
            PopoverButton(title: "About Audune", symbol: "info.circle", leading: true, action: openAbout)
            #if DEBUG
            if let openDebug {
                PopoverButton(title: "Open Debug Window", symbol: "ladybug", leading: true, action: openDebug)
            }
            #endif
            Divider()
            PopoverButton(title: "Quit Audune", symbol: "power", leading: true, action: quit)
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 244)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var studioTitle: LocalizedStringKey {
        model.studioVisible ? "Hide Studio" : "Open Studio"
    }

    private var islandTitle: LocalizedStringKey {
        guard model.islandSupported else { return "Notch Island (No Notch)" }
        return model.islandEnabled ? "Hide Notch Island" : "Show Notch Island"
    }
}

/// Every popover action uses the same height and fills the row, so English and Chinese labels line up.
private struct PopoverButton: View {
    var title: LocalizedStringKey
    var symbol: String
    var leading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
        }
        .controlSize(.large)
    }
}
#endif
