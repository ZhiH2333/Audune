#if os(macOS)
import AppKit
import SwiftUI

/// 1:1 Apple Music Fullscreen Now Playing experience with fluid ambient background,
/// responsive artwork bounce, precise scrubber, transport controls, and rich synced lyrics.
struct FullscreenContentView: View {
    @Bindable var model: FullscreenModel
    @Bindable var spike: ProcessTapSpike
    var togglePlayPause: () -> Void
    var previousTrack: () -> Void
    var nextTrack: () -> Void
    var seek: (Double) -> Void
    var close: () -> Void
    var openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette = FullscreenPalette.defaultAppleMusic
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isShuffle = false
    @State private var isRepeat = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 1. Dynamic Fluid Ambient Aurora / Liquid Background
                AppleMusicFluidBackground(
                    palette: palette,
                    artwork: model.nowPlaying.artwork,
                    reduceMotion: reduceMotion
                )

                // 2. Shared Low-Opacity Visualizer (MVP AudioSnapshot integration)
                StudioVisualizationView(
                    prefs: studioPrefsForViz,
                    spectrum: vizSpectrum,
                    peaks: [],
                    waveform: model.snapshot.waveform,
                    drawsBars: model.snapshot.isSilent == false
                )
                .opacity(0.10)
                .allowsHitTesting(false)
                .blendMode(.screen)

                // 3. Apple Music Top Pill Grabber (Centered at top)
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 40, height: 4.5)
                        .padding(.top, 16)
                    Spacer()
                }
                .allowsHitTesting(false)

                // 4. Two-Column Layout (Left: Player / Artwork & Controls, Right: Apple Music Lyrics)
                let horizontalPadding = max(44, geometry.size.width * 0.055)
                let spacing = max(44, geometry.size.width * 0.05)

                HStack(alignment: .center, spacing: spacing) {
                    // Left Column: Player Pane
                    AppleMusicPlayerPane(
                        snapshot: model.nowPlaying,
                        containerSize: geometry.size,
                        isShuffle: $isShuffle,
                        isRepeat: $isRepeat,
                        togglePlayPause: togglePlayPause,
                        previousTrack: previousTrack,
                        nextTrack: nextTrack,
                        seek: seek
                    )
                    .frame(maxWidth: min(geometry.size.width * 0.42, 480))

                    // Right Column: Apple Music Synced Lyrics
                    AppleMusicLyricsPane(
                        model: model,
                        onSeek: seek,
                        openSettings: openSettings
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 40)
                .padding(.bottom, 36)

                // 5. Floating Controls Overlay (Top Right: Settings & Close - Auto-hiding)
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: openSettings) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Fullscreen Settings"))

                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Close Fullscreen"))
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 28)
                }
                .opacity(controlsVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.3), value: controlsVisible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .focusable()
        .onExitCommand(perform: close)
        .onContinuousHover { _ in
            revealControlsBriefly()
        }
        .task(id: model.nowPlaying.trackIdentity) {
            updatePalette()
        }
        .onAppear {
            updatePalette()
            revealControlsBriefly()
        }
    }

    private func updatePalette() {
        let newPalette = FullscreenPalette.extract(from: model.nowPlaying.artwork)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.75)) {
            palette = newPalette
        }
    }

    private func revealControlsBriefly() {
        controlsVisible = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard Task.isCancelled == false else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                controlsVisible = false
            }
        }
    }

    private var studioPrefsForViz: StudioPreferences {
        var prefs = StudioPreferences.standard
        prefs.mode = model.mode
        prefs.appearance = model.appearance
        prefs.appearance.opacity = min(prefs.appearance.opacity, 0.35)
        prefs.spectrum = model.spectrum
        prefs.spectrum.amplitude = min(prefs.spectrum.amplitude, 0.24)
        prefs.waveform = model.waveform
        prefs.waveform.amplitude = min(prefs.waveform.amplitude, 0.14)
        prefs.waveform.verticalRange = min(prefs.waveform.verticalRange, 0.35)
        prefs.waveform.fillStrength = 0
        prefs.orbit = model.orbit
        prefs.orbit.amplitude = min(prefs.orbit.amplitude, 0.20)
        prefs.orbit.outerScale = min(prefs.orbit.outerScale, 0.72)
        prefs.orbit.pulseStrength = 0
        return prefs
    }

    private var vizSpectrum: [Float] {
        switch model.mode {
        case .spectrum:
            return SpectrumBands.levels(
                binMagnitudes: model.snapshot.binMagnitudes,
                sampleRate: model.snapshot.sampleRate,
                count: model.spectrum.barCount,
                layout: model.spectrum.layout
            )
        case .orbit:
            return SpectrumBands.levels(
                binMagnitudes: model.snapshot.binMagnitudes,
                sampleRate: model.snapshot.sampleRate,
                count: model.orbit.barCount
            )
        case .waveform:
            return model.snapshot.spectrum
        }
    }
}

