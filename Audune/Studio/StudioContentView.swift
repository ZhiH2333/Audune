#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class StudioModel {
    var snapshot = AudioSnapshot.zero
    var studioSpectrum = Array(repeating: Float(0), count: StudioPreferences.standard.barCount)
    var windowMode = StudioPreferences.standard.windowMode
    var mode: StudioVisualMode = .spectrum
    var backgroundOpacity = StudioPreferences.standard.backgroundOpacity
    var accent: StudioAccent = .warm
    var barCount = StudioPreferences.standard.barCount
    var lineWidth = StudioPreferences.standard.lineWidth
    var amplitude = StudioPreferences.standard.amplitude
    var smoothing = StudioPreferences.standard.smoothing
    var barGap = StudioPreferences.standard.barGap
    var cornerRadius = StudioPreferences.standard.cornerRadius
    var spectrumStroke = StudioPreferences.standard.spectrumStroke
    var orbitInner = StudioPreferences.standard.orbitInner
    var displayWaveform = AudioSnapshot.zero.waveform
    var playerID = ""
    var playbackAvailability: PlayerAvailability = .noSelection
    var playbackState: PlayerPlaybackState = .unknown
    var playbackDetail = "Choose a player"
    var playbackBusy = false
    var pointerInside = false
    var pointerDown = false
    var isShown = false
}

