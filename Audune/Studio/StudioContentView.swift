#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class StudioModel {
    var snapshot = AudioSnapshot.zero
    var alwaysOnTop = true
    var mode: StudioVisualMode = .spectrum
}

enum StudioVisualMode: String, CaseIterable, Identifiable {
    case spectrum
    case waveform
    case orbit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrum: return "Spectrum"
        case .waveform: return "Waveform"
        case .orbit: return "Orbit"
        }
    }
}

struct StudioContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: StudioModel
    var setAlwaysOnTop: (Bool) -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Studio")
                    .font(.headline)
                Spacer()
                Button("Close", action: close)
            }
            Text(title)
                .font(.title3)
            if spike.phase == .failed {
                Text(spike.failureText.isEmpty ? "Audio capture failed." : spike.failureText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Text(spike.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Start") {
                    Task { await spike.start() }
                }
                .disabled(startDisabled)
                Button("Stop") {
                    spike.stop()
                }
                .disabled(stopDisabled)
            }
            Toggle("Always on Top", isOn: Binding(
                get: { model.alwaysOnTop },
                set: { setAlwaysOnTop($0) }
            ))
            Picker("Mode", selection: $model.mode) {
                ForEach(StudioVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                switch model.mode {
                case .spectrum:
                    SpectrumCanvas(spectrum: model.snapshot.spectrum, drawsBars: drawsBars)
                case .waveform:
                    WaveformCanvas(samples: model.snapshot.waveform)
                case .orbit:
                    OrbitCanvas(spectrum: model.snapshot.spectrum, drawsLevels: drawsBars)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 24.0 / 255.0, green: 26.0 / 255.0, blue: 30.0 / 255.0))
        .foregroundStyle(Color(red: 0.96, green: 0.94, blue: 0.90))
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