// MARK: - Full-Bleed Album Artwork Background

struct AppleMusicFluidBackground: View {
    var palette: FullscreenPalette
    var artwork: NSImage?
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                Color.black

                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h)
                        .clipped()
                        .blur(radius: reduceMotion ? 18 : 28)
                        .scaleEffect(1.06)
                        .opacity(0.28)
                }

                LinearGradient(
                    colors: palette.allColors.map { $0.opacity(0.16) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.28),
                        Color.black.opacity(0.44),
                        Color.black.opacity(0.66)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Left Column: Apple Music Player (Artwork, Scrubber, Controls)

struct AppleMusicPlayerPane: View {
    var snapshot: NowPlayingSnapshot
    var containerSize: CGSize
    @Binding var isShuffle: Bool
    @Binding var isRepeat: Bool
    var togglePlayPause: () -> Void
    var previousTrack: () -> Void
    var nextTrack: () -> Void
    var seek: (Double) -> Void

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var isShowingMenu = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let artworkSide = min(
            min(containerSize.width * 0.34, 380),
            max(220, containerSize.height * 0.46)
        )

        VStack(alignment: .leading, spacing: 22) {
            // Artwork Hero
            artworkHero(side: artworkSide)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                // Title, Artist and More Button
                metadataRow

                // Apple Music Scrubber Bar
                scrubberBar

                // 5-Icon Transport Controls
                transportRow
            }
            .frame(width: artworkSide)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func artworkHero(side: CGFloat) -> some View {
        Group {
            if let artwork = snapshot.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(.white.opacity(0.35))
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        // Multi-tier soft Apple Music shadow
        .shadow(
            color: Color.black.opacity(snapshot.isPlaying ? 0.45 : 0.28),
            radius: reduceMotion ? 0 : (snapshot.isPlaying ? 32 : 18),
            x: 0,
            y: snapshot.isPlaying ? 16 : 8
        )
        // Signature Apple Music subtle pause scale effect
        .scaleEffect(reduceMotion ? 1.0 : (snapshot.isPlaying ? 1.0 : 0.94))
        .animation(
            reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75),
            value: snapshot.isPlaying
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.35),
            value: snapshot.trackIdentity
        )
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if snapshot.hasTrack {
                    Text(snapshot.title.isEmpty ? String(localized: "Unknown Title") : snapshot.title)
                        .font(.system(size: 21, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(snapshot.artist.isEmpty ? String(localized: "Unknown Artist") : snapshot.artist)
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                } else {
                    Text(emptyTitleCopy)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(emptySubtitleCopy)
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 4)

            // "..." More Button
            if snapshot.hasTrack {
                Button(action: copyTrackInfo) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "More Options"))
            }
        }
    }

    private func copyTrackInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let info = "\(snapshot.title) - \(snapshot.artist)"
        pasteboard.setString(info, forType: .string)
    }

    @ViewBuilder
    private var scrubberBar: some View {
        if snapshot.isPlaying && scrubbing == false {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { _ in
                scrubberBarContent
            }
        } else {
            scrubberBarContent
        }
    }

    private var scrubberBarContent: some View {
        let duration = max(snapshot.durationSeconds, 0)
        let displayed: Double = {
            if scrubbing { return scrubValue }
            return snapshot.displayElapsed()
        }()
        let progress = duration > 0 ? min(max(displayed / duration, 0), 1) : 0

        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: max(4, geo.size.width * progress))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, snapshot.seekSupported else { return }
                            scrubbing = true
                            scrubValue = min(max(0, value.location.x / max(geo.size.width, 1)), 1) * duration
                        }
                        .onEnded { value in
                            guard duration > 0, snapshot.seekSupported else {
                                scrubbing = false
                                return
                            }
                            let seconds = min(max(0, value.location.x / max(geo.size.width, 1)), 1) * duration
                            scrubbing = false
                            seek(seconds)
                        }
                )
            }
            .frame(height: 5)

            // Timers: Left is elapsed (2:27), Right is remaining (-0:45)
            HStack {
                Text(formatElapsed(displayed))
                Spacer()
                Text(formatRemaining(elapsed: displayed, duration: duration))
            }
            .font(.system(size: 12, weight: .medium, design: .default).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
        .opacity(snapshot.seekSupported ? 1 : 0.7)
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            // 1. Shuffle
            Button(action: { isShuffle.toggle() }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isShuffle ? .white : .white.opacity(0.55))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Shuffle"))

            Spacer()

            // 2. Previous
            Button(action: previousTrack) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(snapshot.hasTrack == false)
            .accessibilityLabel(String(localized: "Previous Track"))

            Spacer()

            // 3. Play / Pause (Large & Prominent Apple Music Style)
            Button(action: togglePlayPause) {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .disabled(snapshot.hasTrack == false)
            .accessibilityLabel(snapshot.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

            Spacer()

            // 4. Next
            Button(action: nextTrack) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(snapshot.hasTrack == false)
            .accessibilityLabel(String(localized: "Next Track"))

            Spacer()

            // 5. Repeat
            Button(action: { isRepeat.toggle() }) {
                Image(systemName: "repeat")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isRepeat ? .white : .white.opacity(0.55))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Repeat"))
        }
        .padding(.top, 4)
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatRemaining(elapsed: Double, duration: Double) -> String {
        guard duration > 0 else { return "--:--" }
        let remaining = max(0, duration - elapsed)
        let total = Int(remaining.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "-%d:%02d", m, s)
    }

    private var emptyTitleCopy: String {
        switch snapshot.availability {
        case .unavailable:
            return String(localized: "Now Playing unavailable")
        case .empty, .idle, .listening:
            return String(localized: "Nothing playing")
        }
    }

    private var emptySubtitleCopy: String {
        switch snapshot.availability {
        case .unavailable:
            return String(localized: "MediaRemote adapter is not responding.")
        case .empty, .idle, .listening:
            return String(localized: "Play a song in Music, Spotify, or any player.")
        }
    }
}

// MARK: - Right Column: Apple Music Fluid Synced Lyrics

struct AppleMusicLyricsPane: View {
    @Bindable var model: FullscreenModel
    var onSeek: (Double) -> Void
    var openSettings: () -> Void
    @State private var activeIndex: Int? = nil

    var body: some View {
        Group {
            switch model.lyricsStatus {
            case .idle:
                EmptyView()

            case .disabled:
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "globe")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(String(localized: "Search lyrics online is off"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(String(localized: "Turn on Search lyrics online in Settings to display synced bilingual lyrics."))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: openSettings) {
                        Text(String(localized: "Open Settings"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            case .loading:
                // Pulsing Apple Music lyrics skeleton placeholders
                VStack(alignment: .leading, spacing: 22) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(width: 320, height: 32)
                    Capsule().fill(Color.white.opacity(0.24)).frame(width: 440, height: 42)
                    Capsule().fill(Color.white.opacity(0.18)).frame(width: 260, height: 26)
                    Capsule().fill(Color.white.opacity(0.12)).frame(width: 380, height: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            case .empty:
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(String(localized: "No synced lyrics found"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(String(localized: "Audune will automatically search again when the track changes."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Text(message)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            case .ready:
                lyricsScroller
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Lyrics"))
        .task(id: model.nowPlaying.isPlaying) {
            updateActiveIndex()
            guard model.nowPlaying.isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                updateActiveIndex()
            }
        }
    }

    private func updateActiveIndex() {
        let elapsed = model.nowPlaying.displayElapsed()
        let newActive = LRCParser.activeIndex(in: model.lyricsLines, at: elapsed)
        if newActive != activeIndex {
            activeIndex = newActive
        }
    }

    private var lyricsScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 26) {
                    // Top breathing space
                    Color.clear.frame(height: 60)

                    ForEach(Array(model.lyricsLines.enumerated()), id: \.element.id) { index, line in
                        AppleMusicLyricLineView(
                            line: line,
                            index: index,
                            activeIndex: activeIndex,
                            onSeek: onSeek
                        )
                        .id(index)
                    }

                    // Bottom breathing space
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 20)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: activeIndex) { _, newValue in
                guard let newValue else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    proxy.scrollTo(newValue, anchor: UnitPoint(x: 0.5, y: 0.38))
                }
            }
        }
    }
}

// MARK: - Apple Music Lyric Line Item View

struct AppleMusicLyricLineView: View {
    let line: LyricLine
    let index: Int
    let activeIndex: Int?
    let onSeek: (Double) -> Void

    @State private var isHovered = false

    var isActive: Bool {
        index == activeIndex
    }

    var textOpacity: Double {
        if isActive { return 1.0 }
        if isHovered { return 0.78 }
        return 0.40
    }

    var translationOpacity: Double {
        if isActive { return 0.88 }
        if isHovered { return 0.65 }
        return 0.30
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main lyric line
            Text(line.text)
                .font(.system(
                    size: isActive ? 40 : 28,
                    weight: isActive ? .heavy : .bold,
                    design: .rounded
                ))
                .foregroundStyle(Color.white.opacity(textOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .shadow(
                    color: Color.black.opacity(isActive ? 0.35 : 0),
                    radius: isActive ? 10 : 0,
                    x: 0,
                    y: 4
                )

            // Sub-translation (if present)
            if let translation = line.translation, translation.isEmpty == false {
                Text(translation)
                    .font(.system(
                        size: isActive ? 21 : 16,
                        weight: isActive ? .bold : .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(Color.white.opacity(translationOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek(line.timeSeconds)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}
#endif
