#if os(macOS)
import SwiftUI

struct IslandFullscreenLyricsView: View {
    @Bindable var model: IslandModel
    var importLyrics: () -> Void
    var chooseCandidate: (UUID) -> Void
    var deleteLyrics: (UUID) -> Void

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

            if model.nowPlaying.durationSeconds > 0 {
                ProgressView(value: min(max(model.lyricsPositionSeconds / model.nowPlaying.durationSeconds, 0), 1))
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
        case .local(let document):
            lyricLines(document)
        case .ambiguous(let documents):
            ambiguousChoices(documents)
        case .noTrack:
            emptyState(String(localized: "Play music to view lyrics."))
        case .nowPlayingUnavailable:
            emptyState(String(localized: "Now Playing unavailable"))
        case .metadataUnavailable:
            emptyState(String(localized: "Track information is incomplete."))
        case .onlineUnavailable:
            VStack(alignment: .leading, spacing: 10) {
                emptyState(String(localized: "Online lyrics lookup is unavailable."))
                Text(String(localized: "Import an LRC file to continue."))
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                emptyState(String(localized: "Lyrics could not be loaded."))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func lyricLines(_ document: LyricsDocument) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(document.lines.enumerated()), id: \.offset) { index, line in
                        let distance = model.activeLyricsLineIndex.map { abs(index - $0) } ?? 2
                        VStack(alignment: .leading, spacing: 7) {
                            Text(line.text)
                                .font(.system(
                                    size: index == model.activeLyricsLineIndex ? 32 : 23,
                                    weight: index == model.activeLyricsLineIndex ? .semibold : .medium,
                                    design: .rounded
                                ))
                                .foregroundStyle(.white.opacity(lineOpacity(distance: distance)))
                                .fixedSize(horizontal: false, vertical: true)
                            if let translation = line.translation, translation.isEmpty == false {
                                Text(translation)
                                    .font(.system(size: 16, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.4 * lineOpacity(distance: distance)))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(index)
                        .accessibilityElement(children: .combine)
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
                if reduceMotion {
                    proxy.scrollTo(index, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.42)) {
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
        guard model.nowPlaying.durationSeconds > 0 else { return current }
        return "\(current) / \(timeLabel(model.nowPlaying.durationSeconds))"
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
#endif
