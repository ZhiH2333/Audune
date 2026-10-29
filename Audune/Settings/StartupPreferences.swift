import Foundation

/// UserDefaults keys for process-launch behavior. Absent keys preserve today's launch defaults.
nonisolated enum StartupPreferenceKey {
    static let destination = "startup.destination"
    static let visualMode = "startup.visualMode"
    static let presetID = "startup.presetID"
}

/// Which surfaces Audune presents when the process starts.
nonisolated enum StartupDestination: String, CaseIterable, Identifiable, Sendable {
    /// Menu bar always; Island follows saved `island.isEnabled` + support; Studio stays hidden.
    case followExisting
    /// Studio hidden; Island forced off for this launch.
    case menuBarOnly
    /// Open Studio; Island still follows saved enablement.
    case openStudio
    /// Enable and present Notch Island when supported; Studio stays hidden.
    case showIsland
    /// Open Studio and present Notch Island when supported.
    case openStudioAndIsland

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followExisting: return String(localized: "Follow current behavior")
        case .menuBarOnly: return String(localized: "Menu Bar only")
        case .openStudio: return String(localized: "Open Studio")
        case .showIsland: return String(localized: "Show Notch Island")
        case .openStudioAndIsland: return String(localized: "Open Studio and Notch Island")
        }
    }
}

/// Optional visualization mode override applied once at process launch.
nonisolated enum StartupVisualMode: String, CaseIterable, Identifiable, Sendable {
    case keepCurrent
    case spectrum
    case waveform
    case orbit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepCurrent: return String(localized: "Keep current selection")
        case .spectrum: return String(localized: "Spectrum")
        case .waveform: return String(localized: "Waveform")
        case .orbit: return String(localized: "Orbit")
        }
    }

    /// Concrete Studio/Island mode when this choice overrides the saved selection.
    var studioMode: StudioVisualMode? {
        switch self {
        case .keepCurrent: return nil
        case .spectrum: return .spectrum
        case .waveform: return .waveform
        case .orbit: return .orbit
        }
    }
}

/// How Island enablement is adjusted for one launch. Does not invent a second preference store.
nonisolated enum StartupIslandPolicy: Equatable, Sendable {
    /// Leave `island.isEnabled` alone (after deferred activation).
    case followExisting
    /// Force Island off for this launch via the existing enable API.
    case forceDisabled
    /// Force Island on for this launch when geometry allows.
    case forceEnabled
}

/// Pure outcome of validating startup prefs against the current preset library.
nonisolated struct StartupResolution: Equatable, Sendable {
    var destination: StartupDestination
    var effectiveMode: StudioVisualMode?
    var presetToApply: VisualPreset?
    var presetIDWasInvalid: Bool
    var studioShouldShow: Bool
    var islandPolicy: StartupIslandPolicy

    static func resolve(
        _ preferences: StartupPreferences,
        library: VisualPresetLibrary
    ) -> StartupResolution {
        let destination = preferences.destination
        let resolvedPreset: VisualPreset?
        let presetInvalid: Bool
        if let id = preferences.presetID, id.isEmpty == false {
            if let preset = library.preset(id: id), preset.hasMatchingPayload() {
                resolvedPreset = preset
                presetInvalid = false
            } else {
                resolvedPreset = nil
                presetInvalid = true
            }
        } else {
            resolvedPreset = nil
            presetInvalid = false
        }

        let effectiveMode: StudioVisualMode?
        if let explicit = preferences.visualMode.studioMode {
            // Explicit mode wins for display; a mismatched preset is skipped below.
            effectiveMode = explicit
        } else if let preset = resolvedPreset {
            effectiveMode = preset.mode
        } else {
            effectiveMode = nil
        }

        let presetToApply: VisualPreset?
        if let preset = resolvedPreset {
            if let mode = effectiveMode, preset.mode != mode {
                presetToApply = nil
            } else {
                presetToApply = preset
            }
        } else {
            presetToApply = nil
        }

        let studioShouldShow: Bool
        let islandPolicy: StartupIslandPolicy
        switch destination {
        case .followExisting:
            studioShouldShow = false
            islandPolicy = .followExisting
        case .menuBarOnly:
            studioShouldShow = false
            islandPolicy = .forceDisabled
        case .openStudio:
            studioShouldShow = true
            islandPolicy = .followExisting
        case .showIsland:
            studioShouldShow = false
            islandPolicy = .forceEnabled
        case .openStudioAndIsland:
            studioShouldShow = true
            islandPolicy = .forceEnabled
        }

        return StartupResolution(
            destination: destination,
            effectiveMode: effectiveMode,
            presetToApply: presetToApply,
            presetIDWasInvalid: presetInvalid,
            studioShouldShow: studioShouldShow,
            islandPolicy: islandPolicy
        )
    }
}

/// Launch-only configuration. Missing keys keep Audune's current process-start behavior.
nonisolated struct StartupPreferences: Equatable, Sendable {
    var destination: StartupDestination
    var visualMode: StartupVisualMode
    /// Stable Visual Preset id (`builtin.*` or custom UUID). Nil means no override.
    var presetID: String?

    static let standard = StartupPreferences(
        destination: .followExisting,
        visualMode: .keepCurrent,
        presetID: nil
    )

    static func load(from defaults: UserDefaults = .standard) -> StartupPreferences {
        let destination = defaults.string(forKey: StartupPreferenceKey.destination)
            .flatMap(StartupDestination.init(rawValue:)) ?? standard.destination
        let visualMode = defaults.string(forKey: StartupPreferenceKey.visualMode)
            .flatMap(StartupVisualMode.init(rawValue:)) ?? standard.visualMode
        let rawPreset = defaults.string(forKey: StartupPreferenceKey.presetID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let presetID = (rawPreset?.isEmpty == false) ? rawPreset : nil
        return StartupPreferences(destination: destination, visualMode: visualMode, presetID: presetID)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(destination.rawValue, forKey: StartupPreferenceKey.destination)
        defaults.set(visualMode.rawValue, forKey: StartupPreferenceKey.visualMode)
        if let presetID, presetID.isEmpty == false {
            defaults.set(presetID, forKey: StartupPreferenceKey.presetID)
        } else {
            defaults.removeObject(forKey: StartupPreferenceKey.presetID)
        }
    }

    static func reset(in defaults: UserDefaults = .standard) {
        standard.save(to: defaults)
    }
}