struct StudioContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: StudioModel
    var savePreferences: () -> Void
    var openSettings: () -> Void
    var setChromeVisible: (Bool) -> Void
    var togglePlayback: () -> Void
    var hitMap: StudioHitMap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gripHovering = false
    @State private var exitedAt: TimeInterval?
    @State private var now = Date().timeIntervalSinceReferenceDate
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            visualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            chrome
                .fixedSize()
                .padding(8)
                .opacity(showsChrome ? 1 : 0)
                .allowsHitTesting(showsChrome)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(warmWhite)
        .preferredColorScheme(.dark)
        .coordinateSpace(name: StudioCoordinateSpace.name)
        .animation(chromeAnimation, value: showsChrome)
        .onPreferenceChange(StudioControlFramesKey.self) { frames in
            hitMap.controlFramesTopLeft = frames
        }
        .onPreferenceChange(StudioGripFramesKey.self) { frames in
            hitMap.gripFramesTopLeft = frames
        }
        .onChange(of: model.pointerInside) { _, inside in
            if inside {
                cancelHide()
            } else if model.pointerDown == false {
                beginHideCountdown()
            }
        }
        .onChange(of: model.pointerDown) { _, down in
            if down {
                hideTask?.cancel()
            } else if model.pointerInside == false {
                beginHideCountdown()
            }
        }
        .onChange(of: showsChrome) { _, visible in
            hitMap.chromeVisible = visible
            setChromeVisible(visible)
        }
        .onAppear {
            hitMap.chromeVisible = showsChrome
            if model.pointerInside == false {
                beginHideCountdown()
            }
            setChromeVisible(showsChrome)
        }
    }

    private var chrome: some View {
        VStack(spacing: 8) {
            if spike.phase == .failed {
                Text(failureLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.93, green: 0.55, blue: 0.48))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(width: 220, alignment: .leading)
                    .studioControlRegion()
            }
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 4) {
            grip
            StudioTextButton(
                title: PlaybackButton.title(availability: model.playbackAvailability, state: model.playbackState),
                disabled: playbackDisabled,
                accessibilityLabel: "Play or pause",
                accessibilityValue: model.playbackDetail
            ) {
                togglePlayback()
            }
            ForEach(StudioVisualMode.allCases) { mode in
                StudioIconButton(
                    symbol: mode.symbol,
                    label: mode.title,
                    selected: model.mode == mode
                ) {
                    model.mode = mode
                    savePreferences()
                }
            }
            StudioIconButton(symbol: "gearshape", label: "Settings", selected: false, action: openSettings)
        }
        .frame(height: StudioChrome.barHeight)
    }

    private var grip: some View {
        ZStack {
            StudioDragSurface(hitMap: hitMap)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(warmWhite.opacity(0.8))
                .allowsHitTesting(false)
        }
        .frame(width: StudioChrome.gripWidth, height: StudioChrome.gripHeight)
        .background {
            if gripHovering {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            }
        }
        .onHover { gripHovering = $0 }
        .accessibilityLabel("Drag Studio")
        .studioGripRegion()
    }

    @ViewBuilder
    private var visualization: some View {
        switch model.mode {
        case .spectrum:
            SpectrumCanvas(
                spectrum: model.studioSpectrum,
                drawsBars: drawsBars,
                color: accentColor,
                opacity: model.backgroundOpacity,
                amplitude: model.amplitude,
                lineWidth: model.lineWidth,
                cornerRadius: model.cornerRadius,
                barGap: model.barGap,
                drawsStroke: model.spectrumStroke
            )
        case .waveform:
            WaveformCanvas(
                samples: model.displayWaveform,
                color: accentColor,
                opacity: model.backgroundOpacity,
                amplitude: model.amplitude,
                lineWidth: model.lineWidth,
                smoothing: model.smoothing
            )
        case .orbit:
            OrbitCanvas(
                spectrum: model.studioSpectrum,
                drawsLevels: drawsBars,
                color: accentColor,
                opacity: model.backgroundOpacity,
                amplitude: model.amplitude,
                lineWidth: model.lineWidth,
                innerRatio: model.orbitInner
            )
        }
    }

    private var showsChrome: Bool {
        StudioChrome.isVisible(
            pointerInside: model.pointerInside,
            pointerDown: model.pointerDown,
            holdsChrome: false,
            now: now,
            exitedAt: exitedAt
        )
    }

    private var chromeAnimation: Animation? {
        let duration = StudioChromeMotion.fadeSeconds(hiding: showsChrome == false, reduceMotion: reduceMotion)
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    private func beginHideCountdown() {
        hideTask?.cancel()
        let exit = Date().timeIntervalSinceReferenceDate
        exitedAt = exit
        now = exit
        let delay = StudioChromeMotion.hideDelaySeconds
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard Task.isCancelled == false else { return }
            now = exit + delay
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
        exitedAt = nil
        now = Date().timeIntervalSinceReferenceDate
    }

    private var warmWhite: Color {
        Color(red: 0.96, green: 0.94, blue: 0.90)
    }

    private var accentColor: Color {
        Color(red: model.accent.red, green: model.accent.green, blue: model.accent.blue)
    }

    private var failureLine: String {
        let primary = spike.failureText.isEmpty ? "Audio capture failed." : spike.failureText
        guard spike.statusText.isEmpty == false else { return primary }
        return "\(primary) \(spike.statusText)"
    }

    private var playbackDisabled: Bool {
        PlaybackButton.isEnabled(
            selection: model.playerID,
            availability: model.playbackAvailability,
            busy: model.playbackBusy
        ) == false
    }

    private var drawsBars: Bool {
        spike.phase == .running && model.snapshot.isSilent == false
    }
}

private struct StudioIconButton: View {
    var symbol: String
    var label: String
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background {
                    if hovering || selected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.22 : 0.16))
                    }
                }
        }
        .buttonStyle(StudioPlainButtonStyle(showsFill: selected))
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .studioControlRegion()
    }
}

private struct StudioTextButton: View {
    var title: String
    var disabled: Bool = false
    var highlighted: Bool = false
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if hovering || highlighted {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    }
                }
        }
        .buttonStyle(StudioPlainButtonStyle(showsFill: highlighted))
        .disabled(disabled)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? "")
        .studioControlRegion()
    }
}

private struct StudioPlainButtonStyle: ButtonStyle {
    var showsFill: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if showsFill == false && configuration.isPressed {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                }
            }
    }
}
#endif
