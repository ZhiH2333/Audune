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

    var isSupported: Bool {
        geometry != nil && unsupportedReason == nil
    }

    var isPinned: Bool {
        state == .pinned
    }

    var statusSummary: String {
        if let geometry {
            if prefs.isEnabled == false {
                return "Disabled on \(geometry.screenName)"
            }
            if usedFallbackScreen {
                return "Active on \(geometry.screenName) (fallback notched display)"
            }
            return "Active on \(geometry.screenName)"
        }
        if let unsupportedReason {
            return unsupportedReason.userMessage
        }
        return IslandUnsupportedReason.noNotch.userMessage
    }

    func captureLabel(phase: SpikePhase) -> String {
        switch phase {
        case .idle:
            return "Not listening"
        case .starting:
            return "Starting"
        case .failed:
            return "Failed"
        case .running:
            return snapshot.isSilent ? "No audio" : "Listening"
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
nonisolated struct IslandShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return Path()
        }
        let radius = min(max(bottomRadius.isFinite ? bottomRadius : 0, 0), rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
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
        .accessibilityLabel(drawsBars ? "Notch Island compact spectrum" : "Notch Island compact baseline")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.state.isExpandedOrPinned {
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
        let shape = IslandShape(bottomRadius: 12)
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
        let notchWidth = model.geometry?.notchRect.width ?? 184
        let notchHeight = max(model.geometry?.notchRect.height ?? 32, 28)

        return ZStack {
            IslandShape(bottomRadius: 18)
                .fill(Color.black)
            IslandShape(bottomRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    statusHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                        .frame(width: notchWidth)
                    actionButtons
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .frame(height: notchHeight)

                expandedVisualization
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)

                modePickerRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 6, height: 6)
            Text(model.captureLabel(phase: spike.phase))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(warmWhite.opacity(0.78))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            IslandIconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                label: model.isPinned ? "Unpin Notch Island" : "Pin Notch Island",
                selected: model.isPinned,
                action: togglePin
            )
            IslandIconButton(
                symbol: "macwindow",
                label: "Open Studio",
                selected: false,
                action: openStudio
            )
            IslandIconButton(
                symbol: "gearshape",
                label: "Notch Island Settings",
                selected: false,
                action: openSettings
            )
            IslandIconButton(
                symbol: "chevron.up",
                label: "Collapse Notch Island",
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

    @ViewBuilder
    private var expandedVisualization: some View {
        let fill = model.appearance.color.swiftUI
        let stroke = model.appearance.strokeColor.swiftUI
        switch model.prefs.mode {
        case .spectrum:
            SpectrumCanvas(
                spectrum: model.expandedSpectrum,
                peaks: model.expandedPeaks,
                drawsBars: drawsBars,
                color: fill,
                baseColor: model.appearance.color,
                strokeColor: stroke,
                opacity: model.appearance.opacity,
                amplitude: model.spectrum.amplitude,
                lineWidth: model.appearance.lineWidth,
                cornerRadius: model.spectrum.cornerRadius,
                barGap: model.spectrum.barGap,
                drawsStroke: model.spectrum.stroke,
                colorMode: model.spectrum.colorMode
            )
        case .waveform:
            WaveformCanvas(
                samples: model.expandedWaveform,
                color: (model.waveform.customColor ?? model.appearance.color).swiftUI,
                opacity: model.appearance.opacity,
                amplitude: model.waveform.amplitude,
                lineWidth: model.waveform.lineWidth,
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
                drawsStroke: model.orbit.stroke,
                opacity: model.appearance.opacity,
                amplitude: model.orbit.amplitude,
                lineWidth: model.orbit.lineWidth,
                innerRatio: model.orbit.inner,
                outerScale: model.orbit.outerScale,
                gapDegrees: model.orbit.gapDegrees
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
