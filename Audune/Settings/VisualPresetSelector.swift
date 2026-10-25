#if os(macOS)
import SwiftUI

struct VisualPresetSelector: View {
    var mode: StudioVisualMode
    var preferences: StudioPreferences
    var library: VisualPresetLibrary
    var apply: (VisualPreset) -> Void

    var body: some View {
        Section("Visual preset") {
            LabeledContent("Mode", value: mode.title)
            LabeledContent("Status", value: library.match(in: preferences, mode: mode).statusText)
            Picker("Preset", selection: selection) {
                Text("Unsaved settings").tag("")
                Section("Built-in") {
                    ForEach(builtIns) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                if custom.isEmpty == false {
                    Section("Custom") {
                        ForEach(custom) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            HStack {
                Button("Save Current") {}
                Button("Duplicate") {}
                Button("Rename") {}
                Button("Delete") {}
            }
            .disabled(true)
            if library.canPersist == false {
                Text("Saved presets could not be read. They were left unchanged.")
                    .foregroundStyle(.secondary)
            }
            Text(footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var builtIns: [VisualPreset] {
        library.builtIns.filter { $0.mode == mode }
    }

    private var custom: [VisualPreset] {
        library.customPresets.filter { $0.mode == mode }
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                switch library.match(in: preferences, mode: mode) {
                case .applied(let preset), .modified(let preset):
                    return preset.id
                case .unsaved:
                    return ""
                }
            },
            set: { id in
                guard id.isEmpty == false, let preset = library.preset(id: id) else { return }
                apply(preset)
            }
        )
    }

    private var footnote: String {
        var text = "Applies \(mode.title) settings only. Appearance, Window, and the other visual modes stay as they are."
        if mode != .spectrum {
            text += " A custom color on this mode is replaced when the preset is applied."
        }
        return text
    }
}
#endif
