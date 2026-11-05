#if os(macOS)
import SwiftUI

/// Audune's immersive full-screen Lyrics scene.
///
/// The composition follows an Apple Music-style player: a large, clear album cover and
/// transport on the left, and a left-aligned lyric stage on the right, all sitting over
/// a blurred enlargement of the current artwork.
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

    var body: some View {
        GeometryReader { proxy in
            let metrics = LyricsSceneMetrics(size: proxy.size)
            HStack(alignment: .top, spacing: metrics.columnGap) {
                playerColumn(metrics: metrics)
                    .frame(width: metrics.artworkSide, alignment: .topLeading)

                stage(metrics: metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, metrics.horizontalInset)
            .padding(.top, metrics.topInset)
            .padding(.bottom, metrics.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Player column

    private func playerColumn(metrics: LyricsSceneMetrics) -> some View {
        let titleSize = min(max(metrics.artworkSide * 0.050, 17), 26)
        return VStack(alignment: .leading, spacing: 0) {
            artwork(side: metrics.artworkSide)

            songHeader(titleSize: titleSize)
                .padding(.top, max(18, metrics.artworkSide * 0.085))

            progressBlock
                .padding(.top, max(15, metrics.artworkSide * 0.060))

            transportRow(scale: metrics.artworkSide)
                .padding(.top, max(18, metrics.artworkSide * 0.075))

            Spacer(minLength: 16)

            sourceFooter
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func artwork(side: CGFloat) -> some View {
        let radius = min(max(side * 0.028, 8), 16)
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let artwork = model.nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: max(32, side * 0.22), weight: .light))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: max(18, side * 0.06), y: max(10, side * 0.035))
        .accessibilityLabel(String(localized: "Album artwork"))
        .id(model.lyricsTrackRevision)
        .transition(.opacity)
    }

    private func songHeader(titleSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: max(3, titleSize * 0.14)) {
                Text(displayTitle)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.97))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(displayArtist)
                    .font(.system(size: max(13, titleSize * 0.72), weight: .regular))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            LyricsMoreButton(
                canImport: canImportLyrics,
                localDocumentID: localDocumentID,
                importLyrics: importLyrics,
                retryLyrics: retryLyrics,
                deleteLyrics: deleteLyrics
            )
            .fixedSize()
        }
        .id(model.lyricsTrackRevision)
        .transition(.opacity)
    }

    // MARK: - Playback

    private var progressBlock: some View {
        Group {
            if validDuration {
                VStack(alignment: .leading, spacing: 7) {
                    progressBar
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(timeLabel(displayedPosition))
                            .foregroundStyle(.white.opacity(0.56))
                        Spacer(minLength: 8)
                        Text(remainingLabel)
                            .foregroundStyle(.white.opacity(0.40))
                    }
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Playback position"))
                    .accessibilityValue(playbackAccessibilityValue())
                }
            } else if model.nowPlaying.hasTrack {
                Text(timeLabel(displayedPosition))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.48))
                    .accessibilityLabel(String(localized: "Playback position"))
                    .accessibilityValue(timeLabel(displayedPosition))
            }
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
            let showsKnob = canSeek && (isHoveringProgress || scrubbedFraction != nil)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.17))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white.opacity(canSeek ? 0.94 : 0.72))
                    .frame(width: max(0, width * fraction), height: 4)

                if showsKnob {
                    Circle()
                        .fill(Color.white)
                        .frame(width: scrubbedFraction == nil ? 9 : 12, height: scrubbedFraction == nil ? 9 : 12)
                        .offset(x: min(max(width * fraction - 6, 0), max(width - 12, 0)))
                        .shadow(color: .black.opacity(0.36), radius: 4)
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
            .accessibilityValue(playbackAccessibilityValue())
            .accessibilityAdjustableAction { direction in
                guard canSeek else { return }
                let delta = direction == .increment ? 5.0 : -5.0
                seek(min(max(model.lyricsPositionSeconds + delta, 0), model.nowPlaying.durationSeconds))
            }
        }
        .frame(height: 18)
    }

    private func transportRow(scale: CGFloat) -> some View {
        let secondary = min(max(scale * 0.047, 15), 22)
        let primary = min(max(scale * 0.076, 24), 36)
        return HStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            transportButton(
                symbol: "backward.fill",
                label: String(localized: "Previous Track"),
                size: secondary,
                action: previousTrack
            )
            .frame(maxWidth: .infinity)

            playPauseButton(size: primary)
                .frame(maxWidth: .infinity)

            transportButton(
                symbol: "forward.fill",
                label: String(localized: "Next Track"),
                size: secondary,
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
                .foregroundStyle(.white.opacity(canControlPlayback ? 0.96 : 0.24))
                .frame(width: size * 2.1, height: size * 2.1)
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
                .foregroundStyle(.white.opacity(canControlPlayback ? 0.88 : 0.24))
                .frame(width: size * 2.4, height: size * 2.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(canControlPlayback == false)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var sourceFooter: some View {
        if let document = model.lyricsState.document {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.44))
                    .frame(width: 4, height: 4)
                Text(sourceLabel(for: document))
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.30))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Lyrics source: \(sourceLabel(for: document))"))
        }
    }

    // MARK: - Lyrics stage

    private func stage(metrics: LyricsSceneMetrics) -> some View {
        lyricsContent(metrics: metrics)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(
                shouldReduceMotion ? nil : .easeInOut(duration: IslandMotion.lyricsTrackSeconds),
                value: model.lyricsTrackRevision
            )
            .animation(
                shouldReduceMotion ? nil : .easeInOut(duration: 0.28),
                value: model.lyricsState
            )
    }

    @ViewBuilder
    private func lyricsContent(metrics: LyricsSceneMetrics) -> some View {
        switch model.lyricsState {
        case .local(let document), .found(let document):
            lyricStage(document: document, metrics: metrics)
                .id(document.id)
                .transition(.opacity)
        case .ambiguous(let documents):
            ambiguousChoices(documents, metrics: metrics)
        case .noTrack:
            statusState(
                symbol: "music.note",
                title: String(localized: "Nothing playing"),
                message: String(localized: "Play music to view lyrics."),
                showsRetry: false,
                metrics: metrics
            )
        case .nowPlayingUnavailable:
            statusState(
                symbol: "speaker.slash",
                title: String(localized: "Now Playing unavailable"),
                message: String(localized: "Audune cannot read the current song from the system right now."),
                showsRetry: false,
                metrics: metrics
            )
        case .metadataUnavailable:
            statusState(
                symbol: "questionmark.circle",
                title: String(localized: "Song information is incomplete"),
                message: String(localized: "The current song is missing a title or artist, so lyrics cannot be matched."),
                showsRetry: false,
                metrics: metrics
            )
        case .idle, .identifyingTrack:
            statusState(
                symbol: "music.note.list",
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Identifying the current song."),
                showsRetry: false,
                isLoading: true,
                metrics: metrics
            )
        case .checkingLocal:
            statusState(
                symbol: "music.note.list",
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Checking your imported lyrics."),
                showsRetry: false,
                isLoading: true,
                metrics: metrics
            )
        case .searchingOnline:
            statusState(
                symbol: "globe",
                title: String(localized: "Searching for lyrics"),
                message: String(localized: "Looking for the current song on LRCLIB."),
                showsRetry: false,
                isLoading: true,
                metrics: metrics
            )
        case .loading:
            statusState(
                symbol: "music.note.list",
                title: String(localized: "Finding lyrics"),
                message: String(localized: "Preparing synchronized lyrics."),
                showsRetry: false,
                isLoading: true,
                metrics: metrics
            )
        case .onlineDisabled:
            statusState(
                symbol: "wifi.slash",
                title: String(localized: "Online lyrics are off"),
                message: String(localized: "Turn on Automatic Online Lyrics in Settings, or import an LRC file."),
                showsRetry: false,
                metrics: metrics
            )
        case .instrumental:
            statusState(
                symbol: "waveform",
                title: String(localized: "Instrumental track"),
                message: String(localized: "This song has no lyrics to display."),
                showsRetry: false,
                metrics: metrics
            )
        case .notFound:
            statusState(
                symbol: "text.magnifyingglass",
                title: String(localized: "No lyrics found"),
                message: String(localized: "No matching lyrics were found for this song."),
                showsRetry: true,
                metrics: metrics
            )
        case .offline:
            statusState(
                symbol: "wifi.slash",
                title: String(localized: "You are offline"),
                message: String(localized: "Connect to the internet to search for lyrics."),
                showsRetry: true,
                metrics: metrics
            )
        case .providerUnavailable:
            statusState(
                symbol: "exclamationmark.icloud",
                title: String(localized: "Lyrics service unavailable"),
                message: String(localized: "LRCLIB is not responding right now. Try again in a moment."),
                showsRetry: true,
                metrics: metrics
            )
        case .rateLimited(let retryAfterSeconds):
            statusState(
                symbol: "hourglass",
                title: String(localized: "Too many lyrics requests"),
                message: retryAfterMessage(retryAfterSeconds),
                showsRetry: true,
                metrics: metrics
            )
        case .networkError:
            statusState(
                symbol: "wifi.exclamationmark",
                title: String(localized: "Could not reach the lyrics service"),
                message: String(localized: "Check your connection, then try again."),
                showsRetry: true,
                metrics: metrics
            )
        case .parseError:
            statusState(
                symbol: "doc.text.magnifyingglass",
                title: String(localized: "Lyrics could not be read"),
                message: String(localized: "The lyrics service returned a format Audune cannot display."),
                showsRetry: true,
                metrics: metrics
            )
        case .cancelled:
            statusState(
                symbol: "stop.circle",
                title: String(localized: "Lyrics search stopped"),
                message: String(localized: "Try searching again."),
                showsRetry: true,
                metrics: metrics
            )
        case .importError(let message):
            statusState(
                symbol: "doc.badge.exclamationmark",
                title: String(localized: "Lyrics file could not be imported"),
                message: message,
                showsRetry: false,
                metrics: metrics
            )
        case .error(let message):
            statusState(
                symbol: "exclamationmark.triangle",
                title: String(localized: "Lyrics could not be loaded"),
                message: message,
                showsRetry: true,
                metrics: metrics
            )
        }
    }

    @ViewBuilder
    private func lyricStage(document: LyricsDocument, metrics: LyricsSceneMetrics) -> some View {
        if document.synchronization == .unsynced {
            unsyncedLyrics(document: document, metrics: metrics)
        } else {
            synchronizedLyrics(document: document, metrics: metrics)
        }
    }

    private func synchronizedLyrics(document: LyricsDocument, metrics: LyricsSceneMetrics) -> some View {
        let focusIndex = min(max(model.activeLyricsLineIndex ?? 0, 0), max(document.lines.count - 1, 0))
        let lowerBound = max(0, focusIndex - 2)
        let upperBound = min(max(document.lines.count - 1, 0), focusIndex + 3)

        return VStack(alignment: .leading, spacing: metrics.rowGap) {
            ForEach(Array(lowerBound...upperBound), id: \.self) { index in
                lyricRow(
                    line: document.lines[index],
                    index: index,
                    focusIndex: focusIndex,
                    metrics: metrics
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, max(24, metrics.stageHeight * 0.16))
        .clipped()
    }

    private func lyricRow(
        line: LyricsLine,
        index: Int,
        focusIndex: Int,
        metrics: LyricsSceneMetrics
    ) -> some View {
        let distance = abs(index - focusIndex)
        let isActive = distance == 0
        let opacity = lyricOpacity(distance: distance)
        let translationReveal = contextTranslationOpacity(isActive: isActive, line: line)

        return VStack(alignment: .leading, spacing: max(5, metrics.activeFontSize * 0.16)) {
            Text(line.text)
                .font(.system(size: metrics.activeFontSize, weight: .bold))
                .foregroundStyle(.white.opacity(opacity))
                .lineSpacing(max(2, metrics.activeFontSize * 0.06))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = line.translation, translation.isEmpty == false {
                Text(translation)
                    .font(.system(size: metrics.translationFontSize, weight: .regular))
                    .foregroundStyle(.white.opacity((isActive ? 0.56 : 0.32) * translationReveal * opacity))
                    .lineSpacing(max(2, metrics.translationFontSize * 0.14))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(translationReveal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: line))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func unsyncedLyrics(document: LyricsDocument, metrics: LyricsSceneMetrics) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: max(16, metrics.activeFontSize * 0.66)) {
                ForEach(document.lines) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.text)
                            .font(.system(size: metrics.unsyncedFontSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let translation = line.translation, translation.isEmpty == false {
                            Text(translation)
                                .font(.system(size: metrics.translationFontSize, weight: .regular))
                                .foregroundStyle(.white.opacity(0.42))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.top, max(28, metrics.stageHeight * 0.14))
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Empty, error, and choice states

    private func ambiguousChoices(_ documents: [LyricsDocument], metrics: LyricsSceneMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "Choose the matching local lyrics"))
                    .font(.system(size: metrics.statusTitleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                Text(String(localized: "Several imported files match this song. Pick the version you want to follow."))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.bottom, 6)

                ForEach(documents) { document in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.trackKey.album ?? String(localized: "Unknown Album"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                            Text(syncDescription(for: document))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer()
                        Button {
                            chooseCandidate(document.id)
                        } label: {
                            Text(String(localized: "Use"))
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.9))
                        .accessibilityLabel(String(localized: "Use these lyrics"))

                        Button {
                            deleteLyrics(document.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.42))
                        .accessibilityLabel(String(localized: "Delete imported lyrics"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, max(28, metrics.stageHeight * 0.14))
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private func statusState(
        symbol: String,
        title: String,
        message: String,
        showsRetry: Bool,
        isLoading: Bool = false,
        metrics: LyricsSceneMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 48, height: 48)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 48, height: 48)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.72))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
            .padding(.bottom, 20)

            Text(title)
                .font(.system(size: metrics.statusTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.54))
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .frame(maxWidth: 480, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            if showsRetry || canImportLyrics {
                HStack(spacing: 12) {
                    if showsRetry {
                        Button(action: retryLyrics) {
                            Text(String(localized: "Try Again"))
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 17)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.92), in: Capsule())
                                .foregroundStyle(.black.opacity(0.86))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Search for lyrics again"))
                    }
                    if canImportLyrics {
                        Button(action: importLyrics) {
                            Text(String(localized: "Import LRC"))
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.10), in: Capsule())
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Import a local LRC lyrics file"))
                    }
                }
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, max(30, metrics.stageHeight * 0.20))
        .padding(.bottom, 24)
        .transition(.opacity)
    }

    // MARK: - Derived values

    private var displayTitle: String {
        model.nowPlaying.title.isEmpty ? String(localized: "Unknown Title") : model.nowPlaying.title
    }

    private var displayArtist: String {
        model.nowPlaying.artist.isEmpty ? String(localized: "Unknown Artist") : model.nowPlaying.artist
    }

    private var displayedPosition: TimeInterval {
        if let fraction = scrubbedFraction, validDuration {
            return fraction * model.nowPlaying.durationSeconds
        }
        return model.lyricsPositionSeconds
    }

    private var remainingLabel: String {
        guard validDuration else { return "" }
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

    private var localDocumentID: UUID? {
        if case .local(let document) = model.lyricsState {
            return document.id
        }
        if case .ambiguous(let documents) = model.lyricsState, documents.count == 1 {
            return documents[0].id
        }
        return nil
    }

    private var shouldReduceMotion: Bool {
        reduceMotion && model.prefs.followsReduceMotion
    }

    private func contextTranslationOpacity(isActive: Bool, line: LyricsLine) -> Double {
        guard isActive, shouldReduceMotion == false else { return 1 }
        return LyricsPresentationTiming.translationOpacity(
            lineStartSeconds: line.startSeconds,
            positionSeconds: model.lyricsPositionSeconds
        )
    }

    private func lyricOpacity(distance: Int) -> Double {
        switch distance {
        case 0: return 0.98
        case 1: return 0.52
        case 2: return 0.30
        default: return 0.15
        }
    }

    private func accessibilityLabel(for line: LyricsLine) -> String {
        if let translation = line.translation, translation.isEmpty == false {
            return "\(line.text), \(translation)"
        }
        return line.text
    }

    private func retryAfterMessage(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return String(localized: "Try again in a moment.")
        }
        let rounded = max(1, Int(seconds.rounded(.up)))
        return String(localized: "Try again in about \(rounded) seconds.")
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

    private func playbackAccessibilityValue() -> String {
        guard validDuration else { return timeLabel(displayedPosition) }
        return "\(timeLabel(displayedPosition)) / \(timeLabel(model.nowPlaying.durationSeconds))"
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Metrics

private struct LyricsSceneMetrics {
    var horizontalInset: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat
    var artworkSide: CGFloat
    var columnGap: CGFloat
    var stageHeight: CGFloat
    var activeFontSize: CGFloat
    var translationFontSize: CGFloat
    var unsyncedFontSize: CGFloat
    var statusTitleSize: CGFloat
    var rowGap: CGFloat

    init(size: CGSize) {
        horizontalInset = min(max(size.width * 0.06, 26), 104)
        topInset = min(max(size.height * 0.018, 8), 22)
        bottomInset = min(max(size.height * 0.022, 10), 24)
        stageHeight = max(120, size.height - topInset - bottomInset)

        let availableWidth = max(320, size.width - horizontalInset * 2)
        let gap = min(max(size.width * 0.095, 46), 190)
        let widthDriven = availableWidth * 0.375
        let heightDriven = stageHeight * 0.58
        let maximumStageShare = max(250, availableWidth - gap - 300)
        artworkSide = max(96, min(widthDriven, heightDriven, 620, maximumStageShare))
        columnGap = gap

        let stageWidth = max(220, availableWidth - artworkSide - gap)
        activeFontSize = min(max(stageWidth * 0.082, 26), 56)
        translationFontSize = max(12, activeFontSize * 0.50)
        unsyncedFontSize = max(18, activeFontSize * 0.62)
        statusTitleSize = min(max(stageWidth * 0.050, 22), 32)
        rowGap = max(14, activeFontSize * 0.50)
    }
}

// MARK: - Player accessories

private struct LyricsMoreButton: View {
    var canImport: Bool
    var localDocumentID: UUID?
    var importLyrics: () -> Void
    var retryLyrics: () -> Void
    var deleteLyrics: (UUID) -> Void

    @State private var hovering = false

    var body: some View {
        Menu {
            Button(action: importLyrics) {
                Label(String(localized: "Import LRC"), systemImage: "square.and.arrow.down")
            }
            .disabled(canImport == false)

            Button(action: retryLyrics) {
                Label(String(localized: "Search for lyrics again"), systemImage: "arrow.clockwise")
            }
            .disabled(canImport == false)

            if let localDocumentID {
                Divider()
                Button(role: .destructive) {
                    deleteLyrics(localDocumentID)
                } label: {
                    Label(String(localized: "Delete imported lyrics"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.92 : 0.70))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(hovering ? 0.14 : 0.07))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(String(localized: "Lyrics"))
        .accessibilityLabel(String(localized: "Lyrics"))
    }
}
#endif
