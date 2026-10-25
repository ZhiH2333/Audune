#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class StudioModel {
    var snapshot = AudioSnapshot.zero
    var prefs = StudioPreferences.standard
    var studioSpectrum = Array(repeating: Float(0), count: StudioPreferences.standard.spectrum.barCount)
    var spectrumPeaks: [Float] = []
    var displayWaveform = AudioSnapshot.zero.waveform
    var playerID = ""
    var playbackAvailability: PlayerAvailability = .noSelection
    var playbackState: PlayerPlaybackState = .unknown
    var playbackDetail = "Choose a player"
    var playbackBusy = false
    var playbackRequesting = false
    var settingsCategory: SettingsCategory = .appearance
    var pointerInside = false
    var pointerDown = false
    var menuTracking = false
    var chromeVisible = false
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
    @State private var hide = StudioChromeHide.concealed
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
                .opacity(0)
                .allowsHitTesting(false)
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
            } else if model.pointerDown == false && model.menuTracking == false {
                beginHideCountdown()
            }
        }
        .onChange(of: model.pointerDown) { _, down in
            if down || model.menuTracking {
                cancelHide()
            } else if model.pointerInside == false {
                beginHideCountdown()
            }
        }
        .onChange(of: model.menuTracking) { _, tracking in
            if tracking || model.pointerDown {
                cancelHide()
            } else if model.pointerInside == false {
                beginHideCountdown()
            }
        }
        .onChange(of: model.prefs.window.autoHidesControls) { _, hides in
            if hides == false || model.pointerInside || model.pointerDown || model.menuTracking {
                cancelHide()
            } else {
                beginHideCountdown()
            }
        }
        .onChange(of: model.isShown) { _, shown in
            if shown == false {
                concealControls()
            } else if model.pointerInside {
                cancelHide()
            } else if model.pointerDown == false && model.menuTracking == false {
                concealControls()
            }
        }
        .onChange(of: showsChrome) { _, visible in
            hitMap.chromeVisible = visible
            setChromeVisible(visible)
        }
        .onAppear {
            if model.pointerInside {
                cancelHide()
            } else {
                concealControls()
            }
            hitMap.chromeVisible = showsChrome
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
            StudioControlButton(
                title: PlaybackButton.title(availability: model.playbackAvailability, state: model.playbackState),
                symbol: PlaybackButton.symbol(availability: model.playbackAvailability, state: model.playbackState),
                disabled: playbackDisabled,
                accessibilityLabel: "Play or pause",
                accessibilityValue: model.playbackDetail,
                action: togglePlayback
            )
            ForEach(StudioVisualMode.allCases) { mode in
                StudioControlButton(
                    title: mode.title,
                    symbol: mode.symbol,
                    selected: model.prefs.mode == mode
                ) {
                    model.prefs.mode = mode
                    savePreferences()
                }
            }
            StudioControlButton(title: "Settings", symbol: "gearshape", action: openSettings)
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
        let prefs = model.prefs
        let fill = prefs.appearance.color.swiftUI
        switch prefs.mode {
        case .spectrum:
            SpectrumCanvas(
                spectrum: model.studioSpectrum,
                peaks: model.spectrumPeaks,
                drawsBars: drawsBars,
                color: fill,
                strokeColor: prefs.appearance.strokeColor.swiftUI,
                opacity: prefs.appearance.opacity,
                amplitude: prefs.spectrum.amplitude,
                lineWidth: prefs.appearance.lineWidth,
                cornerRadius: prefs.spectrum.cornerRadius,
                barGap: prefs.spectrum.barGap,
                drawsStroke: prefs.spectrum.stroke
            )
        case .waveform:
            WaveformCanvas(
                samples: model.displayWaveform,
                color: (prefs.waveform.customColor ?? prefs.appearance.color).swiftUI,
                opacity: prefs.appearance.opacity,
                amplitude: prefs.waveform.amplitude,
                lineWidth: prefs.waveform.lineWidth,
                smoothing: prefs.waveform.smoothing,
                density: prefs.waveform.density,
                style: prefs.waveform.style
            )
        case .orbit:
            OrbitCanvas(
                spectrum: model.studioSpectrum,
                drawsLevels: drawsBars,
                barCount: prefs.orbit.barCount,
                mirrored: prefs.orbit.mirrored,
                color: (prefs.orbit.customColor ?? prefs.appearance.color).swiftUI,
                strokeColor: prefs.appearance.strokeColor.swiftUI,
                drawsStroke: prefs.orbit.stroke,
                opacity: prefs.appearance.opacity,
                amplitude: prefs.orbit.amplitude,
                lineWidth: prefs.orbit.lineWidth,
                innerRatio: prefs.orbit.inner,
                outerScale: prefs.orbit.outerScale,
                gapDegrees: prefs.orbit.gapDegrees
            )
        }
    }

    private var showsChrome: Bool {
        StudioChrome.isVisible(
            pointerInside: model.pointerInside,
            pointerDown: model.pointerDown,
            holdsChrome: model.menuTracking,
            now: now,
            exitedAt: hide.exitedAt,
            hideDelay: model.prefs.window.hideDelaySeconds,
            autoHides: model.prefs.window.autoHidesControls
        )
    }

    private var chromeAnimation: Animation? {
        let duration = StudioChromeMotion.fadeSeconds(
            hiding: showsChrome == false,
            reduceMotion: reduceMotion,
            animates: model.prefs.window.animatesChrome,
            followsReduceMotion: model.prefs.window.followsReduceMotion
        )
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    private func concealControls() {
        hideTask?.cancel()
        hideTask = nil
        hide = .concealed
        now = StudioChromeMotion.hideDelaySeconds
    }

    private func beginHideCountdown() {
        hideTask?.cancel()
        guard model.isShown else {
            concealControls()
            return
        }
        let exit = Date().timeIntervalSinceReferenceDate
        now = exit
        guard let token = hide.arm(
            at: exit,
            autoHides: model.prefs.window.autoHidesControls,
            engaged: model.pointerDown || model.menuTracking
        ) else { return }
        let delay = model.prefs.window.hideDelaySeconds
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard Task.isCancelled == false, hide.isCurrent(token) else { return }
            now = exit + delay
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
        hide.cancel()
        now = Date().timeIntervalSinceReferenceDate
    }

    private var warmWhite: Color {
        Color(red: 0.96, green: 0.94, blue: 0.90)
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

struct StudioControlButton: View {
    var title: String
    var symbol: String
    var selected: Bool = false
    var disabled: Bool = false
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if hovering || selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.22 : 0.16))
                }
            }
        }
        .buttonStyle(StudioPlainButtonStyle(showsFill: selected))
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
