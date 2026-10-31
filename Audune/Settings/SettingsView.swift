#if os(macOS)
import AppKit
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case startup
    case appearance
    case layout
    case spectrum
    case waveform
    case orbit
    case window
    case island

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startup: return String(localized: "Startup")
        case .appearance: return String(localized: "Appearance")
        case .layout: return String(localized: "Layout")
        case .spectrum: return String(localized: "Spectrum")
        case .waveform: return String(localized: "Waveform")
        case .orbit: return String(localized: "Orbit")
        case .window: return String(localized: "Window")
        case .island: return String(localized: "Notch Island")
        }
    }

    var symbol: String {
        switch self {
        case .startup: return "power"
        case .appearance: return "paintpalette"
        case .layout: return "rectangle.dashed"
        case .spectrum: return "chart.bar.fill"
        case .waveform: return "waveform"
        case .orbit: return "circle.dotted"
        case .window: return "macwindow"
        case .island: return "rectangle.topthird.inset.filled"
        }
    }
}

struct SettingsView: View {
    let studio: StudioWindowController
    let island: IslandWindowController
    @Bindable var model: StudioModel
    @Bindable var islandModel: IslandModel
    @State private var presetLibrary = VisualPresetCatalog.restoring()
    @State private var startupPrefs = StartupPreferences.load()
    @State private var launchAtLogin = SystemLaunchAtLoginService()

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
                case .startup: startupPane
                case .appearance: appearancePane
                case .layout: layoutPane
                case .spectrum: spectrumPane
                case .waveform: waveformPane
                case .orbit: orbitPane
                case .window: windowPane
                case .island: islandPane
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
            if newCategory == .island {
                island.evaluateScreensAndApply(animated: false)
            }
            if newCategory == .startup {
                startupPrefs = StartupPreferences.load()
                reloadPresetLibrary()
                launchAtLogin.refresh()
            }
        }
        .onChange(of: startupPrefs) { _, newValue in
            newValue.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard model.settingsCategory == .startup else { return }
            launchAtLogin.refresh()
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

    private var studioPreviewRow: some View {
        HStack {
            Text(studioPreviewText)
                .foregroundStyle(.secondary)
            Spacer()
            Button(studioToggleTitle) {
                studio.toggle()
            }
        }
    }

    private var islandToggleTitle: LocalizedStringKey {
        islandModel.prefs.isEnabled ? "Hide Notch Island" : "Show Notch Island"
    }

    private var studioPreviewText: LocalizedStringKey {
        model.isShown ? "Changes show in Studio immediately." : "Studio is hidden. Show it to preview changes."
    }

    private var studioToggleTitle: LocalizedStringKey {
        model.isShown ? "Hide Studio" : "Show Studio"
    }

    private var islandStatusRow: some View {
        HStack {
            Text(islandModel.statusSummary)
                .foregroundStyle(.secondary)
            Spacer()
            if islandModel.isSupported {
                Button(islandToggleTitle) {
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
            Button("Reset Appearance") { model.prefs.appearance = .standard }
        }
    }

    @ViewBuilder
    private var layoutPane: some View {
        Section("Preview") {
            LayoutPreview(model: model)
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
        Section {
            Button("Reset Layout") { model.prefs.layout = .standard }
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
    private var windowPane: some View {
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

/// Mini Studio: outer frame is the window, inner frame is the visualization, drawn with live data.
private struct LayoutPreview: View {
    @Bindable var model: StudioModel

    var body: some View {
        let window = model.windowSize.width > 0 && model.windowSize.height > 0 ? model.windowSize : StudioFrame.defaultSize
        let boxHeight: CGFloat = 170
        let boxWidth: CGFloat = 320
        let fit = min(boxWidth / window.width, boxHeight / window.height)
        let shown = CGSize(width: window.width * fit, height: window.height * fit)
        let inner = VisualLayout.frame(in: shown, layout: model.prefs.layout)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .frame(width: shown.width, height: shown.height)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: shown.width, height: shown.height)
            StudioVisualizationView(
                prefs: model.prefs,
                spectrum: model.studioSpectrum,
                peaks: model.spectrumPeaks,
                waveform: model.displayWaveform,
                drawsBars: model.snapshot.isSilent == false
            )
            .frame(width: inner.width, height: inner.height)
            .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1))
            .offset(x: inner.minX, y: inner.minY)
        }
        .frame(width: shown.width, height: shown.height)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Layout preview")
        .accessibilityValue("Window \(Int(window.width)) by \(Int(window.height)) points")
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
