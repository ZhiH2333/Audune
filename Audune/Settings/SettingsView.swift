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
        .onChange(of: studio.currentPreferences()) { _, _ in
            studio.savePreferences()
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
        Section("Color") {
            Picker("Color", selection: $model.accent) {
                ForEach(StudioAccent.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            .pickerStyle(.segmented)
            SettingsSlider(title: "Opacity", value: $model.backgroundOpacity, range: StudioPreferences.opacityRange, step: 0.01)
            SettingsSlider(title: "Line width", value: $model.lineWidth, range: StudioPreferences.lineWidthRange, step: 0.5)
        }
        Section {
            Text("The Studio window background is always fully transparent. Opacity only changes the graphic.")
                .foregroundStyle(.secondary)
            Button("Reset All Studio Settings") { studio.resetPreferences() }
        }
    }

    @ViewBuilder
    private var spectrumPane: some View {
        Section("Bars") {
            barCountPicker
            SettingsSlider(title: "Gap", value: $model.barGap, range: StudioPreferences.barGapRange, step: 0.5)
            SettingsSlider(title: "Corner radius", value: $model.cornerRadius, range: StudioPreferences.cornerRadiusRange, step: 0.5)
            Toggle("Bar stroke", isOn: $model.spectrumStroke)
        }
        responseSection
    }

    @ViewBuilder
    private var waveformPane: some View {
        Section {
            Text("Draws the real captured PCM samples.")
                .foregroundStyle(.secondary)
        }
        responseSection
    }

    @ViewBuilder
    private var orbitPane: some View {
        Section("Ring") {
            barCountPicker
            SettingsSlider(title: "Inner ring", value: $model.orbitInner, range: StudioPreferences.orbitInnerRange, step: 0.05)
        }
        responseSection
    }

    @ViewBuilder
    private var windowPane: some View {
        Section("Window mode") {
            Picker("Mode", selection: Binding(get: { model.windowMode }, set: { studio.setWindowMode($0) })) {
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

    private var responseSection: some View {
        Section("Response") {
            SettingsSlider(title: "Amplitude", value: $model.amplitude, range: StudioPreferences.amplitudeRange, step: 0.05)
            SettingsSlider(title: "Smoothing", value: $model.smoothing, range: StudioPreferences.smoothingRange, step: 0.05)
        }
    }

    private var barCountPicker: some View {
        Picker("Bars", selection: Binding(get: { model.barCount }, set: { studio.setBarCount($0) })) {
            ForEach(StudioPreferences.barCounts, id: \.self) { count in
                Text("\(count)").tag(count)
            }
        }
    }

    private var windowModeDescription: String {
        switch model.windowMode {
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

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 160)
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
