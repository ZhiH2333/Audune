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
    var cleanCanvas = false
}

struct MenuBarPopoverView: View {
    @Bindable var model: MenuBarModel
    var start: () -> Void
    var stop: () -> Void
    var toggleStudio: () -> Void
    var setCleanCanvas: (Bool) -> Void
    var openDebug: () -> Void
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
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Start", action: start)
                    .disabled(model.startDisabled)
                Button("Stop", action: stop)
                    .disabled(model.stopDisabled)
            }
            Button(model.studioVisible ? "Hide Studio" : "Open Studio", action: toggleStudio)
            Toggle("Clean Canvas", isOn: Binding(
                get: { model.cleanCanvas },
                set: { setCleanCanvas($0) }
            ))
            Button("Open Debug Window", action: openDebug)
            Divider()
            Button("Quit Audune", action: quit)
        }
        .padding(12)
        .frame(width: 220)
        .fixedSize(horizontal: true, vertical: true)
    }
}
#endif
