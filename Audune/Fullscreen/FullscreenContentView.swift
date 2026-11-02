#if os(macOS)
import AppKit
import SwiftUI

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

    var body: some View {
        ZStack {
            FullscreenBackgroundView(
                artwork: model.nowPlaying.artwork,
                reduceMotion: reduceMotion
            )
            StudioVisualizationView(
                prefs: studioPrefsForViz,
                spectrum: vizSpectrum,
                peaks: [],
                waveform: model.snapshot.waveform,
                drawsBars: model.snapshot.isSilent == false
            )
            .opacity(0.28)
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Fullscreen Settings"))
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Close Fullscreen"))
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                Spacer(minLength: 24)

                HStack(alignment: .bottom, spacing: 36) {
                    artworkHero
                    VStack(alignment: .leading, spacing: 18) {
                        trackText
                        FullscreenTransportBar(
                            snapshot: model.nowPlaying,
                            togglePlayPause: togglePlayPause,
                            previousTrack: previousTrack,
                            nextTrack: nextTrack,
                            seek: seek
                        )
                        FullscreenLyricsPane(model: model)
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 64)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .focusable()
        .onExitCommand(perform: close)
    }

    @ViewBuilder
    private var artworkHero: some View {
        let side: CGFloat = 280
        Group {
            if let artwork = model.nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white.opacity(0.35))
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: reduceMotion ? 0 : 28, y: 14)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: model.nowPlaying.trackIdentity)
    }

    private var trackText: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.nowPlaying.hasTrack {
                Text(model.nowPlaying.title.isEmpty ? String(localized: "Unknown Title") : model.nowPlaying.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(model.nowPlaying.artist.isEmpty ? String(localized: "Unknown Artist") : model.nowPlaying.artist)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            } else {
                Text(emptyCopy)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var emptyCopy: String {
        switch model.nowPlaying.availability {
        case .unavailable:
            return String(localized: "Now Playing unavailable")
        case .empty, .idle, .listening:
            return String(localized: "Nothing playing")
        }
    }

    private var studioPrefsForViz: StudioPreferences {
        var prefs = StudioPreferences.standard
        prefs.mode = model.mode
        prefs.appearance = model.appearance
        prefs.spectrum = model.spectrum
        prefs.waveform = model.waveform
        prefs.orbit = model.orbit
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

struct FullscreenBackgroundView: View {
    var artwork: NSImage?
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: reduceMotion ? 8 : 48)
                        .scaleEffect(reduceMotion ? 1.05 : 1.18)
                        .opacity(0.55)
                }
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.72),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: artwork != nil)
    }
}

struct FullscreenTransportBar: View {
    var snapshot: NowPlayingSnapshot
    var togglePlayPause: () -> Void
    var previousTrack: () -> Void
    var nextTrack: () -> Void
    var seek: (Double) -> Void
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.hasTrack {
                progressRow
                HStack(spacing: 22) {
                    transportButton(symbol: "backward.fill", label: String(localized: "Previous Track"), action: previousTrack)
                    transportButton(
                        symbol: snapshot.isPlaying ? "pause.fill" : "play.fill",
                        label: snapshot.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                        action: togglePlayPause
                    )
                    transportButton(symbol: "forward.fill", label: String(localized: "Next Track"), action: nextTrack)
                }
            }
        }
    }

    private var progressRow: some View {
        let duration = max(snapshot.durationSeconds, 0)
        let displayed: Double = {
            if scrubbing { return scrubValue }
            return snapshot.displayElapsed()
        }()
        let progress = duration > 0 ? min(max(displayed / duration, 0), 1) : 0
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white.opacity(0.85))
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
            .frame(height: 6)
            HStack {
                Text(formatTime(displayed))
                Spacer()
                Text(duration > 0 ? formatTime(duration) : "--:--")
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
        }
        .opacity(snapshot.seekSupported ? 1 : 0.7)
    }

    private func transportButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(snapshot.hasTrack == false)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct FullscreenLyricsPane: View {
    @Bindable var model: FullscreenModel

    var body: some View {
        Group {
            switch model.lyricsStatus {
            case .idle:
                EmptyView()
            case .disabled:
                Text(String(localized: "Turn on Search lyrics online in Settings to fetch synced lyrics from lrclib.net."))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            case .empty:
                Text(String(localized: "No synced lyrics found"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            case .failed(let message):
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            case .ready:
                VStack(alignment: .leading, spacing: 8) {
                    if model.lyricsSourceLabel.isEmpty == false {
                        Text(String(format: String(localized: "Source: %@"), model.lyricsSourceLabel))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if model.nowPlaying.isPlaying {
                        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                            lyricsScroller(at: timeline.date)
                        }
                    } else {
                        lyricsScroller(at: .now)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Lyrics"))
    }

    private func lyricsScroller(at date: Date) -> some View {
        let elapsed = model.nowPlaying.displayElapsed(at: date)
        let active = LRCParser.activeIndex(in: model.lyricsLines, at: elapsed)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(model.lyricsLines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(.system(
                                size: index == active ? 22 : 16,
                                weight: index == active ? .semibold : .regular,
                                design: .rounded
                            ))
                            .foregroundStyle(.white.opacity(index == active ? 1 : 0.42))
                            .id(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)
            .onChange(of: active) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}
#endif
