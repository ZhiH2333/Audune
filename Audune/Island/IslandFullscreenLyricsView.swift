#if os(macOS)
import SwiftUI

struct IslandFullscreenLyricsView: View {
    @Bindable var model: IslandModel
    var importLyrics: () -> Void
    var chooseCandidate: (UUID) -> Void
    var deleteLyrics: (UUID) -> Void
    var retryLyrics: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 900
            HStack(spacing: 0) {
                songDetails(artworkSide: min(narrow ? 150 : 220, geometry.size.height * 0.28))
                    .frame(width: narrow ? min(geometry.size.width * 0.32, 250) : min(geometry.size.width * 0.3, 380), alignment: .leading)
                    .padding(.trailing, 36)

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)

                lyricsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, 48)
                    .id(model.lyricsTrackRevision)
                    .transition(.opacity)
                    .animation(trackAnimation, value: model.lyricsTrackRevision)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func songDetails(artworkSide: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                if let artwork = model.nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .frame(width: artworkSide, height: artworkSide)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel(String(localized: "Album artwork"))
            .id(model.lyricsTrackRevision)
            .transition(.opacity)
            .animation(trackAnimation, value: model.lyricsTrackRevision)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.nowPlaying.title.isEmpty ? String(localized: "Unknown Title") : model.nowPlaying.title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                Text(model.nowPlaying.artist.isEmpty ? String(localized: "Unknown Artist") : model.nowPlaying.artist)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .accessibilityElement(children: .combine)

            if let progress = LyricsPlaybackClock.progress(
                position: model.lyricsPositionSeconds,
                duration: model.nowPlaying.durationSeconds
            ) {
                ProgressView(value: progress)
                    .tint(.white.opacity(0.75))
                    .accessibilityLabel(String(localized: "Playback progress"))
            }
            Text(playbackPositionLabel)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            Spacer(minLength: 12)

            Text(String(localized: "Lyrics uses Now Playing metadata while this scene is open. Online lookup is unavailable."))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Button(action: importLyrics) {
                    Label(String(localized: "Import LRC"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(canImportLyrics ? 0.82 : 0.38))
                .disabled(canImportLyrics == false)
                .help(String(localized: "Import a local LRC file for this song"))

                if case .local(let document) = model.lyricsState {
                    Button {
                        deleteLyrics(document.id)
                    } label: {
                        Label(String(localized: "Delete imported lyrics"), systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))
                    .help(String(localized: "Delete imported lyrics"))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var lyricsContent: some View {
        switch model.lyricsState {
        case .local(let document), .found(let document):
            lyricLines(document)
        case .ambiguous(let documents):
            ambiguousChoices(documents)
        case .noTrack:
            statusState(
                title: String(localized: "Nothing playing"),
                message: String(localized: "Play music to view lyrics."),
                showsRetry: false
            )
        case .nowPlayingUnavailable:
            statusState(
                title: String(localized: "Now Playing unavailable"),
                message: String(localized: "Audune cannot read the current song from the system right now."),
                showsRetry: false
            )
        case .metadataUnavailable:
            statusState(
                title: String(localized: "Song information is incomplete"),
                message: String(localized: "The current song is missing a title or artist, so lyrics cannot be matched."),
                showsRetry: false
            )
        case .idle, .identifyingTrack:
            statusState(
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Identifying the current song."),
                showsRetry: false,
                isLoading: true
            )
        case .checkingLocal:
            statusState(
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Checking your imported lyrics."),
                showsRetry: false,
                isLoading: true
            )
        case .searchingOnline:
            statusState(
                title: String(localized: "Searching for lyrics"),
                message: String(localized: "Looking for the current song on LRCLIB."),
                showsRetry: false,
                isLoading: true
            )
        case .loading:
            statusState(
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Preparing synchronized lyrics."),
                showsRetry: false,
                isLoading: true
            )
        case .onlineDisabled:
            statusState(
                title: String(localized: "Online lyrics are off"),
                message: String(localized: "Turn on Automatic Online Lyrics in Settings, or import an LRC file."),
                showsRetry: false
            )
        case .instrumental:
            statusState(
                title: String(localized: "Instrumental track"),
                message: String(localized: "This song has no lyrics to display."),
                showsRetry: false
            )
        case .notFound:
            statusState(
                title: String(localized: "No lyrics found"),
                message: String(localized: "No matching lyrics were found for this song."),
                showsRetry: true
            )
        case .offline:
            statusState(
                title: String(localized: "You are offline"),
                message: String(localized: "Connect to the internet to search for lyrics."),
                showsRetry: true
            )
        case .providerUnavailable:
            statusState(
                title: String(localized: "Lyrics service unavailable"),
                message: String(localized: "LRCLIB is not responding right now. Try again in a moment."),
                showsRetry: true
            )
        case .rateLimited(let retryAfterSeconds):
            statusState(
                title: String(localized: "Too many lyrics requests"),
                message: retryAfterMessage(retryAfterSeconds),
                showsRetry: true
            )
        case .networkError:
            statusState(
                title: String(localized: "Could not reach the lyrics service"),
                message: String(localized: "Check your connection, then try again."),
                showsRetry: true
            )
        case .parseError:
            statusState(
                title: String(localized: "Lyrics could not be read"),
                message: String(localized: "The lyrics service returned a format Audune cannot display."),
                showsRetry: true
            )
        case .cancelled:
            statusState(
                title: String(localized: "Lyrics search stopped"),
                message: String(localized: "Try searching again."),
                showsRetry: true
            )
        case .importError(let message):
            statusState(
                title: String(localized: "Lyrics file could not be imported"),
                message: message,
                showsRetry: false
            )
        case .error(let message):
            statusState(
                title: String(localized: "Lyrics could not be loaded"),
                message: message,
                showsRetry: true
            )
        }
    }

    private func retryAfterMessage(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return String(localized: "Try again in a moment.")
        }
        let rounded = max(1, Int(seconds.rounded(.up)))
        return String(localized: "Try again in about \(rounded) seconds.")
    }

    private func statusState(
        title: String,
        message: String,
        showsRetry: Bool,
        isLoading: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.7))
            }
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
            HStack(spacing: 18) {
                if showsRetry {
                    Button(String(localized: "Try Again"), action: retryLyrics)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .accessibilityLabel(String(localized: "Search for lyrics again"))
                }
                if canImportLyrics {
                    Button(String(localized: "Import LRC"), action: importLyrics)
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityLabel(String(localized: "Import a local LRC lyrics file"))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func lyricLines(_ document: LyricsDocument) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(document.lines.enumerated()), id: \.offset) { index, line in
                        let distance = model.activeLyricsLineIndex.map { abs(index - $0) } ?? 2
                        let opacity = lineOpacity(distance: distance)
                        let translationReveal = shouldReduceMotion || index != model.activeLyricsLineIndex
                            ? 1
                            : translationOpacity
                        VStack(alignment: .leading, spacing: 7) {
                            Group {
                                if let words = line.words, words.isEmpty == false {
                                    LyricsTimedWordLine(
                                        words: words,
                                        position: model.lyricsPositionSeconds,
                                        fontSize: index == model.activeLyricsLineIndex ? 32 : 23,
                                        weight: index == model.activeLyricsLineIndex ? .semibold : .medium,
                                        opacity: opacity,
                                        accessibilityLabel: line.text
                                    )
                                } else {
                                    Text(line.text)
                                        .font(.system(
                                            size: index == model.activeLyricsLineIndex ? 32 : 23,
                                            weight: index == model.activeLyricsLineIndex ? .semibold : .medium,
                                            design: .rounded
                                        ))
                                        .foregroundStyle(.white.opacity(opacity))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if let translation = line.translation, translation.isEmpty == false {
                                Text(translation)
                                    .font(.system(size: 16, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.4 * opacity * translationReveal))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .offset(y: shouldReduceMotion ? 0 : (1 - translationReveal) * 5)
                                    .animation(
                                        shouldReduceMotion ? nil : .linear(duration: 1.0 / 30),
                                        value: translationReveal
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(index)
                        .accessibilityElement(children: .combine)
                        .animation(lineAnimation, value: model.activeLyricsLineIndex)
                    }
                }
                .padding(.vertical, 120)
            }
            .onAppear {
                if let index = model.activeLyricsLineIndex {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: model.activeLyricsLineIndex) { _, index in
                guard let index else { return }
                if shouldReduceMotion {
                    proxy.scrollTo(index, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: IslandMotion.lyricsLineSeconds)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func ambiguousChoices(_ documents: [LyricsDocument]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "Choose the matching local lyrics"))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                ForEach(documents) { document in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(document.trackKey.album ?? String(localized: "Unknown Album"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                            HStack(spacing: 5) {
                                Text(String(document.lines.count))
                                Text(String(localized: "Lyric lines"))
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.52))
                        }
                        Spacer()
                        Button {
                            chooseCandidate(document.id)
                        } label: {
                            Label(String(localized: "Use"), systemImage: "checkmark")
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Use these lyrics"))
                        Button {
                            deleteLyrics(document.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Delete imported lyrics"))
                        .accessibilityLabel(String(localized: "Delete imported lyrics"))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 28)
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "LYRICS"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.45))
            Text(message)
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var canImportLyrics: Bool {
        model.nowPlaying.title.isEmpty == false && model.nowPlaying.artist.isEmpty == false
    }

    private var playbackPositionLabel: String {
        let current = timeLabel(model.lyricsPositionSeconds)
        guard model.nowPlaying.durationSeconds.isFinite, model.nowPlaying.durationSeconds > 0 else { return current }
        return "\(current) / \(timeLabel(model.nowPlaying.durationSeconds))"
    }

    private var translationOpacity: Double {
        LyricsPresentationTiming.translationOpacity(
            sinceLineFocus: ProcessInfo.processInfo.systemUptime - model.activeLyricsLineChangedAtUptime
        )
    }

    private var shouldReduceMotion: Bool {
        reduceMotion && model.prefs.followsReduceMotion
    }

    private var lineAnimation: Animation? {
        shouldReduceMotion ? nil : .easeInOut(duration: IslandMotion.lyricsLineSeconds)
    }

    private var trackAnimation: Animation? {
        shouldReduceMotion ? nil : .easeInOut(duration: IslandMotion.lyricsTrackSeconds)
    }

    private func lineOpacity(distance: Int) -> Double {
        switch distance {
        case 0: 1
        case 1: 0.7
        case 2: 0.46
        default: 0.28
        }
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct LyricsTimedWordLine: View {
    var words: [LyricsWord]
    var position: TimeInterval
    var fontSize: CGFloat
    var weight: Font.Weight
    var opacity: Double
    var accessibilityLabel: String

    var body: some View {
        LyricsTokenFlowLayout {
            ForEach(words) { word in
                LyricsWordFill(
                    word: word,
                    progress: LyricsPlaybackClock.wordProgress(for: word, at: position),
                    font: .system(size: fontSize, weight: weight, design: .rounded),
                    opacity: opacity
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct LyricsWordFill: View {
    var word: LyricsWord
    var progress: Double
    var font: Font
    var opacity: Double

    var body: some View {
        Text(word.text)
            .font(font)
            .foregroundStyle(.white.opacity(opacity * 0.34))
            .fixedSize()
            .overlay(alignment: .leading) {
                Text(word.text)
                    .font(font)
                    .foregroundStyle(.white.opacity(opacity))
                    .fixedSize()
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle()
                                .frame(width: geometry.size.width * min(max(progress, 0), 1))
                        }
                    }
            }
    }
}

private struct LyricsTokenFlowLayout: Layout {
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                widestRow = max(widestRow, x)
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
        widestRow = max(widestRow, x)
        return CGSize(width: proposal.width ?? widestRow, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
