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

    static let waveformLineWidth = "studio.waveform.lineWidth"
    static let waveformAmplitude = "studio.waveform.amplitude"
    static let waveformSmoothing = "studio.waveform.smoothing"
    static let waveformDensity = "studio.waveform.density"
    static let waveformStyle = "studio.waveform.style"
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

    static let windowAllowsDrag = "studio.window.allowsDrag"
    static let windowAllowsResize = "studio.window.allowsResize"
    static let windowRestorePosition = "studio.window.restorePosition"
    static let windowHideDelay = "studio.window.hideDelaySeconds"
    static let windowAnimatesChrome = "studio.window.animatesChrome"
    static let windowFollowsReduceMotion = "studio.window.followsReduceMotion"
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
        case .onDesktop: return "On Desktop"
        case .onTop: return "On Top"
        case .asWindow: return "As Window"
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

    private static func snapped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(max(value, 0), 1) * 255).rounded() / 255
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
        case .warm: return "Warm"
        case .amber: return "Amber"
        case .sea: return "Sea"
        case .mist: return "Mist"
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

nonisolated enum SpectrumScale: String, CaseIterable, Identifiable {
    case log
    case linear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .log: return "Logarithmic"
        case .linear: return "Linear"
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
    var sensitivity: Double
    var amplitude: Double
    var smoothing: Double
    var attackMs: Double
    var releaseMs: Double
    var peakHold: Bool
    var peakHoldSeconds: Double

    static let standard = SpectrumPreferences(
        barCount: 32,
        scale: .log,
        minHz: 40,
        maxHz: 16_000,
        barGap: 2,
        cornerRadius: 2,
        stroke: false,
        sensitivity: 0.5,
        amplitude: 1,
        smoothing: 0.3,
        attackMs: 35,
        releaseMs: 260,
        peakHold: false,
        peakHoldSeconds: 0.6
    )

    /// Sensitivity moves the quiet end of the dB window. 0.5 keeps the original -60 dB floor.
    var floorDecibels: Double {
        -40 - 40 * sensitivity
    }

    var layout: SpectrumBandLayout {
        SpectrumBandLayout(scale: scale, minHz: minHz, maxHz: maxHz, floorDecibels: Float(floorDecibels))
    }

    var dynamics: SpectrumDynamicsSettings {
        SpectrumDynamicsSettings(
            attackSeconds: attackMs / 1000,
            releaseSeconds: releaseMs / 1000,
            neighborSmoothing: Float(smoothing),
            peakHoldSeconds: peakHold ? peakHoldSeconds : nil
        )
    }
}

nonisolated enum WaveformStyle: String, CaseIterable, Identifiable {
    case line
    case filled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "Line"
        case .filled: return "Filled"
        }
    }
}

nonisolated struct WaveformPreferences: Equatable {
    var lineWidth: Double
    var amplitude: Double
    var smoothing: Double
    /// How many of the real PCM points are drawn. Never more than the snapshot provides.
    var density: Int
    var style: WaveformStyle
    /// `nil` follows the Appearance color.
    var customColor: StudioColor?

    static let standard = WaveformPreferences(
        lineWidth: 1.5,
        amplitude: 1,
        smoothing: 0.35,
        density: 64,
        style: .line,
        customColor: nil
    )
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
        customColor: nil
    )

    var bandCount: Int {
        OrbitLayout.bandCount(barCount: barCount, mirrored: mirrored)
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

    static let standard = WindowPreferences(
        allowsDrag: true,
        allowsResize: true,
        restorePosition: true,
        hideDelaySeconds: 0.4,
        animatesChrome: true,
        followsReduceMotion: true
    )
}

