#if os(macOS)
import SwiftUI

nonisolated enum IslandFullScreenScene: String, CaseIterable, Identifiable {
    case visualizer
    case lyrics

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .visualizer: "waveform"
        case .lyrics: "text.quote"
        }
    }
}

nonisolated enum LyricsPresentationState: Equatable {
    case idle
    case noTrack
    case nowPlayingUnavailable
    case metadataUnavailable
    case identifyingTrack
    case checkingLocal
    case searchingOnline
    case loading
    case onlineDisabled
    case local(LyricsDocument)
    case found(LyricsDocument)
    case ambiguous([LyricsDocument])
    case instrumental
    case notFound
    case offline
    case providerUnavailable
    case rateLimited(retryAfterSeconds: TimeInterval?)
    case networkError
    case parseError
    case importError(String)
    case cancelled
    case error(String)

    var document: LyricsDocument? {
        switch self {
        case .local(let document), .found(let document):
            return document
        case .ambiguous(let documents):
            return documents.count == 1 ? documents[0] : nil
        default:
            return nil
        }
    }
}

@MainActor
@Observable
final class IslandModel {
    var snapshot = AudioSnapshot.zero
    var prefs = IslandPreferences.standard
    var appearance = AppearancePreferences.standard
    var spectrum = SpectrumPreferences.standard
    var waveform = WaveformPreferences.standard
    var orbit = OrbitPreferences.standard
    var state: IslandPresentationState = .compact
    var geometry: IslandNotchGeometry?
    var availableScreens: [IslandScreenDescriptor] = []
    var unsupportedReason: IslandUnsupportedReason?
    var usedFallbackScreen = false
    var compactLevels = Array(repeating: Float(0), count: IslandPreferences.standard.compactBarCountPerSide)
    var expandedSpectrum: [Float] = []
    var expandedPeaks: [Float] = []
    var expandedWaveform = AudioSnapshot.zero.waveform
    var pointerInside = false
    var pointerDown = false
    /// Compact-only anticipation. The window frame stays on the compact geometry while this is true.
    var hoverArmed = false
    /// Drives Compact/Expanded chrome. Stays expanded through collapse frame animation so content doesn't pop early.
    var showsExpandedChrome = false
    var isFullScreen = false
    var fullScreenScene: IslandFullScreenScene = .visualizer
    /// Experimental Now Playing snapshot mirrored from `NowPlayingService` for Expanded UI.
    var nowPlaying = NowPlayingSnapshot.idle
    var lyricsState: LyricsPresentationState = .noTrack
    var lyricsPositionSeconds: TimeInterval = 0
    var activeLyricsLineIndex: Int?
    var activeLyricsLineChangedAtUptime: TimeInterval = 0
    var lyricsTrackRevision: UInt64 = 0

    var isSupported: Bool {
        geometry != nil && unsupportedReason == nil
    }

    var isPinned: Bool {
        state == .pinned
    }

    var statusSummary: String {
        if let geometry {
            if prefs.isEnabled == false {
                return String(localized: "Disabled on \(geometry.screenName)")
            }
            if usedFallbackScreen {
                return String(localized: "Active on \(geometry.screenName) (fallback notched display)")
            }
            return String(localized: "Active on \(geometry.screenName)")
        }
        if let unsupportedReason {
            return unsupportedReason.userMessage
        }
        return IslandUnsupportedReason.noNotch.userMessage
    }

    func captureLabel(phase: SpikePhase) -> String {
        switch phase {
        case .idle:
            return String(localized: "Not listening")
        case .starting:
            return String(localized: "Starting")
        case .failed:
            return String(localized: "Failed")
        case .running:
            return snapshot.isSilent ? String(localized: "No audio") : String(localized: "Listening")
        }
    }

    func drawsActiveVisuals(phase: SpikePhase) -> Bool {
        guard phase == .running else { return false }
        if snapshot.isSilent == false { return true }
        if state.isExpandedOrPinned {
            switch prefs.mode {
            case .spectrum:
                return SpectrumDynamics.isSettled(levels: expandedSpectrum, peaks: expandedPeaks) == false
            case .orbit:
                return SpectrumDynamics.isSettled(levels: expandedSpectrum) == false
            case .waveform:
                return SpectrumDynamics.isSettled(levels: expandedWaveform) == false
            }
        }
        return SpectrumDynamics.isSettled(levels: compactLevels) == false
    }
}

