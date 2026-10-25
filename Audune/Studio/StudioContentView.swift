#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class StudioModel {
    var snapshot = AudioSnapshot.zero
    var studioSpectrum = Array(repeating: Float(0), count: StudioPreferences.standard.barCount)
    var alwaysOnTop = StudioPreferences.standard.alwaysOnTop
    var mode: StudioVisualMode = .spectrum
    var backgroundOpacity = StudioPreferences.standard.backgroundOpacity
    var accent: StudioAccent = .warm
    var cleanCanvas = StudioPreferences.standard.cleanCanvas
    var barCount = StudioPreferences.standard.barCount
    var pointerInside = false
    var pointerDown = false
}

struct StudioContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: StudioModel
    var setAlwaysOnTop: (Bool) -> Void
    var savePreferences: () -> Void
    var resetPreferences: () -> Void
    var close: () -> Void
    var setCleanCanvas: (Bool) -> Void
    var setBarCount: (Int) -> Void
    var setChromeVisible: (Bool) -> Void
    var hitMap: StudioHitMap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAppearance = false
    @State private var exitedAt: TimeInterval?
    @State private var now = Date().timeIntervalSinceReferenceDate
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            visualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            StudioDragSurface(hitMap: hitMap)
            chrome
                .padding(8)
                .opacity(showsChrome ? 1 : 0)
                .allowsHitTesting(showsChrome)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(graphite.opacity(panelOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(warmWhite.opacity(showsChrome ? 0.12 : 0), lineWidth: 1)
                }
        }
        .foregroundStyle(warmWhite)
        .preferredColorScheme(.dark)
        .coordinateSpace(name: StudioCoordinateSpace.name)
        .animation(chromeAnimation, value: showsChrome)
        .onPreferenceChange(StudioControlFramesKey.self) { frames in
            hitMap.controlFramesTopLeft = showsChrome ? frames : []
        }
        .onChange(of: model.mode) { _, _ in savePreferences() }
        .onChange(of: model.accent) { _, _ in savePreferences() }
        .onChange(of: model.backgroundOpacity) { _, _ in savePreferences() }
        .onChange(of: model.pointerInside) { _, inside in
            if inside {
                cancelHide()
            } else if model.pointerDown == false, showsAppearance == false {
                beginHideCountdown()
            }
        }
        .onChange(of: model.pointerDown) { _, down in
            if down {
                hideTask?.cancel()
            } else if model.pointerInside == false, showsAppearance == false {
                beginHideCountdown()
            }
        }
        .onChange(of: showsAppearance) { _, open in
            if open {
                hideTask?.cancel()
            } else if model.pointerInside == false, model.pointerDown == false {
                beginHideCountdown()
            }
        }
        .onChange(of: model.cleanCanvas) { _, enabled in
            if enabled == false {
                cancelHide()
            } else if model.pointerInside == false, model.pointerDown == false, showsAppearance == false {
                beginHideCountdown()
            }
        }
        .onChange(of: showsChrome) { _, visible in
            if visible == false {
                hitMap.controlFramesTopLeft = []
            }
            setChromeVisible(visible)
        }
        .onAppear {
            if model.cleanCanvas, model.pointerInside == false, showsAppearance == false {
                beginHideCountdown()
            }
            setChromeVisible(showsChrome)
        }
    }

    private var chrome: some View {
        VStack(spacing: 8) {
            if spike.phase == .failed {
                Text(failureLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.93, green: 0.55, blue: 0.48))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studioControlRegion()
            }
            if showsAppearance {
                appearance
            }
            bar
        }
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
        .frame(height: StudioChrome.barHeight)
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
            if showsBarCount {
                HStack(spacing: 8) {
                    Text("Bars")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(warmWhite.opacity(0.72))
                    Text("\(model.barCount)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .frame(width: 24, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(barIndex) },
                            set: { raw in
                                let index = min(max(Int(raw.rounded()), 0), StudioPreferences.barCounts.count - 1)
                                setBarCount(StudioPreferences.barCounts[index])
                            }
                        ),
                        in: 0...Double(StudioPreferences.barCounts.count - 1),
                        step: 1
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bar count")
                .studioControlRegion()
            }
            Toggle("Always on Top", isOn: Binding(
                get: { model.alwaysOnTop },
                set: { setAlwaysOnTop($0) }
            ))
            .font(.system(size: 12))
            .studioControlRegion()
            Toggle("Clean Canvas", isOn: Binding(
                get: { model.cleanCanvas },
                set: { setCleanCanvas($0) }
            ))
            .font(.system(size: 12))
            .studioControlRegion()
            Button("Reset", action: resetPreferences)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .studioControlRegion()
        }
        .padding(8)
        .background(graphite.opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var visualization: some View {
        switch model.mode {
        case .spectrum:
            SpectrumCanvas(spectrum: model.studioSpectrum, drawsBars: drawsBars, color: accentColor)
        case .waveform:
            WaveformCanvas(samples: model.snapshot.waveform, color: accentColor)
        case .orbit:
            OrbitCanvas(spectrum: model.studioSpectrum, drawsLevels: drawsBars, color: accentColor)
        }
    }

    private var showsChrome: Bool {
        StudioChrome.isVisible(
            cleanCanvas: model.cleanCanvas,
            pointerInside: model.pointerInside,
            pointerDown: model.pointerDown,
            holdsChrome: showsAppearance,
            now: now,
            exitedAt: exitedAt
        )
    }

    private var panelOpacity: Double {
        model.cleanCanvas && showsChrome == false ? 0 : model.backgroundOpacity
    }

    private var chromeAnimation: Animation? {
        let duration = StudioChromeMotion.fadeSeconds(hiding: showsChrome == false, reduceMotion: reduceMotion)
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    private var showsBarCount: Bool {
        model.mode == .spectrum || model.mode == .orbit
    }

    private var barIndex: Int {
        StudioPreferences.barCounts.firstIndex(of: model.barCount) ?? 2
    }

    private func beginHideCountdown() {
        guard model.cleanCanvas else { return }
        hideTask?.cancel()
        let exit = Date().timeIntervalSinceReferenceDate
        exitedAt = exit
        now = exit
        let delay = StudioChromeMotion.hideDelaySeconds
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard Task.isCancelled == false else { return }
            now = exit + delay
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
        exitedAt = nil
        now = Date().timeIntervalSinceReferenceDate
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
