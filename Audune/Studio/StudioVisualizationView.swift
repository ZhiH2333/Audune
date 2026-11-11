#if os(macOS)
import SwiftUI

/// The current visualization for Studio prefs. Shared by the Studio window and the Layout preview.
struct StudioVisualizationView: View {
    var prefs: StudioPreferences
    var spectrum: [Float]
    var peaks: [Float]
    var waveform: [Float]
    var echoWaveform: [Float] = []
    var drawsBars: Bool

    var body: some View {
        let fill = prefs.appearance.color.swiftUI
        switch prefs.mode {
        case .spectrum:
            SpectrumCanvas(
                spectrum: spectrum,
                peaks: peaks,
                drawsBars: drawsBars,
                color: fill,
                baseColor: prefs.appearance.color,
                strokeColor: prefs.appearance.strokeColor.swiftUI,
                baseStrokeColor: prefs.appearance.strokeColor,
                opacity: prefs.appearance.opacity,
                amplitude: prefs.spectrum.amplitude,
                lineWidth: prefs.appearance.lineWidth,
                cornerRadius: prefs.spectrum.cornerRadius,
                barGap: prefs.spectrum.barGap,
                drawsStroke: prefs.spectrum.stroke,
                colorMode: prefs.spectrum.colorMode,
                peakHold: prefs.spectrum.peakHold
            )
        case .waveform:
            WaveformCanvas(
                samples: waveform,
                echoSamples: echoWaveform,
                color: (prefs.waveform.customColor ?? prefs.appearance.color).swiftUI,
                opacity: prefs.appearance.opacity,
                amplitude: prefs.waveform.amplitude,
                verticalRange: prefs.waveform.verticalRange,
                lineWidth: prefs.waveform.lineWidth,
                smoothing: prefs.waveform.smoothing,
                density: prefs.waveform.density,
                style: prefs.waveform.style,
                fillStrength: prefs.waveform.fillStrength
            )
        case .orbit:
            OrbitCanvas(
                spectrum: spectrum,
                drawsLevels: drawsBars,
                barCount: prefs.orbit.barCount,
                mirrored: prefs.orbit.mirrored,
                color: (prefs.orbit.customColor ?? prefs.appearance.color).swiftUI,
                strokeColor: prefs.orbit.effectiveStrokeColor(fallback: prefs.appearance.strokeColor).swiftUI,
                drawsStroke: prefs.orbit.stroke,
                opacity: prefs.appearance.opacity,
                amplitude: prefs.orbit.amplitude,
                lineWidth: prefs.orbit.lineWidth,
                innerRatio: prefs.orbit.inner,
                outerScale: prefs.orbit.outerScale,
                gapDegrees: prefs.orbit.gapDegrees,
                layerMode: prefs.orbit.layerMode,
                pulseStrength: prefs.orbit.pulseStrength
            )
        }
    }
}
#endif
