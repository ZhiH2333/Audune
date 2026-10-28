#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Native save/open panels for visual preset exchange files.
enum VisualPresetFilePanel {
    static let jsonType = UTType.json

    static func defaultExportName(mode: StudioVisualMode, presets: [VisualPreset]) -> String {
        if presets.count == 1 {
            let safe = sanitizedFileComponent(presets[0].displayName)
            return "Audune-\(mode.title)-\(safe).json"
        }
        return "Audune-\(mode.title)-Presets.json"
    }

    static func sanitizedFileComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--", with: "-")
        let clipped = String(cleaned.prefix(40))
        return clipped.isEmpty ? "Preset" : clipped
    }

    @discardableResult
    static func runSavePanel(
        suggestedName: String,
        data: Data,
        onError: (String) -> Void
    ) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [jsonType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName
        panel.title = String(localized: "Export Presets")
        panel.message = String(localized: "Choose where to save the Audune preset file.")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            onError(String(localized: "The presets could not be exported."))
            return false
        }
    }

    static func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [jsonType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "Import Presets")
        panel.message = String(localized: "Choose an Audune preset JSON file.")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
#endif
