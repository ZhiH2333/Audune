import Foundation

nonisolated enum StudioPreferenceKey {
    static let mode = "studio.mode"
    static let alwaysOnTop = "studio.alwaysOnTop"
    static let backgroundOpacity = "studio.backgroundOpacity"
    static let accent = "studio.accent"
    /// Retired. Old installs may still have this key; saving clears it.
    static let cleanCanvas = "studio.cleanCanvas"
    static let barCount = "studio.barCount"
}

nonisolated enum StudioVisualMode: String, CaseIterable, Identifiable {
    case spectrum
    case waveform
    case orbit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrum: return "Spectrum"
        case .waveform: return "Waveform"
        case .orbit: return "Orbit"
        }
    }
}

nonisolated enum StudioAccent: String, CaseIterable, Identifiable {
    case warm
    case amber
    case sea
    case mist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: return "Warm"
        case .amber: return "Amber"
        case .sea: return "Sea"
        case .mist: return "Mist"
        }
    }

    var red: Double {
        switch self {
        case .warm: return 0.96
        case .amber: return 0.92
        case .sea: return 0.45
        case .mist: return 0.73
        }
    }

    var green: Double {
        switch self {
        case .warm: return 0.94
        case .amber: return 0.62
        case .sea: return 0.78
        case .mist: return 0.78
        }
    }

    var blue: Double {
        switch self {
        case .warm: return 0.90
        case .amber: return 0.28
        case .sea: return 0.74
        case .mist: return 0.84
        }
    }
}

nonisolated struct StudioPreferences: Equatable {
    var mode: StudioVisualMode
    var alwaysOnTop: Bool
    var backgroundOpacity: Double
    var accent: StudioAccent
    var barCount: Int

    static let opacityRange: ClosedRange<Double> = 0.35...1
    static let barCounts = [8, 12, 16, 24, 32, 48, 64]
    static let standard = StudioPreferences(
        mode: .spectrum,
        alwaysOnTop: true,
        backgroundOpacity: 0.92,
        accent: .warm,
        barCount: 16
    )

    static func load(from defaults: UserDefaults = .standard) -> StudioPreferences {
        let mode = defaults.string(forKey: StudioPreferenceKey.mode).flatMap(StudioVisualMode.init(rawValue:)) ?? standard.mode
        let accent = defaults.string(forKey: StudioPreferenceKey.accent).flatMap(StudioAccent.init(rawValue:)) ?? standard.accent
        let alwaysOnTop = defaults.object(forKey: StudioPreferenceKey.alwaysOnTop) == nil
            ? standard.alwaysOnTop
            : defaults.bool(forKey: StudioPreferenceKey.alwaysOnTop)
        let backgroundOpacity: Double
        if defaults.object(forKey: StudioPreferenceKey.backgroundOpacity) == nil {
            backgroundOpacity = standard.backgroundOpacity
        } else {
            backgroundOpacity = clampedOpacity(defaults.double(forKey: StudioPreferenceKey.backgroundOpacity))
        }
        let barCount = defaults.object(forKey: StudioPreferenceKey.barCount) == nil
            ? standard.barCount
            : normalizedBarCount(defaults.integer(forKey: StudioPreferenceKey.barCount))
        return StudioPreferences(
            mode: mode,
            alwaysOnTop: alwaysOnTop,
            backgroundOpacity: backgroundOpacity,
            accent: accent,
            barCount: barCount
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: StudioPreferenceKey.mode)
        defaults.set(alwaysOnTop, forKey: StudioPreferenceKey.alwaysOnTop)
        defaults.set(Self.clampedOpacity(backgroundOpacity), forKey: StudioPreferenceKey.backgroundOpacity)
        defaults.set(accent.rawValue, forKey: StudioPreferenceKey.accent)
        defaults.removeObject(forKey: StudioPreferenceKey.cleanCanvas)
        defaults.set(Self.normalizedBarCount(barCount), forKey: StudioPreferenceKey.barCount)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        standard.save(to: defaults)
    }

    static func normalizedBarCount(_ value: Int) -> Int {
        barCounts.contains(value) ? value : standard.barCount
    }

    static func clampedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return standard.backgroundOpacity }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
