import Foundation

nonisolated enum StudioPreferenceKey {
    static let mode = "studio.mode"
    static let windowMode = "studio.windowMode"
    /// Legacy bool. Load migrates it when `windowMode` is absent. Save keeps it in sync.
    static let alwaysOnTop = "studio.alwaysOnTop"
    /// Graphic opacity. The key name is older than the transparent window; it never fills the window.
    static let backgroundOpacity = "studio.backgroundOpacity"
    /// Legacy preset name. Read only when `color` is absent.
    static let accent = "studio.accent"
    static let color = "studio.appearance.color"
    static let strokeColor = "studio.appearance.strokeColor"
    /// Retired. Old installs may still have this key; saving clears it.
    static let cleanCanvas = "studio.cleanCanvas"
    /// Legacy shared keys. They seed the per-mode values below when those are absent.
    static let barCount = "studio.barCount"
    static let lineWidth = "studio.lineWidth"
    static let amplitude = "studio.amplitude"
    static let smoothing = "studio.smoothing"
    static let barGap = "studio.barGap"
    static let cornerRadius = "studio.cornerRadius"
    static let spectrumStroke = "studio.spectrumStroke"
    static let orbitInner = "studio.orbitInner"

    static let spectrumBarCount = "studio.spectrum.barCount"
    static let spectrumScale = "studio.spectrum.scale"
    static let spectrumMinHz = "studio.spectrum.minHz"
    static let spectrumMaxHz = "studio.spectrum.maxHz"
    static let spectrumSensitivity = "studio.spectrum.sensitivity"
    static let spectrumAmplitude = "studio.spectrum.amplitude"
    static let spectrumSmoothing = "studio.spectrum.smoothing"
    static let spectrumAttackMs = "studio.spectrum.attackMs"
    static let spectrumReleaseMs = "studio.spectrum.releaseMs"
    static let spectrumPeakHold = "studio.spectrum.peakHold"
    static let spectrumPeakHoldSeconds = "studio.spectrum.peakHoldSeconds"
    static let spectrumPeakFallPerSecond = "studio.spectrum.peakFallPerSecond"
    static let spectrumSilenceGateEnabled = "studio.spectrum.silenceGateEnabled"
    static let spectrumSilenceThreshold = "studio.spectrum.silenceThreshold"
    static let spectrumColorMode = "studio.spectrum.colorMode"

    static let waveformLineWidth = "studio.waveform.lineWidth"
    static let waveformAmplitude = "studio.waveform.amplitude"
    static let waveformSmoothing = "studio.waveform.smoothing"
    static let waveformDensity = "studio.waveform.density"
    static let waveformStyle = "studio.waveform.style"
    static let waveformFillStrength = "studio.waveform.fillStrength"
    static let waveformVerticalRange = "studio.waveform.verticalRange"
    static let waveformColor = "studio.waveform.color"

    static let orbitBarCount = "studio.orbit.barCount"
    static let orbitLineWidth = "studio.orbit.lineWidth"
    static let orbitAmplitude = "studio.orbit.amplitude"
    static let orbitSmoothing = "studio.orbit.smoothing"
    static let orbitOuterScale = "studio.orbit.outerScale"
    static let orbitGapDegrees = "studio.orbit.gapDegrees"
    static let orbitMirrored = "studio.orbit.mirrored"
    static let orbitStroke = "studio.orbit.stroke"
    static let orbitColor = "studio.orbit.color"
    static let orbitLayerMode = "studio.orbit.layerMode"
    static let orbitPulseStrength = "studio.orbit.pulseStrength"

    static let windowAllowsDrag = "studio.window.allowsDrag"
    static let windowAllowsResize = "studio.window.allowsResize"
    static let windowRestorePosition = "studio.window.restorePosition"
    static let windowHideDelay = "studio.window.hideDelaySeconds"
    static let windowAnimatesChrome = "studio.window.animatesChrome"
    static let windowFollowsReduceMotion = "studio.window.followsReduceMotion"
    static let windowPassesMouseThrough = "studio.window.passesMouseThrough"
    static let windowAutoHidesControls = "studio.window.autoHidesControls"
    static let windowSummonRegion = "studio.window.summonRegion"
    static let windowMinWidth = "studio.window.minWidth"
    static let windowMinHeight = "studio.window.minHeight"
    static let windowMaxWidth = "studio.window.maxWidth"
    static let windowMaxHeight = "studio.window.maxHeight"
    static let windowWidth = "studio.window.width"
    static let windowHeight = "studio.window.height"
    static let layoutMode = "studio.layout.mode"
    static let layoutScale = "studio.layout.scale"
    static let layoutAspect = "studio.layout.aspect"
    /// Versioned JSON for custom visual presets. Built-in presets are not stored here.
    static let visualPresets = "studio.visualPresets"
}

nonisolated enum StudioVisualMode: String, Codable, CaseIterable, Identifiable {
    case spectrum
    case waveform
    case orbit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrum: return String(localized: "Spectrum")
        case .waveform: return String(localized: "Waveform")
        case .orbit: return String(localized: "Orbit")
        }
    }

    var symbol: String {
        switch self {
        case .spectrum: return "chart.bar.fill"
        case .waveform: return "waveform"
        case .orbit: return "circle.dotted"
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
        case .onDesktop: return String(localized: "On Desktop")
        case .onTop: return String(localized: "On Top")
        case .asWindow: return String(localized: "As Window")
        }
    }
}

/// An sRGB color stored as `#RRGGBB`. Components are snapped to 1/255 so save and load round-trip exactly.
nonisolated struct StudioColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.snapped(red)
        self.green = Self.snapped(green)
        self.blue = Self.snapped(blue)
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    func blended(towardWhite amount: Double) -> StudioColor {
        let weight = amount.isFinite ? min(max(amount, 0), 1) : 0
        return StudioColor(
            red: red + (1 - red) * weight,
            green: green + (1 - green) * weight,
            blue: blue + (1 - blue) * weight
        )
    }

    /// Rotates hue by `delta` turns (−0.5…0.5 typical). Saturation and lightness stay close to the base.
    func shiftedHue(by delta: Double) -> StudioColor {
        let shift = delta.isFinite ? delta : 0
        var h = 0.0, s = 0.0, l = 0.0
        Self.rgbToHSL(red, green, blue, h: &h, s: &s, l: &l)
        h = h + shift
        h -= floor(h)
        let rgb = Self.hslToRGB(h: h, s: s, l: l)
        return StudioColor(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// Scales perceived lightness toward black (factor < 1) or white (factor > 1), clamped.
    func scaledLightness(_ factor: Double) -> StudioColor {
        let scale = factor.isFinite ? max(factor, 0) : 1
        var h = 0.0, s = 0.0, l = 0.0
        Self.rgbToHSL(red, green, blue, h: &h, s: &s, l: &l)
        l = min(max(l * scale, 0), 1)
        let rgb = Self.hslToRGB(h: h, s: s, l: l)
        return StudioColor(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private static func snapped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(max(value, 0), 1) * 255).rounded() / 255
    }

    private static func rgbToHSL(_ r: Double, _ g: Double, _ b: Double, h: inout Double, s: inout Double, l: inout Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        l = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0.000_001 else {
            h = 0
            s = 0
            return
        }
        s = l > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC)
        if maxC == r {
            h = (g - b) / delta + (g < b ? 6 : 0)
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h /= 6
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        guard s > 0.000_001 else { return (l, l, l) }
        func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (hue2rgb(p, q, h + 1.0 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3))
    }
}

nonisolated enum SpectrumColorMode: String, Codable, CaseIterable, Identifiable {
    case solid
    case frequency
    case amplitude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return String(localized: "Solid")
        case .frequency: return String(localized: "Frequency")
        case .amplitude: return String(localized: "Amplitude")
        }
    }
}

