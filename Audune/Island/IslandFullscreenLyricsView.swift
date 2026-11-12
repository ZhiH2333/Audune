#if os(macOS)
import AppKit
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
    var setLyricsOffset: (Double) -> Void
    var selectLyricsRouting: (LyricsRoutingSelection) -> Void = { _ in }
    var searchCandidates: (String?, String?, String?, String?) async -> [LyricsScoredCandidate] = { _, _, _, _ in [] }
    var applyCandidate: (LyricsDocument, Bool) -> Void = { _, _ in }
    @Binding var isLyricsPickerPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isManualBrowsing = false
    @State private var routingSelection = LyricsRoutingController.shared.selection
    @State private var healthSnapshots: [LyricsNodeHealthSnapshot] = []

    var body: some View {
        GeometryReader { proxy in
            let metrics = LyricsSceneMetrics(size: proxy.size)
            Group {
                if metrics.isCompact {
                    compactBody(metrics: metrics)
                } else {
                    splitBody(metrics: metrics)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["AUDUNE_LYRICS_PICKER_PREVIEW"] == "1" {
                isLyricsPickerPresented = true
            }
            #endif
        }
        .onChange(of: model.lyricsTrackRevision) {
            isLyricsPickerPresented = false
        }
    }

    private func splitBody(metrics: LyricsSceneMetrics) -> some View {
        HStack(alignment: .top, spacing: metrics.columnGap) {
            playerColumn(metrics: metrics)
                .frame(width: metrics.artworkSide, alignment: .topLeading)
                .padding(.top, max(16, metrics.stageHeight * 0.066))

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, metrics.horizontalInset)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: "lyricsSplit")
        .overlayPreferenceValue(LyricsPlayerGeometryPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let artworkAnchor = anchors.artwork,
                   let pauseAnchor = anchors.pauseButton {
                    let artwork = proxy[artworkAnchor]
                    let pauseButton = proxy[pauseAnchor]
                    let stageTop = max(0, artwork.minY - 12)
                    let stageBottom = min(proxy.size.height, pauseButton.maxY + 12)
                    let stageX = metrics.horizontalInset + metrics.artworkSide + metrics.columnGap
                    let stageWidth = max(0, proxy.size.width - stageX - metrics.horizontalInset)

                    stage(metrics: metrics)
                        .frame(width: stageWidth, height: max(0, stageBottom - stageTop))
                        .position(
                            x: stageX + stageWidth / 2,
                            y: stageTop + max(0, stageBottom - stageTop) / 2
                        )
                }
            }
        }
    }

    /// Short or narrow windows use a stacked player header: the Apple Music composition
    /// no longer has enough vertical room for a full cover column, so the cover shrinks
    /// to a compact tile and the lyric stage takes the space underneath.
    private func compactBody(metrics: LyricsSceneMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            compactHeader(metrics: metrics)

            HStack(alignment: .center, spacing: max(14, metrics.horizontalInset * 0.5)) {
                if validDuration {
                    progressBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // No duration means no progress bar. Keep the transport anchored to
                    // the trailing edge instead of collapsing it under the artwork.
                    progressBlock
                    Spacer(minLength: 12)
                }

                compactTransport(metrics: metrics)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            stage(metrics: metrics)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, metrics.horizontalInset)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private func compactHeader(metrics: LyricsSceneMetrics) -> some View {
        let titleSize = min(max(metrics.artworkSide * 0.27, 18), 24)
        return HStack(alignment: .top, spacing: 14) {
            artwork(side: metrics.artworkSide)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.97))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)

                Text(displayArtist)
                    .font(.system(size: max(12, titleSize * 0.62), weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let album = displayAlbum {
                    Text(album)
                        .font(.system(size: max(10, titleSize * 0.48), weight: .regular))
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 2)

                sourceFooter
            }
            .frame(height: metrics.artworkSide, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.nowPlaying.hasTrack {
                LyricsOffsetButton(
                    offset: model.prefs.lyricsOffsetSeconds,
                    onChange: setLyricsOffset
                )
                .fixedSize()
            }

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

    private func compactTransport(metrics: LyricsSceneMetrics) -> some View {
        let secondary = min(max(metrics.artworkSide * 0.19, 14), 17)
        let primary = min(max(metrics.artworkSide * 0.27, 20), 25)
        return HStack(spacing: 4) {
            transportButton(
                symbol: "backward.fill",
                label: String(localized: "Previous Track"),
                size: secondary,
                action: previousTrack
            )

            playPauseButton(size: primary)

            transportButton(
                symbol: "forward.fill",
                label: String(localized: "Next Track"),
                size: secondary,
                action: nextTrack
            )
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
        let isPlaying = model.nowPlaying.isPlaying && model.nowPlaying.hasTrack
        let artScale = LyricsPresentationTiming.artworkScale(
            isPlaying: isPlaying,
            reduceMotion: shouldReduceMotion
        )
        return ZStack {
            ZStack {
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
            .shadow(
                color: .black.opacity(isPlaying ? 0.48 : 0.24),
                radius: isPlaying ? max(22, side * 0.075) : max(12, side * 0.042),
                y: isPlaying ? max(12, side * 0.045) : max(6, side * 0.022)
            )
            .scaleEffect(artScale)
            .animation(
                shouldReduceMotion ? nil : .spring(response: 0.50, dampingFraction: 0.74),
                value: isPlaying
            )
        }
        .frame(width: side, height: side)
        .anchorPreference(key: LyricsPlayerGeometryPreferenceKey.self, value: .bounds) {
            .init(artwork: $0)
        }
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

            if model.nowPlaying.hasTrack {
                LyricsOffsetButton(
                    offset: model.prefs.lyricsOffsetSeconds,
                    onChange: setLyricsOffset
                )
                .fixedSize()
            }

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
        LyricsProgressSection(
            model: model,
            shouldReduceMotion: shouldReduceMotion,
            seek: seek
        )
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
        .anchorPreference(key: LyricsPlayerGeometryPreferenceKey.self, value: .bounds) {
            .init(pauseButton: $0)
        }
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
        HStack(spacing: 6) {
            lyricsSourceSelector

            if let document = model.lyricsState.document {
                if let url = attributionURL(for: document) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.26))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .help(sourceLabel(for: document))
                    .accessibilityLabel(String(localized: "Lyrics source: \(sourceLabel(for: document))"))
                }

                if document.hasTranslations {
                    tierTogglePill(
                        symbol: "character.bubble",
                        isOn: model.prefs.showsLyricsTranslation,
                        action: { model.prefs.showsLyricsTranslation.toggle() }
                    )
                }
                if document.hasPronunciations {
                    tierTogglePill(
                        symbol: "a.magnify",
                        isOn: model.prefs.showsLyricsPronunciation,
                        action: { model.prefs.showsLyricsPronunciation.toggle() }
                    )
                }
            }
        }
        .task {
            routingSelection = LyricsRoutingController.shared.selection
            await LyricsRoutingController.shared.refreshHealthSnapshots()
            healthSnapshots = LyricsRoutingController.shared.healthSnapshots
        }
    }

    private func tierTogglePill(
        symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 0.86 : 0.36))
                .frame(width: 24, height: 22)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isOn ? 0.14 : 0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isOn ? 0.16 : 0.05), lineWidth: 0.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var lyricsSourceSelector: some View {
        Menu {
            Button {
                applyRouting(.init(mode: .autoFastestReliable, providerID: nil, nodeID: nil))
            } label: {
                selectionLabel(
                    LyricsRoutingMode.autoFastestReliable.displayName,
                    selected: routingSelection.mode == .autoFastestReliable
                )
            }
            Button {
                applyRouting(.init(mode: .autoBestMatch, providerID: nil, nodeID: nil))
            } label: {
                selectionLabel(
                    LyricsRoutingMode.autoBestMatch.displayName,
                    selected: routingSelection.mode == .autoBestMatch
                )
            }

            Divider()

            Section(String(localized: "Aggregators")) {
                ForEach(selectableProviders(type: .aggregator)) { provider in
                    providerMenu(provider)
                }
            }
            Section(String(localized: "International")) {
                ForEach(selectableProviders(region: .international, excludingAggregators: true)) { provider in
                    providerMenu(provider)
                }
            }
            Section(String(localized: "China")) {
                ForEach(selectableProviders(region: .china, excludingAggregators: true)) { provider in
                    providerMenu(provider)
                }
            }

            Divider()

            Button {
                withAnimation(shouldReduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
                    isLyricsPickerPresented = true
                }
            } label: {
                Label(String(localized: "Advanced Settings"), systemImage: "slider.horizontal.3")
            }
            .help(String(localized: "Open advanced lyrics picker"))
            .accessibilityLabel(String(localized: "Open advanced lyrics picker"))
        } label: {
            HStack(spacing: 4) {
                Text(routingMenuTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.50))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(String(localized: "Choose lyrics source"))
        .accessibilityLabel(String(localized: "Lyrics source selector"))
    }

    @ViewBuilder
    private func providerMenu(_ provider: LyricsProviderCapability) -> some View {
        let nodes = provider.defaultNodes.filter(\.enabled)
        if nodes.count > 1 {
            Menu(provider.displayName) {
                Button {
                    applyRouting(.init(mode: .manual, providerID: provider.id, nodeID: nil))
                } label: {
                    selectionLabel(
                        String(localized: "Auto Node"),
                        selected: routingSelection.mode == .manual
                            && routingSelection.providerID == provider.id
                            && routingSelection.nodeID == nil
                    )
                }
                ForEach(nodes) { node in
                    Button {
                        applyRouting(.init(mode: .manual, providerID: provider.id, nodeID: node.id))
                    } label: {
                        selectionLabel(
                            nodeLabel(provider: provider, node: node),
                            selected: routingSelection.mode == .manual
                                && routingSelection.providerID == provider.id
                                && routingSelection.nodeID == node.id
                        )
                    }
                }
            }
        } else {
            Button {
                applyRouting(
                    .init(
                        mode: .manual,
                        providerID: provider.id,
                        nodeID: nodes.first?.id
                    )
                )
            } label: {
                selectionLabel(
                    providerLabel(provider),
                    selected: routingSelection.mode == .manual
                        && routingSelection.providerID == provider.id
                )
            }
        }
    }

    private func selectionLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func applyRouting(_ selection: LyricsRoutingSelection) {
        routingSelection = selection
        selectLyricsRouting(selection)
    }

    private var routingMenuTitle: String {
        switch routingSelection.mode {
        case .autoFastestReliable, .autoBestMatch:
            return routingSelection.mode.displayName
        case .manual:
            if let id = routingSelection.providerID,
               let provider = LyricsProviderRegistry.capability(id: id)
            {
                if let nodeID = routingSelection.nodeID,
                   let node = provider.defaultNodes.first(where: { $0.id == nodeID })
                {
                    return "\(provider.displayName) · \(node.displayName)"
                }
                return provider.displayName
            }
            return String(localized: "Manual")
        }
    }

    private func selectableProviders(
        type: LyricsProviderType? = nil,
        region: LyricsProviderRegionHint? = nil,
        excludingAggregators: Bool = false
    ) -> [LyricsProviderCapability] {
        LyricsProviderRegistry.selectableProviders.filter { provider in
            if let type, provider.providerType != type { return false }
            if excludingAggregators, provider.providerType == .aggregator { return false }
            if let region, provider.region != region, provider.region != .global { return false }
            return true
        }
    }

    private func providerLabel(_ provider: LyricsProviderCapability) -> String {
        let sync = provider.highestSyncLevel.rawValue
        return "\(provider.displayName) · \(sync)"
    }

    private func nodeLabel(provider: LyricsProviderCapability, node: LyricsNodeDescriptor) -> String {
        if let snap = healthSnapshots.first(where: { $0.nodeID == node.id }),
           let latency = snap.ewmaLatencySeconds
        {
            let latencyText = latency < 1
                ? String(format: "%.0fms", latency * 1000)
                : String(format: "%.1fs", latency)
            return "\(node.displayName) · \(latencyText) · \(snap.state.rawValue)"
        }
        return "\(node.displayName) · \(provider.highestSyncLevel.rawValue)"
    }

    private func attributionURL(for document: LyricsDocument) -> URL? {
        if let raw = document.source?.attributionURL, let url = URL(string: raw) {
            return url
        }
        if let providerID = document.source?.resolvedProviderID,
           let url = LyricsProviderRegistry.capability(id: providerID)?.attributionURL
        {
            return url
        }
        return nil
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
                message: nil,
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
        let lyricsOffsetSeconds = model.prefs.lyricsOffsetSeconds
        let seekSupported = model.nowPlaying.seekSupported

        return LyricsDepthStage(
            document: document,
            activeIndex: model.activeLyricsLineIndex,
            isPlaying: model.nowPlaying.isPlaying,
            clockAnchor: model.nowPlaying.playbackClockAnchor,
            playbackRate: model.nowPlaying.playbackRate,
            durationSeconds: model.nowPlaying.durationSeconds,
            interlude: model.isLyricsInterlude,
            introWait: model.isLyricsIntroWait,
            metrics: metrics,
            reduceMotion: shouldReduceMotion,
            blurLyrics: model.prefs.lyricsBlurEnabled,
            showsTranslation: model.prefs.showsLyricsTranslation,
            showsPronunciation: model.prefs.showsLyricsPronunciation,
            isSeekSupported: seekSupported,
            lyricsOffsetSeconds: lyricsOffsetSeconds,
            onManualModeChange: { isManualBrowsing = $0 },
            onSeekLine: { line in
                guard LyricsPlaybackClock.canSeek(
                    to: line,
                    isSeekSupported: seekSupported
                ),
                let start = line.startSeconds
                else { return false }
                seek(
                    LyricsPlaybackClock.playbackPosition(
                        forPresentationTime: start,
                        offsetSeconds: lyricsOffsetSeconds
                    )
                )
                return true
            }
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
                    let alignTrailing = line.isSecondaryVocal
                    VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 6) {
                        if model.prefs.showsLyricsPronunciation,
                           let pronunciation = line.pronunciation,
                           pronunciation.isEmpty == false
                        {
                            Text(pronunciation)
                                .font(.system(size: max(12, metrics.translationFontSize * 0.88), weight: .medium))
                                .foregroundStyle(.white.opacity(0.46))
                                .multilineTextAlignment(alignTrailing ? .trailing : .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(line.text)
                            .font(.system(size: metrics.unsyncedFontSize, weight: .bold))
                            .foregroundStyle(.white.opacity(0.86))
                            .multilineTextAlignment(alignTrailing ? .trailing : .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let bg = line.backgroundText, bg.isEmpty == false {
                            Text(formattedBackgroundVocal(bg))
                                .font(.system(size: max(13, metrics.translationFontSize * 0.94), weight: .semibold))
                                .foregroundStyle(.white.opacity(0.52))
                                .multilineTextAlignment(alignTrailing ? .trailing : .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if model.prefs.showsLyricsTranslation,
                           let translation = line.translation,
                           translation.isEmpty == false
                        {
                            Text(translation)
                                .font(.system(size: metrics.translationFontSize, weight: .regular))
                                .foregroundStyle(.white.opacity(0.42))
                                .multilineTextAlignment(alignTrailing ? .trailing : .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
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
        message: String?,
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

            if let message, message.isEmpty == false {
                Text(message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.54))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .frame(maxWidth: 480, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }

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

    private func formattedBackgroundVocal(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
            || (trimmed.hasPrefix("（") && trimmed.hasSuffix("）"))
        {
            return trimmed
        }
        return "(\(trimmed))"
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
            let name = document.source?.providerName ?? String(localized: "LRCLIB")
            return String(localized: "Lyrics by \(name)")
        case .online:
            let provider = document.source?.providerName
                ?? document.source?.resolvedProviderID
                ?? String(localized: "Lyrics")
            if let upstream = document.source?.upstreamProviderID, upstream.isEmpty == false {
                return String(localized: "Lyrics via \(provider) · \(upstream)")
            }
            return String(localized: "Lyrics by \(provider)")
        case nil:
            if let name = document.source?.providerName {
                return String(localized: "Lyrics by \(name)")
            }
            return String(localized: "Lyrics")
        }
    }

    private func syncDescription(for document: LyricsDocument) -> String {
        switch document.synchronization {
        case .syllableSynced:
            return String(localized: "Syllable-synchronized lyrics")
        case .wordSynced:
            return String(localized: "Word-by-word synchronized lyrics")
        case .lineSynced:
            return String(localized: "Line-synchronized lyrics")
        case .unsynced:
            return String(localized: "Plain lyrics without timing")
        }
    }
}

/// Isolated playback progress view so position updates only invalidate the progress bar
/// and time labels, never the full-screen lyrics stage.
private struct LyricsProgressSection: View {
    @Bindable var model: IslandModel
    var shouldReduceMotion: Bool
    var seek: (Double) -> Void

    @State private var scrubbedFraction: Double?
    @State private var isHoveringProgress = false

    private var validDuration: Bool {
        model.nowPlaying.durationSeconds.isFinite && model.nowPlaying.durationSeconds > 0
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

    var body: some View {
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
            let canSeek = model.nowPlaying.seekSupported && validDuration
            let isExpandedTrack = canSeek && (isHoveringProgress || scrubbedFraction != nil)
            let trackHeight: CGFloat = isExpandedTrack ? 7 : 4

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: model.nowPlaying.isPlaying == false || scrubbedFraction != nil)) { _ in
                let livePos = model.nowPlaying.isPlaying
                    ? LyricsPlaybackClock.position(
                        anchor: model.nowPlaying.playbackClockAnchor,
                        isPlaying: model.nowPlaying.isPlaying,
                        playbackRate: model.nowPlaying.playbackRate,
                        durationSeconds: model.nowPlaying.durationSeconds,
                        nowUptime: ProcessInfo.processInfo.systemUptime
                    )
                    : model.lyricsPositionSeconds
                let actual = LyricsPlaybackClock.progress(
                    position: livePos,
                    duration: model.nowPlaying.durationSeconds
                ) ?? 0
                let fraction = min(max(scrubbedFraction ?? actual, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(isExpandedTrack ? 0.24 : 0.17))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(Color.white.opacity(isExpandedTrack ? 1.0 : (canSeek ? 0.90 : 0.72)))
                        .frame(width: max(0, width * fraction), height: trackHeight)
                        .shadow(
                            color: .white.opacity(isExpandedTrack ? 0.30 : 0),
                            radius: isExpandedTrack ? 6 : 0
                        )
                }
                .frame(height: 18)
            }
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
            .animation(
                shouldReduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.76),
                value: isExpandedTrack
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

private struct LyricsPlayerGeometryPreferenceKey: PreferenceKey {
    struct Value {
        var artwork: Anchor<CGRect>?
        var pauseButton: Anchor<CGRect>?
    }

    static var defaultValue = Value()

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        value.artwork = next.artwork ?? value.artwork
        value.pauseButton = next.pauseButton ?? value.pauseButton
    }
}

// MARK: - Depth stage

/// A single native scroll view keeps every lyric row in a stable layout while focus
/// changes animate the viewport to the active line.
private struct LyricsDepthStage: View, Equatable {
    var document: LyricsDocument
    var activeIndex: Int?
    var isPlaying: Bool
    var clockAnchor: PlaybackClockAnchor
    var playbackRate: Double
    var durationSeconds: Double
    var interlude: Bool
    var introWait: Bool = false
    var metrics: LyricsSceneMetrics
    var reduceMotion: Bool
    var blurLyrics: Bool
    var showsTranslation: Bool = true
    var showsPronunciation: Bool = true
    var isSeekSupported: Bool = false
    var lyricsOffsetSeconds: Double = 0
    var onManualModeChange: (Bool) -> Void = { _ in }
    var onSeekLine: ((LyricsLine) -> Bool)? = nil

    @State private var rowHeights: [Int: CGFloat] = [:]
    @State private var focusTranslationReveal: Double = 1
    @State private var cascadeOffset: CGFloat = 0
    @State private var hoveredLineIndex: Int?
    @State private var isManualScrolling = false
    @State private var hasUserScrolled = false
    @State private var autoResumeTask: Task<Void, Never>?
    @State private var lastResumeScheduleUptime: TimeInterval = 0
    @State private var lastFocusChangeUptime: TimeInterval = 0
    @State private var isRapidFocusCadence = false
    @State private var lastWheelScrollUptime: TimeInterval = 0

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
            let focusTop = proxy.size.height * metrics.focusFraction
            let isReady = rowHeights[focus] != nil
            // Apple Music keeps the lyric measure comfortably narrower than the whole
            // right column, so long lines never turn into full-window banners.
            // Reserve horizontal inset inside the ScrollView so the large rounded hover
            // selection pill and 1.06 visual scale never clip against the scroll view edge.
            let pillHInset: CGFloat = metrics.isCompact ? 24 : 32
            let pillVInset: CGFloat = metrics.isCompact ? 16 : 22
            let contentWidth = min(max(180, proxy.size.width * 0.86 - pillHInset), metrics.isCompact ? 720 : 780)
            let effectiveRowGap = max(2, metrics.rowGap - pillVInset * 1.35)

            ScrollViewReader { reader in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView(.vertical) {
                        VStack(spacing: effectiveRowGap) {
                            Color.clear
                                .frame(height: max(0, focusTop - pillVInset))
                                .accessibilityHidden(true)

                            ForEach(0..<count, id: \.self) { index in
                                let line = document.lines[index]
                                let canSeekLine = LyricsPlaybackClock.canSeek(
                                    to: line,
                                    isSeekSupported: isSeekSupported
                                ) && onSeekLine != nil
                                Button {
                                    seekToLine(index: index)
                                } label: {
                                    lyricRow(
                                        line: line,
                                        index: index,
                                        focus: focus,
                                        isInterlude: interlude && index == focus,
                                        manualMode: isManualScrolling,
                                        isHovered: hoveredLineIndex == index,
                                        contentWidth: contentWidth,
                                        pillHInset: pillHInset,
                                        pillVInset: pillVInset
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(canSeekLine == false)
                                .onHover { hovering in
                                    let now = ProcessInfo.processInfo.systemUptime
                                    // Suppress hover churn while rows are actively moving under a stationary cursor.
                                    if hovering, now - lastWheelScrollUptime < 0.16 {
                                        return
                                    }
                                    if hovering {
                                        if hoveredLineIndex != index {
                                            hoveredLineIndex = index
                                        }
                                    } else if hoveredLineIndex == index {
                                        hoveredLineIndex = nil
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                                .onGeometryChange(for: CGFloat.self) { geometry in
                                    geometry.size.height
                                } action: { height in
                                    guard height > 0 else { return }
                                    if let existing = rowHeights[index], abs(existing - height) < 0.5 {
                                        return
                                    }
                                    rowHeights[index] = height
                                }
                                .accessibilityLabel(accessibilityLabel(for: line))
                            }

                            Color.clear
                                .frame(height: max(0, proxy.size.height - focusTop))
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .opacity(isReady ? 1 : 0)
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
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollToFocus(reader, focus: focusIndex, viewportHeight: proxy.size.height, focusTop: focusTop)
                        }
                    }
                    .onChange(of: focus) { oldFocus, newFocus in
                        let now = ProcessInfo.processInfo.systemUptime
                        let dt = lastFocusChangeUptime > 0 ? (now - lastFocusChangeUptime) : .infinity
                        lastFocusChangeUptime = now
                        let rapid = dt < 0.24
                        if isRapidFocusCadence != rapid {
                            isRapidFocusCadence = rapid
                        }
                        if rapid {
                            if focusTranslationReveal != 1 { focusTranslationReveal = 1 }
                            if cascadeOffset != 0 { cascadeOffset = 0 }
                        } else {
                            revealFocusTranslation()
                            triggerCascadeSpring(from: oldFocus, to: newFocus)
                        }
                        guard isManualScrolling == false else { return }
                        scrollToFocus(
                            reader,
                            focus: newFocus,
                            viewportHeight: proxy.size.height,
                            focusTop: focusTop,
                            animated: true,
                            rapid: rapid
                        )
                    }
                    .onChange(of: isManualScrolling) { _, isBrowsing in
                        guard isBrowsing == false else { return }
                        scrollToFocus(reader, focus: focusIndex, viewportHeight: proxy.size.height, focusTop: focusTop, animated: true)
                    }
                    .onChange(of: isReady) { _, ready in
                        guard ready, isManualScrolling == false else { return }
                        scrollToFocus(
                            reader,
                            focus: focus,
                            viewportHeight: proxy.size.height,
                            focusTop: focusTop,
                            animated: false
                        )
                    }
                    .auduneOnScrollPhaseChange(
                        onActive: {
                            lastWheelScrollUptime = ProcessInfo.processInfo.systemUptime
                            if hoveredLineIndex != nil { hoveredLineIndex = nil }
                            beginManualBrowsing()
                            scheduleAutoResume(force: true)
                        },
                        onIdleWhileManual: {
                            guard isManualScrolling else { return }
                            scheduleAutoResume(force: true)
                        }
                    )

                    if isManualScrolling {
                        resumeButton(metrics: metrics)
                            .padding(metrics.isCompact ? 12 : 20)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomTrailing)
                .overlay {
                    LyricsScrollMonitor {
                        lastWheelScrollUptime = ProcessInfo.processInfo.systemUptime
                        if hoveredLineIndex != nil { hoveredLineIndex = nil }
                        beginManualBrowsing()
                        scheduleAutoResume(force: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            revealFocusTranslation()
            #if DEBUG
            if ProcessInfo.processInfo.environment["AUDUNE_LYRICS_MANUAL_PREVIEW"] == "1",
               isManualScrolling == false {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    hoveredLineIndex = focusIndex
                    beginManualBrowsing()
                }
            }
            #endif
        }
        .onChange(of: document.id) {
            autoResumeTask?.cancel()
            autoResumeTask = nil
            rowHeights = [:]
            cascadeOffset = 0
            hoveredLineIndex = nil
            isManualScrolling = false
            hasUserScrolled = false
            lastFocusChangeUptime = 0
            isRapidFocusCadence = false
            revealFocusTranslation()
            onManualModeChange(false)
        }
        .onDisappear {
            autoResumeTask?.cancel()
            autoResumeTask = nil
            if isManualScrolling {
                isManualScrolling = false
                onManualModeChange(false)
            }
        }
    }

    static func == (lhs: LyricsDepthStage, rhs: LyricsDepthStage) -> Bool {
        lhs.document == rhs.document
            && lhs.activeIndex == rhs.activeIndex
            && lhs.isPlaying == rhs.isPlaying
            && lhs.playbackRate == rhs.playbackRate
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.interlude == rhs.interlude
            && lhs.introWait == rhs.introWait
            && lhs.metrics == rhs.metrics
            && lhs.reduceMotion == rhs.reduceMotion
            && lhs.blurLyrics == rhs.blurLyrics
            && lhs.showsTranslation == rhs.showsTranslation
            && lhs.showsPronunciation == rhs.showsPronunciation
            && lhs.isSeekSupported == rhs.isSeekSupported
            && lhs.lyricsOffsetSeconds == rhs.lyricsOffsetSeconds
    }

    private func scrollToFocus(
        _ reader: ScrollViewProxy,
        focus: Int,
        viewportHeight: CGFloat,
        focusTop: CGFloat,
        animated: Bool = false,
        rapid: Bool = false
    ) {
        guard document.lines.indices.contains(focus) else { return }
        let rowHeight = rowHeights[focus] ?? metrics.activeFontSize * 1.4
        let anchorY = focusTop / max(1, viewportHeight - rowHeight)
        let anchor = UnitPoint(x: 0, y: min(max(anchorY, 0), 1))
        let scroll = {
            reader.scrollTo(focus, anchor: anchor)
        }
        if animated, reduceMotion == false {
            let animation: Animation = rapid
                ? .easeOut(duration: 0.14)
                : .timingCurve(0.175, 0.885, 0.32, 1.1, duration: 0.6)
            withAnimation(
                animation,
                scroll
            )
        } else {
            scroll()
        }
    }

    /// Keep the native ScrollView mounted while the user browses so its content offset
    /// and scroll physics continue from the exact position reached by automatic follow.
    private func beginManualBrowsing() {
        guard document.lines.count > 1, isManualScrolling == false else { return }
        autoResumeTask?.cancel()
        autoResumeTask = nil
        hasUserScrolled = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isManualScrolling = true
        }
        onManualModeChange(true)
    }

    private func seekToLine(index: Int) {
        guard index >= 0, index < document.lines.count else { return }
        let line = document.lines[index]
        guard onSeekLine?(line) == true else { return }
        // Let the playback model publish the new line before the stage leaves manual
        // mode; otherwise it would briefly re-centre the old line.
        autoResumeTask?.cancel()
        autoResumeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            finishManualBrowsing()
        }
    }

    private func scheduleAutoResume(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if force == false, now - lastResumeScheduleUptime < 0.25, autoResumeTask != nil {
            return
        }
        lastResumeScheduleUptime = now
        autoResumeTask?.cancel()
        autoResumeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(3500))
            guard !Task.isCancelled else { return }
            finishManualBrowsing()
        }
    }

    /// Resume auto-follow and scroll the existing native list to the current playing line.
    private func finishManualBrowsing() {
        guard isManualScrolling else { return }
        autoResumeTask?.cancel()
        autoResumeTask = nil
        hasUserScrolled = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isManualScrolling = false
        }
        onManualModeChange(false)
    }

    private func resumeButton(metrics: LyricsSceneMetrics) -> some View {
        Button {
            finishManualBrowsing()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: metrics.isCompact ? 10 : 11, weight: .semibold))
                Text(String(localized: "Back to current lyric"))
                    .font(.system(size: metrics.isCompact ? 11 : 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, metrics.isCompact ? 11 : 14)
            .padding(.vertical, metrics.isCompact ? 7 : 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Back to current lyric"))
        .accessibilityHint(String(localized: "Return to the currently playing line"))
        .help(String(localized: "Return to the currently playing line"))
    }

    private func lyricRow(
        line: LyricsLine,
        index: Int,
        focus: Int,
        isInterlude: Bool,
        manualMode: Bool,
        isHovered: Bool = false,
        contentWidth: CGFloat,
        pillHInset: CGFloat,
        pillVInset: CGFloat
    ) -> some View {
        let distance = abs(index - focus)
        let isFocus = distance == 0 && hasActiveLine
        let isWaiting = isFocus && isInterlude
        // Before the first timed line starts, keep the upcoming line sharp-ish and fade
        // the rest by distance instead of flattening every row to the same blur.
        let visualDistance = hasActiveLine ? distance : min(4, abs(index - focus))
        // AMLL's active line is fully bright while its neighbours sit at 0.2. Audune's
        // backdrop can be brighter than AMLL's, so we keep a little more context: the
        // next line stays readable, then falls away quickly.
        // Past lines fall away faster than upcoming lines, like Apple Music: the
        // singer has moved on, so context only needs to hint at what was just sung.
        let isPast = hasActiveLine && index < focus
        let baseOpacity: Double = {
            if isFocus { return isWaiting ? 0.56 : 1 }
            switch visualDistance {
            case 0: return 0.48
            case 1: return 0.32
            case 2: return 0.15
            case 3: return 0.07
            case 4: return 0.03
            default: return 0
            }
        }()
        // Manual browsing deliberately flattens the hierarchy: every line gets the
        // same size and blur, and opacity only distinguishes the line that is
        // currently playing. This mirrors Apple Music, where the viewport becomes a
        // readable index of the song while the user is scrolling.
        let rawOpacity = manualMode
            ? LyricsPresentationTiming.manualBrowsingOpacity(isFocused: isFocus)
            : (isPast ? baseOpacity * 0.72 : baseOpacity)
        let opacity = isHovered ? max(rawOpacity, 0.88) : rawOpacity
        // The reference animation uses a light 1.5–2 pt blur rather than a heavy
        // frosted layer, so the next lines stay readable but recede. Hovering a line
        // sharpens it immediately like Apple Music so the user can read and click it.
        // Rows with baseOpacity == 0 (visualDistance > 4) are completely invisible, so
        // skip allocating an offscreen Gaussian blur pass for them.
        let blurRadius: CGFloat = (manualMode || isHovered || reduceMotion || blurLyrics == false || isFocus || visualDistance > 4)
            ? 0
            : min(1.5 + CGFloat(visualDistance) * 0.45 + (isPast ? 0.3 : 0), 3.2)
        // Scale is a render transform, not layout. Every row keeps the same font
        // and measure, so focus never re-wraps; it only grows slightly from the
        // leading edge, exactly like the reference's transform-origin: left center.
        let rowScale: CGFloat = manualMode ? 1 : (reduceMotion ? 1 : (isFocus ? 1.06 : 0.96))
        let rowFontSize = metrics.activeFontSize
        let translationReveal = manualMode ? 1 : (isFocus ? focusTranslationReveal : 1)
        let lineGap = max(5, metrics.activeFontSize * 0.15)
        let activeGlow = (manualMode == false && isFocus && isWaiting == false) ? 0.18 : 0.0
        let translationOpacity: Double = manualMode
            ? (isFocus ? 0.82 : LyricsPresentationTiming.manualBrowsingOpacity(isFocused: false))
            : (isFocus ? (isWaiting ? 0.30 : 0.62) : 0.26) * (0.70 + 0.30 * opacity) * translationReveal
        let staggerDelay = (manualMode || isRapidFocusCadence || visualDistance > 5)
            ? 0
            : LyricsPresentationTiming.staggeredRowDelay(
                distance: visualDistance,
                reduceMotion: reduceMotion
            )
        let rowCascadeY: CGFloat = (manualMode || reduceMotion || isRapidFocusCadence || isFocus || visualDistance > 5)
            ? 0
            : cascadeOffset * min(CGFloat(visualDistance) * 0.34, 1.5)
        let shouldAnimateFocus = reduceMotion == false && (manualMode || visualDistance <= 5)
        let showsIntroDots = introWait && hasActiveLine == false && index == 0 && manualMode == false
        let alignTrailing = line.isSecondaryVocal
        let hAlignment: HorizontalAlignment = alignTrailing ? .trailing : .leading
        let frameAlignment: Alignment = alignTrailing ? .trailing : .leading
        let textAlignment: TextAlignment = alignTrailing ? .trailing : .leading
        let scaleAnchor: UnitPoint = alignTrailing ? .trailing : .leading
        let followsWordClock = isFocus && manualMode == false

        let pillCornerRadius: CGFloat = metrics.isCompact ? 26 : 34
        let pillShape = RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)

        return VStack(alignment: hAlignment, spacing: lineGap) {
            if showsIntroDots {
                LyricInterludeDots(
                    fontSize: rowFontSize,
                    animated: isPlaying && reduceMotion == false && manualMode == false,
                    lines: document.lines,
                    activeIndex: nil,
                    clockAnchor: clockAnchor,
                    isPlaying: isPlaying,
                    playbackRate: playbackRate,
                    durationSeconds: durationSeconds,
                    lyricsOffsetSeconds: lyricsOffsetSeconds
                )
                .padding(.bottom, max(4, lineGap * 0.35))
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: 0.72, anchor: scaleAnchor).combined(with: .opacity)
                )
            }

            if showsPronunciation,
               let pronunciation = line.pronunciation,
               pronunciation.isEmpty == false
            {
                Text(pronunciation)
                    .font(.system(size: max(12, metrics.translationFontSize * 0.86), weight: .medium))
                    .foregroundStyle(.white.opacity(opacity * 0.62))
                    .lineSpacing(max(1, metrics.translationFontSize * 0.12))
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }

            if followsWordClock, let words = line.words, words.count >= 2 {
                LyricsTimedWordLine(
                    words: words,
                    lineText: line.text,
                    clockAnchor: clockAnchor,
                    isPlaying: isPlaying,
                    playbackRate: playbackRate,
                    durationSeconds: durationSeconds,
                    lyricsOffsetSeconds: lyricsOffsetSeconds,
                    fontSize: rowFontSize,
                    weight: .bold,
                    opacity: opacity,
                    followsPlayback: true,
                    reduceMotion: reduceMotion,
                    alignment: hAlignment,
                    accessibilityLabel: accessibilityLabel(for: line)
                )
            } else {
                Text(line.text)
                    .font(.system(size: rowFontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(opacity))
                    .lineSpacing(max(1, rowFontSize * 0.03))
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }

            if let bgText = line.backgroundText, bgText.isEmpty == false {
                let formattedBg = formattedBackgroundText(bgText)
                let bgFontSize = max(13, metrics.translationFontSize * 0.96)
                if followsWordClock, let bgWords = line.backgroundWords, bgWords.count >= 2 {
                    LyricsTimedWordLine(
                        words: bgWords,
                        lineText: formattedBg,
                        clockAnchor: clockAnchor,
                        isPlaying: isPlaying,
                        playbackRate: playbackRate,
                        durationSeconds: durationSeconds,
                        lyricsOffsetSeconds: lyricsOffsetSeconds,
                        fontSize: bgFontSize,
                        weight: .semibold,
                        opacity: opacity * 0.72,
                        followsPlayback: true,
                        reduceMotion: reduceMotion,
                        alignment: hAlignment,
                        accessibilityLabel: formattedBg
                    )
                } else {
                    Text(formattedBg)
                        .font(.system(size: bgFontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(opacity * 0.68))
                        .lineSpacing(max(1, bgFontSize * 0.12))
                        .multilineTextAlignment(textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                }
            }

            if showsTranslation,
               let translation = line.translation,
               translation.isEmpty == false
            {
                Text(translation)
                    .font(.system(size: metrics.translationFontSize, weight: .regular))
                    .foregroundStyle(.white.opacity(translationOpacity))
                    .lineSpacing(max(2, metrics.translationFontSize * 0.16))
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .opacity(translationReveal)
            }

            if isWaiting {
                LyricInterludeDots(
                    fontSize: rowFontSize,
                    animated: isPlaying && reduceMotion == false && manualMode == false,
                    lines: document.lines,
                    activeIndex: index,
                    clockAnchor: clockAnchor,
                    isPlaying: isPlaying,
                    playbackRate: playbackRate,
                    durationSeconds: durationSeconds,
                    lyricsOffsetSeconds: lyricsOffsetSeconds
                )
                .padding(.top, max(2, lineGap * 0.2))
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: 0.72, anchor: scaleAnchor).combined(with: .opacity)
                )
            }
        }
        .frame(width: contentWidth, alignment: frameAlignment)
        .padding(.horizontal, pillHInset)
        .padding(.vertical, pillVInset)
        .background {
            if isHovered {
                pillShape
                    .fill(Color.white.opacity(manualMode ? 0.16 : 0.12))
                    .overlay(
                        pillShape
                            .strokeBorder(Color.white.opacity(manualMode ? 0.24 : 0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.24), radius: 16, y: 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(pillShape)
        .scaleEffect(isHovered && reduceMotion == false ? 1.015 : 1.0, anchor: scaleAnchor)
        .shadow(color: .black.opacity(activeGlow), radius: 16, y: 2)
        .blur(radius: blurRadius)
        .animation(
            shouldAnimateFocus
                ? (isRapidFocusCadence ? .easeOut(duration: 0.12) : .spring(response: 0.48, dampingFraction: 0.82).delay(staggerDelay))
                : nil,
            value: focus
        )
        .scaleEffect(rowScale, anchor: scaleAnchor)
        .offset(y: rowCascadeY)
        .animation(
            shouldAnimateFocus
                ? (isRapidFocusCadence ? .easeOut(duration: 0.12) : .spring(response: 0.50, dampingFraction: 0.76).delay(staggerDelay))
                : nil,
            value: focus
        )
        .animation(
            shouldAnimateFocus && isRapidFocusCadence == false
                ? .spring(response: 0.48, dampingFraction: 0.78).delay(staggerDelay)
                : nil,
            value: cascadeOffset
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: manualMode)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: isHovered)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78), value: isWaiting)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78), value: showsIntroDots)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: line))
        .accessibilityAddTraits(isFocus ? .isSelected : [])
    }

    private func formattedBackgroundText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
            || (trimmed.hasPrefix("（") && trimmed.hasSuffix("）"))
        {
            return trimmed
        }
        return "(\(trimmed))"
    }

    private func triggerCascadeSpring(from oldFocus: Int, to newFocus: Int) {
        guard reduceMotion == false, isManualScrolling == false, oldFocus != newFocus else {
            return
        }
        let direction: CGFloat = newFocus > oldFocus ? 1 : -1
        cascadeOffset = direction * 14
        withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
            cascadeOffset = 0
        }
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

}

// MARK: - Interlude

/// Three breathing dots mark an instrumental wait. They are deliberately static when
/// playback is paused or Reduce Motion is on, so the stage never animates while frozen.
private struct LyricInterludeDots: View {
    var fontSize: CGFloat
    var animated: Bool
    var lines: [LyricsLine] = []
    var activeIndex: Int? = nil
    var clockAnchor: PlaybackClockAnchor = .zero
    var isPlaying: Bool = false
    var playbackRate: Double = 1
    var durationSeconds: Double = 0
    var lyricsOffsetSeconds: Double = 0

    private var dotSize: CGFloat {
        min(max(fontSize * 0.20, 6), 12)
    }

    private var spacing: CGFloat { dotSize * 1.30 }

    /// Swells slightly during the final 18% of the wait window so the dots visibly gather
    /// energy right before the singer enters, matching Apple Music's interlude cue.
    private static func anticipationScale(progress: Double?) -> CGFloat {
        guard let progress, progress > 0.82 else { return 1.0 }
        let normalized = min(max((progress - 0.82) / 0.18, 0), 1)
        return 1.0 + 0.14 * CGFloat(sin(normalized * .pi))
    }

    @State private var start = Date()

    var body: some View {
        if animated {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                let livePos = LyricsPlaybackClock.presentationPosition(
                    LyricsPlaybackClock.position(
                        anchor: clockAnchor,
                        isPlaying: isPlaying,
                        playbackRate: playbackRate,
                        durationSeconds: durationSeconds,
                        nowUptime: ProcessInfo.processInfo.systemUptime
                    ),
                    offsetSeconds: lyricsOffsetSeconds
                )
                let countdown = LyricsPlaybackClock.interludeProgress(
                    in: lines,
                    activeIndex: activeIndex,
                    at: livePos
                )
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { index in
                        let phase = Self.phase(elapsed: elapsed, index: index)
                        Circle()
                            .fill(Color.white.opacity(0.32 + 0.68 * phase))
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(0.88 + 0.22 * phase)
                            .offset(y: -dotSize * 0.85 * phase)
                            .shadow(color: .white.opacity(0.28 * phase), radius: dotSize * 0.6)
                    }
                }
                .scaleEffect(Self.anticipationScale(progress: countdown), anchor: .leading)
            }
            .frame(height: dotSize * 1.9)
            .accessibilityHidden(true)
            .onAppear { start = Date() }
        } else {
            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.50))
                        .frame(width: dotSize, height: dotSize)
                }
            }
            .frame(height: dotSize * 1.9)
            .accessibilityHidden(true)
        }
    }

    /// A smooth hop across the first 80% of each 1.2 s cycle, then a short rest.
    /// The three dots are offset in phase so they read as a wave, not a blinking ellipsis.
    private static func phase(elapsed: TimeInterval, index: Int) -> Double {
        let cycle = elapsed / 1.2 - Double(index) * 0.16
        guard cycle >= 0 else { return 0 }
        let normalized = cycle.truncatingRemainder(dividingBy: 1)
        guard normalized < 0.8 else { return 0 }
        return sin(normalized / 0.8 * .pi)
    }
}

