#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class StudioModel {
    var snapshot = AudioSnapshot.zero
    var alwaysOnTop = StudioPreferences.standard.alwaysOnTop
    var mode: StudioVisualMode = .spectrum
    var backgroundOpacity = StudioPreferences.standard.backgroundOpacity
    var accent: StudioAccent = .warm
}

struct StudioContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: StudioModel
    var setAlwaysOnTop: (Bool) -> Void
    var savePreferences: () -> Void
    var resetPreferences: () -> Void
    var close: () -> Void
    var hitMap: StudioHitMap

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Studio")
                    .font(.headline)
                StudioDragSurface(hitMap: hitMap)
                    .frame(maxWidth: .infinity, minHeight: 28)
                Button("Reset", action: resetPreferences)
                    .studioControlRegion()
                Button("Close", action: close)
                    .studioControlRegion()
            }
            Text(title)
                .font(.title3)
            if spike.phase == .failed {
                Text(spike.failureText.isEmpty ? "Audio capture failed." : spike.failureText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .studioControlRegion()
                Text(spike.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .studioControlRegion()
            }
            HStack {
                Button("Start") {
                    Task { await spike.start() }
                }
                .disabled(startDisabled)
                .studioControlRegion()
                Button("Stop") {
                    spike.stop()
                }
                .disabled(stopDisabled)
                .studioControlRegion()
            }
            Toggle("Always on Top", isOn: Binding(
                get: { model.alwaysOnTop },
                set: { setAlwaysOnTop($0) }
            ))
            .studioControlRegion()
            Picker("Mode", selection: $model.mode) {
                ForEach(StudioVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .studioControlRegion()
            Picker("Color", selection: $model.accent) {
                ForEach(StudioAccent.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            .studioControlRegion()
            HStack {
                Text("Opacity")
                Slider(value: $model.backgroundOpacity, in: StudioPreferences.opacityRange)
            }
            .accessibilityElement(children: .combine)
            .studioControlRegion()
            ZStack {
                visualization
                    .allowsHitTesting(false)
                StudioDragSurface(hitMap: hitMap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 24.0 / 255.0, green: 26.0 / 255.0, blue: 30.0 / 255.0).opacity(model.backgroundOpacity))
        .foregroundStyle(Color(red: 0.96, green: 0.94, blue: 0.90))
        .coordinateSpace(name: StudioCoordinateSpace.name)
        .onPreferenceChange(StudioControlFramesKey.self) { frames in
            hitMap.controlFramesTopLeft = frames
        }
        .onChange(of: model.mode) { _, _ in savePreferences() }
        .onChange(of: model.accent) { _, _ in savePreferences() }
        .onChange(of: model.backgroundOpacity) { _, _ in savePreferences() }
    }

    @ViewBuilder
    private var visualization: some View {
        switch model.mode {
        case .spectrum:
            SpectrumCanvas(spectrum: model.snapshot.spectrum, drawsBars: drawsBars, color: accentColor)
        case .waveform:
            WaveformCanvas(samples: model.snapshot.waveform, color: accentColor)
        case .orbit:
            OrbitCanvas(spectrum: model.snapshot.spectrum, drawsLevels: drawsBars, color: accentColor)
        }
    }

    private var accentColor: Color {
        Color(red: model.accent.red, green: model.accent.green, blue: model.accent.blue)
    }

    private var title: String {
        switch spike.phase {
        case .idle:
            return "Not listening"
        case .starting:
            return "Starting"
        case .failed:
            return "Capture failed"
        case .running:
            return model.snapshot.isSilent ? "No audio" : "Listening"
        }
    }

    private var startDisabled: Bool {
        spike.phase == .starting || spike.phase == .running
    }

    private var stopDisabled: Bool {
        spike.phase == .idle
    }

    private var drawsBars: Bool {
        spike.phase == .running && model.snapshot.isSilent == false
    }
}
#endif
