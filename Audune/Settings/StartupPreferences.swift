import Foundation

/// UserDefaults keys for process-launch behavior. Absent surface keys preserve today's launch defaults.
nonisolated enum StartupPreferenceKey {
    static let openStudioAtLaunch = "startup.openStudioAtLaunch"
    static let showIslandAtLaunch = "startup.showIslandAtLaunch"
    static let openSettingsAtLaunch = "startup.openSettingsAtLaunch"
    static let visualMode = "startup.visualMode"
    static let presetID = "startup.presetID"
    static let autoStartCapture = "startup.autoStartCapture"
    /// Legacy mutually exclusive destination; migrated once into independent surface booleans.
    static let legacyDestination = "startup.destination"
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

/// Pure outcome of validating startup prefs against the current preset library.
nonisolated struct StartupResolution: Equatable, Sendable {
    var openStudioAtLaunch: Bool
    var showIslandAtLaunch: Bool
    var openSettingsAtLaunch: Bool
    var autoStartCapture: Bool
    var effectiveMode: StudioVisualMode?
    var presetToApply: VisualPreset?
    var presetIDWasInvalid: Bool

    var studioShouldShow: Bool { openStudioAtLaunch }
    var settingsShouldShow: Bool { openSettingsAtLaunch }
    var islandShouldPresent: Bool { showIslandAtLaunch }

    static func resolve(
        _ preferences: StartupPreferences,
        library: VisualPresetLibrary
    ) -> StartupResolution {
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

        // keepCurrent never switches Studio/Island mode. Startup UI sets an explicit
        // visualMode when the user picks a launch preset; that path still overrides.
        let effectiveMode = preferences.visualMode.studioMode

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

        return StartupResolution(
            openStudioAtLaunch: preferences.openStudioAtLaunch,
            showIslandAtLaunch: preferences.showIslandAtLaunch,
            openSettingsAtLaunch: preferences.openSettingsAtLaunch,
            autoStartCapture: preferences.autoStartCapture,
            effectiveMode: effectiveMode,
            presetToApply: presetToApply,
            presetIDWasInvalid: presetInvalid
        )
    }
}

/// Launch-only configuration. Missing surface keys keep Audune's current process-start behavior.
nonisolated struct StartupPreferences: Equatable, Sendable {
    var openStudioAtLaunch: Bool
    var showIslandAtLaunch: Bool
    var openSettingsAtLaunch: Bool
    var visualMode: StartupVisualMode
    /// Stable Visual Preset id (`builtin.*` or custom UUID). Nil means no override.
    var presetID: String?
    /// Starts capture at cold launch when permission is already granted; never implies window visibility.
    var autoStartCapture: Bool

    /// Matches pre-checkbox launch: Studio/Settings hidden; Island follows saved enablement.
    static let standard = StartupPreferences(
        openStudioAtLaunch: false,
        showIslandAtLaunch: true,
        openSettingsAtLaunch: false,
        visualMode: .keepCurrent,
        presetID: nil,
        autoStartCapture: true
    )

    static func load(from defaults: UserDefaults = .standard) -> StartupPreferences {
        let visualMode = defaults.string(forKey: StartupPreferenceKey.visualMode)
            .flatMap(StartupVisualMode.init(rawValue:)) ?? standard.visualMode
        let rawPreset = defaults.string(forKey: StartupPreferenceKey.presetID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let presetID = (rawPreset?.isEmpty == false) ? rawPreset : nil
        let autoStartCapture = defaults.object(forKey: StartupPreferenceKey.autoStartCapture) == nil
            ? standard.autoStartCapture
            : defaults.bool(forKey: StartupPreferenceKey.autoStartCapture)

        if hasSurfaceKeys(in: defaults) {
            return StartupPreferences(
                openStudioAtLaunch: bool(
                    forKey: StartupPreferenceKey.openStudioAtLaunch,
                    in: defaults,
                    fallback: standard.openStudioAtLaunch
                ),
                showIslandAtLaunch: bool(
                    forKey: StartupPreferenceKey.showIslandAtLaunch,
                    in: defaults,
                    fallback: standard.showIslandAtLaunch
                ),
                openSettingsAtLaunch: bool(
                    forKey: StartupPreferenceKey.openSettingsAtLaunch,
                    in: defaults,
                    fallback: standard.openSettingsAtLaunch
                ),
                visualMode: visualMode,
                presetID: presetID,
                autoStartCapture: autoStartCapture
            )
        }

        if let legacy = defaults.string(forKey: StartupPreferenceKey.legacyDestination),
           let migrated = migrateLegacyDestination(legacy) {
            let prefs = StartupPreferences(
                openStudioAtLaunch: migrated.openStudioAtLaunch,
                showIslandAtLaunch: migrated.showIslandAtLaunch,
                openSettingsAtLaunch: migrated.openSettingsAtLaunch,
                visualMode: visualMode,
                presetID: presetID,
                autoStartCapture: autoStartCapture
            )
            prefs.save(to: defaults)
            return prefs
        }

        return StartupPreferences(
            openStudioAtLaunch: standard.openStudioAtLaunch,
            showIslandAtLaunch: standard.showIslandAtLaunch,
            openSettingsAtLaunch: standard.openSettingsAtLaunch,
            visualMode: visualMode,
            presetID: presetID,
            autoStartCapture: autoStartCapture
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(openStudioAtLaunch, forKey: StartupPreferenceKey.openStudioAtLaunch)
        defaults.set(showIslandAtLaunch, forKey: StartupPreferenceKey.showIslandAtLaunch)
        defaults.set(openSettingsAtLaunch, forKey: StartupPreferenceKey.openSettingsAtLaunch)
        defaults.set(visualMode.rawValue, forKey: StartupPreferenceKey.visualMode)
        defaults.set(autoStartCapture, forKey: StartupPreferenceKey.autoStartCapture)
        if let presetID, presetID.isEmpty == false {
            defaults.set(presetID, forKey: StartupPreferenceKey.presetID)
        } else {
            defaults.removeObject(forKey: StartupPreferenceKey.presetID)
        }
        defaults.removeObject(forKey: StartupPreferenceKey.legacyDestination)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        standard.save(to: defaults)
    }

    private static func hasSurfaceKeys(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: StartupPreferenceKey.openStudioAtLaunch) != nil
            || defaults.object(forKey: StartupPreferenceKey.showIslandAtLaunch) != nil
            || defaults.object(forKey: StartupPreferenceKey.openSettingsAtLaunch) != nil
    }

    private static func bool(forKey key: String, in defaults: UserDefaults, fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    /// Maps AUD-18B mutually exclusive destinations into independent surface checkboxes.
    private static func migrateLegacyDestination(
        _ raw: String
    ) -> (openStudioAtLaunch: Bool, showIslandAtLaunch: Bool, openSettingsAtLaunch: Bool)? {
        switch raw {
        case "followExisting":
            return (false, true, false)
        case "menuBarOnly":
            return (false, false, false)
        case "openStudio":
            return (true, true, false)
        case "showIsland":
            return (false, true, false)
        case "openStudioAndIsland":
            return (true, true, false)
        default:
            return nil
        }
    }
}
