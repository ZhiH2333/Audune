#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class StudioModel {
    var snapshot = AudioSnapshot.zero
    var prefs = StudioPreferences.standard
    var studioSpectrum = Array(repeating: Float(0), count: StudioPreferences.standard.spectrum.barCount)
    var spectrumPeaks: [Float] = []
    var displayWaveform = AudioSnapshot.zero.waveform
    var echoWaveform = AudioSnapshot.zero.waveform
    var settingsCategory: SettingsCategory = .appearance
    var pointerInside = false
    var pointerDown = false
    var menuTracking = false
    var chromeVisible = false
    var isShown = false
    /// Live Studio window content size in points. Used only by the Layout preview.
    var windowSize = StudioFrame.defaultSize
}

struct StudioContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: StudioModel
    var savePreferences: () -> Void
    var openSettings: () -> Void
    var hitMap: StudioHitMap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gripHovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            visualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            chrome
                .fixedSize()
                .padding(8)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(warmWhite)
        .preferredColorScheme(.dark)
        .coordinateSpace(name: StudioCoordinateSpace.name)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.windowSize = $0 }
        .animation(chromeAnimation, value: model.chromeVisible)
        .onPreferenceChange(StudioControlFramesKey.self) { frames in
            hitMap.controlFramesTopLeft = frames
        }
        .onPreferenceChange(StudioGripFramesKey.self) { frames in
            hitMap.gripFramesTopLeft = frames
        }
        .onChange(of: model.chromeVisible) { _, visible in
            hitMap.chromeVisible = visible
        }
        .onAppear {
            hitMap.chromeVisible = model.chromeVisible
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
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 4) {
            grip
            ForEach(StudioVisualMode.allCases) { mode in
                StudioControlButton(
                    title: mode.title,
                    symbol: mode.symbol,
                    selected: model.prefs.mode == mode
                ) {
                    model.prefs.mode = mode
                    savePreferences()
                }
            }
            StudioControlButton(title: String(localized: "Settings"), symbol: "gearshape", action: openSettings)
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

    /// The visualization sits in its own frame inside the window; the window size only sets the area around it.
    private var visualization: some View {
        GeometryReader { proxy in
            let frame = VisualLayout.frame(in: proxy.size, layout: model.prefs.layout)
            StudioVisualizationView(
                prefs: model.prefs,
                spectrum: model.studioSpectrum,
                peaks: model.spectrumPeaks,
                waveform: model.displayWaveform,
                echoWaveform: model.echoWaveform,
                drawsBars: drawsBars
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    private var chromeAnimation: Animation? {
        let duration = StudioChromeMotion.fadeSeconds(
            hiding: model.chromeVisible == false,
            reduceMotion: reduceMotion,
            animates: model.prefs.window.animatesChrome,
            followsReduceMotion: model.prefs.window.followsReduceMotion
        )
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    private var warmWhite: Color {
        Color(red: 0.96, green: 0.94, blue: 0.90)
    }

    private var failureLine: String {
        #if DEBUG
        return "\(spike.userFailureSummary) \(spike.statusText)"
        #else
        return spike.userFailureSummary
        #endif
    }

    private var drawsBars: Bool {
        guard spike.phase == .running else { return false }
        if model.snapshot.isSilent == false { return true }
        switch model.prefs.mode {
        case .spectrum:
            return SpectrumDynamics.isSettled(levels: model.studioSpectrum, peaks: model.spectrumPeaks) == false
        case .orbit:
            return SpectrumDynamics.isSettled(levels: model.studioSpectrum) == false
        case .waveform:
            return SpectrumDynamics.isSettled(levels: model.displayWaveform, peaks: model.echoWaveform) == false
        }
    }
}

struct StudioControlButton: View {
    var title: String
    var symbol: String
    var selected: Bool = false
    var disabled: Bool = false
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if hovering || selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.22 : 0.16))
                }
            }
        }
        .buttonStyle(StudioPlainButtonStyle(showsFill: selected))
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .studioControlRegion()
    }
}

private struct StudioPlainButtonStyle: ButtonStyle {
    var showsFill: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if showsFill == false && configuration.isPressed {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                }
            }
    }
}
#endif
