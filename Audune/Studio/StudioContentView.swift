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
    var setBarCount: (Int) -> Void
    var setChromeVisible: (Bool) -> Void
    var hitMap: StudioHitMap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAppearance = false
    @State private var gripHovering = false
    @State private var exitedAt: TimeInterval?
    @State private var now = Date().timeIntervalSinceReferenceDate
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            visualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            chrome
                .fixedSize()
                .padding(8)
                .opacity(showsChrome ? 1 : 0)
                .allowsHitTesting(showsChrome)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(warmWhite)
        .preferredColorScheme(.dark)
        .coordinateSpace(name: StudioCoordinateSpace.name)
        .animation(chromeAnimation, value: showsChrome)
        .onPreferenceChange(StudioControlFramesKey.self) { frames in
            hitMap.controlFramesTopLeft = showsChrome ? frames : []
        }
        .onPreferenceChange(StudioGripFramesKey.self) { frames in
            hitMap.gripFramesTopLeft = showsChrome ? frames : []
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
        .onChange(of: showsChrome) { _, visible in
            if visible == false {
                hitMap.controlFramesTopLeft = []
                hitMap.gripFramesTopLeft = []
            }
            setChromeVisible(visible)
        }
        .onAppear {
            if model.pointerInside == false, showsAppearance == false {
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
                    .frame(width: 220, alignment: .leading)
                    .studioControlRegion()
            }
            if showsAppearance {
                appearance
            }
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 6) {
            grip
            Picker("Mode", selection: $model.mode) {
                ForEach(StudioVisualMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Mode")
            .studioControlRegion()
            StudioTextButton(title: showsAppearance ? "Done" : "Settings") {
                showsAppearance.toggle()
            }
            StudioTextButton(
                title: model.alwaysOnTop ? "On Top" : "Pin",
                highlighted: model.alwaysOnTop,
                accessibilityLabel: "Always on Top",
                accessibilityValue: model.alwaysOnTop ? "On" : "Off"
            ) {
                setAlwaysOnTop(!model.alwaysOnTop)
            }
            StudioTextButton(title: "Hide", action: close)
        }
        .frame(height: StudioChrome.barHeight)
    }

    private var grip: some View {
        ZStack {
            StudioDragSurface(hitMap: hitMap)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(warmWhite.opacity(0.8))
                .allowsHitTesting(false)
        }
        .frame(width: StudioChrome.gripWidth, height: StudioChrome.gripHeight)
        .background {
            if gripHovering {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            }
        }
        .onHover { gripHovering = $0 }
        .accessibilityLabel("Drag Studio")
        .studioGripRegion()
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StudioTextButton(title: "Start", disabled: startDisabled) {
                    Task { await spike.start() }
                }
                StudioTextButton(title: "Stop", disabled: stopDisabled) {
                    spike.stop()
                }
            }
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
            .accessibilityLabel("Opacity")
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
            StudioTextButton(title: "Reset", action: resetPreferences)
        }
        .frame(width: 220, alignment: .leading)
    }

    @ViewBuilder
    private var visualization: some View {
        switch model.mode {
        case .spectrum:
            SpectrumCanvas(spectrum: model.studioSpectrum, drawsBars: drawsBars, color: accentColor, opacity: model.backgroundOpacity)
        case .waveform:
            WaveformCanvas(samples: model.snapshot.waveform, color: accentColor, opacity: model.backgroundOpacity)
        case .orbit:
            OrbitCanvas(spectrum: model.studioSpectrum, drawsLevels: drawsBars, color: accentColor, opacity: model.backgroundOpacity)
        }
    }

    private var showsChrome: Bool {
        StudioChrome.isVisible(
            pointerInside: model.pointerInside,
            pointerDown: model.pointerDown,
            holdsChrome: showsAppearance,
            now: now,
            exitedAt: exitedAt
        )
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

private struct StudioTextButton: View {
    var title: String
    var disabled: Bool = false
    var highlighted: Bool = false
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if hovering || focused || highlighted {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .focusable()
        .focused($focused)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? "")
        .studioControlRegion()
    }
}
#endif