/// Pure fill colors for Spectrum bars. Compact Island keeps Appearance solid color.
nonisolated enum SpectrumColorMap {
    static func fill(
        mode: SpectrumColorMode,
        base: StudioColor,
        index: Int,
        count: Int,
        level: Float
    ) -> StudioColor {
        switch mode {
        case .solid:
            return base
        case .frequency:
            let t = count > 1 ? Double(index) / Double(count - 1) : 0
            return base.shiftedHue(by: (t - 0.5) * 0.4)
        case .amplitude:
            let safe = level.isFinite ? min(max(Double(level), 0), 1) : 0
            return base.scaledLightness(0.55 + 0.55 * safe)
        }
    }
}

/// One-tap color presets. Applying one sets the fill and stroke colors; it is not stored on its own.
nonisolated enum StudioAccent: String, CaseIterable, Identifiable {
    case warm
    case amber
    case sea
    case mist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: return String(localized: "Warm")
        case .amber: return String(localized: "Amber")
        case .sea: return String(localized: "Sea")
        case .mist: return String(localized: "Mist")
        }
    }

    var color: StudioColor {
        switch self {
        case .warm: return StudioColor(red: 0.96, green: 0.94, blue: 0.90)
        case .amber: return StudioColor(red: 0.92, green: 0.62, blue: 0.28)
        case .sea: return StudioColor(red: 0.45, green: 0.78, blue: 0.74)
        case .mist: return StudioColor(red: 0.73, green: 0.78, blue: 0.84)
        }
    }

    var strokeColor: StudioColor {
        color.blended(towardWhite: 0.35)
    }

    static func matching(color: StudioColor, strokeColor: StudioColor) -> StudioAccent? {
        allCases.first { $0.color == color && $0.strokeColor == strokeColor }
    }
}

nonisolated enum SpectrumScale: String, Codable, CaseIterable, Identifiable {
    case log
    case linear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .log: return String(localized: "Logarithmic")
        case .linear: return String(localized: "Linear")
        }
    }
}

nonisolated struct AppearancePreferences: Equatable {
    var color: StudioColor
    var strokeColor: StudioColor
    var opacity: Double
    var lineWidth: Double

    static let standard = AppearancePreferences(
        color: StudioAccent.warm.color,
        strokeColor: StudioAccent.warm.strokeColor,
        opacity: 0.92,
        lineWidth: 1.5
    )

    mutating func apply(_ preset: StudioAccent) {
        color = preset.color
        strokeColor = preset.strokeColor
    }
}

nonisolated struct SpectrumPreferences: Equatable {
    var barCount: Int
    var scale: SpectrumScale
    var minHz: Double
    var maxHz: Double
    var barGap: Double
    var cornerRadius: Double
    var stroke: Bool
    /// How bar fill color is derived from Appearance. Default solid matches older installs.
    var colorMode: SpectrumColorMode
    var sensitivity: Double
    var amplitude: Double
    var smoothing: Double
    var attackMs: Double
    var releaseMs: Double
    var peakHold: Bool
    var peakHoldSeconds: Double
    /// Peak cap fall speed after hold, in display units per second.
    var peakFallPerSecond: Double
    /// When true, low PCM RMS marks the shared snapshot silent for visuals only.
    var silenceGateEnabled: Bool
    /// Raw PCM RMS enter threshold. Same scale as analyzer RMS before unit clamping.
    var silenceThreshold: Double

    static let standard = SpectrumPreferences(
        barCount: 32,
        scale: .log,
        minHz: 40,
        maxHz: 16_000,
        barGap: 2,
        cornerRadius: 2,
        stroke: false,
        colorMode: .solid,
        sensitivity: 0.5,
        amplitude: 1,
        smoothing: 0.3,
        attackMs: 35,
        releaseMs: 260,
        peakHold: false,
        peakHoldSeconds: 0.6,
        peakFallPerSecond: Double(SpectrumDynamicsSettings.defaultPeakFallPerSecond),
        silenceGateEnabled: true,
        silenceThreshold: Double(SilenceGateSettings.standard.enterRMS)
    )

    var silenceGate: SilenceGateSettings {
        SilenceGateSettings.from(enabled: silenceGateEnabled, threshold: silenceThreshold)
    }

    /// Sensitivity moves the quiet end of the dB window. 0.5 keeps the original -60 dB floor.
    var floorDecibels: Double {
        -40 - 40 * sensitivity
    }

    var layout: SpectrumBandLayout {
        SpectrumBandLayout(
            scale: scale,
            minHz: minHz,
            maxHz: maxHz,
            floorDecibels: Float(floorDecibels),
            tiltDecibels: SpectrumBandLayout.perceptualTiltDecibels
        )
    }

    var dynamics: SpectrumDynamicsSettings {
        SpectrumDynamicsSettings(
            attackSeconds: attackMs / 1000,
            releaseSeconds: releaseMs / 1000,
            neighborSmoothing: Float(smoothing),
            peakHoldSeconds: peakHold ? peakHoldSeconds : nil,
            peakFallPerSecond: Float(peakFallPerSecond)
        )
    }
}

nonisolated enum WaveformStyle: String, Codable, CaseIterable, Identifiable {
    case line
    case softFill
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return String(localized: "Fine Line")
        case .softFill: return String(localized: "Soft Fill")
        case .mirror: return String(localized: "Mirror")
        }
    }

    /// Accepts the legacy `"filled"` raw value from older prefs and presets.
    init?(rawValue: String) {
        switch rawValue {
        case "line": self = .line
        case "softFill", "filled": self = .softFill
        case "mirror": self = .mirror
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WaveformStyle(rawValue: raw) ?? .line
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct WaveformPreferences: Equatable {
    var lineWidth: Double
    /// Visual amplitude only. Does not change captured PCM or system volume.
    var amplitude: Double
    /// Peak-to-peak share of the drawable height the waveform may occupy (display only).
    var verticalRange: Double
    /// Motion smoothing 0…1 mapped to a time constant. Spatial soften uses a fraction of this.
    var smoothing: Double
    /// How many of the real PCM points are drawn. Never more than the snapshot provides.
    var density: Int
    var style: WaveformStyle
    /// Fill opacity share for Soft Fill / Mirror. Ignored by Fine Line.
    var fillStrength: Double
    /// `nil` follows the Appearance color.
    var customColor: StudioColor?

    static let standard = WaveformPreferences(
        lineWidth: 1.25,
        amplitude: 0.55,
        verticalRange: 0.7,
        smoothing: 0.4,
        density: 64,
        style: .line,
        fillStrength: 0.32,
        customColor: nil
    )
}

nonisolated enum OrbitLayerMode: String, Codable, CaseIterable, Identifiable {
    case single
    case dualBand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return String(localized: "Single")
        case .dualBand: return String(localized: "Dual Band")
        }
    }
}

