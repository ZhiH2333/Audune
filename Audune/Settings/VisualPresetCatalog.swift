import Foundation

/// Built-in looks are code constants. They are never written into the user's preset blob.
nonisolated enum VisualPresetCatalog {
    static let clean = spectrum(id: "builtin.spectrum.clean", name: "Clean") { prefs in
        prefs.barCount = 24
        prefs.barGap = 4
        prefs.cornerRadius = 3
        prefs.smoothing = 0.55
        prefs.attackMs = 50
        prefs.releaseMs = 420
        prefs.amplitude = 0.85
        prefs.sensitivity = 0.4
        prefs.stroke = false
        prefs.peakHold = false
    }

    static let dense = spectrum(id: "builtin.spectrum.dense", name: "Dense") { prefs in
        prefs.barCount = 64
        prefs.barGap = 0.5
        prefs.cornerRadius = 0.5
        prefs.smoothing = 0.15
        prefs.attackMs = 20
        prefs.releaseMs = 180
        prefs.amplitude = 1.15
        prefs.sensitivity = 0.65
        prefs.minHz = 30
        prefs.maxHz = 18_000
        prefs.colorMode = .frequency
    }

    static let dynamic = spectrum(id: "builtin.spectrum.dynamic", name: "Dynamic") { prefs in
        prefs.barCount = 32
        prefs.amplitude = 1.8
        prefs.smoothing = 0.05
        prefs.attackMs = 8
        prefs.releaseMs = 90
        prefs.sensitivity = 0.85
        prefs.peakHold = true
        prefs.peakHoldSeconds = 0.4
        prefs.stroke = true
        prefs.colorMode = .amplitude
    }

    static let fineLine = waveform(id: "builtin.waveform.fineLine", name: "Fine Line") { prefs in
        prefs.style = .line
        prefs.lineWidth = 0.75
        prefs.density = 128
        prefs.smoothing = 0.25
        prefs.amplitude = 0.45
        prefs.fillStrength = 0
        prefs.customColor = nil
    }

    static let softFill = waveform(id: "builtin.waveform.softFill", name: "Soft Fill") { prefs in
        prefs.style = .softFill
        prefs.lineWidth = 1.5
        prefs.density = 64
        prefs.smoothing = 0.55
        prefs.amplitude = 0.6
        prefs.fillStrength = 0.4
        prefs.customColor = nil
    }

    static let mirror = waveform(id: "builtin.waveform.mirror", name: "Mirror") { prefs in
        prefs.style = .mirror
        prefs.lineWidth = 1.25
        prefs.density = 64
        prefs.smoothing = 0.35
        prefs.amplitude = 0.5
        prefs.fillStrength = 0.22
        prefs.customColor = nil
    }

    static let compact = orbit(id: "builtin.orbit.compact", name: "Compact") { prefs in
        prefs.barCount = 24
        prefs.inner = 0.72
        prefs.outerScale = 0.7
        prefs.gapDegrees = 4
        prefs.mirrored = true
        prefs.amplitude = 0.8
        prefs.smoothing = 0.5
    }

    static let halo = orbit(id: "builtin.orbit.halo", name: "Halo") { prefs in
        prefs.barCount = 32
        prefs.inner = 0.48
        prefs.outerScale = 0.98
        prefs.gapDegrees = 1.5
        prefs.stroke = true
        prefs.lineWidth = 1
        prefs.smoothing = 0.4
        prefs.layerMode = .dualBand
        prefs.pulseStrength = 0.12
    }

    static let denseRing = orbit(id: "builtin.orbit.denseRing", name: "Dense Ring") { prefs in
        prefs.barCount = 64
        prefs.inner = 0.4
        prefs.outerScale = 0.95
        prefs.gapDegrees = 0.5
        prefs.mirrored = false
        prefs.amplitude = 1.3
        prefs.smoothing = 0.15
        prefs.layerMode = .single
        prefs.pulseStrength = 0.2
    }

    static let all = [clean, dense, dynamic, fineLine, softFill, mirror, compact, halo, denseRing]

    static func restoring(from defaults: UserDefaults = .standard) -> VisualPresetLibrary {
        VisualPresetLibrary.load(from: defaults, builtIns: all)
    }

    private static func spectrum(
        id: String,
        name: String,
        _ edit: (inout SpectrumPreferences) -> Void
    ) -> VisualPreset {
        var prefs = SpectrumPreferences.standard
        edit(&prefs)
        return VisualPreset(id: id, name: name, mode: .spectrum, kind: .builtIn, spectrum: prefs.clamped())
    }

    private static func waveform(
        id: String,
        name: String,
        _ edit: (inout WaveformPreferences) -> Void
    ) -> VisualPreset {
        var prefs = WaveformPreferences.standard
        edit(&prefs)
        return VisualPreset(id: id, name: name, mode: .waveform, kind: .builtIn, waveform: prefs.clamped())
    }

    private static func orbit(
        id: String,
        name: String,
        _ edit: (inout OrbitPreferences) -> Void
    ) -> VisualPreset {
        var prefs = OrbitPreferences.standard
        edit(&prefs)
        return VisualPreset(id: id, name: name, mode: .orbit, kind: .builtIn, orbit: prefs.clamped())
    }
}

nonisolated enum VisualPresetMatch: Equatable {
    case applied(VisualPreset)
    case modified(VisualPreset)
    case unsaved

    var statusText: String {
        switch self {
        case .applied(let preset):
            return preset.kind == .builtIn ? "\(preset.name) · Built-in" : "\(preset.name) · Custom"
        case .modified(let preset):
            return "\(preset.name) · Modified"
        case .unsaved:
            return "Unsaved settings"
        }
    }
}