// MARK: - Manual scroll capture

/// A zero-interaction view that detects the start of manual browsing without consuming
/// the wheel event, leaving scrolling and momentum to the native ScrollView.
private struct LyricsScrollMonitor: NSViewRepresentable {
    var onScroll: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        view.setAccessibilityHidden(true)
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class MonitorView: NSView {
        var onScroll: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // The monitor observes events globally; this view must never take clicks.
            nil
        }

        func installMonitor() {
            removeMonitor()
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window
                else { return event }

                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }

                let deltaX = event.scrollingDeltaX
                let deltaY = event.scrollingDeltaY
                guard deltaY.isFinite, deltaY != 0, abs(deltaY) >= abs(deltaX) else {
                    return event
                }

                self.onScroll?()
                return event
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            removeMonitor()
        }
    }
}

// MARK: - Metrics

private struct LyricsSceneMetrics: Equatable {
    var isCompact: Bool
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
    var focusFraction: CGFloat
    init(size: CGSize) {
        let compact = size.width < 780 || size.height < 580
        isCompact = compact

        if compact {
            horizontalInset = min(max(size.width * 0.05, 18), 40)
            topInset = 12
            bottomInset = 12
            stageHeight = max(120, size.height - topInset - bottomInset)
            artworkSide = min(max(size.height * 0.16, 64), 96)
            columnGap = 0
            activeFontSize = min(max(size.width * 0.062, 24), 40)
            translationFontSize = min(max(activeFontSize * 0.46, 14), 22)
            unsyncedFontSize = min(max(activeFontSize * 0.70, 18), 30)
            statusTitleSize = 22
            rowGap = max(12, activeFontSize * 0.40)
            focusFraction = 0.34
        } else {
            horizontalInset = min(max(size.width * 0.06, 26), 104)
            topInset = min(max(size.height * 0.018, 8), 22)
            bottomInset = min(max(size.height * 0.022, 10), 24)
            stageHeight = max(120, size.height - topInset - bottomInset)

            let availableWidth = max(320, size.width - horizontalInset * 2)
            let gap = min(max(size.width * 0.095, 46), 190)
            let widthDriven = availableWidth * 0.375
            let heightDriven = stageHeight * 0.52
            let maximumStageShare = max(250, availableWidth - gap - 300)
            artworkSide = max(96, min(widthDriven, heightDriven, 620, maximumStageShare))
            columnGap = gap

            let stageWidth = max(220, availableWidth - artworkSide - gap)
            activeFontSize = min(max(stageWidth * 0.085, 28), 70)
            translationFontSize = min(max(activeFontSize * 0.42, 14), 30)
            unsyncedFontSize = min(max(activeFontSize * 0.62, 18), 38)
            statusTitleSize = min(max(stageWidth * 0.050, 22), 32)
            rowGap = max(14, activeFontSize * 0.50)
            focusFraction = 0.205
        }
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

// MARK: - Lyric offset

/// Small, glanceable timing trim for the lyric stage. The same value is editable in
/// Settings; keeping it beside the source menu makes it reachable during playback.
private struct LyricsOffsetButton: View {
    var offset: Double
    var onChange: (Double) -> Void

    @State private var isPresented = false

    private var offsetText: String {
        String(format: "%+.1f s", offset)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                if abs(offset) >= 0.05 {
                    Text(offsetText)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(abs(offset) >= 0.05 ? 0.86 : 0.52))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(Color.white.opacity(abs(offset) >= 0.05 ? 0.13 : 0.065))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Adjust lyrics timing"))
        .accessibilityLabel(String(localized: "Lyrics offset"))
        .accessibilityValue(offsetText)
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 13) {
                Text(String(localized: "Lyrics Offset"))
                    .font(.system(size: 13, weight: .semibold))

                Text(String(localized: "Shift every lyric line relative to playback."))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    offsetStepButton(symbol: "minus") { adjust(by: -0.1) }
                    Text(offsetText)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .frame(maxWidth: .infinity)
                    offsetStepButton(symbol: "plus") { adjust(by: 0.1) }
                }

                Slider(
                    value: Binding(
                        get: { offset },
                        set: { onChange(clamped($0)) }
                    ),
                    in: IslandPreferences.lyricsOffsetRange,
                    step: 0.1
                )
                .tint(.primary)

                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "Positive values show lyrics later."))
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 10)
                    Button(String(localized: "Reset")) {
                        onChange(0)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .disabled(abs(offset) < 0.05)
                }
            }
            .padding(16)
            .frame(width: 290)
            .preferredColorScheme(.dark)
        }
    }

    private func offsetStepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 24)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? String(localized: "Show lyrics later") : String(localized: "Show lyrics earlier"))
    }

    private func adjust(by delta: Double) {
        onChange(clamped(offset + delta))
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, IslandPreferences.lyricsOffsetRange.lowerBound), IslandPreferences.lyricsOffsetRange.upperBound)
    }
}