nonisolated struct OrbitPreferences: Equatable {
    /// Total bars around the ring. Mirrored rings read half as many bands and show each twice.
    var barCount: Int
    /// Inner radius as a share of the outer radius.
    var inner: Double
    /// Outer radius as a share of the half of the shorter canvas side.
    var outerScale: Double
    var gapDegrees: Double
    var mirrored: Bool
    var stroke: Bool
    var lineWidth: Double
    var amplitude: Double
    var smoothing: Double
    /// Single ring or dual rings mapped from low / high halves of the band list.
    var layerMode: OrbitLayerMode
    /// Extra bar length from mean band energy. 0 disables. Capped for a restrained look.
    var pulseStrength: Double
    /// `nil` follows the Appearance color.
    var customColor: StudioColor?

    static let standard = OrbitPreferences(
        barCount: 48,
        inner: 0.55,
        outerScale: 0.92,
        gapDegrees: 2.5,
        mirrored: true,
        stroke: false,
        lineWidth: 1.5,
        amplitude: 1,
        smoothing: 0.35,
        layerMode: .single,
        pulseStrength: 0,
        customColor: nil
    )

    var bandCount: Int {
        OrbitLayout.bandCount(barCount: barCount, mirrored: mirrored)
    }

    var bandLayout: SpectrumBandLayout {
        var layout = SpectrumBandLayout.standard
        layout.tiltDecibels = SpectrumBandLayout.perceptualTiltDecibels
        return layout
    }

    /// Asymmetric fast-attack / smooth-release dynamics derived from `smoothing` so radial bars punch on transients.
    var dynamics: SpectrumDynamicsSettings {
        let amount = smoothing.isFinite ? min(max(smoothing, 0), 1) : 0.35
        return SpectrumDynamicsSettings(
            attackSeconds: 0.018 + amount * 0.055,
            releaseSeconds: 0.14 + amount * 0.38,
            neighborSmoothing: Float(amount * 0.35),
            peakHoldSeconds: nil,
            peakFallPerSecond: SpectrumDynamicsSettings.defaultPeakFallPerSecond
        )
    }
}

/// Where the pointer brings hidden Studio controls back. The hidden buttons themselves are not a target.
nonisolated enum StudioSummonRegion: String, CaseIterable, Identifiable, Sendable {
    case grip
    case bottomEdge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grip: "Grip"
        case .bottomEdge: "Bottom edge"
        }
    }
}

/// Window behavior that is not the level. The level and Spaces behavior come from `StudioWindowMode`.
nonisolated struct WindowPreferences: Equatable {
    var allowsDrag: Bool
    var allowsResize: Bool
    var restorePosition: Bool
    /// Wait after the pointer leaves before the controls fade out.
    var hideDelaySeconds: Double
    var animatesChrome: Bool
    /// When true, the system Reduce Motion setting removes the fade.
    var followsReduceMotion: Bool
    /// Canvas clicks pass through. Controls live on a separate panel.
    var passesMouseThrough: Bool
    /// When false, the controls stay visible.
    var autoHidesControls: Bool
    var summonRegion: StudioSummonRegion
    /// Preferred Studio window size in points. Synced with the live frame after resize.
    var width: Double
    var height: Double
    /// Legacy min/max limits. Kept for decode/save compatibility; AppKit uses internal floors instead.
    var minWidth: Double
    var minHeight: Double
    var maxWidth: Double
    var maxHeight: Double

    static let standard = WindowPreferences(
        allowsDrag: true,
        allowsResize: true,
        restorePosition: true,
        hideDelaySeconds: 0.8,
        animatesChrome: true,
        followsReduceMotion: true,
        passesMouseThrough: true,
        autoHidesControls: true,
        summonRegion: .bottomEdge,
        width: Double(StudioFrame.defaultSize.width),
        height: Double(StudioFrame.defaultSize.height),
        minWidth: Double(StudioFrame.absoluteMinimum.width),
        minHeight: Double(StudioFrame.absoluteMinimum.height),
        maxWidth: Double(StudioFrame.defaultMaximumSize.width),
        maxHeight: Double(StudioFrame.defaultMaximumSize.height)
    )
}

/// How the visualization is sized inside the Studio window. Independent of the window's own size limits.
nonisolated enum VisualLayoutMode: String, CaseIterable, Identifiable {
    /// Visualization fills the whole window (older behavior).
    case fill
    /// Visualization keeps its own size; the window is only the area it sits in.
    case fixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return String(localized: "Fill window")
        case .fixed: return String(localized: "Fixed size")
        }
    }
}

nonisolated enum VisualAspect: String, CaseIterable, Identifiable {
    case wide
    case standard
    case square
    case ultrawide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wide: return "16:10"
        case .standard: return "4:3"
        case .square: return "1:1"
        case .ultrawide: return "2:1"
        }
    }

    /// Width divided by height.
    var ratio: Double {
        switch self {
        case .wide: return 16.0 / 10.0
        case .standard: return 4.0 / 3.0
        case .square: return 1
        case .ultrawide: return 2
        }
    }
}

nonisolated struct VisualLayoutPreferences: Equatable {
    var mode: VisualLayoutMode
    /// Multiplies the 640 pt reference width in Fixed mode.
    var scale: Double
    var aspect: VisualAspect

    static let standard = VisualLayoutPreferences(mode: .fixed, scale: 1, aspect: .wide)
    static let scaleRange: ClosedRange<Double> = 0.25...2
    static let referenceWidth: Double = 640
}

