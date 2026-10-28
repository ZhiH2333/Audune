#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class MenuBarModel {
    var title = "Not listening"
    var detail = ""
    var statusText = ""
    var showDetail = false
    var startDisabled = false
    var stopDisabled = true
    var studioVisible = false
    var islandEnabled = true
    var islandSupported = false
}

struct MenuBarPopoverView: View {
    @Bindable var model: MenuBarModel
    var start: () -> Void
    var stop: () -> Void
    var toggleStudio: () -> Void
    var toggleIsland: () -> Void = {}
    var openSettings: () -> Void
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
            HStack {
                Button("Start", action: start)
                    .disabled(model.startDisabled)
                Button("Stop", action: stop)
                    .disabled(model.stopDisabled)
            }
            Button(model.studioVisible ? "Hide Studio" : "Open Studio", action: toggleStudio)
            Button(islandButtonTitle, action: toggleIsland)
                .disabled(model.islandSupported == false)
            Button("Settings\u{2026}", action: openSettings)
            #if DEBUG
            if let openDebug {
                Button("Open Debug Window", action: openDebug)
            }
            #endif
            Divider()
            Button("Quit Audune", action: quit)
        }
        .padding(12)
        .frame(width: 220)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var islandButtonTitle: String {
        guard model.islandSupported else {
            return "Notch Island (No Notch)"
        }
        return model.islandEnabled ? "Hide Notch Island" : "Show Notch Island"
    }
}
#endif
