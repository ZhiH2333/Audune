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
}

struct MenuBarPopoverView: View {
    @Bindable var model: MenuBarModel
    var start: () -> Void
    var stop: () -> Void
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
