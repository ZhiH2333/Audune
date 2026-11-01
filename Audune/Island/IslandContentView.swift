#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class IslandModel {
    var snapshot = AudioSnapshot.zero
    var prefs = IslandPreferences.standard
    var appearance = AppearancePreferences.standard
    var spectrum = SpectrumPreferences.standard
    var waveform = WaveformPreferences.standard
    var orbit = OrbitPreferences.standard
    var state: IslandPresentationState = .compact
    var geometry: IslandNotchGeometry?
    var availableScreens: [IslandScreenDescriptor] = []
    var unsupportedReason: IslandUnsupportedReason?
    var usedFallbackScreen = false
    var compactLevels = Array(repeating: Float(0), count: IslandPreferences.standard.compactBarCountPerSide)
    var expandedSpectrum: [Float] = []
    var expandedPeaks: [Float] = []
    var expandedWaveform = AudioSnapshot.zero.waveform
    var pointerInside = false
    var pointerDown = false
    /// Compact-only anticipation. The window frame stays on the compact geometry while this is true.
    var hoverArmed = false
    /// Drives Compact/Expanded chrome. Stays expanded through collapse frame animation so content doesn't pop early.
    var showsExpandedChrome = false
    /// Experimental Now Playing snapshot mirrored from `NowPlayingService` for Expanded UI.
    var nowPlaying = NowPlayingSnapshot.idle

    var isSupported: Bool {
        geometry != nil && unsupportedReason == nil
    }

    var isPinned: Bool {
        state == .pinned
    }

    var statusSummary: String {
        if let geometry {
            if prefs.isEnabled == false {
                return String(localized: "Disabled on \(geometry.screenName)")
            }
            if usedFallbackScreen {
                return String(localized: "Active on \(geometry.screenName) (fallback notched display)")
            }
            return String(localized: "Active on \(geometry.screenName)")
        }
        if let unsupportedReason {
            return unsupportedReason.userMessage
        }
        return IslandUnsupportedReason.noNotch.userMessage
    }

    func captureLabel(phase: SpikePhase) -> String {
        switch phase {
        case .idle:
            return String(localized: "Not listening")
        case .starting:
            return String(localized: "Starting")
        case .failed:
            return String(localized: "Failed")
        case .running:
            return snapshot.isSilent ? String(localized: "No audio") : String(localized: "Listening")
        }
    }

    func drawsActiveVisuals(phase: SpikePhase) -> Bool {
        guard phase == .running else { return false }
        if snapshot.isSilent == false { return true }
        if state.isExpandedOrPinned {
            switch prefs.mode {
            case .spectrum:
                return SpectrumDynamics.isSettled(levels: expandedSpectrum, peaks: expandedPeaks) == false
            case .orbit:
                return SpectrumDynamics.isSettled(levels: expandedSpectrum) == false
            case .waveform:
                return SpectrumDynamics.isSettled(levels: expandedWaveform) == false
            }
        }
        return SpectrumDynamics.isSettled(levels: compactLevels) == false
    }
}

/// Top-flush, bottom-rounded silhouette that merges with the top screen edge and physical camera housing.
nonisolated enum IslandChrome {
    static let compactBottomRadius: CGFloat = 18
    static let expandedBottomRadius: CGFloat = 28
}

nonisolated struct IslandShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return Path()
        }
        let radius = min(max(bottomRadius.isFinite ? bottomRadius : 0, 0), rect.width / 2, rect.height / 2)
        return Path(
            roundedRect: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: radius,
                bottomTrailing: radius,
                topTrailing: 0
            ),
            style: .continuous
        )
    }
}

struct IslandCompactSpectrumCanvas: View {
    var levels: [Float]
    var geometry: IslandNotchGeometry?
    var barsPerSide: Int
    var drawsBars: Bool
    var color: Color
    var opacity: Double

    var body: some View {
        Canvas { context, size in
            guard let geometry else { return }
            let compactFrame = CGRect(
                x: geometry.compactFrame.minX,
                y: geometry.compactFrame.minY,
                width: size.width,
                height: size.height
            )
            let bars = IslandGeometry.compactBars(
                levels: levels,
                notchRect: geometry.notchRect,
                compactFrame: compactFrame,
                barsPerSide: barsPerSide,
                amplitude: 1,
                drawsActiveBars: drawsBars
            )
            let shading = GraphicsContext.Shading.color(color.opacity(drawsBars ? opacity : opacity * 0.45))
            for rect in bars.left + bars.right {
                let radius = min(rect.width / 2, rect.height / 2)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: shading)
            }
        }
        .accessibilityLabel(drawsBars ? String(localized: "Notch Island compact spectrum") : String(localized: "Notch Island compact baseline"))
    }
}