nonisolated struct StudioPreferences: Equatable {
    var mode: StudioVisualMode
    var windowMode: StudioWindowMode
    var window: WindowPreferences
    var appearance: AppearancePreferences
    var spectrum: SpectrumPreferences
    var waveform: WaveformPreferences
    var orbit: OrbitPreferences

    static let opacityRange: ClosedRange<Double> = 0.35...1
    static let lineWidthRange: ClosedRange<Double> = 0.5...4
    static let amplitudeRange: ClosedRange<Double> = 0.25...3
    static let smoothingRange: ClosedRange<Double> = 0...1
    static let barGapRange: ClosedRange<Double> = 0...8
    static let cornerRadiusRange: ClosedRange<Double> = 0...8
    static let orbitInnerRange: ClosedRange<Double> = 0.35...0.8
    static let orbitOuterRange: ClosedRange<Double> = 0.6...1
    static let orbitGapRange: ClosedRange<Double> = 0...10
    static let hideDelayRange: ClosedRange<Double> = 0.1...2
    static let minHzRange: ClosedRange<Double> = 20...500
    static let maxHzRange: ClosedRange<Double> = 2_000...20_000
    static let sensitivityRange: ClosedRange<Double> = 0...1
    static let attackMsRange: ClosedRange<Double> = 5...200
    static let releaseMsRange: ClosedRange<Double> = 60...1_000
    static let peakHoldSecondsRange: ClosedRange<Double> = 0.1...2
    static let barCounts = [8, 12, 16, 24, 32, 48, 64]
    static let densities = [32, 64, 128]

    static let standard = StudioPreferences(
        mode: .spectrum,
        windowMode: .onTop,
        window: .standard,
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
                followsReduceMotion: reader.bool(StudioPreferenceKey.windowFollowsReduceMotion, fallback: standard.window.followsReduceMotion)
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
                sensitivity: reader.double(StudioPreferenceKey.spectrumSensitivity, range: sensitivityRange, fallback: standard.spectrum.sensitivity),
                amplitude: reader.double(StudioPreferenceKey.spectrumAmplitude, legacy: legacyAmplitude, range: amplitudeRange, fallback: standard.spectrum.amplitude),
                smoothing: reader.double(StudioPreferenceKey.spectrumSmoothing, legacy: legacySmoothing, range: smoothingRange, fallback: standard.spectrum.smoothing),
                attackMs: reader.double(StudioPreferenceKey.spectrumAttackMs, range: attackMsRange, fallback: standard.spectrum.attackMs),
                releaseMs: reader.double(StudioPreferenceKey.spectrumReleaseMs, range: releaseMsRange, fallback: standard.spectrum.releaseMs),
                peakHold: reader.bool(StudioPreferenceKey.spectrumPeakHold, fallback: standard.spectrum.peakHold),
                peakHoldSeconds: reader.double(StudioPreferenceKey.spectrumPeakHoldSeconds, range: peakHoldSecondsRange, fallback: standard.spectrum.peakHoldSeconds)
            ),
            waveform: WaveformPreferences(
                lineWidth: reader.double(StudioPreferenceKey.waveformLineWidth, legacy: legacyLine, range: lineWidthRange, fallback: standard.waveform.lineWidth),
                amplitude: reader.double(StudioPreferenceKey.waveformAmplitude, legacy: legacyAmplitude, range: amplitudeRange, fallback: standard.waveform.amplitude),
                smoothing: reader.double(StudioPreferenceKey.waveformSmoothing, legacy: legacySmoothing, range: smoothingRange, fallback: standard.waveform.smoothing),
                density: reader.density(StudioPreferenceKey.waveformDensity, fallback: standard.waveform.density),
                style: defaults.string(forKey: StudioPreferenceKey.waveformStyle).flatMap(WaveformStyle.init(rawValue:)) ?? standard.waveform.style,
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
                customColor: defaults.string(forKey: StudioPreferenceKey.orbitColor).flatMap(StudioColor.init(hex:))
            )
        ).normalized()
    }

    /// Clamps every value into its documented range. Applied on load and before save.
    func normalized() -> StudioPreferences {
        var result = self
        let standard = Self.standard
        result.window.hideDelaySeconds = Self.clamped(window.hideDelaySeconds, to: Self.hideDelayRange, fallback: standard.window.hideDelaySeconds)
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
        result.waveform.lineWidth = Self.clamped(waveform.lineWidth, to: Self.lineWidthRange, fallback: standard.waveform.lineWidth)
        result.waveform.amplitude = Self.clamped(waveform.amplitude, to: Self.amplitudeRange, fallback: standard.waveform.amplitude)
        result.waveform.smoothing = Self.clamped(waveform.smoothing, to: Self.smoothingRange, fallback: standard.waveform.smoothing)
        result.waveform.density = Self.densities.contains(waveform.density) ? waveform.density : standard.waveform.density
        result.orbit.barCount = Self.normalizedBarCount(orbit.barCount)
        result.orbit.inner = Self.clamped(orbit.inner, to: Self.orbitInnerRange, fallback: standard.orbit.inner)
        result.orbit.outerScale = Self.clamped(orbit.outerScale, to: Self.orbitOuterRange, fallback: standard.orbit.outerScale)
        result.orbit.gapDegrees = Self.clamped(orbit.gapDegrees, to: Self.orbitGapRange, fallback: standard.orbit.gapDegrees)
        result.orbit.lineWidth = Self.clamped(orbit.lineWidth, to: Self.lineWidthRange, fallback: standard.orbit.lineWidth)
        result.orbit.amplitude = Self.clamped(orbit.amplitude, to: Self.amplitudeRange, fallback: standard.orbit.amplitude)
        result.orbit.smoothing = Self.clamped(orbit.smoothing, to: Self.smoothingRange, fallback: standard.orbit.smoothing)
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
        defaults.set(p.spectrum.sensitivity, forKey: StudioPreferenceKey.spectrumSensitivity)
        defaults.set(p.spectrum.amplitude, forKey: StudioPreferenceKey.spectrumAmplitude)
        defaults.set(p.spectrum.smoothing, forKey: StudioPreferenceKey.spectrumSmoothing)
        defaults.set(p.spectrum.attackMs, forKey: StudioPreferenceKey.spectrumAttackMs)
        defaults.set(p.spectrum.releaseMs, forKey: StudioPreferenceKey.spectrumReleaseMs)
        defaults.set(p.spectrum.peakHold, forKey: StudioPreferenceKey.spectrumPeakHold)
        defaults.set(p.spectrum.peakHoldSeconds, forKey: StudioPreferenceKey.spectrumPeakHoldSeconds)

        defaults.set(p.waveform.lineWidth, forKey: StudioPreferenceKey.waveformLineWidth)
        defaults.set(p.waveform.amplitude, forKey: StudioPreferenceKey.waveformAmplitude)
        defaults.set(p.waveform.smoothing, forKey: StudioPreferenceKey.waveformSmoothing)
        defaults.set(p.waveform.density, forKey: StudioPreferenceKey.waveformDensity)
        defaults.set(p.waveform.style.rawValue, forKey: StudioPreferenceKey.waveformStyle)
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
