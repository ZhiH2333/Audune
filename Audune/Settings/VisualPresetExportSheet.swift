#if os(macOS)
import SwiftUI

/// Mode-scoped multi-select sheet for exporting one or more visual presets.
struct VisualPresetExportSheet: View {
    var mode: StudioVisualMode
    var presets: [VisualPreset]
    var initiallySelectedIDs: Set<String>
    var onExport: ([VisualPreset]) -> Void
    var onCancel: () -> Void

    @State private var selectedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Presets")
                .font(.headline)
            Text("Choose which \(mode.title) presets to export.")
                .foregroundStyle(.secondary)
            List {
                ForEach(presets) { preset in
                    Toggle(isOn: Binding(
                        get: { selectedIDs.contains(preset.id) },
                        set: { isOn in
                            if isOn {
                                selectedIDs.insert(preset.id)
                            } else {
                                selectedIDs.remove(preset.id)
                            }
                        }
                    )) {
                        HStack {
                            Text(preset.displayName)
                            Spacer()
                            Text(preset.kind == .builtIn
                                 ? String(localized: "Built-in")
                                 : String(localized: "Custom"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(minHeight: 180, maxHeight: 280)
            HStack {
                Button("Select All") {
                    selectedIDs = Set(presets.map(\.id))
                }
                .disabled(presets.isEmpty)
                Button("Select None") {
                    selectedIDs = []
                }
                .disabled(selectedIDs.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Export") {
                    let chosen = presets.filter { selectedIDs.contains($0.id) }
                    onExport(chosen)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            selectedIDs = initiallySelectedIDs.intersection(Set(presets.map(\.id)))
            if selectedIDs.isEmpty, let first = presets.first {
                selectedIDs = [first.id]
            }
        }
    }
}
#endif