nonisolated struct StudioPreferences: Equatable {
    var mode: StudioVisualMode
    var windowMode: StudioWindowMode
    var window: WindowPreferences
    var layout: VisualLayoutPreferences = .standard
    var appearance: AppearancePreferences
    var spectrum: SpectrumPreferences
    var waveform: WaveformPreferences
    var orbit: OrbitPreferences

    static let opacityRange: ClosedRange<Double> = 0.35...1
    static let lineWidthRange: ClosedRange<Double> = 0.5...4
    static let amplitudeRange: ClosedRange<Double> = 0.25...3
    /// Waveform visual amplitude. Narrower and calmer than Spectrum/Orbit amplitude.
    static let waveformAmplitudeRange: ClosedRange<Double> = 0.1...2
    /// Maximum peak-to-peak share of drawable height. Separate from visual amplitude.
    static let waveformVerticalRangeRange: ClosedRange<Double> = 0.3...1
    static let fillStrengthRange: ClosedRange<Double> = 0...1
    static let smoothingRange: ClosedRange<Double> = 0...1
    static let barGapRange: ClosedRange<Double> = 0...8
    static let cornerRadiusRange: ClosedRange<Double> = 0...8
    static let orbitInnerRange: ClosedRange<Double> = 0.35...0.8
    static let orbitOuterRange: ClosedRange<Double> = 0.6...1
    static let orbitGapRange: ClosedRange<Double> = 0...10
    static let orbitPulseRange: ClosedRange<Double> = 0...0.35
    static let hideDelayRange: ClosedRange<Double> = 0.2...3
    static let minHzRange: ClosedRange<Double> = 20...500
    static let maxHzRange: ClosedRange<Double> = 2_000...20_000
    static let sensitivityRange: ClosedRange<Double> = 0...1
    static let attackMsRange: ClosedRange<Double> = 5...200
    static let releaseMsRange: ClosedRange<Double> = 60...1_000
    static let peakHoldSecondsRange: ClosedRange<Double> = 0.1...2
    static let peakFallPerSecondRange: ClosedRange<Double> = 0.2...2
    static let silenceThresholdRange: ClosedRange<Double> = 0.0001...0.01
    static let windowMinWidthRange: ClosedRange<Double> = 360...800
    static let windowMinHeightRange: ClosedRange<Double> = 240...600
    static let windowMaxWidthRange: ClosedRange<Double> = 640...3840
    static let windowMaxHeightRange: ClosedRange<Double> = 400...2160
    /// Preferred Studio window size in points (not physical pixels).
    static let windowWidthRange: ClosedRange<Double> = 360...3840
    static let windowHeightRange: ClosedRange<Double> = 240...2160
    static let barCounts = [8, 12, 16, 24, 32, 48, 64]
    static let densities = [32, 64, 128]

    static let standard = StudioPreferences(
        mode: .spectrum,
        windowMode: .onTop,
        window: .standard,
        layout: .standard,
        appearance: .standard,
        spectrum: .standard,
        waveform: .standard,
        orbit: .standard
    )

    static func load(from defaults: UserDefaults = .standard) -> StudioPreferences {
        let reader = Reader(defaults: defaults)
        let standard = Self.standard
        let mode = defaults.string(forKey: StudioPreferenceKey.mode).flatMap(StudioVisualMode.init(rawValue:)) ?? standard.mode
        let legacyAccent = defaults.string(forKey: StudioPreferenceKey.accent).flatMap(StudioAccent.init(rawValue:))
        let color = reader.color(StudioPreferenceKey.color, fallback: legacyAccent?.color ?? standard.appearance.color)
        let strokeColor = reader.color(StudioPreferenceKey.strokeColor, fallback: legacyAccent?.strokeColor ?? standard.appearance.strokeColor)
        let lineWidth = reader.double(StudioPreferenceKey.lineWidth, range: lineWidthRange, fallback: standard.appearance.lineWidth)
        let legacyLine = defaults.object(forKey: StudioPreferenceKey.lineWidth) == nil ? nil : lineWidth
        let legacyAmplitude = reader.optionalDouble(StudioPreferenceKey.amplitude, range: amplitudeRange)
        let legacySmoothing = reader.optionalDouble(StudioPreferenceKey.smoothing, range: smoothingRange)
        let legacyCount = reader.optionalBarCount(StudioPreferenceKey.barCount)
        let minHz = reader.double(StudioPreferenceKey.spectrumMinHz, range: minHzRange, fallback: standard.spectrum.minHz)
        let maxHz = reader.double(StudioPreferenceKey.spectrumMaxHz, range: maxHzRange, fallback: standard.spectrum.maxHz)

        return StudioPreferences(
            mode: mode,
            windowMode: resolvedWindowMode(from: defaults),
            window: WindowPreferences(
                allowsDrag: reader.bool(StudioPreferenceKey.windowAllowsDrag, fallback: standard.window.allowsDrag),
                allowsResize: reader.bool(StudioPreferenceKey.windowAllowsResize, fallback: standard.window.allowsResize),
                restorePosition: reader.bool(StudioPreferenceKey.windowRestorePosition, fallback: standard.window.restorePosition),
                hideDelaySeconds: reader.double(StudioPreferenceKey.windowHideDelay, range: hideDelayRange, fallback: standard.window.hideDelaySeconds),
                animatesChrome: reader.bool(StudioPreferenceKey.windowAnimatesChrome, fallback: standard.window.animatesChrome),
                followsReduceMotion: reader.bool(StudioPreferenceKey.windowFollowsReduceMotion, fallback: standard.window.followsReduceMotion),
                passesMouseThrough: true,
                autoHidesControls: reader.bool(StudioPreferenceKey.windowAutoHidesControls, fallback: standard.window.autoHidesControls),
                summonRegion: defaults.string(forKey: StudioPreferenceKey.windowSummonRegion).flatMap(StudioSummonRegion.init(rawValue:)) ?? standard.window.summonRegion,
                width: reader.double(StudioPreferenceKey.windowWidth, range: windowWidthRange, fallback: standard.window.width),
                height: reader.double(StudioPreferenceKey.windowHeight, range: windowHeightRange, fallback: standard.window.height),
                minWidth: reader.double(StudioPreferenceKey.windowMinWidth, range: windowMinWidthRange, fallback: standard.window.minWidth),
                minHeight: reader.double(StudioPreferenceKey.windowMinHeight, range: windowMinHeightRange, fallback: standard.window.minHeight),
                maxWidth: reader.double(StudioPreferenceKey.windowMaxWidth, range: windowMaxWidthRange, fallback: standard.window.maxWidth),
                maxHeight: reader.double(StudioPreferenceKey.windowMaxHeight, range: windowMaxHeightRange, fallback: standard.window.maxHeight)
            ),
            layout: VisualLayoutPreferences(
                mode: defaults.string(forKey: StudioPreferenceKey.layoutMode).flatMap(VisualLayoutMode.init(rawValue:)) ?? standard.layout.mode,
                scale: reader.double(StudioPreferenceKey.layoutScale, range: VisualLayoutPreferences.scaleRange, fallback: standard.layout.scale),
                aspect: defaults.string(forKey: StudioPreferenceKey.layoutAspect).flatMap(VisualAspect.init(rawValue:)) ?? standard.layout.aspect
            ),
            appearance: AppearancePreferences(
                color: color,
                strokeColor: strokeColor,
                opacity: reader.double(StudioPreferenceKey.backgroundOpacity, range: opacityRange, fallback: standard.appearance.opacity),
                lineWidth: lineWidth
            ),
            spectrum: SpectrumPreferences(
                barCount: reader.barCount(StudioPreferenceKey.spectrumBarCount, legacy: legacyCount, fallback: standard.spectrum.barCount),
                scale: defaults.string(forKey: StudioPreferenceKey.spectrumScale).flatMap(SpectrumScale.init(rawValue:)) ?? standard.spectrum.scale,
                minHz: minHz,
                maxHz: maxHz,
                barGap: reader.double(StudioPreferenceKey.barGap, range: barGapRange, fallback: standard.spectrum.barGap),
                cornerRadius: reader.double(StudioPreferenceKey.cornerRadius, range: cornerRadiusRange, fallback: standard.spectrum.cornerRadius),
                stroke: reader.bool(StudioPreferenceKey.spectrumStroke, fallback: standard.spectrum.stroke),
                colorMode: defaults.string(forKey: StudioPreferenceKey.spectrumColorMode).flatMap(SpectrumColorMode.init(rawValue:)) ?? standard.spectrum.colorMode,
                sensitivity: reader.double(StudioPreferenceKey.spectrumSensitivity, range: sensitivityRange, fallback: standard.spectrum.sensitivity),
                amplitude: reader.double(StudioPreferenceKey.spectrumAmplitude, legacy: legacyAmplitude, range: amplitudeRange, fallback: standard.spectrum.amplitude),
                smoothing: reader.double(StudioPreferenceKey.spectrumSmoothing, legacy: legacySmoothing, range: smoothingRange, fallback: standard.spectrum.smoothing),
                attackMs: reader.double(StudioPreferenceKey.spectrumAttackMs, range: attackMsRange, fallback: standard.spectrum.attackMs),
                releaseMs: reader.double(StudioPreferenceKey.spectrumReleaseMs, range: releaseMsRange, fallback: standard.spectrum.releaseMs),
                peakHold: reader.bool(StudioPreferenceKey.spectrumPeakHold, fallback: standard.spectrum.peakHold),
                peakHoldSeconds: reader.double(StudioPreferenceKey.spectrumPeakHoldSeconds, range: peakHoldSecondsRange, fallback: standard.spectrum.peakHoldSeconds),
                peakFallPerSecond: reader.double(StudioPreferenceKey.spectrumPeakFallPerSecond, range: peakFallPerSecondRange, fallback: standard.spectrum.peakFallPerSecond),
                silenceGateEnabled: reader.bool(StudioPreferenceKey.spectrumSilenceGateEnabled, fallback: standard.spectrum.silenceGateEnabled),
                silenceThreshold: reader.double(StudioPreferenceKey.spectrumSilenceThreshold, range: silenceThresholdRange, fallback: standard.spectrum.silenceThreshold)
            ),
            waveform: WaveformPreferences(
                lineWidth: reader.double(StudioPreferenceKey.waveformLineWidth, legacy: legacyLine, range: lineWidthRange, fallback: standard.waveform.lineWidth),
                amplitude: reader.double(StudioPreferenceKey.waveformAmplitude, legacy: legacyAmplitude, range: waveformAmplitudeRange, fallback: standard.waveform.amplitude),
                verticalRange: reader.double(StudioPreferenceKey.waveformVerticalRange, range: waveformVerticalRangeRange, fallback: standard.waveform.verticalRange),
                smoothing: reader.double(StudioPreferenceKey.waveformSmoothing, legacy: legacySmoothing, range: smoothingRange, fallback: standard.waveform.smoothing),
                density: reader.density(StudioPreferenceKey.waveformDensity, fallback: standard.waveform.density),
                style: defaults.string(forKey: StudioPreferenceKey.waveformStyle).flatMap(WaveformStyle.init(rawValue:)) ?? standard.waveform.style,
                fillStrength: reader.double(StudioPreferenceKey.waveformFillStrength, range: fillStrengthRange, fallback: standard.waveform.fillStrength),
                customColor: defaults.string(forKey: StudioPreferenceKey.waveformColor).flatMap(StudioColor.init(hex:))
            ),
            orbit: OrbitPreferences(
                barCount: reader.barCount(StudioPreferenceKey.orbitBarCount, legacy: legacyCount, fallback: standard.orbit.barCount),
                inner: reader.double(StudioPreferenceKey.orbitInner, range: orbitInnerRange, fallback: standard.orbit.inner),
                outerScale: reader.double(StudioPreferenceKey.orbitOuterScale, range: orbitOuterRange, fallback: standard.orbit.outerScale),
                gapDegrees: reader.double(StudioPreferenceKey.orbitGapDegrees, range: orbitGapRange, fallback: standard.orbit.gapDegrees),
                mirrored: reader.bool(StudioPreferenceKey.orbitMirrored, fallback: standard.orbit.mirrored),
                stroke: reader.bool(StudioPreferenceKey.orbitStroke, fallback: standard.orbit.stroke),
                lineWidth: reader.double(StudioPreferenceKey.orbitLineWidth, legacy: legacyLine, range: lineWidthRange, fallback: standard.orbit.lineWidth),
                amplitude: reader.double(StudioPreferenceKey.orbitAmplitude, legacy: legacyAmplitude, range: amplitudeRange, fallback: standard.orbit.amplitude),
                smoothing: reader.double(StudioPreferenceKey.orbitSmoothing, legacy: legacySmoothing, range: smoothingRange, fallback: standard.orbit.smoothing),
                layerMode: defaults.string(forKey: StudioPreferenceKey.orbitLayerMode).flatMap(OrbitLayerMode.init(rawValue:)) ?? standard.orbit.layerMode,
                pulseStrength: reader.double(StudioPreferenceKey.orbitPulseStrength, range: orbitPulseRange, fallback: standard.orbit.pulseStrength),
                customColor: defaults.string(forKey: StudioPreferenceKey.orbitColor).flatMap(StudioColor.init(hex:))
            )
        ).normalized()
    }

    /// Clamps every value into its documented range. Applied on load and before save.
    func normalized() -> StudioPreferences {
        var result = self
        let standard = Self.standard
        result.window.hideDelaySeconds = Self.clamped(window.hideDelaySeconds, to: Self.hideDelayRange, fallback: standard.window.hideDelaySeconds)
        result.window.passesMouseThrough = true
        result.window.width = Self.clamped(window.width, to: Self.windowWidthRange, fallback: standard.window.width)
        result.window.height = Self.clamped(window.height, to: Self.windowHeightRange, fallback: standard.window.height)
        // Legacy limits stay in range for old keys; live windows use absolute floor + screen max.
        result.window.minWidth = Self.clamped(window.minWidth, to: Self.windowMinWidthRange, fallback: standard.window.minWidth)
        result.window.minHeight = Self.clamped(window.minHeight, to: Self.windowMinHeightRange, fallback: standard.window.minHeight)
        result.window.maxWidth = Self.clamped(window.maxWidth, to: Self.windowMaxWidthRange, fallback: standard.window.maxWidth)
        result.window.maxHeight = Self.clamped(window.maxHeight, to: Self.windowMaxHeightRange, fallback: standard.window.maxHeight)
        if result.window.maxWidth < result.window.minWidth {
            result.window.maxWidth = result.window.minWidth
        }
        if result.window.maxHeight < result.window.minHeight {
            result.window.maxHeight = result.window.minHeight
        }
        result.layout.scale = Self.clamped(layout.scale, to: VisualLayoutPreferences.scaleRange, fallback: standard.layout.scale)
        result.appearance.opacity = Self.clamped(appearance.opacity, to: Self.opacityRange, fallback: standard.appearance.opacity)
        result.appearance.lineWidth = Self.clamped(appearance.lineWidth, to: Self.lineWidthRange, fallback: standard.appearance.lineWidth)
        result.spectrum.barCount = Self.normalizedBarCount(spectrum.barCount)
        result.spectrum.minHz = Self.clamped(spectrum.minHz, to: Self.minHzRange, fallback: standard.spectrum.minHz)
        result.spectrum.maxHz = Self.clamped(spectrum.maxHz, to: Self.maxHzRange, fallback: standard.spectrum.maxHz)
        result.spectrum.barGap = Self.clamped(spectrum.barGap, to: Self.barGapRange, fallback: standard.spectrum.barGap)
        result.spectrum.cornerRadius = Self.clamped(spectrum.cornerRadius, to: Self.cornerRadiusRange, fallback: standard.spectrum.cornerRadius)
        result.spectrum.sensitivity = Self.clamped(spectrum.sensitivity, to: Self.sensitivityRange, fallback: standard.spectrum.sensitivity)
        result.spectrum.amplitude = Self.clamped(spectrum.amplitude, to: Self.amplitudeRange, fallback: standard.spectrum.amplitude)
        result.spectrum.smoothing = Self.clamped(spectrum.smoothing, to: Self.smoothingRange, fallback: standard.spectrum.smoothing)
        result.spectrum.attackMs = Self.clamped(spectrum.attackMs, to: Self.attackMsRange, fallback: standard.spectrum.attackMs)
        result.spectrum.releaseMs = Self.clamped(spectrum.releaseMs, to: Self.releaseMsRange, fallback: standard.spectrum.releaseMs)
        result.spectrum.peakHoldSeconds = Self.clamped(spectrum.peakHoldSeconds, to: Self.peakHoldSecondsRange, fallback: standard.spectrum.peakHoldSeconds)
        result.spectrum.peakFallPerSecond = Self.clamped(spectrum.peakFallPerSecond, to: Self.peakFallPerSecondRange, fallback: standard.spectrum.peakFallPerSecond)
        result.spectrum.silenceThreshold = Self.clamped(spectrum.silenceThreshold, to: Self.silenceThresholdRange, fallback: standard.spectrum.silenceThreshold)
        result.waveform.lineWidth = Self.clamped(waveform.lineWidth, to: Self.lineWidthRange, fallback: standard.waveform.lineWidth)
        result.waveform.amplitude = Self.clamped(waveform.amplitude, to: Self.waveformAmplitudeRange, fallback: standard.waveform.amplitude)
        result.waveform.verticalRange = Self.clamped(waveform.verticalRange, to: Self.waveformVerticalRangeRange, fallback: standard.waveform.verticalRange)
        result.waveform.smoothing = Self.clamped(waveform.smoothing, to: Self.smoothingRange, fallback: standard.waveform.smoothing)
        result.waveform.density = Self.densities.contains(waveform.density) ? waveform.density : standard.waveform.density
        result.waveform.fillStrength = Self.clamped(waveform.fillStrength, to: Self.fillStrengthRange, fallback: standard.waveform.fillStrength)
        result.orbit.barCount = Self.normalizedBarCount(orbit.barCount)
        result.orbit.inner = Self.clamped(orbit.inner, to: Self.orbitInnerRange, fallback: standard.orbit.inner)
        result.orbit.outerScale = Self.clamped(orbit.outerScale, to: Self.orbitOuterRange, fallback: standard.orbit.outerScale)
        result.orbit.gapDegrees = Self.clamped(orbit.gapDegrees, to: Self.orbitGapRange, fallback: standard.orbit.gapDegrees)
        result.orbit.lineWidth = Self.clamped(orbit.lineWidth, to: Self.lineWidthRange, fallback: standard.orbit.lineWidth)
        result.orbit.amplitude = Self.clamped(orbit.amplitude, to: Self.amplitudeRange, fallback: standard.orbit.amplitude)
        result.orbit.smoothing = Self.clamped(orbit.smoothing, to: Self.smoothingRange, fallback: standard.orbit.smoothing)
        result.orbit.pulseStrength = Self.clamped(orbit.pulseStrength, to: Self.orbitPulseRange, fallback: standard.orbit.pulseStrength)
        return result
    }

    func save(to defaults: UserDefaults = .standard) {
        let p = normalized()
        defaults.set(p.mode.rawValue, forKey: StudioPreferenceKey.mode)
        defaults.set(p.windowMode.rawValue, forKey: StudioPreferenceKey.windowMode)
        defaults.set(p.windowMode == .onTop, forKey: StudioPreferenceKey.alwaysOnTop)
        defaults.removeObject(forKey: StudioPreferenceKey.cleanCanvas)
        defaults.removeObject(forKey: StudioPreferenceKey.accent)

        defaults.set(p.window.allowsDrag, forKey: StudioPreferenceKey.windowAllowsDrag)
        defaults.set(p.window.allowsResize, forKey: StudioPreferenceKey.windowAllowsResize)
        defaults.set(p.window.restorePosition, forKey: StudioPreferenceKey.windowRestorePosition)
        defaults.set(p.window.hideDelaySeconds, forKey: StudioPreferenceKey.windowHideDelay)
        defaults.set(p.window.animatesChrome, forKey: StudioPreferenceKey.windowAnimatesChrome)
        defaults.set(p.window.followsReduceMotion, forKey: StudioPreferenceKey.windowFollowsReduceMotion)
        defaults.set(p.window.passesMouseThrough, forKey: StudioPreferenceKey.windowPassesMouseThrough)
        defaults.set(p.window.autoHidesControls, forKey: StudioPreferenceKey.windowAutoHidesControls)
        defaults.set(p.window.summonRegion.rawValue, forKey: StudioPreferenceKey.windowSummonRegion)
        defaults.set(p.window.width, forKey: StudioPreferenceKey.windowWidth)
        defaults.set(p.window.height, forKey: StudioPreferenceKey.windowHeight)
        defaults.set(p.window.minWidth, forKey: StudioPreferenceKey.windowMinWidth)
        defaults.set(p.window.minHeight, forKey: StudioPreferenceKey.windowMinHeight)
        defaults.set(p.window.maxWidth, forKey: StudioPreferenceKey.windowMaxWidth)
        defaults.set(p.window.maxHeight, forKey: StudioPreferenceKey.windowMaxHeight)
        defaults.set(p.layout.mode.rawValue, forKey: StudioPreferenceKey.layoutMode)
        defaults.set(p.layout.scale, forKey: StudioPreferenceKey.layoutScale)
        defaults.set(p.layout.aspect.rawValue, forKey: StudioPreferenceKey.layoutAspect)

        defaults.set(p.appearance.color.hex, forKey: StudioPreferenceKey.color)
        defaults.set(p.appearance.strokeColor.hex, forKey: StudioPreferenceKey.strokeColor)
        defaults.set(p.appearance.opacity, forKey: StudioPreferenceKey.backgroundOpacity)
        defaults.set(p.appearance.lineWidth, forKey: StudioPreferenceKey.lineWidth)

        defaults.set(p.spectrum.barCount, forKey: StudioPreferenceKey.spectrumBarCount)
        defaults.set(p.spectrum.scale.rawValue, forKey: StudioPreferenceKey.spectrumScale)
        defaults.set(p.spectrum.minHz, forKey: StudioPreferenceKey.spectrumMinHz)
        defaults.set(p.spectrum.maxHz, forKey: StudioPreferenceKey.spectrumMaxHz)
        defaults.set(p.spectrum.barGap, forKey: StudioPreferenceKey.barGap)
        defaults.set(p.spectrum.cornerRadius, forKey: StudioPreferenceKey.cornerRadius)
        defaults.set(p.spectrum.stroke, forKey: StudioPreferenceKey.spectrumStroke)
        defaults.set(p.spectrum.colorMode.rawValue, forKey: StudioPreferenceKey.spectrumColorMode)
        defaults.set(p.spectrum.sensitivity, forKey: StudioPreferenceKey.spectrumSensitivity)
        defaults.set(p.spectrum.amplitude, forKey: StudioPreferenceKey.spectrumAmplitude)
        defaults.set(p.spectrum.smoothing, forKey: StudioPreferenceKey.spectrumSmoothing)
        defaults.set(p.spectrum.attackMs, forKey: StudioPreferenceKey.spectrumAttackMs)
        defaults.set(p.spectrum.releaseMs, forKey: StudioPreferenceKey.spectrumReleaseMs)
        defaults.set(p.spectrum.peakHold, forKey: StudioPreferenceKey.spectrumPeakHold)
        defaults.set(p.spectrum.peakHoldSeconds, forKey: StudioPreferenceKey.spectrumPeakHoldSeconds)
        defaults.set(p.spectrum.peakFallPerSecond, forKey: StudioPreferenceKey.spectrumPeakFallPerSecond)
        defaults.set(p.spectrum.silenceGateEnabled, forKey: StudioPreferenceKey.spectrumSilenceGateEnabled)
        defaults.set(p.spectrum.silenceThreshold, forKey: StudioPreferenceKey.spectrumSilenceThreshold)

        defaults.set(p.waveform.lineWidth, forKey: StudioPreferenceKey.waveformLineWidth)
        defaults.set(p.waveform.amplitude, forKey: StudioPreferenceKey.waveformAmplitude)
        defaults.set(p.waveform.verticalRange, forKey: StudioPreferenceKey.waveformVerticalRange)
        defaults.set(p.waveform.smoothing, forKey: StudioPreferenceKey.waveformSmoothing)
        defaults.set(p.waveform.density, forKey: StudioPreferenceKey.waveformDensity)
        defaults.set(p.waveform.style.rawValue, forKey: StudioPreferenceKey.waveformStyle)
        defaults.set(p.waveform.fillStrength, forKey: StudioPreferenceKey.waveformFillStrength)
        if let custom = p.waveform.customColor {
            defaults.set(custom.hex, forKey: StudioPreferenceKey.waveformColor)
        } else {
            defaults.removeObject(forKey: StudioPreferenceKey.waveformColor)
        }

        defaults.set(p.orbit.barCount, forKey: StudioPreferenceKey.orbitBarCount)
        defaults.set(p.orbit.inner, forKey: StudioPreferenceKey.orbitInner)
        defaults.set(p.orbit.lineWidth, forKey: StudioPreferenceKey.orbitLineWidth)
        defaults.set(p.orbit.amplitude, forKey: StudioPreferenceKey.orbitAmplitude)
        defaults.set(p.orbit.smoothing, forKey: StudioPreferenceKey.orbitSmoothing)
        defaults.set(p.orbit.outerScale, forKey: StudioPreferenceKey.orbitOuterScale)
        defaults.set(p.orbit.gapDegrees, forKey: StudioPreferenceKey.orbitGapDegrees)
        defaults.set(p.orbit.mirrored, forKey: StudioPreferenceKey.orbitMirrored)
        defaults.set(p.orbit.stroke, forKey: StudioPreferenceKey.orbitStroke)
        defaults.set(p.orbit.layerMode.rawValue, forKey: StudioPreferenceKey.orbitLayerMode)
        defaults.set(p.orbit.pulseStrength, forKey: StudioPreferenceKey.orbitPulseStrength)
        if let custom = p.orbit.customColor {
            defaults.set(custom.hex, forKey: StudioPreferenceKey.orbitColor)
        } else {
            defaults.removeObject(forKey: StudioPreferenceKey.orbitColor)
        }
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
        barCounts.contains(value) ? value : standard.spectrum.barCount
    }

    static func clampedOpacity(_ value: Double) -> Double {
        clamped(value, to: opacityRange, fallback: standard.appearance.opacity)
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Reads one value, falling back to a legacy value and then to the default.
    private struct Reader {
        let defaults: UserDefaults

        func optionalDouble(_ key: String, range: ClosedRange<Double>) -> Double? {
            guard defaults.object(forKey: key) != nil else { return nil }
            let raw = defaults.double(forKey: key)
            return raw.isFinite ? min(max(raw, range.lowerBound), range.upperBound) : nil
        }

        func double(_ key: String, legacy: Double? = nil, range: ClosedRange<Double>, fallback: Double) -> Double {
            if defaults.object(forKey: key) != nil {
                return StudioPreferences.clamped(defaults.double(forKey: key), to: range, fallback: legacy ?? fallback)
            }
            return legacy ?? fallback
        }

        func bool(_ key: String, fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }

        func color(_ key: String, fallback: StudioColor) -> StudioColor {
            defaults.string(forKey: key).flatMap(StudioColor.init(hex:)) ?? fallback
        }

        func density(_ key: String, fallback: Int) -> Int {
            guard defaults.object(forKey: key) != nil else { return fallback }
            let stored = defaults.integer(forKey: key)
            return StudioPreferences.densities.contains(stored) ? stored : fallback
        }

        func optionalBarCount(_ key: String) -> Int? {
            guard defaults.object(forKey: key) != nil else { return nil }
            return StudioPreferences.barCounts.contains(defaults.integer(forKey: key)) ? defaults.integer(forKey: key) : nil
        }

        func barCount(_ key: String, legacy: Int?, fallback: Int) -> Int {
            if defaults.object(forKey: key) != nil {
                let stored = defaults.integer(forKey: key)
                return StudioPreferences.barCounts.contains(stored) ? stored : fallback
            }
            return legacy ?? fallback
        }
    }
}

extension StudioColor: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard let color = StudioColor(hex: hex) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a #RRGGBB color.")
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

extension AppearancePreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case color, strokeColor, opacity, lineWidth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        self.init(
            color: try container.decodeIfPresent(StudioColor.self, forKey: .color) ?? standard.color,
            strokeColor: try container.decodeIfPresent(StudioColor.self, forKey: .strokeColor) ?? standard.strokeColor,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? standard.opacity,
            lineWidth: try container.decodeIfPresent(Double.self, forKey: .lineWidth) ?? standard.lineWidth
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(lineWidth, forKey: .lineWidth)
    }
}

