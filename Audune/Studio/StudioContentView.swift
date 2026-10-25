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
}

struct StudioContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: StudioModel
    var setWindowMode: (StudioWindowMode) -> Void
    var savePreferences: () -> Void
    var resetPreferences: () -> Void
    var close: () -> Void
    var setBarCount: (Int) -> Void
    var setChromeVisible: (Bool) -> Void
    var playerChoices: [PlayerChoice]
    var setPlayerID: (String) -> Void
    var togglePlayback: () -> Void
    var hitMap: StudioHitMap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAppearance = false
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
        .onChange(of: model.mode) { _, _ in savePreferences() }
        .onChange(of: model.accent) { _, _ in savePreferences() }
        .onChange(of: model.backgroundOpacity) { _, _ in savePreferences() }
        .onChange(of: model.lineWidth) { _, _ in savePreferences() }
        .onChange(of: model.amplitude) { _, _ in savePreferences() }
        .onChange(of: model.smoothing) { _, _ in savePreferences() }
        .onChange(of: model.barGap) { _, _ in savePreferences() }
        .onChange(of: model.cornerRadius) { _, _ in savePreferences() }
        .onChange(of: model.spectrumStroke) { _, _ in savePreferences() }
        .onChange(of: model.orbitInner) { _, _ in savePreferences() }
        .onChange(of: model.pointerInside) { _, inside in
            if inside {
                cancelHide()
            } else if model.pointerDown == false, showsAppearance == false {
                beginHideCountdown()
            }
        }
        .onChange(of: model.pointerDown) { _, down in
            if down {
                hideTask?.cancel()
            } else if model.pointerInside == false, showsAppearance == false {
                beginHideCountdown()
            }
        }
        .onChange(of: showsAppearance) { _, open in
            if open {
                hideTask?.cancel()
            } else if model.pointerInside == false, model.pointerDown == false {
                beginHideCountdown()
            }
        }
        .onChange(of: showsChrome) { _, visible in
            hitMap.chromeVisible = visible
            setChromeVisible(visible)
        }
        .onAppear {
            hitMap.chromeVisible = showsChrome
            if model.pointerInside == false, showsAppearance == false {
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
            if showsAppearance {
                appearance
            }
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 6) {
            grip
            Picker("Mode", selection: $model.mode) {
                ForEach(StudioVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Mode")
            .studioControlRegion()
            Picker("Player", selection: Binding(get: { model.playerID }, set: setPlayerID)) {
                Text("None").tag("")
                ForEach(playerChoices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Player")
            .studioControlRegion()
            StudioTextButton(
                title: PlaybackButton.title(availability: model.playbackAvailability, state: model.playbackState),
                disabled: playbackDisabled,
                accessibilityLabel: "Play or pause",
                accessibilityValue: model.playbackDetail
            ) {
                togglePlayback()
            }
            StudioTextButton(title: showsAppearance ? "Done" : "Settings") {
                showsAppearance.toggle()
            }
            Picker("Window", selection: Binding(
                get: { model.windowMode },
                set: { setWindowMode($0) }
            )) {
                ForEach(StudioWindowMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Window mode")
            .studioControlRegion()
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

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StudioTextButton(title: "Start", disabled: startDisabled) {
                    Task { await spike.start() }
                }
                StudioTextButton(title: "Stop", disabled: stopDisabled) {
                    spike.stop()
                }
            }
            Picker("Color", selection: $model.accent) {
                ForEach(StudioAccent.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Color")
            .studioControlRegion()
            HStack(spacing: 8) {
                Text("Opacity")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(warmWhite.opacity(0.72))
                Slider(value: $model.backgroundOpacity, in: StudioPreferences.opacityRange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Opacity")
            .studioControlRegion()
            settingSlider("Line", value: $model.lineWidth, range: StudioPreferences.lineWidthRange, step: 0.5)
            settingSlider("Amplitude", value: $model.amplitude, range: StudioPreferences.amplitudeRange, step: 0.05)
            settingSlider("Smooth", value: $model.smoothing, range: StudioPreferences.smoothingRange, step: 0.05)
            if showsBarCount {
                HStack(spacing: 8) {
                    Text("Bars")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(warmWhite.opacity(0.72))
                    Text("\(model.barCount)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .frame(width: 24, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(barIndex) },
                            set: { raw in
                                let index = min(max(Int(raw.rounded()), 0), StudioPreferences.barCounts.count - 1)
                                setBarCount(StudioPreferences.barCounts[index])
                            }
                        ),
                        in: 0...Double(StudioPreferences.barCounts.count - 1),
                        step: 1
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bar count")
                .studioControlRegion()
            }
            if model.mode == .spectrum {
                settingSlider("Gap", value: $model.barGap, range: StudioPreferences.barGapRange, step: 0.5)
                settingSlider("Corner", value: $model.cornerRadius, range: StudioPreferences.cornerRadiusRange, step: 0.5)
                Toggle("Bar stroke", isOn: $model.spectrumStroke)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .studioControlRegion()
            }
            if model.mode == .orbit {
                settingSlider("Ring", value: $model.orbitInner, range: StudioPreferences.orbitInnerRange, step: 0.05)
            }
            StudioTextButton(title: "Reset", action: resetPreferences)
            StudioTextButton(title: "Hide", action: close)
        }
        .frame(width: 220, alignment: .leading)
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
            holdsChrome: showsAppearance,
            now: now,
            exitedAt: exitedAt
        )
    }

    private var chromeAnimation: Animation? {
        let duration = StudioChromeMotion.fadeSeconds(hiding: showsChrome == false, reduceMotion: reduceMotion)
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    private var showsBarCount: Bool {
        model.mode == .spectrum || model.mode == .orbit
    }

    private var barIndex: Int {
        StudioPreferences.barCounts.firstIndex(of: model.barCount) ?? 2
    }

    private func settingSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(warmWhite.opacity(0.72))
                .frame(width: 68, alignment: .leading)
            Slider(value: value, in: range, step: step)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .studioControlRegion()
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

    private var startDisabled: Bool {
        spike.phase == .starting || spike.phase == .running
    }

    private var stopDisabled: Bool {
        spike.phase == .idle
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

private struct StudioTextButton: View {
    var title: String
    var disabled: Bool = false
    var highlighted: Bool = false
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if hovering || focused || highlighted {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    }
                }
        }
        .buttonStyle(StudioPlainButtonStyle(showsFill: highlighted))
        .disabled(disabled)
        .focusable()
        .focused($focused)
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