struct IslandContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: IslandModel
    var selectMode: (StudioVisualMode) -> Void
    var togglePin: () -> Void
    var expand: () -> Void
    var collapse: () -> Void
    var openStudio: () -> Void
    var openSettings: () -> Void
    var toggleNowPlaying: () -> Void = {}
    var previousTrack: () -> Void = {}
    var nextTrack: () -> Void = {}
    var seekNowPlaying: (Double) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.showsExpandedChrome {
                expandedBody
            } else {
                compactBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(warmWhite)
        .preferredColorScheme(.dark)
    }

    private var compactBody: some View {
        let shape = IslandShape(bottomRadius: IslandChrome.compactBottomRadius)
        let armedScale = IslandMotion.prefeedbackScale(
            hoverArmed: model.hoverArmed,
            reduceMotion: reduceMotion,
            followsReduceMotion: model.prefs.followsReduceMotion
        )
        return ZStack {
            shape.fill(Color.black)
            shape.stroke(Color.white.opacity(model.hoverArmed ? 0.16 : 0), lineWidth: 0.5)
            IslandCompactSpectrumCanvas(
                levels: model.compactLevels,
                geometry: model.geometry,
                barsPerSide: model.prefs.compactBarCountPerSide,
                drawsBars: drawsBars,
                color: model.appearance.color.swiftUI,
                opacity: model.appearance.opacity
            )
            .scaleEffect(armedScale)
            .allowsHitTesting(false)
        }
        .clipShape(shape)
        .animation(prefeedbackAnimation, value: model.hoverArmed)
        .contentShape(shape)
        .onTapGesture {
            expand()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notch Island, \(model.captureLabel(phase: spike.phase))")
        .accessibilityAddTraits(.isButton)
    }

    private var expandedBody: some View {
        let geometry = model.geometry
        let notchWidth = geometry?.notchRect.width ?? 184
        let notchHeight = max(geometry?.notchRect.height ?? 32, 28)
        let windowFrame = geometry.map {
            $0.expandedFrame(nowPlayingEnabled: model.prefs.nowPlayingEnabled)
        }
        let sideClearance = windowFrame.flatMap { frame in
            geometry?.expandedSideClearance(in: frame)
        }
        let leftWing = max(sideClearance?.left ?? 120, 120) - 16
        let rightWing = max(sideClearance?.right ?? 120, 120) - 16

        let shape = IslandShape(bottomRadius: IslandChrome.expandedBottomRadius)
        return ZStack {
            shape.fill(Color.black)
            shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5)

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    statusHeader
                        .frame(width: max(leftWing, 1), alignment: .leading)
                        .padding(.leading, 14)
                    Spacer(minLength: 0)
                        .frame(width: notchWidth)
                    actionButtons
                        .frame(width: max(rightWing, 1), alignment: .trailing)
                        .padding(.trailing, 14)
                }
                .frame(height: notchHeight)

                if model.prefs.nowPlayingEnabled {
                    VStack(spacing: 0) {
                        IslandExpandedNowPlayingView(
                            snapshot: model.nowPlaying,
                            onTogglePlay: toggleNowPlaying,
                            onPrevious: previousTrack,
                            onNext: nextTrack,
                            onSeek: seekNowPlaying
                        )
                        .padding(.horizontal, 18)
                        .padding(.top, 2)

                        Spacer(minLength: 4)

                        // Readable ambient strip: spectrum/waveform fill width; orbit keeps a square viewport.
                        ZStack(alignment: .bottom) {
                            nowPlayingAmbientVisualization
                                .allowsHitTesting(false)

                            modePickerRow
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.55))
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                        }
                                }
                                .padding(.bottom, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: model.prefs.mode == .orbit ? 96 : 58)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 4) {
                        expandedVisualization
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                            .allowsHitTesting(false)

                        modePickerRow
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .clipShape(shape)
    }

    private var statusHeader: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 6, height: 6)
            Text(model.captureLabel(phase: spike.phase))
                .font(.system(size: model.prefs.nowPlayingEnabled ? 11 : 10, weight: .medium))
                .foregroundStyle(warmWhite.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            IslandIconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                label: model.isPinned ? String(localized: "Unpin Notch Island") : String(localized: "Pin Notch Island"),
                selected: model.isPinned,
                action: togglePin
            )
            IslandIconButton(
                symbol: "macwindow",
                label: String(localized: "Open Studio"),
                selected: false,
                action: openStudio
            )
            IslandIconButton(
                symbol: "gearshape",
                label: String(localized: "Notch Island Settings"),
                selected: false,
                action: openSettings
            )
            IslandIconButton(
                symbol: "chevron.up",
                label: String(localized: "Collapse Notch Island"),
                selected: false,
                action: collapse
            )
        }
    }

    private var modePickerRow: some View {
        HStack(spacing: 6) {
            ForEach(StudioVisualMode.allCases) { mode in
                IslandModeButton(
                    mode: mode,
                    selected: model.prefs.mode == mode
                ) {
                    selectMode(mode)
                }
            }
        }
        .frame(height: 22)
    }

    /// Now Playing ambient strip — brighter than the old backdrop wash, orbit gets a square stage.
    @ViewBuilder
    private var nowPlayingAmbientVisualization: some View {
        let strength = min(max(model.appearance.opacity * 1.15, 0.72), 1)
        switch model.prefs.mode {
        case .orbit:
            expandedVisualization(opacityOverride: strength, orbitBoost: true)
                .frame(width: 92, height: 92)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(0.92)
        case .spectrum, .waveform:
            expandedVisualization(opacityOverride: strength, orbitBoost: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.88)
                .mask(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.35),
                            Color.black,
                            Color.black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    @ViewBuilder
    private var expandedVisualization: some View {
        expandedVisualization(opacityOverride: nil, orbitBoost: false)
    }

    @ViewBuilder
    private func expandedVisualization(opacityOverride: Double?, orbitBoost: Bool) -> some View {
        let fill = model.appearance.color.swiftUI
        let stroke = model.appearance.strokeColor.swiftUI
        let opacity = opacityOverride ?? model.appearance.opacity
        switch model.prefs.mode {
        case .spectrum:
            SpectrumCanvas(
                spectrum: model.expandedSpectrum,
                peaks: model.expandedPeaks,
                drawsBars: drawsBars,
                color: fill,
                baseColor: model.appearance.color,
                strokeColor: stroke,
                opacity: opacity,
                amplitude: model.spectrum.amplitude,
                lineWidth: model.appearance.lineWidth,
                cornerRadius: model.spectrum.cornerRadius,
                barGap: model.spectrum.barGap,
                drawsStroke: model.spectrum.stroke,
                colorMode: model.spectrum.colorMode,
                peakHold: model.spectrum.peakHold
            )
        case .waveform:
            WaveformCanvas(
                samples: model.expandedWaveform,
                color: (model.waveform.customColor ?? model.appearance.color).swiftUI,
                opacity: opacity,
                amplitude: model.waveform.amplitude,
                verticalRange: model.waveform.verticalRange,
                lineWidth: max(model.waveform.lineWidth, opacityOverride == nil ? model.waveform.lineWidth : 1.8),
                smoothing: model.waveform.smoothing,
                density: model.waveform.density,
                style: model.waveform.style,
                fillStrength: model.waveform.fillStrength
            )
        case .orbit:
            OrbitCanvas(
                spectrum: model.expandedSpectrum,
                drawsLevels: drawsBars,
                barCount: model.orbit.barCount,
                mirrored: model.orbit.mirrored,
                color: (model.orbit.customColor ?? model.appearance.color).swiftUI,
                strokeColor: stroke,
                drawsStroke: model.orbit.stroke || orbitBoost,
                opacity: opacity,
                amplitude: orbitBoost ? max(model.orbit.amplitude, 1.05) : model.orbit.amplitude,
                lineWidth: orbitBoost ? max(model.orbit.lineWidth, 2) : model.orbit.lineWidth,
                innerRatio: orbitBoost ? min(model.orbit.inner, 0.48) : model.orbit.inner,
                outerScale: orbitBoost ? max(model.orbit.outerScale, 0.96) : model.orbit.outerScale,
                gapDegrees: model.orbit.gapDegrees,
                layerMode: model.orbit.layerMode,
                pulseStrength: model.orbit.pulseStrength
            )
        }
    }

    private var prefeedbackAnimation: Animation? {
        let duration = IslandMotion.prefeedbackSeconds(
            expandDelay: model.prefs.expandDelaySeconds,
            reduceMotion: reduceMotion,
            followsReduceMotion: model.prefs.followsReduceMotion
        )
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    private var drawsBars: Bool {
        model.drawsActiveVisuals(phase: spike.phase)
    }

    private var statusDotColor: Color {
        switch spike.phase {
        case .idle, .starting:
            return warmWhite.opacity(0.35)
        case .failed:
            return Color(red: 0.93, green: 0.55, blue: 0.48)
        case .running:
            return model.snapshot.isSilent ? warmWhite.opacity(0.45) : model.appearance.color.swiftUI
        }
    }

    private var warmWhite: Color {
        Color(red: 0.96, green: 0.94, blue: 0.90)
    }
}

private struct IslandIconButton: View {
    var symbol: String
    var label: String
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 20, height: 20)
                .background {
                    if hovering || selected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.22 : 0.14))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct IslandModeButton: View {
    var mode: StudioVisualMode
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(mode.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if hovering || selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.20 : 0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
