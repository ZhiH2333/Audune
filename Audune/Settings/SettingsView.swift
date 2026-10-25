#if os(macOS)
import AppKit
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case spectrum
    case waveform
    case orbit
    case window
    case island
    case playback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .spectrum: return "Spectrum"
        case .waveform: return "Waveform"
        case .orbit: return "Orbit"
        case .window: return "Window"
        case .island: return "Notch Island"
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
        case .island: return "rectangle.topthird.inset.filled"
        case .playback: return "play.circle"
        }
    }
}

struct SettingsView: View {
    let studio: StudioWindowController
    let island: IslandWindowController
    @Bindable var model: StudioModel
    @Bindable var islandModel: IslandModel
    @State private var presetLibrary = VisualPresetCatalog.restoring()

    init(studio: StudioWindowController, island: IslandWindowController) {
        self.studio = studio
        self.island = island
        self.model = studio.model
        self.islandModel = island.model
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $model.settingsCategory) { category in
                Label(category.title, systemImage: category.symbol)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                Text(model.settingsCategory.title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            Form {
                Section {
                    if model.settingsCategory == .island {
                        islandStatusRow
                    } else {
                        studioPreviewRow
                    }
                }
                switch model.settingsCategory {
                case .appearance: appearancePane
                case .spectrum: spectrumPane
                case .waveform: waveformPane
                case .orbit: orbitPane
                case .window: windowPane
                case .island: islandPane
                case .playback: playbackPane
                }
            }
            .formStyle(.grouped)
            }
        }
        .toolbar(removing: .sidebarToggle)
        .onChange(of: model.prefs) { _, newValue in
            studio.preferencesDidChange()
            island.updateSharedVisuals(newValue)
        }
        .onChange(of: islandModel.prefs) { _, _ in
            island.preferencesDidChange()
        }
        .onChange(of: model.settingsCategory) { _, newCategory in
            studio.updatePlaybackTimer()
            if newCategory == .playback {
                studio.refreshPlaybackNow()
            } else if newCategory == .island {
                island.evaluateScreensAndApply(animated: false)
            }
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

    private var islandStatusRow: some View {
        HStack {
            Text(islandModel.statusSummary)
                .foregroundStyle(.secondary)
            Spacer()
            if islandModel.isSupported {
                Button(islandModel.prefs.isEnabled ? "Hide Notch Island" : "Show Notch Island") {
                    island.toggleEnabled()
                }
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
        visualPresetSection(.spectrum)
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
                studio.clearAppliedVisualPreset(for: .spectrum)
                reloadPresetLibrary()
            }
        }
    }

    @ViewBuilder
    private var waveformPane: some View {
        visualPresetSection(.waveform)
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
            Button("Reset Waveform") {
                model.prefs.waveform = .standard
                studio.clearAppliedVisualPreset(for: .waveform)
                reloadPresetLibrary()
            }
        }
    }

