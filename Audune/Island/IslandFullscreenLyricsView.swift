#if os(macOS)
import SwiftUI

struct IslandFullscreenLyricsView: View {
    @Bindable var model: IslandModel
    var importLyrics: () -> Void
    var chooseCandidate: (UUID) -> Void
    var deleteLyrics: (UUID) -> Void
    var retryLyrics: () -> Void
    var seek: (Double) -> Void
    var togglePlay: () -> Void
    var previousTrack: () -> Void
    var nextTrack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubbedFraction: Double?
    @State private var isHoveringProgress = false

    private let contentMaxWidth: CGFloat = 980

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let compact = size.width < 980 || size.height < 560
            Group {
                if compact {
                    compactLayout(size: size)
                } else {
                    regularLayout(size: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout

    private func regularLayout(size: CGSize) -> some View {
        // The player column is exactly as wide as the artwork so the title, progress bar,
        // timestamps, and transport controls share the album art's left/right edges.
        let artworkSide = min(min(max(size.width * 0.30, 300), max(220, size.height * 0.42)), 420)
        let gutter = min(max(size.width * 0.045, 36), 80)
        return HStack(alignment: .top, spacing: 0) {
            identityPanel(artworkSide: artworkSide)
                .frame(width: artworkSide, alignment: .leading)
                .padding(.trailing, gutter)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
                .padding(.vertical, 8)

            stage(size: size)
                .padding(.leading, gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func compactLayout(size: CGSize) -> some View {
        VStack(spacing: 22) {
            compactIdentity(size: size)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            stage(size: size)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Song identity

    private func identityPanel(artworkSide: CGFloat) -> some View {
        let titleSize = min(max(artworkSide * 0.064, 20), 28)
        return VStack(alignment: .leading, spacing: 0) {
            artwork(side: artworkSide, cornerRadius: artworkCornerRadius(artworkSide))

            songHeader(titleSize: titleSize)
                .padding(.top, artworkSide * 0.10)

            progressBlock
                .padding(.top, artworkSide * 0.075)

            transportRow(scale: artworkSide)
                .padding(.top, artworkSide * 0.09)

            lyricsAccessory()
                .padding(.top, artworkSide * 0.075)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func songHeader(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: max(3, titleSize * 0.14)) {
            if let album = albumName {
                Text(album)
                    .font(.system(size: max(9, titleSize * 0.42), weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Text(displayTitle)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(displayArtist)
                .font(.system(size: max(12, titleSize * 0.7), weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(model.lyricsTrackRevision)
        .transition(.opacity)
    }

    private func compactIdentity(size: CGSize) -> some View {
        let side = min(max(size.height * 0.13, 76), 104)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                artwork(side: side, cornerRadius: artworkCornerRadius(side))
                VStack(alignment: .leading, spacing: 4) {
                    if let album = albumName, size.height > 520 {
                        Text(album)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    Text(displayTitle)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(displayArtist)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if let document = model.lyricsState.document {
                    sourceBadge(document: document)
                        .fixedSize()
                }
            }
            progressBlock
            transportRow(scale: side * 1.9)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func artworkCornerRadius(_ side: CGFloat) -> CGFloat {
        min(max(side * 0.022, 8), 14)
    }

    private func artwork(side: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let artwork = model.nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: max(28, side * 0.24), weight: .light))
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.42), radius: 28, y: 16)
        .accessibilityLabel(String(localized: "Album artwork"))
        .id(model.lyricsTrackRevision)
        .transition(.opacity)
    }

    // MARK: - Playback

    /// Progress bar with elapsed/remaining timestamps underneath, matching the reference layout.
    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            progressBar
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(timeLabel(displayedPosition))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 8)
                Text(remainingLabel)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Playback position"))
            .accessibilityValue(playbackAccessibilityValue)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let actual = LyricsPlaybackClock.progress(
                position: model.lyricsPositionSeconds,
                duration: model.nowPlaying.durationSeconds
            ) ?? 0
            let fraction = min(max(scrubbedFraction ?? actual, 0), 1)
            let canSeek = model.nowPlaying.seekSupported && validDuration
            // The knob stays hidden until the pointer is over the bar, like the reference player.
            let showsKnob = canSeek && (isHoveringProgress || scrubbedFraction != nil)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.white.opacity(canSeek ? 0.92 : 0.7))
                    .frame(width: max(0, width * fraction), height: 4)
                if showsKnob {
                    Circle()
                        .fill(Color.white)
                        .frame(width: scrubbedFraction == nil ? 9 : 12, height: scrubbedFraction == nil ? 9 : 12)
                        .offset(x: min(max(width * fraction - 6, 0), max(width - 12, 0)))
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .onHover { isHoveringProgress = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek else { return }
                        scrubbedFraction = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        guard canSeek, let fraction = scrubbedFraction else { return }
                        seek(fraction * model.nowPlaying.durationSeconds)
                        scrubbedFraction = nil
                        _ = value
                    }
            )
            .animation(.easeOut(duration: 0.16), value: scrubbedFraction == nil)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Playback progress"))
            .accessibilityValue(playbackAccessibilityValue)
            .accessibilityAdjustableAction { direction in
                guard canSeek else { return }
                let step = 5.0
                let delta = direction == .increment ? step : -step
                seek(min(max(model.lyricsPositionSeconds + delta, 0), model.nowPlaying.durationSeconds))
            }
        }
        .frame(height: 18)
    }

    /// Five equal slots keep previous / play-pause / next on the reference player's centers.
    private func transportRow(scale: CGFloat) -> some View {
        let glyph = min(max(scale * 0.052, 14), 21)
        let primary = min(max(scale * 0.075, 19), 30)
        return HStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 1)
            transportButton(
                symbol: "backward.fill",
                label: String(localized: "Previous Track"),
                size: glyph,
                action: previousTrack
            )
            .frame(maxWidth: .infinity)
            playPauseButton(size: primary)
                .frame(maxWidth: .infinity)
            transportButton(
                symbol: "forward.fill",
                label: String(localized: "Next Track"),
                size: glyph,
                action: nextTrack
            )
            .frame(maxWidth: .infinity)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func playPauseButton(size: CGFloat) -> some View {
        let label = model.nowPlaying.isPlaying ? String(localized: "Pause") : String(localized: "Play")
        return Button(action: togglePlay) {
            Image(systemName: model.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(canControlPlayback ? 0.95 : 0.26))
                .frame(width: size * 2, height: size * 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(canControlPlayback == false)
        .help(label)
        .accessibilityLabel(label)
    }

    private func transportButton(
        symbol: String,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(canControlPlayback ? 0.9 : 0.26))
                .frame(width: size * 2.2, height: size * 2.2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(canControlPlayback == false)
        .help(label)
        .accessibilityLabel(label)
    }

    private var playbackAccessibilityValue: String {
        guard validDuration else { return timeLabel(displayedPosition) }
        return "\(timeLabel(displayedPosition)) / \(timeLabel(model.nowPlaying.durationSeconds))"
    }

    // MARK: - Source

    private func lyricsAccessory() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let document = model.lyricsState.document {
                    sourceBadge(document: document)
                } else {
                    Text(String(localized: "No lyrics loaded yet"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.32))
                }
                Spacer(minLength: 8)
                Button(action: importLyrics) {
                    Label(String(localized: "Import LRC"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .buttonStyle(LyricsQuietButtonStyle())
                .disabled(canImportLyrics == false)
                .help(String(localized: "Import a local LRC file for this song"))
                .accessibilityLabel(String(localized: "Import a local LRC lyrics file"))

                if case .local(let document) = model.lyricsState {
                    Button {
                        deleteLyrics(document.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(LyricsQuietButtonStyle())
                    .help(String(localized: "Delete imported lyrics"))
                    .accessibilityLabel(String(localized: "Delete imported lyrics"))
                }
            }
            if let document = model.lyricsState.document {
                Text(syncDescription(for: document))
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sourceBadge(document: LyricsDocument) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 4, height: 4)
            Text(sourceLabel(for: document))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Lyrics source: \(sourceLabel(for: document))"))
    }

    private func sourceLabel(for document: LyricsDocument) -> String {
        switch document.source?.kind {
        case .localImport:
            return String(localized: "Imported LRC")
        case .lrclib:
            return String(localized: "LRCLIB")
        case nil:
            return String(localized: "Lyrics")
        }
    }

    private func syncDescription(for document: LyricsDocument) -> String {
        switch document.synchronization {
        case .wordSynced:
            return String(localized: "Word-by-word synchronized lyrics")
        case .lineSynced:
            return String(localized: "Line-synchronized lyrics")
        case .unsynced:
            return String(localized: "Plain lyrics without timing")
        }
    }

    // MARK: - Lyrics stage

    private func stage(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(String(localized: "LYRICS"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(3.2)
                    .foregroundStyle(.white.opacity(0.34))
                Spacer()
                if let document = model.lyricsState.document,
                   document.synchronization != .unsynced {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .medium))
                        Text(String(localized: "Following playback"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.28))
                }
            }
            .padding(.bottom, 10)

            lyricsContent(size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    shouldReduceMotion ? nil : .easeInOut(duration: IslandMotion.lyricsTrackSeconds),
                    value: model.lyricsTrackRevision
                )
                .animation(
                    shouldReduceMotion ? nil : .easeInOut(duration: 0.28),
                    value: model.lyricsState
                )
        }
    }

    @ViewBuilder
    private func lyricsContent(size: CGSize) -> some View {
        switch model.lyricsState {
        case .local(let document), .found(let document):
            lyricStage(document: document, size: size)
                .id(document.id)
                .transition(.opacity)
        case .ambiguous(let documents):
            ambiguousChoices(documents)
        case .noTrack:
            statusState(
                symbol: "music.note",
                title: String(localized: "Nothing playing"),
                message: String(localized: "Play music to view lyrics."),
                showsRetry: false
            )
        case .nowPlayingUnavailable:
            statusState(
                symbol: "speaker.slash",
                title: String(localized: "Now Playing unavailable"),
                message: String(localized: "Audune cannot read the current song from the system right now."),
                showsRetry: false
            )
        case .metadataUnavailable:
            statusState(
                symbol: "questionmark.circle",
                title: String(localized: "Song information is incomplete"),
                message: String(localized: "The current song is missing a title or artist, so lyrics cannot be matched."),
                showsRetry: false
            )
        case .idle, .identifyingTrack:
            statusState(
                symbol: "music.note.list",
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Identifying the current song."),
                showsRetry: false,
                isLoading: true
            )
        case .checkingLocal:
            statusState(
                symbol: "music.note.list",
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Checking your imported lyrics."),
                showsRetry: false,
                isLoading: true
            )
        case .searchingOnline:
            statusState(
                symbol: "globe",
                title: String(localized: "Searching for lyrics"),
                message: String(localized: "Looking for the current song on LRCLIB."),
                showsRetry: false,
                isLoading: true
            )
        case .loading:
            statusState(
                symbol: "music.note.list",
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Preparing synchronized lyrics."),
                showsRetry: false,
                isLoading: true
            )
        case .onlineDisabled:
            statusState(
                symbol: "wifi.slash",
                title: String(localized: "Online lyrics are off"),
                message: String(localized: "Turn on Automatic Online Lyrics in Settings, or import an LRC file."),
                showsRetry: false
            )
        case .instrumental:
            statusState(
                symbol: "waveform",
                title: String(localized: "Instrumental track"),
                message: String(localized: "This song has no lyrics to display."),
                showsRetry: false
            )
        case .notFound:
            statusState(
                symbol: "text.magnifyingglass",
                title: String(localized: "No lyrics found"),
                message: String(localized: "No matching lyrics were found for this song."),
                showsRetry: true
            )
        case .offline:
            statusState(
                symbol: "wifi.slash",
                title: String(localized: "You are offline"),
                message: String(localized: "Connect to the internet to search for lyrics."),
                showsRetry: true
            )
        case .providerUnavailable:
            statusState(
                symbol: "exclamationmark.icloud",
                title: String(localized: "Lyrics service unavailable"),
                message: String(localized: "LRCLIB is not responding right now. Try again in a moment."),
                showsRetry: true
            )
        case .rateLimited(let retryAfterSeconds):
            statusState(
                symbol: "hourglass",
                title: String(localized: "Too many lyrics requests"),
                message: retryAfterMessage(retryAfterSeconds),
                showsRetry: true
            )
        case .networkError:
            statusState(
                symbol: "wifi.exclamationmark",
                title: String(localized: "Could not reach the lyrics service"),
                message: String(localized: "Check your connection, then try again."),
                showsRetry: true
            )
        case .parseError:
            statusState(
                symbol: "doc.text.magnifyingglass",
                title: String(localized: "Lyrics could not be read"),
                message: String(localized: "The lyrics service returned a format Audune cannot display."),
                showsRetry: true
            )
        case .cancelled:
            statusState(
                symbol: "stop.circle",
                title: String(localized: "Lyrics search stopped"),
                message: String(localized: "Try searching again."),
                showsRetry: true
            )
        case .importError(let message):
            statusState(
                symbol: "doc.badge.exclamationmark",
                title: String(localized: "Lyrics file could not be imported"),
                message: message,
                showsRetry: false
            )
        case .error(let message):
            statusState(
                symbol: "exclamationmark.triangle",
                title: String(localized: "Lyrics could not be loaded"),
                message: message,
                showsRetry: true
            )
        }
    }

    private func lyricStage(document: LyricsDocument, size: CGSize) -> some View {
        if document.synchronization == .unsynced {
            return AnyView(unsyncedLyrics(document: document, size: size))
        }
        return AnyView(synchronizedLyrics(document: document, size: size))
    }

    private func unsyncedLyrics(document: LyricsDocument, size: CGSize) -> some View {
        let fontSize = min(max(size.height * 0.026, 20), 30)
        return ScrollView(.vertical) {
            VStack(spacing: max(14, fontSize * 0.72)) {
                ForEach(document.lines) { line in
                    VStack(spacing: 6) {
                        Text(line.text)
                            .font(.system(size: fontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if let translation = line.translation, translation.isEmpty == false {
                            Text(translation)
                                .font(.system(size: fontSize * 0.66, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.42))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: max(0, size.height - 140), alignment: .center)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func synchronizedLyrics(document: LyricsDocument, size: CGSize) -> some View {
        let activeSize = min(max(size.height * 0.036, 28), 43)
        let focusIndex = min(max(model.activeLyricsLineIndex ?? 0, 0), max(document.lines.count - 1, 0))
        let lowerBound = max(0, focusIndex - 3)
        let upperBound = min(max(document.lines.count - 1, 0), focusIndex + 3)
        let visibleIndices = Array(lowerBound...upperBound)

        return VStack(spacing: max(18, activeSize * 0.72)) {
            ForEach(visibleIndices, id: \.self) { index in
                lyricRow(
                    document: document,
                    line: document.lines[index],
                    index: index,
                    focusIndex: focusIndex,
                    activeSize: activeSize
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
            }
        }
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
        .animation(
            shouldReduceMotion ? nil : .easeInOut(duration: IslandMotion.lyricsLineSeconds),
            value: focusIndex
        )
    }

    private func lyricRow(
        document: LyricsDocument,
        line: LyricsLine,
        index: Int,
        focusIndex: Int,
        activeSize: CGFloat
    ) -> some View {
        let isActive = index == focusIndex
        let distance = abs(index - focusIndex)
        let fontSize = lyricFontSize(distance: distance, activeSize: activeSize)
        let opacity = lyricOpacity(distance: distance)
        let translationReveal = shouldReduceMotion || isActive == false
            ? 1
            : LyricsPresentationTiming.translationOpacity(
                lineStartSeconds: line.startSeconds,
                positionSeconds: model.lyricsPositionSeconds
            )
        let hasWords = line.words?.isEmpty == false

        return VStack(spacing: max(7, activeSize * 0.2)) {
            Group {
                if isActive, hasWords, let words = line.words {
                    LyricsTimedWordLine(
                        words: words,
                        position: model.lyricsPositionSeconds,
                        fontSize: activeSize,
                        weight: .semibold,
                        opacity: 1,
                        accessibilityLabel: line.text
                    )
                } else {
                    Text(line.text)
                        .font(.system(size: fontSize, weight: isActive ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(opacity))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentTransition(.opacity)

            if let translation = line.translation, translation.isEmpty == false {
                Text(translation)
                    .font(.system(
                        size: isActive ? activeSize * 0.46 : max(13, fontSize * 0.52),
                        weight: .regular,
                        design: .rounded
                    ))
                    .foregroundStyle(.white.opacity((isActive ? 0.5 : 0.34) * translationReveal))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: shouldReduceMotion ? 0 : (1 - translationReveal) * 6)
                    .opacity(translationReveal)
            }
        }
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)
        .scaleEffect(isActive || shouldReduceMotion ? 1 : 0.985, anchor: .center)
        .animation(
            shouldReduceMotion ? nil : .easeInOut(duration: IslandMotion.lyricsLineSeconds),
            value: focusIndex
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: line))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func accessibilityLabel(for line: LyricsLine) -> String {
        if let translation = line.translation, translation.isEmpty == false {
            return "\(line.text), \(translation)"
        }
        return line.text
    }

    private func lyricFontSize(distance: Int, activeSize: CGFloat) -> CGFloat {
        switch distance {
        case 0: return activeSize
        case 1: return activeSize * 0.74
        default: return activeSize * 0.6
        }
    }

    private func lyricOpacity(distance: Int) -> Double {
        switch distance {
        case 0: return 0.96
        case 1: return 0.48
        case 2: return 0.28
        default: return 0.14
        }
    }

    // MARK: - Ambiguous and status states

    private func ambiguousChoices(_ documents: [LyricsDocument]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Choose the matching local lyrics"))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                Text(String(localized: "Several imported files match this song. Pick the version you want to follow."))
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.bottom, 8)

                ForEach(documents) { document in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(document.trackKey.album ?? String(localized: "Unknown Album"))
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(syncDescription(for: document))
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer()
                        Button {
                            chooseCandidate(document.id)
                        } label: {
                            Text(String(localized: "Use"))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.88))
                        .accessibilityLabel(String(localized: "Use these lyrics"))
                        Button {
                            deleteLyrics(document.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.4))
                        .accessibilityLabel(String(localized: "Delete imported lyrics"))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private func statusState(
        symbol: String,
        title: String,
        message: String,
        showsRetry: Bool,
        isLoading: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 72, height: 72)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.7))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.bottom, 24)

            Text(title)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if showsRetry || canImportLyrics {
                HStack(spacing: 14) {
                    if showsRetry {
                        Button(action: retryLyrics) {
                            Text(String(localized: "Try Again"))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.9), in: Capsule())
                                .foregroundStyle(.black.opacity(0.86))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Search for lyrics again"))
                    }
                    if canImportLyrics {
                        Button(action: importLyrics) {
                            Text(String(localized: "Import LRC"))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Import a local LRC lyrics file"))
                    }
                }
                .padding(.top, 24)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .transition(.opacity)
    }

    // MARK: - Derived values

    private var displayTitle: String {
        model.nowPlaying.title.isEmpty ? String(localized: "Unknown Title") : model.nowPlaying.title
    }

    private var displayArtist: String {
        model.nowPlaying.artist.isEmpty ? String(localized: "Unknown Artist") : model.nowPlaying.artist
    }

    private var albumName: String? {
        let album = model.nowPlaying.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return album.isEmpty ? nil : album
    }

    private var displayedPosition: TimeInterval {
        if let fraction = scrubbedFraction, validDuration {
            return fraction * model.nowPlaying.durationSeconds
        }
        return model.lyricsPositionSeconds
    }

    /// Remaining time with the leading minus sign, like the reference player's right label.
    private var remainingLabel: String {
        guard validDuration else { return "--:--" }
        let remaining = max(model.nowPlaying.durationSeconds - displayedPosition, 0)
        return "-\(timeLabel(remaining))"
    }

    private var canControlPlayback: Bool {
        model.nowPlaying.hasTrack && model.nowPlaying.availability == .listening
    }

    private var validDuration: Bool {
        model.nowPlaying.durationSeconds.isFinite && model.nowPlaying.durationSeconds > 0
    }

    private var canImportLyrics: Bool {
        model.nowPlaying.title.isEmpty == false && model.nowPlaying.artist.isEmpty == false
    }

    private var shouldReduceMotion: Bool {
        reduceMotion && model.prefs.followsReduceMotion
    }

    private func retryAfterMessage(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return String(localized: "Try again in a moment.")
        }
        let rounded = max(1, Int(seconds.rounded(.up)))
        return String(localized: "Try again in about \(rounded) seconds.")
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Word-level rendering

private struct LyricsQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? (configuration.isPressed ? 0.6 : 0.52) : 0.22))
            .contentShape(Rectangle())
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
        LyricsTokenFlowLayout(lineSpacing: max(6, fontSize * 0.22)) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                LyricsWordFill(
                    text: displayText(for: word, at: index),
                    progress: LyricsPlaybackClock.wordProgress(for: word, at: position),
                    font: .system(size: fontSize, weight: weight, design: .rounded),
                    opacity: opacity
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func displayText(for word: LyricsWord, at index: Int) -> String {
        guard index + 1 < words.count else { return word.text }
        let next = words[index + 1].text
        return word.text + (needsSeparator(after: word.text, before: next) ? " " : "")
    }

    private func needsSeparator(after current: String, before next: String) -> Bool {
        guard let left = current.last, let right = next.first else { return false }
        if isCJK(left) || isCJK(right) { return false }
        if right.isPunctuation || right.isSymbol { return false }
        if left.isPunctuation || left.isSymbol { return left == "," || left == "." || left == "!" || left == "?" }
        return left.isLetter || left.isNumber
    }

    private func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x3040...0x30FF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0x4E00...0x9FFF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
            || (0xFF00...0xFFEF).contains(scalar.value)
    }
}

private struct LyricsWordFill: View {
    var text: String
    var progress: Double
    var font: Font
    var opacity: Double

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.white.opacity(opacity * 0.28))
            .fixedSize()
            .overlay(alignment: .leading) {
                Text(text)
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
        var rows: [[(subview: LayoutSubview, size: CGSize)]] = []
        var currentRow: [(subview: LayoutSubview, size: CGSize)] = []
        var currentWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth > 0, currentWidth + size.width > bounds.width {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0
                rowHeight = 0
            }
            currentRow.append((subview, size))
            currentWidth += size.width
            rowHeight = max(rowHeight, size.height)
        }
        if currentRow.isEmpty == false {
            rows.append(currentRow)
        }

        var y = bounds.minY
        for row in rows {
            let rowWidth = row.reduce(CGFloat.zero) { $0 + $1.size.width }
            let rowHeight = row.reduce(CGFloat.zero) { max($0, $1.size.height) }
            var x = bounds.minX + max(0, (bounds.width - rowWidth) / 2)
            for item in row {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width
            }
            y += rowHeight + lineSpacing
        }
    }
}
#endif
