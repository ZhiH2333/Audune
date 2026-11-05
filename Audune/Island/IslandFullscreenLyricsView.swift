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
                    .padding(.top, max(16, metrics.stageHeight * 0.066))

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
        // Apple Music keeps the song title optically large even with a big cover: the
        // title block reads as one unit with the artwork instead of a caption under it.
        let titleSize = min(max(metrics.artworkSide * 0.072, 20), 33)
        return VStack(alignment: .leading, spacing: 0) {
            artwork(side: metrics.artworkSide)

            songHeader(titleSize: titleSize)
                .padding(.top, max(16, metrics.artworkSide * 0.060))

            progressBlock
                .padding(.top, max(18, metrics.artworkSide * 0.086))

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
        .shadow(color: .black.opacity(0.46), radius: max(22, side * 0.075), y: max(12, side * 0.045))
        .accessibilityLabel(String(localized: "Album artwork"))
        .id(model.lyricsTrackRevision)
        .transition(.opacity)
    }

    private func songHeader(titleSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: max(3, titleSize * 0.12)) {
                Text(displayTitle)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.97))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(displayArtist)
                    .font(.system(size: max(13, titleSize * 0.62), weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let album = displayAlbum {
                    Text(album)
                        .font(.system(size: max(11, titleSize * 0.46), weight: .regular))
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, max(1, titleSize * 0.04))
                }
            }

            Spacer(minLength: 4)

            LyricsMoreButton(
                canImport: canImportLyrics,
                canSearch: canSearchLyrics,
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
                            .foregroundStyle(.white.opacity(0.58))
                        Spacer(minLength: 8)
                        Text(remainingLabel)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
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
        LyricsDepthStage(
            document: document,
            activeIndex: model.activeLyricsLineIndex,
            // Word timing is the only thing that needs a per-frame position. Line-synced
            // documents stay visually stable between line changes, which also keeps the
            // blurred stage off the 30 Hz redraw path.
            position: document.synchronization == .wordSynced ? model.lyricsPositionSeconds : 0,
            isPlaying: model.nowPlaying.isPlaying,
            metrics: metrics,
            reduceMotion: shouldReduceMotion
        )
        .equatable()
    }

    private func unsyncedLyrics(document: LyricsDocument, metrics: LyricsSceneMetrics) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: max(16, metrics.activeFontSize * 0.66)) {
                Text(String(localized: "Plain lyrics without timing"))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.40))
                    .padding(.bottom, max(6, metrics.activeFontSize * 0.20))

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
            .padding(.top, max(24, metrics.stageHeight * 0.12))
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.06),
                    .init(color: .white, location: 0.92),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

            if (showsRetry && canSearchLyrics) || canImportLyrics {
                HStack(spacing: 12) {
                    if showsRetry && canSearchLyrics {
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

    private var displayAlbum: String? {
        let album = model.nowPlaying.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return album.isEmpty ? nil : album
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

    /// `retry()` deliberately refuses to issue an online request while the user has
    /// automatic online lyrics switched off. Expose that honestly instead of leaving a
    /// menu item that appears actionable but does nothing.
    private var canSearchLyrics: Bool {
        canImportLyrics
            && model.prefs.automaticOnlineLyricsEnabled
            && model.lyricsState != .onlineDisabled
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

// MARK: - Depth stage

/// A single lyric stage shared by every row. Rows are absolute-positioned around a
/// stable focal line, so changing lines moves the stack as one composition instead of
/// rebuilding a scrolling list. Distance controls blur, opacity, and scale continuously.
private struct LyricsDepthStage: View, Equatable {
    var document: LyricsDocument
    var activeIndex: Int?
    var position: TimeInterval
    var isPlaying: Bool
    var metrics: LyricsSceneMetrics
    var reduceMotion: Bool

    @State private var entrance: CGFloat = 1
    @State private var rowHeights: [Int: CGFloat] = [:]
    @State private var focusTranslationReveal: Double = 1

    private var focusIndex: Int {
        min(max(activeIndex ?? 0, 0), max(document.lines.count - 1, 0))
    }

    private var hasActiveLine: Bool {
        activeIndex != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let count = document.lines.count
            let focus = focusIndex
            let first = max(0, focus - 4)
            let last = min(count - 1, focus + 4)
            let focusTop = proxy.size.height * 0.205
            let currentEntrance = Double(entrance)
            let prefix = prefixHeight(first: first, focus: focus)
            let isReady = rowHeights[focus] != nil && prefix.ready
            // Apple Music keeps the lyric measure comfortably narrower than the whole
            // right column, so long lines never turn into full-window banners.
            let contentWidth = min(proxy.size.width, 820)

            VStack(alignment: .leading, spacing: metrics.rowGap) {
                if count > 0 {
                    ForEach(first...last, id: \.self) { index in
                        lyricRow(
                            line: document.lines[index],
                            index: index,
                            focus: focus,
                            entrance: currentEntrance
                        )
                        .frame(width: contentWidth, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            guard height > 0, rowHeights[index] != height else { return }
                            rowHeights[index] = height
                        }
                        .zIndex(index == focus ? 1 : 0)
                    }
                }
            }
            .frame(width: contentWidth, alignment: .leading)
            .offset(y: focusTop - prefix.height)
            .opacity(isReady ? 1 : 0)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.10),
                        .init(color: .white, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.88),
                value: focusTop - prefix.height
            )
            .animation(.easeOut(duration: 0.12), value: isReady)
        }
        .onAppear {
            restartFocusMotion()
            revealFocusTranslation()
        }
        .onChange(of: focusIndex) { _, _ in
            restartFocusMotion()
            revealFocusTranslation()
        }
        .onChange(of: document.id) {
            rowHeights = [:]
            restartFocusMotion()
            revealFocusTranslation()
        }
    }

    static func == (lhs: LyricsDepthStage, rhs: LyricsDepthStage) -> Bool {
        guard lhs.document == rhs.document,
              lhs.activeIndex == rhs.activeIndex,
              lhs.isPlaying == rhs.isPlaying,
              lhs.metrics == rhs.metrics,
              lhs.reduceMotion == rhs.reduceMotion
        else { return false }
        return lhs.document.synchronization != .wordSynced || lhs.position == rhs.position
    }

    private func prefixHeight(first: Int, focus: Int) -> (height: CGFloat, ready: Bool) {
        guard focus > first else { return (0, true) }
        var height: CGFloat = 0
        var ready = true
        for index in first..<focus {
            if let rowHeight = rowHeights[index] {
                height += rowHeight
            } else {
                height += metrics.activeFontSize * 1.4
                ready = false
            }
            height += metrics.rowGap
        }
        return (height, ready)
    }

    private func lyricRow(
        line: LyricsLine,
        index: Int,
        focus: Int,
        entrance: Double
    ) -> some View {
        let distance = abs(index - focus)
        let isFocus = distance == 0 && hasActiveLine
        // Before the first timed line starts, keep the upcoming line sharp-ish and fade
        // the rest by distance instead of flattening every row to the same blur.
        let visualDistance = hasActiveLine ? distance : min(4, abs(index - focus))
        // AMLL's active line is fully bright while its neighbours sit at 0.2. Audune's
        // backdrop can be brighter than AMLL's, so we keep a little more context: the
        // next line stays readable, then falls away quickly.
        let opacity: Double = {
            if isFocus { return 1 }
            switch visualDistance {
            case 0: return 0.48
            case 1: return 0.32
            case 2: return 0.15
            case 3: return 0.07
            case 4: return 0.03
            default: return 0
            }
        }()
        let blurRadius: CGFloat = reduceMotion
            ? 0
            : min(CGFloat(visualDistance) * 3.4, visualDistance == 0 ? 0 : 8)
        let rowFontSize = metrics.activeFontSize * (isFocus ? 1 : max(0.88, 1 - CGFloat(visualDistance) * 0.026))
        let scale = isFocus
            ? 0.988 + 0.012 * entrance
            : max(0.96, 1 - CGFloat(visualDistance) * 0.012)
        let translationReveal = isFocus ? focusTranslationReveal : 1
        let lineGap = max(5, metrics.activeFontSize * 0.15)
        let activeGlow = isFocus ? 0.18 : 0.0

        return VStack(alignment: .leading, spacing: lineGap) {
            if let words = line.words, words.count >= 2 {
                LyricsTimedWordLine(
                    words: words,
                    lineText: line.text,
                    position: position,
                    fontSize: rowFontSize,
                    weight: .semibold,
                    opacity: opacity,
                    followsPlayback: isFocus,
                    accessibilityLabel: accessibilityLabel(for: line)
                )
            } else {
                Text(line.text)
                    .font(.system(size: rowFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(opacity))
                    .lineSpacing(max(1, rowFontSize * 0.03))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let translation = line.translation, translation.isEmpty == false {
                Text(translation)
                    .font(.system(size: metrics.translationFontSize * (isFocus ? 1 : 0.86), weight: .regular))
                    .foregroundStyle(.white.opacity((isFocus ? 0.62 : 0.26) * (0.70 + 0.30 * opacity) * translationReveal))
                    .lineSpacing(max(2, metrics.translationFontSize * 0.16))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(translationReveal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(activeGlow), radius: 16, y: 2)
        .blur(radius: blurRadius)
        .scaleEffect(scale, anchor: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: line))
        .accessibilityAddTraits(isFocus ? .isSelected : [])
    }

    private func revealFocusTranslation() {
        guard reduceMotion == false, isPlaying else {
            focusTranslationReveal = 1
            return
        }
        focusTranslationReveal = 0
        withAnimation(.easeOut(duration: 0.14)) {
            focusTranslationReveal = 1
        }
    }

    private func accessibilityLabel(for line: LyricsLine) -> String {
        if let translation = line.translation, translation.isEmpty == false {
            return "\(line.text), \(translation)"
        }
        return line.text
    }

    private func restartFocusMotion() {
        guard reduceMotion == false, isPlaying else {
            entrance = 1
            return
        }
        entrance = 0
        withAnimation(.easeOut(duration: IslandMotion.lyricsLineSeconds)) {
            entrance = 1
        }
    }
}

// MARK: - Metrics

private struct LyricsSceneMetrics: Equatable {
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
        activeFontSize = min(max(stageWidth * 0.085, 28), 70)
        translationFontSize = min(max(activeFontSize * 0.42, 14), 30)
        unsyncedFontSize = min(max(activeFontSize * 0.62, 18), 38)
        statusTitleSize = min(max(stageWidth * 0.050, 22), 32)
        rowGap = max(14, activeFontSize * 0.50)
    }
}

// MARK: - Player accessories

private struct LyricsMoreButton: View {
    var canImport: Bool
    var canSearch: Bool
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
            .disabled(canSearch == false)

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
        .help(String(localized: "Controls"))
        .accessibilityLabel(String(localized: "Controls"))
    }
}

// MARK: - Word fill

/// A word-timed lyric row. Every token occupies the same fixed slot whether or not it
/// has been sung, so the text never reflows as playback advances. Only the mask grows.
private struct LyricsTimedWordLine: View {
    var words: [LyricsWord]
    var lineText: String
    var position: TimeInterval
    var fontSize: CGFloat
    var weight: Font.Weight
    var opacity: Double
    var followsPlayback: Bool
    var accessibilityLabel: String

    /// Word timings trim whitespace, so the display strings have to be rebuilt from the
    /// original line. Without this an English word split by the timing source (e.g.
    /// "aval" + "anche") would render as two words and could wrap mid-word.
    private var tokens: [String] {
        rebuiltTokens() ?? fallbackTokens()
    }

    /// Tokens that must stay on one line together. Latin word fragments separated by a
    /// timing boundary share a run; CJK characters and whitespace remain break points.
    private var runs: [[Int]] {
        guard words.isEmpty == false else { return [] }
        var result: [[Int]] = []
        var current: [Int] = [0]
        for index in 1..<words.count {
            if canBreak(after: tokens[index - 1], before: tokens[index]) {
                result.append(current)
                current = [index]
            } else {
                current.append(index)
            }
        }
        result.append(current)
        return result
    }

    var body: some View {
        LyricsTokenFlowLayout(lineSpacing: max(4, fontSize * 0.14)) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(run, id: \.self) { index in
                        LyricsWordFill(
                            text: tokens[index],
                            progress: progress(for: words[index]),
                            font: .system(size: fontSize, weight: weight),
                            opacity: opacity,
                            glow: followsPlayback
                        )
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func progress(for word: LyricsWord) -> Double {
        guard followsPlayback else { return 1 }
        return LyricsPlaybackClock.wordProgress(for: word, at: position)
    }

    /// Greedily aligns each timed token with the original line so the gaps between them
    /// (spaces, commas, hyphens) are preserved exactly.
    private func rebuiltTokens() -> [String]? {
        let text = lineText
        guard text.isEmpty == false, words.isEmpty == false else { return nil }
        var result = words.map(\.text)
        var cursor = text.startIndex
        for index in words.indices {
            let token = words[index].text
            guard token.isEmpty == false,
                  let range = text.range(of: token, range: cursor..<text.endIndex)
            else { return nil }
            if range.lowerBound > cursor {
                let gap = String(text[cursor..<range.lowerBound])
                if index == 0 {
                    result[0] = gap + result[0]
                } else {
                    result[index - 1] += gap
                }
            }
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result[result.count - 1] += String(text[cursor...])
        }
        return result
    }

    private func fallbackTokens() -> [String] {
        words.enumerated().map { index, word in
            guard index + 1 < words.count else { return word.text }
            let next = words[index + 1].text
            return word.text + (needsSeparator(after: word.text, before: next) ? " " : "")
        }
    }

    private func needsSeparator(after current: String, before next: String) -> Bool {
        guard let left = current.last, let right = next.first else { return false }
        if isCJK(left) || isCJK(right) { return false }
        if right.isPunctuation || right.isSymbol { return false }
        if "([{“‘'’-‐".contains(left) { return false }
        return true
    }

    private func canBreak(after current: String, before next: String) -> Bool {
        guard let left = current.last, let right = next.first else { return true }
        if left.isWhitespace { return true }
        if isCJK(left) || isCJK(right) { return true }
        if left.isPunctuation || left.isSymbol { return true }
        return false
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

/// Two identical text layers keep the token's measured width stable: the lower layer is
/// the unsung state, while the upper layer is revealed left-to-right by a time mask.
/// The mask has a feathered leading edge and a soft glow, matching the Apple Music /
/// AMLL karaoke sweep instead of a hard typewriter cut.
private struct LyricsWordFill: View {
    var text: String
    var progress: Double
    var font: Font
    var opacity: Double
    var glow: Bool

    private var isCurrentWord: Bool {
        glow && progress > 0 && progress < 1
    }

    var body: some View {
        Group {
            if progress >= 1 {
                sungText
            } else if progress <= 0 {
                unsungText
            } else {
                unsungText.overlay(alignment: .leading) {
                    sungText
                        .mask(alignment: .leading) {
                            LyricsWordFillMask(progress: progress)
                        }
                        .shadow(
                            color: .white.opacity(glow ? 0.38 : 0),
                            radius: glow ? 9 : 0
                        )
                }
            }
        }
        .offset(y: isCurrentWord ? -1.5 : 0)
        .animation(.easeOut(duration: 0.14), value: isCurrentWord)
    }

    private var sungText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.white.opacity(opacity))
            .fixedSize()
    }

    private var unsungText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.white.opacity(opacity * 0.36))
            .fixedSize()
    }
}

/// A left-to-right reveal mask whose last few points fade out. The feather keeps the
/// karaoke edge luminous on thin Latin strokes and avoids a visible stair-step on CJK.
private struct LyricsWordFillMask: View {
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let filled = width * min(max(progress, 0), 1)
            let feather = max(4, min(14, width * 0.22))

            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: max(0, (filled - feather) / width)),
                    .init(color: .white.opacity(0.55), location: min(1, filled / width)),
                    .init(color: .clear, location: min(1, (filled + feather) / width))
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

/// Wraps word tokens from a stable left edge. The default `Text` wrapping cannot expose
/// per-word frames, and measuring each token once keeps every playback update layout-free.
private struct LyricsTokenFlowLayout: Layout {
    var lineSpacing: CGFloat = 6

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

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth > 0, currentWidth + size.width > bounds.width {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0
            }
            currentRow.append((subview, size))
            currentWidth += size.width
        }
        if currentRow.isEmpty == false {
            rows.append(currentRow)
        }

        var y = bounds.minY
        for row in rows {
            let rowHeight = row.reduce(CGFloat.zero) { max($0, $1.size.height) }
            var x = bounds.minX
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