    @ViewBuilder
    private var orbitPane: some View {
        visualPresetSection(.orbit)
        Section("Ring") {
            Picker("Bars", selection: Binding(get: { model.prefs.orbit.barCount }, set: { studio.setOrbitBarCount($0) })) {
                ForEach(StudioPreferences.barCounts, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            Toggle("Mirror left and right", isOn: $model.prefs.orbit.mirrored)
            Text(model.prefs.orbit.mirrored
                ? "Mirrored rings read \(model.prefs.orbit.bandCount) real bands and show each twice, low at the top."
                : "Each bar reads its own real band.")
                .foregroundStyle(.secondary)
            SettingsSlider(title: "Inner radius", value: $model.prefs.orbit.inner, range: StudioPreferences.orbitInnerRange, step: 0.05)
            SettingsSlider(title: "Outer radius", value: $model.prefs.orbit.outerScale, range: StudioPreferences.orbitOuterRange, step: 0.02)
            SettingsSlider(title: "Angular gap (deg)", value: $model.prefs.orbit.gapDegrees, range: StudioPreferences.orbitGapRange, step: 0.5, fractionDigits: 1)
        }
        Section("Style") {
            Toggle("Custom color", isOn: Binding(
                get: { model.prefs.orbit.customColor != nil },
                set: { model.prefs.orbit.customColor = $0 ? model.prefs.appearance.color : nil }
            ))
            if model.prefs.orbit.customColor != nil {
                ColorPicker("Color", selection: Binding(
                    get: { (model.prefs.orbit.customColor ?? model.prefs.appearance.color).swiftUI },
                    set: { model.prefs.orbit.customColor = StudioColor($0) }
                ), supportsOpacity: false)
            }
            Toggle("Bar stroke", isOn: $model.prefs.orbit.stroke)
            SettingsSlider(title: "Stroke width", value: $model.prefs.orbit.lineWidth, range: StudioPreferences.lineWidthRange, step: 0.5)
        }
        Section("Response") {
            SettingsSlider(title: "Amplitude", value: $model.prefs.orbit.amplitude, range: StudioPreferences.amplitudeRange, step: 0.05)
            SettingsSlider(title: "Smoothing", value: $model.prefs.orbit.smoothing, range: StudioPreferences.smoothingRange, step: 0.05)
        }
        Section {
            Button("Reset Orbit") {
                model.prefs.orbit = .standard
                studio.setOrbitBarCount(OrbitPreferences.standard.barCount)
                studio.clearAppliedVisualPreset(for: .orbit)
                reloadPresetLibrary()
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
            Text(windowSpacesDescription)
                .foregroundStyle(.secondary)
            Text("Window levels, multiple desktops, and full-screen behavior have not been verified on a real Mac yet.")
                .foregroundStyle(.secondary)
        }
        Section("Move and resize") {
            Toggle("Allow dragging by the grip", isOn: $model.prefs.window.allowsDrag)
            Toggle("Allow resizing from the edges", isOn: $model.prefs.window.allowsResize)
            Toggle("Restore position and size at launch", isOn: $model.prefs.window.restorePosition)
            Button("Reset Position and Size") { studio.resetWindowFrame() }
        }
        Section("Controls") {
            SettingsSlider(title: "Hide delay (s)", value: $model.prefs.window.hideDelaySeconds, range: StudioPreferences.hideDelayRange, step: 0.1)
            Toggle("Fade controls in and out", isOn: $model.prefs.window.animatesChrome)
            Toggle("Follow system Reduce Motion", isOn: $model.prefs.window.followsReduceMotion)
            Text(reduceMotion ? "Reduce Motion is on in System Settings." : "Reduce Motion is off in System Settings.")
                .foregroundStyle(.secondary)
        }
        Section {
            Button("Reset Window Settings") {
                model.prefs.window = .standard
                studio.setWindowMode(StudioPreferences.standard.windowMode)
            }
            Button("Reset All Studio Settings") {
                studio.resetPreferences()
                studio.clearAppliedVisualPresets()
                island.updateSharedVisuals(StudioPreferences.standard)
                reloadPresetLibrary()
            }
        }
    }

    @ViewBuilder
    private var islandPane: some View {
        Section("Display & Status") {
            Toggle("Enable Notch Island", isOn: Binding(
                get: { islandModel.prefs.isEnabled },
                set: { island.setEnabled($0) }
            ))
            Picker("Display", selection: Binding(
                get: { islandModel.prefs.targetScreenID },
                set: { island.setTargetScreenID($0) }
            )) {
                Text("Automatic (Notched Display)").tag("")
                ForEach(islandModel.availableScreens) { screen in
                    Text(screen.localizedName).tag(screen.id)
                }
            }
            LabeledContent("State") {
                Text(islandStateDescription)
                    .foregroundStyle(.secondary)
            }
            if islandModel.isSupported == false {
                Text("Notch Island requires a Mac display with a camera housing and valid top auxiliary areas. Menu Bar and Studio remain available on non-notched displays.")
                    .foregroundStyle(.secondary)
            }
        }
        Section("Visuals") {
            Picker("Expanded mode", selection: Binding(
                get: { islandModel.prefs.mode },
                set: { island.selectMode($0) }
            )) {
                ForEach(StudioVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Picker("Compact bars per side", selection: Binding(
                get: { islandModel.prefs.compactBarCountPerSide },
                set: { island.setCompactBarCountPerSide($0) }
            )) {
                ForEach(IslandPreferences.compactBarCounts, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
            Text("Compact mode draws a symmetric live spectrum on both sides of the notch. Colors follow Appearance.")
                .foregroundStyle(.secondary)
        }
        Section("Interaction & Motion") {
            Toggle("Expand on pointer hover", isOn: $islandModel.prefs.hoverToExpand)
            SettingsSlider(
                title: "Expand delay (s)",
                value: $islandModel.prefs.expandDelaySeconds,
                range: IslandPreferences.expandDelayRange,
                step: 0.05
            )
            SettingsSlider(
                title: "Collapse delay (s)",
                value: $islandModel.prefs.collapseDelaySeconds,
                range: IslandPreferences.collapseDelayRange,
                step: 0.05
            )
            Toggle("Show in full-screen apps", isOn: $islandModel.prefs.showsInFullScreen)
            Toggle("Follow system Reduce Motion", isOn: $islandModel.prefs.followsReduceMotion)
            if islandModel.isSupported && islandModel.prefs.isEnabled {
                HStack {
                    Button(islandModel.state.isExpandedOrPinned ? "Collapse Now" : "Expand Now") {
                        if islandModel.state.isExpandedOrPinned {
                            island.collapse()
                        } else {
                            island.expand()
                        }
                    }
                    Button(islandModel.isPinned ? "Unpin Expanded" : "Pin Expanded") {
                        island.togglePin()
                    }
                }
            }
        }
        Section {
            Button("Reset Notch Island Settings") {
                island.resetPreferences()
            }
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
            if model.playerID.isEmpty == false {
                LabeledContent("Installed") { Text(installedText) }
                LabeledContent("Running") { Text(runningText) }
                LabeledContent("Automation") { Text(automationText) }
                LabeledContent("Playback") { Text(playbackStateText) }
                if model.playbackDetail.isEmpty == false {
                    Text(model.playbackDetail)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Choose Music or Spotify to enable Play/Pause in Studio.")
                    .foregroundStyle(.secondary)
            }
        }
        Section("Control") {
            Button(model.playbackRequesting ? "Waiting for macOS" : "Request Access") {
                studio.requestPlayerAccess()
            }
            .disabled(model.playbackAvailability != .automationNotRequested || model.playbackRequesting)
            Button("Open Automation Settings") { studio.openAutomationSettings() }
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
            Text("Audune can only control Music or Spotify, and only after you allow it. It cannot pause browser audio or other system output. Open the player first, then choose Request Access.")
                .foregroundStyle(.secondary)
            Text("Automation has not been verified on a real Mac yet.")
                .foregroundStyle(.secondary)
        }
    }

    private func visualPresetSection(_ mode: StudioVisualMode) -> some View {
        VisualPresetSelector(
            mode: mode,
            preferences: model.prefs,
            library: presetLibrary,
            apply: { preset in
                studio.applyVisualPreset(preset)
                reloadPresetLibrary()
            },
            save: { name in
                let result = studio.saveCurrentVisualPreset(name: name, mode: mode)
                reloadPresetLibrary()
                return result
            },
            duplicate: { preset in
                let result = studio.duplicateVisualPreset(id: preset.id)
                reloadPresetLibrary()
                return result
            },
            rename: { preset, name in
                let result = studio.renameVisualPreset(id: preset.id, to: name)
                reloadPresetLibrary()
                return result
            },
            delete: { preset in
                let result = studio.deleteVisualPreset(id: preset.id)
                reloadPresetLibrary()
                return result
            },
            resetLibrary: {
                let didReset = studio.resetVisualPresetLibrary()
                reloadPresetLibrary()
                return didReset
            }
        )
    }

    private func reloadPresetLibrary() {
        presetLibrary = VisualPresetCatalog.restoring()
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

    private var windowSpacesDescription: String {
        switch model.prefs.windowMode {
        case .onDesktop: return "On Desktop is set to join all desktops. Whether it appears on every desktop is not confirmed."
        case .onTop: return "On Top joins all desktops and is allowed beside full-screen apps."
        case .asWindow: return "As Window stays on its own desktop and full-screen apps can cover it."
        }
    }

    private var islandStateDescription: String {
        switch islandModel.state {
        case .disabled:
            return islandModel.isSupported ? "Disabled" : "Unsupported display"
        case .compact:
            return "Compact"
        case .expanded:
            return "Expanded"
        case .pinned:
            return "Pinned Expanded"
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var installedText: String {
        model.playbackAvailability == .notInstalled ? "No" : "Yes"
    }

    private var runningText: String {
        switch model.playbackAvailability {
        case .notInstalled, .noSelection: return "Unknown"
        case .notRunning: return "No"
        default: return "Yes"
        }
    }

    private var automationText: String {
        switch model.playbackAvailability {
        case .ready: return "Allowed"
        case .automationNotRequested: return "Not requested yet"
        case .automationDenied: return "Denied"
        case .checking: return "Checking\u{2026}"
        case .notInstalled, .notRunning, .noSelection: return "Unknown until the player is running"
        case .failed: return "Unavailable"
        }
    }

    private var playbackStateText: String {
        guard model.playbackAvailability == .ready else { return "Not available" }
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