// MARK: - Word fill

/// A word-timed lyric row. Every token occupies the same fixed slot whether or not it
/// has been sung, so the text never reflows as playback advances. Only the mask grows.
private struct LyricsTimedWordLine: View {
    var words: [LyricsWord]
    var lineText: String
    var clockAnchor: PlaybackClockAnchor
    var isPlaying: Bool
    var playbackRate: Double
    var durationSeconds: Double
    var lyricsOffsetSeconds: Double
    var fontSize: CGFloat
    var weight: Font.Weight
    var opacity: Double
    var followsPlayback: Bool
    var reduceMotion: Bool = false
    var alignment: HorizontalAlignment = .leading
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
        let tokenStrings = tokens
        let groupedRuns = runs
        Group {
            if followsPlayback {
                // Only the single active line runs a display-rate (60/120 Hz ProMotion)
                // TimelineView; all inactive lines stay completely static off the animation loop.
                TimelineView(.animation(minimumInterval: nil, paused: isPlaying == false)) { _ in
                    let livePosition = LyricsPlaybackClock.presentationPosition(
                        LyricsPlaybackClock.position(
                            anchor: clockAnchor,
                            isPlaying: isPlaying,
                            playbackRate: playbackRate,
                            durationSeconds: durationSeconds,
                            nowUptime: ProcessInfo.processInfo.systemUptime
                        ),
                        offsetSeconds: lyricsOffsetSeconds
                    )
                    wordFlowContent(
                        tokenStrings: tokenStrings,
                        groupedRuns: groupedRuns,
                        position: livePosition,
                        active: true
                    )
                }
            } else {
                wordFlowContent(
                    tokenStrings: tokenStrings,
                    groupedRuns: groupedRuns,
                    position: 0,
                    active: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func wordFlowContent(
        tokenStrings: [String],
        groupedRuns: [[Int]],
        position: TimeInterval,
        active: Bool
    ) -> some View {
        LyricsTokenFlowLayout(
            lineSpacing: max(4, fontSize * 0.14),
            alignment: alignment
        ) {
            ForEach(Array(groupedRuns.enumerated()), id: \.offset) { _, run in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(run, id: \.self) { index in
                        LyricsWordFill(
                            text: tokenStrings[index],
                            progress: active ? LyricsPlaybackClock.wordProgress(for: words[index], at: position) : 1,
                            durationSeconds: words[index].durationSeconds,
                            font: .system(size: fontSize, weight: weight),
                            opacity: opacity,
                            glow: active,
                            reduceMotion: reduceMotion
                        )
                    }
                }
                .fixedSize()
            }
        }
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
    var durationSeconds: TimeInterval = 0
    var font: Font
    var opacity: Double
    var glow: Bool
    var reduceMotion: Bool = false

    private var liftOffset: CGFloat {
        guard glow else { return 0 }
        return CGFloat(
            LyricsPresentationTiming.wordLiftOffset(
                progress: progress,
                durationSeconds: durationSeconds,
                reduceMotion: reduceMotion
            )
        )
    }

    private var emphasisScale: CGFloat {
        guard glow else { return 1.0 }
        return CGFloat(
            LyricsPresentationTiming.wordEmphasisScale(
                progress: progress,
                durationSeconds: durationSeconds,
                reduceMotion: reduceMotion
            )
        )
    }

    private var glowOpacity: Double {
        guard glow else { return 0 }
        return LyricsPresentationTiming.wordGlowOpacity(
            progress: progress,
            durationSeconds: durationSeconds
        )
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
                            color: .white.opacity(glowOpacity),
                            radius: durationSeconds >= 0.75 ? 12 : 9
                        )
                }
            }
        }
        .scaleEffect(emphasisScale, anchor: .bottom)
        .offset(y: liftOffset)
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
    var alignment: HorizontalAlignment = .leading

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
            let rowWidth = row.reduce(CGFloat.zero) { $0 + $1.size.width }
            var x = alignment == .trailing ? max(bounds.minX, bounds.maxX - rowWidth) : bounds.minX
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

private extension View {
    /// `onScrollPhaseChange` needs macOS 15+. Below that, `LyricsScrollMonitor` still drives browse mode.
    @ViewBuilder
    func auduneOnScrollPhaseChange(
        onActive: @escaping () -> Void,
        onIdleWhileManual: @escaping () -> Void
    ) -> some View {
        if #available(macOS 15.0, *) {
            onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating {
                    onActive()
                } else if phase == .idle {
                    onIdleWhileManual()
                }
            }
        } else {
            self
        }
    }
}