extension SpectrumPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case barCount, scale, minHz, maxHz, barGap, cornerRadius, stroke, colorMode
        case sensitivity, amplitude, smoothing, attackMs, releaseMs, peakHold, peakHoldSeconds, peakFallPerSecond
        case silenceGateEnabled, silenceThreshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        self.init(
            barCount: try container.decodeIfPresent(Int.self, forKey: .barCount) ?? standard.barCount,
            scale: try container.decodeIfPresent(SpectrumScale.self, forKey: .scale) ?? standard.scale,
            minHz: try container.decodeIfPresent(Double.self, forKey: .minHz) ?? standard.minHz,
            maxHz: try container.decodeIfPresent(Double.self, forKey: .maxHz) ?? standard.maxHz,
            barGap: try container.decodeIfPresent(Double.self, forKey: .barGap) ?? standard.barGap,
            cornerRadius: try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? standard.cornerRadius,
            stroke: try container.decodeIfPresent(Bool.self, forKey: .stroke) ?? standard.stroke,
            colorMode: try container.decodeIfPresent(SpectrumColorMode.self, forKey: .colorMode) ?? standard.colorMode,
            sensitivity: try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? standard.sensitivity,
            amplitude: try container.decodeIfPresent(Double.self, forKey: .amplitude) ?? standard.amplitude,
            smoothing: try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? standard.smoothing,
            attackMs: try container.decodeIfPresent(Double.self, forKey: .attackMs) ?? standard.attackMs,
            releaseMs: try container.decodeIfPresent(Double.self, forKey: .releaseMs) ?? standard.releaseMs,
            peakHold: try container.decodeIfPresent(Bool.self, forKey: .peakHold) ?? standard.peakHold,
            peakHoldSeconds: try container.decodeIfPresent(Double.self, forKey: .peakHoldSeconds) ?? standard.peakHoldSeconds,
            peakFallPerSecond: try container.decodeIfPresent(Double.self, forKey: .peakFallPerSecond) ?? standard.peakFallPerSecond,
            silenceGateEnabled: try container.decodeIfPresent(Bool.self, forKey: .silenceGateEnabled) ?? standard.silenceGateEnabled,
            silenceThreshold: try container.decodeIfPresent(Double.self, forKey: .silenceThreshold) ?? standard.silenceThreshold
        )
        self = clamped()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(barCount, forKey: .barCount)
        try container.encode(scale, forKey: .scale)
        try container.encode(minHz, forKey: .minHz)
        try container.encode(maxHz, forKey: .maxHz)
        try container.encode(barGap, forKey: .barGap)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(stroke, forKey: .stroke)
        try container.encode(colorMode, forKey: .colorMode)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encode(amplitude, forKey: .amplitude)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(attackMs, forKey: .attackMs)
        try container.encode(releaseMs, forKey: .releaseMs)
        try container.encode(peakHold, forKey: .peakHold)
        try container.encode(peakHoldSeconds, forKey: .peakHoldSeconds)
        try container.encode(peakFallPerSecond, forKey: .peakFallPerSecond)
        try container.encode(silenceGateEnabled, forKey: .silenceGateEnabled)
        try container.encode(silenceThreshold, forKey: .silenceThreshold)
    }

    func clamped() -> SpectrumPreferences {
        var prefs = StudioPreferences.standard
        prefs.spectrum = self
        return prefs.normalized().spectrum
    }
}

