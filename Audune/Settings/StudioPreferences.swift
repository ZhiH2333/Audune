import Foundation

nonisolated enum StudioPreferenceKey {
    static let mode = "studio.mode"
    static let windowMode = "studio.windowMode"
    /// Legacy bool. Load migrates it when `windowMode` is absent. Save keeps it in sync.
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

nonisolated enum StudioWindowMode: String, CaseIterable, Identifiable {
    case onDesktop
    case onTop
    case asWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDesktop: return "On Desktop"
        case .onTop: return "On Top"
        case .asWindow: return "As Window"
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
    var windowMode: StudioWindowMode
    var backgroundOpacity: Double
    var accent: StudioAccent
    var barCount: Int

    static let opacityRange: ClosedRange<Double> = 0.35...1
    static let barCounts = [8, 12, 16, 24, 32, 48, 64]
    static let standard = StudioPreferences(
        mode: .spectrum,
        windowMode: .onTop,
        backgroundOpacity: 0.92,
        accent: .warm,
        barCount: 16
    )

    static func load(from defaults: UserDefaults = .standard) -> StudioPreferences {
        let mode = defaults.string(forKey: StudioPreferenceKey.mode).flatMap(StudioVisualMode.init(rawValue:)) ?? standard.mode
        let accent = defaults.string(forKey: StudioPreferenceKey.accent).flatMap(StudioAccent.init(rawValue:)) ?? standard.accent
        let windowMode = resolvedWindowMode(from: defaults)
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
            windowMode: windowMode,
            backgroundOpacity: backgroundOpacity,
            accent: accent,
            barCount: barCount
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: StudioPreferenceKey.mode)
        defaults.set(windowMode.rawValue, forKey: StudioPreferenceKey.windowMode)
        defaults.set(windowMode == .onTop, forKey: StudioPreferenceKey.alwaysOnTop)
        defaults.set(Self.clampedOpacity(backgroundOpacity), forKey: StudioPreferenceKey.backgroundOpacity)
        defaults.set(accent.rawValue, forKey: StudioPreferenceKey.accent)
        defaults.removeObject(forKey: StudioPreferenceKey.cleanCanvas)
        defaults.set(Self.normalizedBarCount(barCount), forKey: StudioPreferenceKey.barCount)
    }

    static func resolvedWindowMode(from defaults: UserDefaults) -> StudioWindowMode {
        if let stored = defaults.string(forKey: StudioPreferenceKey.windowMode).flatMap(StudioWindowMode.init(rawValue:)) {
            return stored
        }
        if defaults.object(forKey: StudioPreferenceKey.alwaysOnTop) == nil {
            return standard.windowMode
        }
        return defaults.bool(forKey: StudioPreferenceKey.alwaysOnTop) ? .onTop : .asWindow
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
