#if os(macOS)
import SwiftUI

struct VisualPresetSelector: View {
    var mode: StudioVisualMode
    var preferences: StudioPreferences
    var library: VisualPresetLibrary
    var apply: (VisualPreset) -> Void
    var save: (String) -> Result<VisualPreset, VisualPresetEditError>
    var duplicate: (VisualPreset) -> Result<VisualPreset, VisualPresetEditError>
    var rename: (VisualPreset, String) -> Result<Void, VisualPresetEditError>
    var delete: (VisualPreset) -> Result<Void, VisualPresetEditError>
    var resetLibrary: () -> Bool

    @State private var draftName = ""
    @State private var isSaving = false
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var notice: String?

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
                Button("Save Current") {
                    draftName = ""
                    notice = nil
                    isSaving = true
                }
                .disabled(library.canPersist == false)
                Button("Duplicate") {
                    guard let selectedPreset else { return }
                    notice = nil
                    if case .failure(let error) = duplicate(selectedPreset) {
                        notice = error.message
                    }
                }
                .disabled(selectedPreset == nil || library.canPersist == false)
                Button("Rename") {
                    draftName = selectedPreset?.name ?? ""
                    notice = nil
                    isRenaming = true
                }
                .disabled(selectedPreset?.kind != .custom || library.canPersist == false)
                Button("Delete") {
                    notice = nil
                    isDeleting = true
                }
                .disabled(selectedPreset?.kind != .custom || library.canPersist == false)
            }
            if let notice {
                Text(notice)
                    .foregroundStyle(.secondary)
            }
            if library.canPersist == false {
                Text("Saved presets could not be read. They were left unchanged.")
                    .foregroundStyle(.secondary)
                Button("Reset Preset Library") {
                    if resetLibrary() {
                        notice = nil
                    }
                }
            }
            Text(footnote)
                .foregroundStyle(.secondary)
        }
        .alert("Save Current", isPresented: $isSaving) {
            TextField("Name", text: $draftName)
            Button("Save") { commitSave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name the current \(mode.title) settings.")
        }
        .alert("Rename Preset", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Built-in presets keep their names.")
        }
        .confirmationDialog("Delete this preset?", isPresented: $isDeleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedPreset?.name ?? "This preset") will be removed. The current \(mode.title) settings stay as they are.")
        }
    }

    private var selectedPreset: VisualPreset? {
        switch library.match(in: preferences, mode: mode) {
        case .applied(let preset), .modified(let preset):
            return preset
        case .unsaved:
            return nil
        }
    }

    private func commitSave() {
        switch save(draftName) {
        case .success:
            notice = nil
        case .failure(let error):
            notice = error.message
        }
    }

    private func commitRename() {
        guard let selectedPreset else { return }
        switch rename(selectedPreset, draftName) {
        case .success:
            notice = nil
        case .failure(let error):
            notice = error.message
        }
    }

    private func commitDelete() {
        guard let selectedPreset else { return }
        switch delete(selectedPreset) {
        case .success:
            notice = nil
        case .failure(let error):
            notice = error.message
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