extension WaveformPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case lineWidth, amplitude, verticalRange, smoothing, density, style, fillStrength, customColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        self.init(
            lineWidth: try container.decodeIfPresent(Double.self, forKey: .lineWidth) ?? standard.lineWidth,
            amplitude: try container.decodeIfPresent(Double.self, forKey: .amplitude) ?? standard.amplitude,
            verticalRange: try container.decodeIfPresent(Double.self, forKey: .verticalRange) ?? standard.verticalRange,
            smoothing: try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? standard.smoothing,
            density: try container.decodeIfPresent(Int.self, forKey: .density) ?? standard.density,
            style: try container.decodeIfPresent(WaveformStyle.self, forKey: .style) ?? standard.style,
            fillStrength: try container.decodeIfPresent(Double.self, forKey: .fillStrength) ?? standard.fillStrength,
            customColor: try container.decodeIfPresent(StudioColor.self, forKey: .customColor)
        )
        self = clamped()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(amplitude, forKey: .amplitude)
        try container.encode(verticalRange, forKey: .verticalRange)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(density, forKey: .density)
        try container.encode(style, forKey: .style)
        try container.encode(fillStrength, forKey: .fillStrength)
        try container.encodeIfPresent(customColor, forKey: .customColor)
    }

    func clamped() -> WaveformPreferences {
        var prefs = StudioPreferences.standard
        prefs.waveform = self
        return prefs.normalized().waveform
    }
}

