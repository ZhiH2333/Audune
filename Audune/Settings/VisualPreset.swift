import Foundation

nonisolated enum VisualPresetKind: String, Codable, Equatable {
    case builtIn
    case custom
}

nonisolated enum VisualPresetEditError: String, Error, Equatable {
    case unreadableStore
    case emptyName
    case nameTooLong
    case duplicateName
    case builtInLocked
    case notFound
    case duplicateID
    case limitReached
    case modeMismatch
    case persistFailed

    var message: String {
        switch self {
        case .unreadableStore: return "Saved presets could not be read."
        case .emptyName: return "Enter a name."
        case .nameTooLong: return "Use 40 characters or fewer."
        case .duplicateName: return "That name is already used for this mode."
        case .builtInLocked: return "Built-in presets cannot be changed."
        case .notFound: return "That preset is no longer available."
        case .duplicateID: return "A new preset id could not be created."
        case .limitReached: return "This mode already has 24 custom presets."
        case .modeMismatch: return "The preset does not match this visual mode."
        case .persistFailed: return "The preset could not be saved."
        }
    }
}

/// One visual snapshot for a single Studio mode. Built-in values live in code; only custom presets are stored.
nonisolated struct VisualPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var mode: StudioVisualMode
    var kind: VisualPresetKind
    var spectrum: SpectrumPreferences?
    var waveform: WaveformPreferences?
    var orbit: OrbitPreferences?

    func hasMatchingPayload() -> Bool {
        switch mode {
        case .spectrum:
            return spectrum != nil && waveform == nil && orbit == nil
        case .waveform:
            return waveform != nil && spectrum == nil && orbit == nil
        case .orbit:
            return orbit != nil && spectrum == nil && waveform == nil
        }
    }

    func clamped() -> VisualPreset {
        var copy = self
        copy.spectrum = spectrum?.clamped()
        copy.waveform = waveform?.clamped()
        copy.orbit = orbit?.clamped()
        return copy
    }
}

nonisolated struct VisualPresetDocument: Codable, Equatable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var customPresets: [VisualPreset]
    var appliedIDByMode: [String: String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, customPresets, appliedIDByMode
    }

    init(schemaVersion: Int, customPresets: [VisualPreset], appliedIDByMode: [String: String]) {
        self.schemaVersion = schemaVersion
        self.customPresets = customPresets
        self.appliedIDByMode = appliedIDByMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        customPresets = try container.decodeIfPresent([VisualPreset].self, forKey: .customPresets) ?? []
        appliedIDByMode = try container.decodeIfPresent([String: String].self, forKey: .appliedIDByMode) ?? [:]
    }
}
