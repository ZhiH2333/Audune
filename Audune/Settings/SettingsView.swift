#if os(macOS)
import AppKit
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case startup
    case appearance
    case visualization
    case studio
    case island
    case fullscreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startup: return String(localized: "Startup")
        case .appearance: return String(localized: "Appearance")
        case .visualization: return String(localized: "Visualization")
        case .studio: return String(localized: "Studio")
        case .island: return String(localized: "Notch Island")
        case .fullscreen: return String(localized: "Zen")
        }
    }

    var symbol: String {
        switch self {
        case .startup: return "power"
        case .appearance: return "paintpalette"
        case .visualization: return "waveform.path.ecg"
        case .studio: return "macwindow"
        case .island: return "rectangle.topthird.inset.filled"
        case .fullscreen: return "macwindow"
        }
    }
}

struct SettingsView: View {
    let studio: StudioWindowController
    let island: IslandWindowController
    let fullscreen: FullscreenWindowController?
    @Bindable var model: StudioModel
    @Bindable var islandModel: IslandModel
    @State private var presetLibrary = VisualPresetCatalog.restoring()
    @State private var startupPrefs = StartupPreferences.load()
    @State private var fullscreenPrefs = FullscreenPreferences.load()
    @State private var launchAtLogin = SystemLaunchAtLoginService()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var layoutPreviewEnergy = LayoutPreviewEnergyState()
    @State private var islandPreviewEnergy = IslandLayoutPreviewEnergyState()