/// Top-flush, bottom-rounded silhouette that merges with the top screen edge and physical camera housing.
nonisolated enum IslandChrome {
    static let compactBottomRadius: CGFloat = 18
    static let expandedBottomRadius: CGFloat = 28
}

nonisolated struct IslandShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return Path()
        }
        let radius = min(max(bottomRadius.isFinite ? bottomRadius : 0, 0), rect.width / 2, rect.height / 2)
        return Path(
            roundedRect: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: radius,
                bottomTrailing: radius,
                topTrailing: 0
            ),
            style: .continuous
        )
    }
}

struct IslandCompactSpectrumCanvas: View {
    var levels: [Float]
    var geometry: IslandNotchGeometry?
    var barsPerSide: Int
    var drawsBars: Bool
    var color: Color
    var opacity: Double

    var body: some View {
        Canvas { context, size in
            guard let geometry else { return }
            let compactFrame = CGRect(
                x: geometry.compactFrame.minX,
                y: geometry.compactFrame.minY,
                width: size.width,
                height: size.height
            )
            let bars = IslandGeometry.compactBars(
                levels: levels,
                notchRect: geometry.notchRect,
                compactFrame: compactFrame,
                barsPerSide: barsPerSide,
                amplitude: 1,
                drawsActiveBars: drawsBars
            )
            let shading = GraphicsContext.Shading.color(color.opacity(drawsBars ? opacity : opacity * 0.45))
            for rect in bars.left + bars.right {
                let radius = min(rect.width / 2, rect.height / 2)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: shading)
            }
        }
        .accessibilityLabel(drawsBars ? String(localized: "Notch Island compact spectrum") : String(localized: "Notch Island compact baseline"))
    }
}

struct IslandContentView: View {
    @Bindable var spike: ProcessTapSpike
    @Bindable var model: IslandModel
    var selectMode: (StudioVisualMode) -> Void
    var togglePin: () -> Void
    var expand: () -> Void
    var collapse: () -> Void
    var toggleFullScreen: () -> Void
    var openStudio: () -> Void
    var openSettings: () -> Void
    var toggleNowPlaying: () -> Void = {}
    var previousTrack: () -> Void = {}
    var nextTrack: () -> Void = {}
    var seekNowPlaying: (Double) -> Void = { _ in }
    var selectFullScreenScene: (IslandFullScreenScene) -> Void = { _ in }
    var importLyrics: () -> Void = {}
    var chooseLyricsCandidate: (UUID) -> Void = { _ in }
    var deleteLyrics: (UUID) -> Void = { _ in }
    var retryLyrics: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.isFullScreen {
                fullScreenBody
            } else if model.showsExpandedChrome {
                expandedBody
            } else {
                compactBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(warmWhite)
        .preferredColorScheme(.dark)
    }