extension OrbitPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case barCount, inner, outerScale, gapDegrees, mirrored, stroke, lineWidth, amplitude, smoothing
        case layerMode, pulseStrength, customColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        self.init(
            barCount: try container.decodeIfPresent(Int.self, forKey: .barCount) ?? standard.barCount,
            inner: try container.decodeIfPresent(Double.self, forKey: .inner) ?? standard.inner,
            outerScale: try container.decodeIfPresent(Double.self, forKey: .outerScale) ?? standard.outerScale,
            gapDegrees: try container.decodeIfPresent(Double.self, forKey: .gapDegrees) ?? standard.gapDegrees,
            mirrored: try container.decodeIfPresent(Bool.self, forKey: .mirrored) ?? standard.mirrored,
            stroke: try container.decodeIfPresent(Bool.self, forKey: .stroke) ?? standard.stroke,
            lineWidth: try container.decodeIfPresent(Double.self, forKey: .lineWidth) ?? standard.lineWidth,
            amplitude: try container.decodeIfPresent(Double.self, forKey: .amplitude) ?? standard.amplitude,
            smoothing: try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? standard.smoothing,
            layerMode: try container.decodeIfPresent(OrbitLayerMode.self, forKey: .layerMode) ?? standard.layerMode,
            pulseStrength: try container.decodeIfPresent(Double.self, forKey: .pulseStrength) ?? standard.pulseStrength,
            customColor: try container.decodeIfPresent(StudioColor.self, forKey: .customColor)
        )
        self = clamped()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(barCount, forKey: .barCount)
        try container.encode(inner, forKey: .inner)
        try container.encode(outerScale, forKey: .outerScale)
        try container.encode(gapDegrees, forKey: .gapDegrees)
        try container.encode(mirrored, forKey: .mirrored)
        try container.encode(stroke, forKey: .stroke)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(amplitude, forKey: .amplitude)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(layerMode, forKey: .layerMode)
        try container.encode(pulseStrength, forKey: .pulseStrength)
        try container.encodeIfPresent(customColor, forKey: .customColor)
    }

    func clamped() -> OrbitPreferences {
        var prefs = StudioPreferences.standard
        prefs.orbit = self
        return prefs.normalized().orbit
    }
}