    init(
        studio: StudioWindowController,
        island: IslandWindowController,
        fullscreen: FullscreenWindowController? = nil
    ) {
        self.studio = studio
        self.island = island
        self.fullscreen = fullscreen
        self.model = studio.model
        self.islandModel = island.model
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsCategory.allCases, selection: $model.settingsCategory) { category in
                Label(category.title, systemImage: category.symbol)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .toolbar(removing: .sidebarToggle)
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
                    switch model.settingsCategory {
                    case .startup: startupPane
                    case .appearance: appearancePane
                    case .visualization: visualizationPane
                    case .studio: studioPane
                    case .island: islandPane
                    case .fullscreen: fullscreenPane
                    }
                }
                .formStyle(.grouped)
            }
            .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: columnVisibility) { _, visibility in
            if visibility != .all {
                columnVisibility = .all
            }
        }
        .onChange(of: model.prefs) { _, newValue in
            studio.preferencesDidChange()
            island.updateSharedVisuals(newValue)
            fullscreen?.updateSharedVisuals(newValue)
        }
        .onChange(of: islandModel.prefs) { _, _ in
            island.preferencesDidChange()
        }
        .onChange(of: model.settingsCategory) { oldCategory, newCategory in
            if oldCategory == .studio && newCategory != .studio {
                pauseLayoutPreview()
            }
            if oldCategory == .island && newCategory != .island {
                pauseIslandPreview()
            }
            if newCategory == .island {
                island.evaluateScreensAndApply(animated: false)
            }
            if newCategory == .startup {
                startupPrefs = StartupPreferences.load()
                reloadPresetLibrary()
                launchAtLogin.refresh()
            }
            if newCategory == .fullscreen {
                fullscreenPrefs = fullscreen?.model.prefs ?? FullscreenPreferences.load()
            }
        }
        .onChange(of: startupPrefs) { _, newValue in
            newValue.save()
        }
        .onChange(of: fullscreenPrefs) { _, newValue in
            newValue.save()
            if let fullscreen {
                fullscreen.model.prefs = newValue
                fullscreen.preferencesDidChange()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard model.settingsCategory == .startup else { return }
            launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if model.settingsCategory == .studio {
                pauseLayoutPreview()
            }
            if model.settingsCategory == .island {
                pauseIslandPreview()
            }
        }
    }

    @ViewBuilder
    private var startupPane: some View {
        Section("Show at launch") {
            Toggle("Studio", isOn: $startupPrefs.openStudioAtLaunch)
            Toggle("Notch Island", isOn: $startupPrefs.showIslandAtLaunch)
            Toggle("Settings", isOn: $startupPrefs.openSettingsAtLaunch)
            if startupPrefs.showIslandAtLaunch && islandModel.prefs.isEnabled == false {
                Text("Notch Island is disabled. Enable it under Notch Island, or it will not appear at launch.")
                    .foregroundStyle(.secondary)
                Button("Enable Notch Island") {
                    island.setEnabled(true)
                    model.settingsCategory = .island
                }
            }
        }
        Section("Login") {
            Toggle(
                "Launch Audune at login",
                isOn: Binding(
                    get: { launchAtLogin.status.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            if let message = launchAtLogin.status.statusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            }
            if let error = launchAtLogin.lastErrorDescription, launchAtLogin.status.isEnabled == false {
                Text(error)
                    .foregroundStyle(.secondary)
            }
            if launchAtLogin.status.needsApproval || launchAtLogin.status == .notFound || launchAtLogin.status == .unavailable {
                Button("Open Login Items…") {
                    launchAtLogin.openLoginItemsSettings()
                }
            }
        }
        Section("Visualization") {
            Picker("Mode", selection: modeBinding) {
                ForEach(StartupVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Picker("Visual preset", selection: startupPresetBinding) {
                Text("None").tag(Optional<String>.none)
                if startupPresetMissing {
                    Text("Selected preset is no longer available")
                        .tag(Optional(startupPrefs.presetID))
                }
                ForEach(compatibleStartupPresets) { preset in
                    Text(preset.displayName).tag(Optional(preset.id))
                }
            }
            Toggle("Start system audio capture automatically", isOn: $startupPrefs.autoStartCapture)
        }
    }

    private var modeBinding: Binding<StartupVisualMode> {
        Binding(
            get: { startupPrefs.visualMode },
            set: { newMode in
                startupPrefs.visualMode = newMode
                if let id = startupPrefs.presetID,
                   let preset = presetLibrary.preset(id: id),
                   let required = newMode.studioMode,
                   preset.mode != required {
                    startupPrefs.presetID = nil
                }
            }
        )
    }

    private var startupPresetBinding: Binding<String?> {
        Binding(
            get: { startupPrefs.presetID },
            set: { newID in
                startupPrefs.presetID = newID
                guard let newID, let preset = presetLibrary.preset(id: newID) else { return }
                switch preset.mode {
                case .spectrum: startupPrefs.visualMode = .spectrum
                case .waveform: startupPrefs.visualMode = .waveform
                case .orbit: startupPrefs.visualMode = .orbit
                }
            }
        )
    }

    private var compatibleStartupPresets: [VisualPreset] {
        let mode = startupPrefs.visualMode.studioMode ?? model.prefs.mode
        return presetLibrary.presets(for: mode)
    }

    private var startupPresetMissing: Bool {
        guard let id = startupPrefs.presetID, id.isEmpty == false else { return false }
        return presetLibrary.preset(id: id) == nil
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
            Button("Reset Appearance") { model.prefs.appearance = .standard }
        }
    }

    @ViewBuilder
    private var visualizationPane: some View {
        Section {
            Picker("Mode", selection: Binding(
                get: { model.prefs.mode },
                set: { studio.selectMode($0) }
            )) {
                ForEach(StudioVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        switch model.prefs.mode {
        case .spectrum: spectrumPane
        case .waveform: waveformPane
        case .orbit: orbitPane
        }
    }

    @ViewBuilder
    private var studioPane: some View {
        Section("Preview") {
            LayoutPreview(
                model: model,
                energySaving: layoutPreviewEnergy.isEnergySaving,
                frozen: layoutPreviewEnergy.snapshot,
                onPause: pauseLayoutPreview,
                onResume: { layoutPreviewEnergy.resume() }
            )
        }
        Section("Visualization size") {
            Picker("Mode", selection: $model.prefs.layout.mode) {
                ForEach(VisualLayoutMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Picker("Aspect ratio", selection: $model.prefs.layout.aspect) {
                ForEach(VisualAspect.allCases) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.prefs.layout.mode == .fill)
            LabeledContent("Scale") {
                HStack {
                    Slider(value: $model.prefs.layout.scale, in: VisualLayoutPreferences.scaleRange, step: 0.05)
                        .frame(minWidth: 160)
                    Text(model.prefs.layout.scale, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            .disabled(model.prefs.layout.mode == .fill)
        }
        Section("Window mode") {
            Picker("Mode", selection: Binding(get: { model.prefs.windowMode }, set: { studio.setWindowMode($0) })) {
                ForEach(StudioWindowMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        Section("Move and resize") {
            Toggle("Allow dragging by the grip", isOn: $model.prefs.window.allowsDrag)
            Toggle("Allow resizing from the edges", isOn: $model.prefs.window.allowsResize)
            Toggle("Restore position and size at launch", isOn: $model.prefs.window.restorePosition)
            Button("Reset Position and Size") { studio.resetWindowFrame() }
        }
        Section("Size") {
            SettingsSlider(
                title: "Width (pt)",
                value: $model.prefs.window.width,
                range: StudioPreferences.windowWidthRange,
                step: 10,
                fractionDigits: 0
            )
            SettingsSlider(
                title: "Height (pt)",
                value: $model.prefs.window.height,
                range: StudioPreferences.windowHeightRange,
                step: 10,
                fractionDigits: 0
            )
        }
        Section("Controls") {
            Toggle("Automatically hide controls", isOn: $model.prefs.window.autoHidesControls)
            Toggle("Fade controls in and out", isOn: $model.prefs.window.animatesChrome)
            Toggle("Follow system Reduce Motion", isOn: $model.prefs.window.followsReduceMotion)
            Text(reduceMotionStatus)
                .foregroundStyle(.secondary)
        }
        Section {
            Button("Reset Layout") { model.prefs.layout = .standard }
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
        }
        Section("Shape") {
            SettingsSlider(title: "Gap", value: $model.prefs.spectrum.barGap, range: StudioPreferences.barGapRange, step: 0.5)
            SettingsSlider(title: "Corner radius", value: $model.prefs.spectrum.cornerRadius, range: StudioPreferences.cornerRadiusRange, step: 0.5)
            Toggle("Bar stroke", isOn: $model.prefs.spectrum.stroke)
            Picker("Color mapping", selection: $model.prefs.spectrum.colorMode) {
                ForEach(SpectrumColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
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
            SettingsSlider(title: "Fall speed", value: $model.prefs.spectrum.peakFallPerSecond, range: StudioPreferences.peakFallPerSecondRange, step: 0.05)
                .disabled(model.prefs.spectrum.peakHold == false)
        }
        Section("Silence") {
            Toggle("Silence gate", isOn: $model.prefs.spectrum.silenceGateEnabled)
            SettingsSlider(
                title: "Noise floor",
                value: $model.prefs.spectrum.silenceThreshold,
                range: StudioPreferences.silenceThresholdRange,
                step: 0.0001,
                fractionDigits: 4
            )
            .disabled(model.prefs.spectrum.silenceGateEnabled == false)
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
        Section("Look") {
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
            SettingsSlider(title: "Stroke width", value: $model.prefs.waveform.lineWidth, range: StudioPreferences.lineWidthRange, step: 0.5)
            SettingsSlider(
                title: "Fill strength",
                value: $model.prefs.waveform.fillStrength,
                range: StudioPreferences.fillStrengthRange,
                step: 0.05
            )
        }
        Section("Motion") {
            SettingsSlider(
                title: "Maximum display height",
                value: $model.prefs.waveform.verticalRange,
                range: StudioPreferences.waveformVerticalRangeRange,
                step: 0.05
            )
            SettingsSlider(
                title: "Visual amplitude",
                value: $model.prefs.waveform.amplitude,
                range: StudioPreferences.waveformAmplitudeRange,
                step: 0.05
            )
            SettingsSlider(
                title: "Motion smoothing",
                value: $model.prefs.waveform.smoothing,
                range: StudioPreferences.smoothingRange,
                step: 0.05
            )
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
            SettingsSlider(title: "Inner radius", value: $model.prefs.orbit.inner, range: StudioPreferences.orbitInnerRange, step: 0.05)
            SettingsSlider(title: "Outer radius", value: $model.prefs.orbit.outerScale, range: StudioPreferences.orbitOuterRange, step: 0.02)
            SettingsSlider(title: "Angular gap (deg)", value: $model.prefs.orbit.gapDegrees, range: StudioPreferences.orbitGapRange, step: 0.5, fractionDigits: 1)
            Picker("Layers", selection: $model.prefs.orbit.layerMode) {
                ForEach(OrbitLayerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
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
            SettingsSlider(title: "Motion smoothing", value: $model.prefs.orbit.smoothing, range: StudioPreferences.smoothingRange, step: 0.05)
            SettingsSlider(
                title: "Pulse strength",
                value: $model.prefs.orbit.pulseStrength,
                range: StudioPreferences.orbitPulseRange,
                step: 0.05
            )
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
        }
        Section("Preview") {
            IslandLayoutPreview(
                islandModel: islandModel,
                studioModel: model,
                energySaving: islandPreviewEnergy.isEnergySaving,
                frozen: islandPreviewEnergy.snapshot,
                onPause: pauseIslandPreview,
                onResume: { islandPreviewEnergy.resume() }
            )
        }
        Section("Experimental Now Playing") {
            Toggle("Show Now Playing when expanded", isOn: Binding(
                get: { islandModel.prefs.nowPlayingEnabled },
                set: { island.setNowPlayingEnabled($0) }
            ))
            if islandModel.prefs.nowPlayingEnabled {
                switch islandModel.nowPlaying.availability {
                case .unavailable:
                    Text("Now Playing unavailable")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .empty:
                    Text("Nothing playing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .listening, .idle:
                    EmptyView()
                }
            }
        }
        Section("Now Playing layout") {
            Toggle("Artwork", isOn: $islandModel.prefs.nowPlayingLayout.showArtwork)
            Toggle("Title & Artist", isOn: $islandModel.prefs.nowPlayingLayout.showTitleArtist)
            Toggle("Progress", isOn: $islandModel.prefs.nowPlayingLayout.showProgress)
            Toggle("Controls", isOn: $islandModel.prefs.nowPlayingLayout.showTransport)
            Toggle("Visualization", isOn: $islandModel.prefs.nowPlayingLayout.showVisualization)
        }
        Section("Interaction & Motion") {
            Toggle("Expand on pointer hover", isOn: $islandModel.prefs.hoverToExpand)
            SettingsSlider(
                title: "Expand delay (s)",
                value: $islandModel.prefs.expandDelaySeconds,
                range: IslandPreferences.expandDelayRange,
                step: 0.05
            )
            Picker("Haptic feedback", selection: $islandModel.prefs.hapticStrength) {
                ForEach(IslandHapticStrength.allCases) { strength in
                    Text(strength.title).tag(strength)
                }
            }
            SettingsSlider(
                title: "Collapse delay (s)",
                value: $islandModel.prefs.collapseDelaySeconds,
                range: IslandPreferences.collapseDelayRange,
                step: 0.05
            )
            Toggle("Show in full-screen apps", isOn: $islandModel.prefs.showsInFullScreen)
            SettingsSlider(
                title: "Animation speed",
                value: $islandModel.prefs.animationSpeed,
                range: IslandPreferences.animationSpeedRange,
                step: 0.1,
                fractionDigits: 1
            )
            Toggle("Follow system Reduce Motion", isOn: $islandModel.prefs.followsReduceMotion)
            if islandModel.isSupported && islandModel.prefs.isEnabled {
                HStack {
                    Button(islandExpandTitle) {
                        if islandModel.state.isExpandedOrPinned {
                            island.collapse()
                        } else {
                            island.expand()
                        }
                    }
                    Button(islandPinTitle) {
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
    private var fullscreenPane: some View {
        Section {
            Text("Experimental Zen player window. Uses the same Now Playing metadata as Notch Island and never starts or stops system audio capture.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        Section("Zen Mode") {
            Toggle("Enable Zen", isOn: $fullscreenPrefs.isEnabled)
            if fullscreenPrefs.isEnabled {
                Button("Open Zen") {
                    fullscreen?.show()
                }
                .disabled(fullscreen == nil)
            }
        }
        Section("Lyrics") {
            Toggle("Search lyrics online", isOn: $fullscreenPrefs.lyricsNetworkEnabled)
                .disabled(fullscreenPrefs.isEnabled == false)
            Picker("Lyrics source", selection: $fullscreenPrefs.lyricsSource) {
                ForEach(LyricsSourceSelection.allCases) { selection in
                    Text(selection.title).tag(selection)
                }
            }
            .disabled(fullscreenPrefs.isEnabled == false || fullscreenPrefs.lyricsNetworkEnabled == false)
            Text("Automatic checks enabled sources in parallel and uses the first good result. Choose a source to query it alone. Searches use song metadata only; artwork and audio are never uploaded. Default is off.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        Section {
            Button("Reset Zen Settings") {
                FullscreenPreferences.reset()
                fullscreenPrefs = .standard
                if let fullscreen {
                    fullscreen.model.prefs = .standard
                    fullscreen.preferencesDidChange()
                    fullscreen.hide()
                }
            }
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
            },
            exportPresets: { presets in
                switch studio.encodeVisualPresets(presets) {
                case .failure(let error):
                    return error.message
                case .success(let data):
                    var writeError: String?
                    _ = VisualPresetFilePanel.runSavePanel(
                        suggestedName: VisualPresetFilePanel.defaultExportName(mode: mode, presets: presets),
                        data: data,
                        onError: { writeError = $0 }
                    )
                    return writeError
                }
            },
            loadImportEntries: {
                guard let url = VisualPresetFilePanel.runOpenPanel() else { return nil }
                do {
                    let data = try Data(contentsOf: url)
                    return VisualPresetExchange.decode(data)
                } catch {
                    return .failure(.unreadableFile)
                }
            },
            commitImport: { plan in
                let result = studio.commitVisualPresetImport(plan)
                reloadPresetLibrary()
                return result
            }
        )
    }

    private func reloadPresetLibrary() {
        presetLibrary = VisualPresetCatalog.restoring()
    }

    private func pauseLayoutPreview() {
        layoutPreviewEnergy.enterEnergySaving(capturing: .live(from: model))
    }

    private func pauseIslandPreview() {
        islandPreviewEnergy.enterEnergySaving(capturing: .live(from: islandModel, studio: model))
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

    private var islandExpandTitle: LocalizedStringKey {
        islandModel.state.isExpandedOrPinned ? "Collapse Now" : "Expand Now"
    }

    private var islandPinTitle: LocalizedStringKey {
        islandModel.isPinned ? "Unpin Expanded" : "Pin Expanded"
    }

    private var islandStateDescription: LocalizedStringKey {
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

    private var reduceMotionStatus: LocalizedStringKey {
        reduceMotion ? "Reduce Motion is on in System Settings." : "Reduce Motion is off in System Settings."
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Mini Expanded Island: chrome + viz follow Now Playing layout toggles (Studio-style pause/resume).
private struct IslandLayoutPreview: View {
    @Bindable var islandModel: IslandModel
    @Bindable var studioModel: StudioModel
    var energySaving: Bool
    var frozen: IslandLayoutPreviewSnapshot?
    var onPause: () -> Void
    var onResume: () -> Void

    private let previewSize = CGSize(width: 360, height: 148)

    var body: some View {
        let shape = IslandShape(bottomRadius: IslandChrome.expandedBottomRadius)
        let frame = displayFrame
        let layout = islandModel.prefs.nowPlayingLayout
        ZStack {
            shape.fill(Color.black)
            shape.stroke(Color.white.opacity(0.1), lineWidth: 0.6)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(StudioVisualMode.allCases) { mode in
                        Image(systemName: mode.symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(islandModel.prefs.mode == mode ? 0.95 : 0.35))
                            .frame(width: 18, height: 18)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                ZStack {
                    if layout.showVisualization {
                        // Island Expanded mode is independent of Studio; preview must follow island prefs.
                        StudioVisualizationView(
                            prefs: islandPreviewPrefs,
                            spectrum: frame.spectrum,
                            peaks: frame.peaks,
                            waveform: frame.waveform,
                            drawsBars: frame.drawsBars
                        )
                        .opacity(0.45)
                        .blur(radius: energySaving ? 6 : 1.5)
                        .mask {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .inset(by: 6)
                                .fill(Color.white)
                                .blur(radius: 8)
                        }
                        .id(islandModel.prefs.mode)
                    }

                    // Match live Island: chrome only when Show Now Playing is on.
                    if islandModel.prefs.nowPlayingEnabled, layout.showsAnyChrome {
                        IslandExpandedNowPlayingView(
                            snapshot: frame.nowPlaying,
                            layout: layout,
                            onTogglePlay: {},
                            onPrevious: {},
                            onNext: {},
                            onSeek: { _ in }
                        )
                        .padding(.horizontal, 14)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if energySaving {
                shape.fill(.regularMaterial.opacity(0.92))
                VStack(spacing: 10) {
                    Text("Preview is in energy-saving mode")
                        .font(.callout.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Button("Resume Preview", action: onResume)
                        .buttonStyle(.glass)
                }
                .padding(12)
            } else {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help("Pause Preview")
                .accessibilityLabel("Pause Preview")
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(shape)
        .frame(width: previewSize.width, height: previewSize.height)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Island layout preview")
        .accessibilityValue(energySaving
            ? String(localized: "Preview is in energy-saving mode")
            : String(localized: "Expanded Island layout preview"))
    }

    private var displayFrame: IslandLayoutPreviewSnapshot {
        if energySaving, let frozen {
            return frozen
        }
        return .live(from: islandModel, studio: studioModel)
    }

    /// Appearance/spectrum params from Studio prefs, but mode from Notch Island.
    private var islandPreviewPrefs: StudioPreferences {
        var prefs = studioModel.prefs
        prefs.mode = islandModel.prefs.mode
        return prefs
    }
}

/// Mini Studio: outer frame is the window, inner frame is the visualization.
/// Live while active; frozen while energy-saving after leaving Layout or pausing.
private struct LayoutPreview: View {
    @Bindable var model: StudioModel
    var energySaving: Bool
    var frozen: LayoutPreviewSnapshot?
    var onPause: () -> Void
    var onResume: () -> Void

    var body: some View {
        let window = model.windowSize.width > 0 && model.windowSize.height > 0 ? model.windowSize : StudioFrame.defaultSize
        let boxHeight: CGFloat = 170
        let boxWidth: CGFloat = 320
        let fit = min(boxWidth / window.width, boxHeight / window.height)
        let shown = CGSize(width: window.width * fit, height: window.height * fit)
        let inner = VisualLayout.frame(in: shown, layout: model.prefs.layout)
        let frame = displayFrame
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .frame(width: shown.width, height: shown.height)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: shown.width, height: shown.height)
            StudioVisualizationView(
                prefs: model.prefs,
                spectrum: frame.spectrum,
                peaks: frame.peaks,
                waveform: frame.waveform,
                drawsBars: frame.drawsBars
            )
            .blur(radius: energySaving ? 8 : 0)
            .frame(width: inner.width, height: inner.height)
            .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1))
            .offset(x: inner.minX, y: inner.minY)
            if energySaving {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.32))
                    }
                    .frame(width: shown.width, height: shown.height)
                VStack(spacing: 12) {
                    Text("Preview is in energy-saving mode")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Button("Resume Preview", action: onResume)
                        .buttonStyle(.glass)
                }
                .padding(16)
                .frame(width: shown.width, height: shown.height)
            } else {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help("Pause Preview")
                .accessibilityLabel("Pause Preview")
                .padding(8)
                .frame(width: shown.width, height: shown.height, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(width: shown.width, height: shown.height)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Layout preview")
        .accessibilityValue(energySaving
            ? String(localized: "Preview is in energy-saving mode")
            : "Window \(Int(window.width)) by \(Int(window.height)) points")
    }

    private var displayFrame: LayoutPreviewSnapshot {
        if energySaving, let frozen {
            return frozen
        }
        return .live(from: model)
    }
}

private struct SettingsSlider: View {
    var title: LocalizedStringKey
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
