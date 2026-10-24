import SwiftUI
#if os(macOS)
import AppKit
#else
import Playgrounds
#endif

#if os(macOS)
struct ContentView: View {
    @Bindable var spike: ProcessTapSpike

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AUD-01 spike")
                .font(.title2.bold())
            Text("System output Process Tap. This panel only shows capture counters.")
                .foregroundStyle(.secondary)
            Text("Debug macOS App Sandbox is off for this local spike. That setting is temporary and does not change Release or other platforms.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("tapautostart stays on. With it off, the output device still clocks IO, but the tap buffers stayed at zero while audio played.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Start") {
                    Task { await spike.start() }
                }
                .disabled(spike.phase == .starting || spike.phase == .running)
                Button("Stop") {
                    spike.stop()
                }
                .disabled(spike.phase == .idle)
                Toggle("tapautostart", isOn: $spike.tapAutoStart)
                    .disabled(spike.phase == .starting || spike.phase == .running)
            }

            LabeledContent("State", value: spike.displayState)
            LabeledContent("Applied tapautostart", value: spike.appliedTapAutoStart ? "1" : "0")
            LabeledContent("Frames", value: String(spike.reading.frames))
            LabeledContent("RMS", value: rmsText)
            LabeledContent("Finite samples", value: String(spike.reading.finiteSamples))
            LabeledContent("Non-finite samples", value: String(spike.reading.nonFiniteSamples))
            LabeledContent("Buffer count", value: String(spike.reading.bufferCount))
            LabeledContent("Format mismatch", value: spike.reading.formatMismatch ? "yes" : "no")
            LabeledContent("Stream format", value: spike.formatText)
            LabeledContent("DeviceIsAlive", value: spike.aliveText)
            LabeledContent("Last OSStatus", value: spike.statusText)
            LabeledContent("Output UID at start", value: spike.outputUIDAtStart)
            LabeledContent("Output UID after start", value: spike.outputUIDAfterStart)
            LabeledContent("Output UID after stop", value: spike.outputUIDAfterStop)
            if spike.failureText.isEmpty == false {
                Text(spike.failureText)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if spike.cleanupText.isEmpty == false {
                Text(spike.cleanupText)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
        .task {
            while Task.isCancelled == false {
                spike.refreshReading()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private var rmsText: String {
        guard let rms = spike.reading.rms else { return "none" }
        return String(format: "%.8f", rms)
    }
}

#Preview {
    ContentView(spike: ProcessTapSpike())
}
#else
struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
#endif