    private var compactBody: some View {
        let shape = IslandShape(bottomRadius: IslandChrome.compactBottomRadius)
        let armedScale = IslandMotion.prefeedbackScale(
            hoverArmed: model.hoverArmed,
            reduceMotion: reduceMotion,
            followsReduceMotion: model.prefs.followsReduceMotion
        )
        return ZStack {
            shape.fill(Color.black)
            shape.stroke(Color.white.opacity(model.hoverArmed ? 0.16 : 0.08), lineWidth: 0.5)
            IslandCompactSpectrumCanvas(
                levels: model.compactLevels,
                geometry: model.geometry,
                barsPerSide: model.prefs.compactBarCountPerSide,
                drawsBars: drawsBars,
                color: model.appearance.color.swiftUI,
                opacity: model.appearance.opacity
            )
            .scaleEffect(armedScale)
            .allowsHitTesting(false)
        }
        .clipShape(shape)
        .animation(prefeedbackAnimation, value: model.hoverArmed)
        .contentShape(shape)
        .onTapGesture {
            expand()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notch Island, \(model.captureLabel(phase: spike.phase))")
        .accessibilityAddTraits(.isButton)
    }

    private var expandedBody: some View {
        let geometry = model.geometry
        let notchWidth = geometry?.notchRect.width ?? 184
        let notchHeight = max(geometry?.notchRect.height ?? 32, 28)
        let windowFrame = geometry.map { $0.expandedPlayerFrame() }
        let sideClearance = windowFrame.flatMap { frame in
            geometry?.expandedSideClearance(in: frame)
        }
        let leftWing = max(sideClearance?.left ?? 120, 120) - 16
        let rightWing = max(sideClearance?.right ?? 120, 120) - 16

        let shape = IslandShape(bottomRadius: IslandChrome.expandedBottomRadius)
        return ZStack {
            shape.fill(Color.black)
            shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5)

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    modeIconRow
                        .frame(width: max(leftWing, 1), alignment: .leading)
                        .padding(.leading, 12)
                    Spacer(minLength: 0)
                        .frame(width: notchWidth)
                    actionButtons
                        .frame(width: max(rightWing, 1), alignment: .trailing)
                        .padding(.trailing, 14)
                }
                .frame(height: notchHeight)

                ZStack {
                    if model.prefs.nowPlayingLayout.showVisualization {
                        if model.prefs.nowPlayingEnabled {
                            nowPlayingBackdrop
                                .allowsHitTesting(false)
                        } else {
                            softEdgedVisualization(
                                expandedVisualization
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                        }
                    }

                    if model.prefs.nowPlayingEnabled {
                        IslandExpandedNowPlayingView(
                            snapshot: model.nowPlaying,
                            layout: model.prefs.nowPlayingLayout,
                            onTogglePlay: toggleNowPlaying,
                            onPrevious: previousTrack,
                            onNext: nextTrack,
                            onSeek: seekNowPlaying
                        )
                        .padding(.horizontal, 18)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(shape)
    }

    private var fullScreenBody: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.white.opacity(0.08), Color.black],
                center: .center,
                startRadius: 0,
                endRadius: 720
            )
            VStack(spacing: 0) {
                HStack {
                    fullScreenScenePicker
                    modeIconRow
                    Spacer()
                    IslandIconButton(
                        symbol: "arrow.down.right.and.arrow.up.left",
                        label: String(localized: "Exit full screen"),
                        selected: false,
                        action: toggleFullScreen
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                Group {
                    if model.fullScreenScene == .visualizer {
                        expandedVisualization(opacityOverride: nil, orbitBoost: false)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                    } else {
                        IslandFullscreenLyricsView(
                            model: model,
                            importLyrics: importLyrics,
                            chooseCandidate: chooseLyricsCandidate,
                            deleteLyrics: deleteLyrics,
                            retryLyrics: retryLyrics
                        )
                        .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, model.fullScreenScene == .visualizer ? 72 : 48)
                .padding(.vertical, 32)
                .animation(fullScreenSceneAnimation, value: model.fullScreenScene)

                HStack(alignment: .center, spacing: 18) {
                    if model.fullScreenScene == .visualizer {
                        fullScreenNowPlayingMetadata
                    }
                    Spacer()
                    fullScreenPlaybackButton
                }
                .padding(.horizontal, 36)
                .frame(minHeight: 64)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var fullScreenScenePicker: some View {
        HStack(spacing: 2) {
            ForEach(IslandFullScreenScene.allCases) { scene in
                IslandIconButton(
                    symbol: scene.symbol,
                    label: scene == .visualizer
                        ? String(localized: "Visualizer")
                        : String(localized: "Lyrics"),
                    selected: model.fullScreenScene == scene,
                    action: { selectFullScreenScene(scene) }
                )
            }
        }
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private var fullScreenNowPlayingMetadata: some View {
        if model.prefs.nowPlayingEnabled, model.prefs.nowPlayingLayout.showsFullScreenMetadata {
            switch model.nowPlaying.availability {
            case .unavailable:
                fullScreenNowPlayingStatus(String(localized: "Now Playing unavailable"))
            case .empty, .idle:
                fullScreenNowPlayingStatus(String(localized: "Nothing playing"))
            case .listening:
                if model.nowPlaying.hasTrack {
                    HStack(alignment: .center, spacing: 12) {
                        if model.prefs.nowPlayingLayout.showArtwork {
                            fullScreenArtwork
                        }
                        if model.prefs.nowPlayingLayout.showTitleArtist {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.nowPlaying.title.isEmpty ? String(localized: "Unknown Title") : model.nowPlaying.title)
                                    .font(.system(size: 17, weight: .medium, design: .rounded))
                                    .foregroundStyle(warmWhite)
                                    .lineLimit(1)
                                Text(model.nowPlaying.artist.isEmpty ? String(localized: "Unknown Artist") : model.nowPlaying.artist)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(warmWhite.opacity(0.65))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: 280, alignment: .leading)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    fullScreenNowPlayingStatus(String(localized: "Nothing playing"))
                }
            }
        }
    }

    private var fullScreenArtwork: some View {
        ZStack {
            if let artwork = model.nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(warmWhite.opacity(0.72))
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
        .accessibilityHidden(true)
    }

    private func fullScreenNowPlayingStatus(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(warmWhite.opacity(0.72))
            .accessibilityAddTraits(.isStaticText)
    }

    private var fullScreenPlaybackButton: some View {
        Button(action: toggleNowPlaying) {
            Image(systemName: model.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(warmWhite.opacity(canToggleFullScreenPlayback ? 0.9 : 0.4))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(canToggleFullScreenPlayback == false)
        .help(fullScreenPlaybackHelp)
        .accessibilityLabel(model.nowPlaying.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
    }

    private var canToggleFullScreenPlayback: Bool {
        (model.prefs.nowPlayingEnabled || model.fullScreenScene == .lyrics)
            && model.nowPlaying.availability == .listening
            && model.nowPlaying.hasTrack
    }

    private var fullScreenPlaybackHelp: String {
        guard model.prefs.nowPlayingEnabled || model.fullScreenScene == .lyrics else {
            return String(localized: "Enable Now Playing in Notch Island settings to control playback.")
        }
        switch model.nowPlaying.availability {
        case .unavailable:
            return String(localized: "Now Playing unavailable")
        case .empty, .idle:
            return String(localized: "Nothing playing")
        case .listening:
            return model.nowPlaying.hasTrack
                ? (model.nowPlaying.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                : String(localized: "Nothing playing")
        }
    }

    /// Icon-only Spectrum / Waveform / Orbit switcher in the left wing (replaces status text).
    private var modeIconRow: some View {
        HStack(spacing: 2) {
            ForEach(StudioVisualMode.allCases) { mode in
                IslandIconButton(
                    symbol: mode.symbol,
                    label: mode.title,
                    selected: model.prefs.mode == mode,
                    action: { selectMode(mode) }
                )
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            IslandIconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                label: model.isPinned ? String(localized: "Unpin Notch Island") : String(localized: "Pin Notch Island"),
                selected: model.isPinned,
                action: togglePin
            )
            IslandIconButton(
                symbol: "macwindow",
                label: String(localized: "Open Studio"),
                selected: false,
                action: openStudio
            )
            IslandIconButton(
                symbol: "gearshape",
                label: String(localized: "Notch Island Settings"),
                selected: false,
                action: openSettings
            )
            IslandIconButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                label: String(localized: "Enter full screen"),
                selected: false,
                action: toggleFullScreen
            )
            IslandIconButton(
                symbol: "chevron.up",
                label: String(localized: "Collapse Notch Island"),
                selected: false,
                action: collapse
            )
        }
    }

    /// Fade viz alpha at the perimeter so bars don't hard-clip against the Island edge.
    private func softEdgedVisualization<Content: View>(_ content: Content) -> some View {
        content
            .mask {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .inset(by: 7)
                    .fill(Color.white)
                    .blur(radius: reduceMotion ? 0 : 10)
            }
            .overlay {
                // Extra press: soft black falloff around the rim.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.55),
                                Color.black.opacity(0.12),
                                Color.black.opacity(0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 14
                    )
                    .blur(radius: reduceMotion ? 0 : 6)
                    .opacity(0.85)
            }
    }

    /// Dimmer backdrop with soft perimeter fade + gentle bottom press.
    private var nowPlayingBackdrop: some View {
        ZStack {
            softEdgedVisualization(
                nowPlayingAmbientVisualization
                    .opacity(0.48)
            )

            if reduceMotion == false {
                softEdgedVisualization(
                    nowPlayingAmbientVisualization
                        .opacity(0.35)
                        .blur(radius: 4)
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.5),
                            .init(color: .black.opacity(0.45), location: 0.8),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.4), location: 0),
                    .init(color: Color.black.opacity(0.18), location: 0.4),
                    .init(color: Color.black.opacity(0.22), location: 0.7),
                    .init(color: Color.black.opacity(0.55), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Full-bleed Now Playing backdrop (edge soft-mask applied by the caller).
    @ViewBuilder
    private var nowPlayingAmbientVisualization: some View {
        let strength = min(max(model.appearance.opacity * 0.85, 0.45), 0.7)
        Group {
            switch model.prefs.mode {
            case .orbit:
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height) * 0.88
                    expandedVisualization(opacityOverride: strength, orbitBoost: true)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .spectrum, .waveform:
                expandedVisualization(opacityOverride: strength, orbitBoost: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var expandedVisualization: some View {
        expandedVisualization(opacityOverride: nil, orbitBoost: false)
    }

    @ViewBuilder
    private func expandedVisualization(opacityOverride: Double?, orbitBoost: Bool) -> some View {
        let fill = model.appearance.color.swiftUI
        let stroke = model.appearance.strokeColor.swiftUI
        let opacity = opacityOverride ?? model.appearance.opacity
        switch model.prefs.mode {
        case .spectrum:
            SpectrumCanvas(
                spectrum: model.expandedSpectrum,
                peaks: model.expandedPeaks,
                drawsBars: drawsBars,
                color: fill,
                baseColor: model.appearance.color,
                strokeColor: stroke,
                opacity: opacity,
                amplitude: model.spectrum.amplitude,
                lineWidth: model.appearance.lineWidth,
                cornerRadius: model.spectrum.cornerRadius,
                barGap: model.spectrum.barGap,
                drawsStroke: model.spectrum.stroke,
                colorMode: model.spectrum.colorMode,
                peakHold: model.spectrum.peakHold
            )
        case .waveform:
            WaveformCanvas(
                samples: model.expandedWaveform,
                color: (model.waveform.customColor ?? model.appearance.color).swiftUI,
                opacity: opacity,
                amplitude: model.waveform.amplitude,
                verticalRange: model.waveform.verticalRange,
                lineWidth: max(model.waveform.lineWidth, opacityOverride == nil ? model.waveform.lineWidth : 1.8),
                smoothing: model.waveform.smoothing,
                density: model.waveform.density,
                style: model.waveform.style,
                fillStrength: model.waveform.fillStrength
            )
        case .orbit:
            OrbitCanvas(
                spectrum: model.expandedSpectrum,
                drawsLevels: drawsBars,
                barCount: model.orbit.barCount,
                mirrored: model.orbit.mirrored,
                color: (model.orbit.customColor ?? model.appearance.color).swiftUI,
                strokeColor: stroke,
                drawsStroke: model.orbit.stroke || orbitBoost,
                opacity: opacity,
                amplitude: orbitBoost ? max(model.orbit.amplitude, 1.05) : model.orbit.amplitude,
                lineWidth: orbitBoost ? max(model.orbit.lineWidth, 2) : model.orbit.lineWidth,
                innerRatio: orbitBoost ? min(model.orbit.inner, 0.48) : model.orbit.inner,
                outerScale: orbitBoost ? max(model.orbit.outerScale, 0.96) : model.orbit.outerScale,
                gapDegrees: model.orbit.gapDegrees,
                layerMode: model.orbit.layerMode,
                pulseStrength: model.orbit.pulseStrength
            )
        }
    }

    private var prefeedbackAnimation: Animation? {
        let duration = IslandMotion.prefeedbackSeconds(
            expandDelay: model.prefs.expandDelaySeconds,
            reduceMotion: reduceMotion,
            followsReduceMotion: model.prefs.followsReduceMotion
        )
        guard duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    private var fullScreenSceneAnimation: Animation? {
        guard reduceMotion == false || model.prefs.followsReduceMotion == false else { return nil }
        return .easeInOut(duration: IslandMotion.lyricsSceneSeconds)
    }

    private var drawsBars: Bool {
        model.drawsActiveVisuals(phase: spike.phase)
    }

    private var warmWhite: Color {
        Color(red: 0.96, green: 0.94, blue: 0.90)
    }
}

private struct IslandIconButton: View {
    var symbol: String
    var label: String
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 20, height: 20)
                .background {
                    if hovering || selected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.22 : 0.14))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#endif
