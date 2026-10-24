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
    @State private var showsAppearance = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                visualization
                    .allowsHitTesting(false)
                StudioDragSurface(hitMap: hitMap)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if spike.phase == .failed {
                Text(failureLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.93, green: 0.55, blue: 0.48))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .studioControlRegion()
            }
            if showsAppearance {
                appearance
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            bar
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(graphite.opacity(model.backgroundOpacity))
        .foregroundStyle(warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .preferredColorScheme(.dark)
        .coordinateSpace(name: StudioCoordinateSpace.name)
        .onPreferenceChange(StudioControlFramesKey.self) { frames in
            hitMap.controlFramesTopLeft = frames
        }
        .onChange(of: model.mode) { _, _ in savePreferences() }
        .onChange(of: model.accent) { _, _ in savePreferences() }
        .onChange(of: model.backgroundOpacity) { _, _ in savePreferences() }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(warmWhite.opacity(0.72))
                .lineLimit(1)
            StudioDragSurface(hitMap: hitMap)
                .frame(maxWidth: .infinity, minHeight: 22)
            Picker("Mode", selection: $model.mode) {
                ForEach(StudioVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 228)
            .accessibilityLabel("Mode")
            .studioControlRegion()
            HStack(spacing: 6) {
                Button("Start") {
                    Task { await spike.start() }
                }
                .disabled(startDisabled)
                Button("Stop") {
                    spike.stop()
                }
                .disabled(stopDisabled)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .studioControlRegion()
            Button(showsAppearance ? "Done" : "More") {
                showsAppearance.toggle()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .studioControlRegion()
            Button("Close", action: close)
                .controlSize(.small)
                .buttonStyle(.borderless)
                .studioControlRegion()
        }
        .frame(height: 28)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .studioControlRegion()
            Toggle("Always on Top", isOn: Binding(
                get: { model.alwaysOnTop },
                set: { setAlwaysOnTop($0) }
            ))
            .font(.system(size: 12))
            .studioControlRegion()
            Button("Reset", action: resetPreferences)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .studioControlRegion()
        }
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

    private var graphite: Color {
        Color(red: 0.11, green: 0.11, blue: 0.12)
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