// MARK: - Interactive Lyrics Candidate Picker

struct LyricsCandidatePickerOverlay: View {
    var initialTitle: String
    var initialArtist: String
    var initialAlbum: String
    var trackDurationSeconds: Double
    var currentDocument: LyricsDocument?
    var clockAnchor: PlaybackClockAnchor
    var isPlaying: Bool
    var playbackRate: Double
    var lyricsOffsetSeconds: Double
    var canImport: Bool
    var searchCandidates: (String?, String?, String?, String?) async -> [LyricsScoredCandidate]
    var onSelect: (LyricsDocument, Bool) -> Void
    var onImportLocal: () -> Void
    var onDismiss: () -> Void

    @State private var queryTitle: String = ""
    @State private var queryArtist: String = ""
    @State private var isEditingQuery = false
    @State private var hasSearched = false
    @State private var candidates: [LyricsScoredCandidate] = []
    @State private var selectedCandidateID: UUID?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var selectedCandidate: LyricsScoredCandidate? {
        if let selectedCandidateID,
           let match = candidates.first(where: { $0.id == selectedCandidateID })
        {
            return match
        }
        return candidates.first
    }

    private var currentLivePosition: TimeInterval {
        LyricsPlaybackClock.presentationPosition(
            LyricsPlaybackClock.position(
                anchor: clockAnchor,
                isPlaying: isPlaying,
                playbackRate: playbackRate,
                durationSeconds: trackDurationSeconds,
                nowUptime: ProcessInfo.processInfo.systemUptime
            ),
            offsetSeconds: lyricsOffsetSeconds
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                candidateListColumn
                    .frame(width: 300)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .overlay(Color.white.opacity(0.08))

            footerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.42), radius: 28, y: 12)
        .preferredColorScheme(.dark)
        .onAppear {
            queryTitle = initialTitle
            queryArtist = initialArtist
            seedCurrentDocumentOnly()
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(initialTitle.isEmpty ? String(localized: "Lyrics") : initialTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                    if initialArtist.isEmpty == false {
                        Text(initialArtist)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                headerTextButton(
                    title: String(localized: "Search other sources"),
                    symbol: "magnifyingglass",
                    emphasized: isSearching
                ) {
                    triggerSearch()
                }
                .disabled(isSearching)

                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isEditingQuery.toggle()
                    }
                } label: {
                    Text(String(localized: "Edit keywords"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(isEditingQuery ? 0.92 : 0.52))
                }
                .buttonStyle(.plain)

                if canImport {
                    headerTextButton(
                        title: String(localized: "Import LRC"),
                        symbol: "square.and.arrow.down",
                        emphasized: false,
                        action: onImportLocal
                    )
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close lyrics picker"))
            }

            if isEditingQuery {
                HStack(spacing: 8) {
                    searchField(placeholder: String(localized: "Song title"), text: $queryTitle)
                    searchField(placeholder: String(localized: "Artist"), text: $queryArtist)
                    Button {
                        triggerSearch()
                    } label: {
                        Text(String(localized: "Search"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSearching)
                }
                .transition(.opacity)
            }
        }
    }

    private func headerTextButton(
        title: String,
        symbol: String,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.white.opacity(emphasized ? 0.92 : 0.58))
        }
        .buttonStyle(.plain)
    }

