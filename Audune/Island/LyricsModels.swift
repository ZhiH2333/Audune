import Foundation

nonisolated struct PlaybackClockAnchor: Equatable, Sendable {
    var elapsedSeconds: Double
    var monotonicUptime: TimeInterval
    var revision: UInt64

    static let zero = PlaybackClockAnchor(
        elapsedSeconds: 0,
        monotonicUptime: 0,
        revision: 0
    )
}

nonisolated struct LyricsPlaybackClock {
    static func position(
        anchor: PlaybackClockAnchor,
        isPlaying: Bool,
        playbackRate: Double,
        durationSeconds: Double,
        nowUptime: TimeInterval
    ) -> Double {
        let base = max(0, anchor.elapsedSeconds.isFinite ? anchor.elapsedSeconds : 0)
        let uptimeDelta = max(0, nowUptime - anchor.monotonicUptime)
        let rate = playbackRate.isFinite ? max(0, playbackRate) : 0
        let advanced = isPlaying ? base + uptimeDelta * rate : base
        let finitePosition = advanced.isFinite ? max(0, advanced) : base
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return finitePosition
        }
        return min(finitePosition, durationSeconds)
    }

    static func progress(position: TimeInterval, duration: TimeInterval) -> Double? {
        guard position.isFinite, duration.isFinite, duration > 0 else {
            return nil
        }
        return min(max(position / duration, 0), 1)
    }

    static func activeLineIndex(in lines: [LyricsLine], at position: TimeInterval) -> Int? {
        guard position.isFinite else { return nil }
        return lines.lastIndex { line in
            guard let start = line.startSeconds, start.isFinite else { return false }
            return start <= position
        }
    }

    static func wordProgress(for word: LyricsWord, at position: TimeInterval) -> Double {
        guard position.isFinite, word.startSeconds.isFinite, word.durationSeconds.isFinite,
              word.durationSeconds > 0
        else {
            return 0
        }
        return min(max((position - word.startSeconds) / word.durationSeconds, 0), 1)
    }
}

nonisolated enum LyricsPresentationTiming {
    static func translationOpacity(sinceLineFocus: TimeInterval) -> Double {
        guard sinceLineFocus.isFinite else { return 0 }
        let progress = (sinceLineFocus - IslandMotion.lyricsTranslationDelaySeconds)
            / IslandMotion.lyricsTranslationFadeSeconds
        return min(max(progress, 0), 1)
    }

    /// Reveal follows playback position, so pausing freezes the translation and
    /// seeking jumps straight to the correct reveal state.
    static func translationOpacity(
        lineStartSeconds: Double?,
        positionSeconds: Double
    ) -> Double {
        guard let lineStartSeconds, lineStartSeconds.isFinite, positionSeconds.isFinite else {
            return 1
        }
        return translationOpacity(sinceLineFocus: max(0, positionSeconds - lineStartSeconds))
    }
}

nonisolated struct LyricsTrackKey: Codable, Equatable, Hashable, Sendable {
    var isrc: String?
    var title: String
    var artist: String
    var album: String?
    var durationSeconds: Double?
}

nonisolated struct LyricsWord: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var text: String
    var startSeconds: Double
    var durationSeconds: Double
}

nonisolated struct LyricsLine: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    /// `nil` for a plain, unsynchronized lyric line. Never invent a timestamp for it.
    var startSeconds: Double?
    var endSeconds: Double?
    var text: String
    var translation: String?
    /// Optional pronunciation/romanization. Kept separate from the translation tier.
    var pronunciation: String? = nil
    var words: [LyricsWord]?
}

/// How precisely a document can follow playback. Derived from the data, never guessed.
nonisolated enum LyricsSynchronization: String, Codable, Equatable, Sendable {
    case unsynced
    case lineSynced
    case wordSynced
}

nonisolated struct LyricsSourceInfo: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Equatable, Sendable {
        case localImport
        case lrclib
    }

    var kind: Kind
    var providerName: String?
    var providerRecordIdentifier: String?
    var isPersisted: Bool

    static let localImport = LyricsSourceInfo(
        kind: .localImport,
        providerName: nil,
        providerRecordIdentifier: nil,
        isPersisted: true
    )
}

nonisolated struct LyricsDocument: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var trackKey: LyricsTrackKey
    var language: String?
    var lines: [LyricsLine]
    /// Missing in documents saved before source tracking existed; those are local imports.
    var source: LyricsSourceInfo? = nil

    var synchronization: LyricsSynchronization {
        guard lines.contains(where: { $0.startSeconds != nil }) else { return .unsynced }
        let hasWords = lines.contains { line in
            line.words?.isEmpty == false
        }
        return hasWords ? .wordSynced : .lineSynced
    }

    var isSynchronized: Bool {
        synchronization != .unsynced
    }

    var isPersistedLocally: Bool {
        source?.kind == .localImport || source == nil
    }
}
