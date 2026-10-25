#if os(macOS)
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case spectrum
    case waveform
    case orbit
    case window
    case playback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .spectrum: return "Spectrum"
        case .waveform: return "Waveform"
        case .orbit: return "Orbit"
        case .window: return "Window"
        case .playback: return "Playback"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "paintpalette"
        case .spectrum: return "chart.bar.fill"
        case .waveform: return "waveform"
        case .orbit: return "circle.dotted"
        case .window: return "macwindow"
        case .playback: return "play.circle"
        }
    }
}

struct SettingsView: View {
    let studio: StudioWindowController
    @Bindable var model: StudioModel
    @State private var selection: SettingsCategory = .appearance

    init(studio: StudioWindowController) {
        self.studio = studio
        self.model = studio.model
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label(category.title, systemImage: category.symbol)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Form {
                Section {
                    studioPreviewRow
                }
                switch selection {
                case .appearance: appearancePane
                case .spectrum: spectrumPane
                case .waveform: waveformPane
                case .orbit: orbitPane
                case .window: windowPane
                case .playback: playbackPane
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection.title)
        }
        .onChange(of: model.prefs) { _, _ in
            studio.preferencesDidChange()
        }
    }

    private var studioPreviewRow: some View {
        HStack {
            Text(model.isShown ? "Changes show in Studio immediately." : "Studio is hidden. Show it to preview changes.")
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.isShown ? "Hide Studio" : "Show Studio") {
                studio.toggle()
            }
        }
    }

    // MARK: Panes

    @ViewBuilder
    private var appearancePane: some View {
        Section("Preset") {
            Picker("Preset", selection: presetBinding) {
                ForEach(StudioAccent.allCases) { preset in
                    Text(preset.title).tag(Optional(preset))
                }
            }
            .pickerStyle(.segmented)
        }
        Section("Colors") {
            ColorPicker("Fill and line", selection: colorBinding(\.appearance.color), supportsOpacity: false)
            ColorPicker("Stroke", selection: colorBinding(\.appearance.strokeColor), supportsOpacity: false)
            SettingsSlider(title: "Opacity", value: $model.prefs.appearance.opacity, range: StudioPreferences.opacityRange, step: 0.01)
            SettingsSlider(title: "Stroke width", value: $model.prefs.appearance.lineWidth, range: StudioPreferences.lineWidthRange, step: 0.5)
        }
        Section {
            Text("The Studio window background is always fully transparent. Opacity only changes the graphic.")
                .foregroundStyle(.secondary)
            Button("Reset Appearance") { model.prefs.appearance = .standard }
        }
    }

    @ViewBuilder
    private var spectrumPane: some View {
        Section("Bars") {
            Picker("Bars", selection: Binding(get: { model.prefs.spectrum.barCount }, set: { studio.setSpectrumBarCount($0) })) {
                ForEach(StudioPreferences.barCounts, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            Picker("Bands", selection: $model.prefs.spectrum.scale) {
                ForEach(SpectrumScale.allCases) { scale in
                    Text(scale.title).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            SettingsSlider(title: "Low frequency (Hz)", value: $model.prefs.spectrum.minHz, range: StudioPreferences.minHzRange, step: 5, fractionDigits: 0)
            SettingsSlider(title: "High frequency (Hz)", value: $model.prefs.spectrum.maxHz, range: StudioPreferences.maxHzRange, step: 100, fractionDigits: 0)
            Text("Each bar reads real FFT bins. A bar narrower than one bin reads the bins on either side of it.")
                .foregroundStyle(.secondary)
        }
        Section("Shape") {
            SettingsSlider(title: "Gap", value: $model.prefs.spectrum.barGap, range: StudioPreferences.barGapRange, step: 0.5)
            SettingsSlider(title: "Corner radius", value: $model.prefs.spectrum.cornerRadius, range: StudioPreferences.cornerRadiusRange, step: 0.5)
            Toggle("Bar stroke", isOn: $model.prefs.spectrum.stroke)
        }
        Section("Response") {
            SettingsSlider(title: "Sensitivity", value: $model.prefs.spectrum.sensitivity, range: StudioPreferences.sensitivityRange, step: 0.05)
            SettingsSlider(title: "Amplitude", value: $model.prefs.spectrum.amplitude, range: StudioPreferences.amplitudeRange, step: 0.05)
            SettingsSlider(title: "Smoothing", value: $model.prefs.spectrum.smoothing, range: StudioPreferences.smoothingRange, step: 0.05)
            SettingsSlider(title: "Attack (ms)", value: $model.prefs.spectrum.attackMs, range: StudioPreferences.attackMsRange, step: 5, fractionDigits: 0)
            SettingsSlider(title: "Release (ms)", value: $model.prefs.spectrum.releaseMs, range: StudioPreferences.releaseMsRange, step: 10, fractionDigits: 0)
        }
        Section("Peaks") {
            Toggle("Peak hold", isOn: $model.prefs.spectrum.peakHold)
            SettingsSlider(title: "Hold time (s)", value: $model.prefs.spectrum.peakHoldSeconds, range: StudioPreferences.peakHoldSecondsRange, step: 0.1)
                .disabled(model.prefs.spectrum.peakHold == false)
        }
        Section {
            Button("Reset Spectrum") {
                model.prefs.spectrum = .standard
                studio.setSpectrumBarCount(SpectrumPreferences.standard.barCount)
            }
        }
    }

    @ViewBuilder
    private var waveformPane: some View {
        Section("Shape") {
            Text("Draws the real captured PCM samples. Density only chooses how many of them are drawn.")
                .foregroundStyle(.secondary)
            Picker("Style", selection: $model.prefs.waveform.style) {
                ForEach(WaveformStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            Picker("Density", selection: $model.prefs.waveform.density) {
                ForEach(StudioPreferences.densities, id: \.self) { density in
                    Text("\(density)").tag(density)
                }
            }
            .pickerStyle(.segmented)
        }
        Section("Line") {
            Toggle("Custom line color", isOn: Binding(
                get: { model.prefs.waveform.customColor != nil },
                set: { model.prefs.waveform.customColor = $0 ? model.prefs.appearance.color : nil }
            ))
            if model.prefs.waveform.customColor != nil {
                ColorPicker("Line color", selection: Binding(
                    get: { (model.prefs.waveform.customColor ?? model.prefs.appearance.color).swiftUI },
                    set: { model.prefs.waveform.customColor = StudioColor($0) }
                ), supportsOpacity: false)
            }
            SettingsSlider(title: "Line width", value: $model.prefs.waveform.lineWidth, range: StudioPreferences.lineWidthRange, step: 0.5)
            SettingsSlider(title: "Amplitude", value: $model.prefs.waveform.amplitude, range: StudioPreferences.amplitudeRange, step: 0.05)
            SettingsSlider(title: "Smoothing", value: $model.prefs.waveform.smoothing, range: StudioPreferences.smoothingRange, step: 0.05)
        }
        Section {
            Button("Reset Waveform") { model.prefs.waveform = .standard }
        }
    }

    @ViewBuilder
    private var orbitPane: some View {
        Section("Ring") {
            Picker("Bars", selection: Binding(get: { model.prefs.orbit.barCount }, set: { studio.setOrbitBarCount($0) })) {
                ForEach(StudioPreferences.barCounts, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            SettingsSlider(title: "Inner ring", value: $model.prefs.orbit.inner, range: StudioPreferences.orbitInnerRange, step: 0.05)
            SettingsSlider(title: "Line width", value: $model.prefs.orbit.lineWidth, range: StudioPreferences.lineWidthRange, step: 0.5)
        }
        Section("Response") {
            SettingsSlider(title: "Amplitude", value: $model.prefs.orbit.amplitude, range: StudioPreferences.amplitudeRange, step: 0.05)
            SettingsSlider(title: "Smoothing", value: $model.prefs.orbit.smoothing, range: StudioPreferences.smoothingRange, step: 0.05)
        }
        Section {
            Button("Reset Orbit") {
                model.prefs.orbit = .standard
                studio.setOrbitBarCount(OrbitPreferences.standard.barCount)
            }
        }
    }

    @ViewBuilder
    private var windowPane: some View {
        Section("Window mode") {
            Picker("Mode", selection: Binding(get: { model.prefs.windowMode }, set: { studio.setWindowMode($0) })) {
                ForEach(StudioWindowMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(windowModeDescription)
                .foregroundStyle(.secondary)
            Text("Multi-desktop and full-screen behavior has not been verified on a real Mac yet.")
                .foregroundStyle(.secondary)
        }
        Section {
            Button("Reset All Studio Settings") { studio.resetPreferences() }
        }
    }

    @ViewBuilder
    private var playbackPane: some View {
        Section("Player") {
            Picker("Player", selection: Binding(get: { model.playerID }, set: { studio.setPlayerID($0) })) {
                Text("None").tag("")
                ForEach(studio.playerChoices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            LabeledContent("Status") {
                Text(playbackStatus)
            }
            Button(PlaybackButton.title(availability: model.playbackAvailability, state: model.playbackState)) {
                studio.togglePlayback()
            }
            .disabled(PlaybackButton.isEnabled(
                selection: model.playerID,
                availability: model.playbackAvailability,
                busy: model.playbackBusy
            ) == false)
        }
        Section {
            Text("Audune can only control Music or Spotify. It cannot pause browser audio or other system output.")
                .foregroundStyle(.secondary)
        }
        .onAppear { studio.refreshPlaybackNow() }
    }

    private var presetBinding: Binding<StudioAccent?> {
        Binding(
            get: {
                StudioAccent.matching(color: model.prefs.appearance.color, strokeColor: model.prefs.appearance.strokeColor)
            },
            set: { preset in
                if let preset { model.prefs.appearance.apply(preset) }
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<StudioPreferences, StudioColor>) -> Binding<Color> {
        Binding(
            get: { model.prefs[keyPath: keyPath].swiftUI },
            set: { model.prefs[keyPath: keyPath] = StudioColor($0) }
        )
    }

    private var windowModeDescription: String {
        switch model.prefs.windowMode {
        case .onDesktop: return "On Desktop sits above the wallpaper and below ordinary windows."
        case .onTop: return "On Top stays above ordinary windows and can sit beside a full-screen app."
        case .asWindow: return "As Window behaves like an ordinary window and can be covered by others."
        }
    }

    private var playbackStatus: String {
        if model.playerID.isEmpty { return "Choose a player" }
        if model.playbackDetail.isEmpty == false { return model.playbackDetail }
        switch model.playbackState {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .unknown: return "Unknown"
        }
    }
}

private struct SettingsSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var fractionDigits = 2

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 160)
                Text(value, format: .number.precision(.fractionLength(fractionDigits)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