    private func searchField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onSubmit {
                triggerSearch()
            }
    }

    // MARK: - Left Candidate List

    private var candidateListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(
                    hasSearched
                        ? String(localized: "Versions (\(candidates.count))")
                        : String(localized: "Current")
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                Spacer()
                if isSearching {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(String(localized: "Searching…"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.44))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            if candidates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: isSearching ? "waveform.badge.magnifyingglass" : "music.note.list")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.white.opacity(0.32))
                    Text(emptyListMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.46))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    if hasSearched == false, isSearching == false {
                        Button(String(localized: "Search other sources")) {
                            triggerSearch()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(candidates) { candidate in
                            candidateCard(candidate)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var emptyListMessage: String {
        if isSearching {
            return String(localized: "Searching lyrics providers…")
        }
        if hasSearched {
            return String(localized: "No lyrics found for this search.")
        }
        return String(localized: "No lyrics loaded for this song yet.")
    }

    private func candidateCard(_ candidate: LyricsScoredCandidate) -> some View {
        let isSelected = selectedCandidate?.id == candidate.id
        let isCurrent = currentDocument?.id == candidate.document.id
        let doc = candidate.document
        let isRichSync = doc.synchronization == .syllableSynced || doc.synchronization == .wordSynced
        let snippet = previewSnippet(for: doc)

        return Button {
            selectedCandidateID = candidate.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Text(candidateSourceName(candidate))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)

                    if isCurrent {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text(String(localized: "In Use"))
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.16), in: Capsule())
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Image(systemName: syncSymbol(doc.synchronization))
                            .font(.system(size: 8.5, weight: .bold))
                        Text(syncBadgeLabel(doc.synchronization))
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundStyle(isRichSync ? Color.black.opacity(0.88) : Color.white.opacity(0.78))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(isRichSync ? Color.white.opacity(0.90) : Color.white.opacity(0.11))
                    )
                }

                if snippet.isEmpty == false {
                    Text("“\(snippet)”")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(isSelected ? 0.86 : 0.64))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if doc.hasTranslations {
                        featureTag(String(localized: "Translation"))
                    }
                    if doc.hasPronunciations {
                        featureTag(String(localized: "Romaji"))
                    }
                    Text("\(doc.lines.count) \(String(localized: "lines"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.38))

                    if let dur = doc.trackKey.durationSeconds, dur > 0 {
                        Text("· \(formatDurationShort(dur))")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.15 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.30 : 0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func featureTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.70))
            .padding(.horizontal, 5.5)
            .padding(.vertical, 1.5)
            .background(Color.white.opacity(0.09), in: Capsule())
    }

    // MARK: - Right Live Sync & Timeline Preview

    private var previewColumn: some View {
        Group {
            if let candidate = selectedCandidate {
                TimelineView(.animation(minimumInterval: 0.25, paused: isPlaying == false)) { _ in
                    let livePos = currentLivePosition
                    let lines = candidate.document.lines
                    let activeIdx = LyricsPlaybackClock.activeLineIndex(in: lines, at: livePos)
                    let activeLine = activeIdx.flatMap { lines.indices.contains($0) ? lines[$0] : nil }
                        ?? lines.first

                    VStack(alignment: .leading, spacing: 0) {
                        // Top pinned "Now Singing" comparison box
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.white.opacity(isPlaying ? 0.88 : 0.38))
                                    .frame(width: 6, height: 6)
                                Text(String(localized: "NOW AT \(formatTimestamp(livePos))"))
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .tracking(0.6)
                                    .foregroundStyle(.white.opacity(0.50))
                                Spacer()
                                Text("\(candidateSourceName(candidate)) · \(syncBadgeLabel(candidate.document.synchronization))")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.46))
                            }

                            if let activeLine {
                                Text(activeLine.text)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.98))
                                    .lineLimit(2)
                                if let translation = activeLine.translation, translation.isEmpty == false {
                                    Text(translation)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))

                        Divider().overlay(Color.white.opacity(0.08))

                        // Full scrollable timeline
                        ScrollViewReader { reader in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                        let isCurrentLine = activeIdx == idx
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Text(line.startSeconds.map(formatTimestamp) ?? "--:--")
                                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                                .foregroundStyle(.white.opacity(isCurrentLine ? 0.88 : 0.30))
                                                .frame(width: 48, alignment: .leading)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(line.text)
                                                    .font(.system(size: isCurrentLine ? 14 : 12.5, weight: isCurrentLine ? .bold : .medium))
                                                    .foregroundStyle(.white.opacity(isCurrentLine ? 0.98 : 0.58))
                                                if let translation = line.translation, translation.isEmpty == false {
                                                    Text(translation)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.white.opacity(isCurrentLine ? 0.72 : 0.36))
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.white.opacity(isCurrentLine ? 0.11 : 0))
                                        )
                                        .id(idx)
                                    }
                                }
                                .padding(14)
                            }
                            .onAppear {
                                if let activeIdx {
                                    reader.scrollTo(activeIdx, anchor: .center)
                                }
                            }
                            .onChange(of: activeIdx) { _, newActive in
                                guard let newActive else { return }
                                withAnimation(.easeOut(duration: 0.20)) {
                                    reader.scrollTo(newActive, anchor: .center)
                                }
                            }
                            .onChange(of: candidate.id) { _, _ in
                                if let activeIdx {
                                    reader.scrollTo(activeIdx, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white.opacity(0.32))
                    Text(String(localized: "Select a version on the left to preview"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            Text(String(localized: "Remembered for this song."))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)

            Spacer()

            Button(String(localized: "Cancel"), action: onDismiss)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))

            Button {
                guard let chosen = selectedCandidate?.document else { return }
                onSelect(chosen, true)
            } label: {
                Text(String(localized: "Use Lyrics"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(selectedCandidate == nil ? 0.35 : 0.94))
            }
            .buttonStyle(.plain)
            .disabled(selectedCandidate == nil)
        }
    }

    // MARK: - Helpers

    private func seedCurrentDocumentOnly() {
        hasSearched = false
        guard let currentDocument,
              let currentScored = LyricsCandidateRanker.scoreLenient(
                  document: currentDocument,
                  expected: currentDocument.trackKey,
                  providerID: currentDocument.source?.resolvedProviderID ?? "current",
                  nodeID: currentDocument.source?.nodeID,
                  latencySeconds: 0,
                  reliabilityScore: 1
              )
        else {
            candidates = []
            selectedCandidateID = nil
            return
        }
        candidates = [currentScored]
        selectedCandidateID = currentScored.id
    }

    private func triggerSearch() {
        searchTask?.cancel()
        isSearching = true
        hasSearched = true
        let title = queryTitle
        let artist = queryArtist
        let album = initialAlbum

        searchTask = Task { @MainActor in
            // nil filter → LyricsRouter uses the footer Menu routing selection.
            let fetched = await searchCandidates(title, artist, album, nil)
            guard Task.isCancelled == false else { return }
            isSearching = false
            var combined = fetched
            if let currentDocument,
               combined.contains(where: { $0.document.id == currentDocument.id }) == false,
               let currentScored = LyricsCandidateRanker.scoreLenient(
                   document: currentDocument,
                   expected: currentDocument.trackKey,
                   providerID: currentDocument.source?.resolvedProviderID ?? "current",
                   nodeID: currentDocument.source?.nodeID,
                   latencySeconds: 0,
                   reliabilityScore: 1
               )
            {
                combined.insert(currentScored, at: 0)
            }
            candidates = combined
            if selectedCandidateID == nil || combined.contains(where: { $0.id == selectedCandidateID }) == false {
                selectedCandidateID = combined.first?.id
            }
        }
    }

    private func previewSnippet(for document: LyricsDocument) -> String {
        let pos = currentLivePosition
        if let idx = LyricsPlaybackClock.activeLineIndex(in: document.lines, at: pos),
           document.lines.indices.contains(idx)
        {
            let text = document.lines[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false { return text }
        }
        return document.lines
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false } ?? ""
    }

    private func syncSymbol(_ sync: LyricsSynchronization) -> String {
        switch sync {
        case .syllableSynced, .wordSynced: return "sparkles"
        case .lineSynced: return "list.bullet"
        case .unsynced: return "doc.plaintext"
        }
    }

    private func syncBadgeLabel(_ sync: LyricsSynchronization) -> String {
        switch sync {
        case .syllableSynced: return String(localized: "Syllable")
        case .wordSynced: return String(localized: "Word")
        case .lineSynced: return String(localized: "Line")
        case .unsynced: return String(localized: "Plain")
        }
    }

    private func candidateSourceName(_ candidate: LyricsScoredCandidate) -> String {
        if candidate.document.source?.kind == .localImport {
            return String(localized: "Imported LRC")
        }
        if let name = candidate.document.source?.providerName, name.isEmpty == false {
            if let upstream = candidate.document.source?.upstreamProviderID, upstream.isEmpty == false {
                return "\(name) · \(upstream)"
            }
            return name
        }
        if let cap = LyricsProviderRegistry.capability(id: candidate.providerID) {
            return cap.displayName
        }
        return candidate.providerID
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let mins = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%04.1f", mins, secs)
    }

    private func formatDurationShort(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#endif
