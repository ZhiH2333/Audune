#if DEBUG && os(macOS)
import AppKit
import SwiftUI

/// Developer-only capture counters. This file is not compiled into Release builds.
struct DebugCaptureView: View {
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
    DebugCaptureView(spike: ProcessTapSpike())
}

/// Hosts `DebugCaptureView` in a plain window so it does not depend on a SwiftUI scene.
@MainActor
final class DebugWindowController {
    private let window: NSWindow

    init(spike: ProcessTapSpike) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Audune Debug"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 420)
        window.contentView = NSHostingView(rootView: DebugCaptureView(spike: spike))
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func shutdown() {
        window.orderOut(nil)
    }
}
#endif
