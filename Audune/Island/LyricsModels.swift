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

    /// Converts playback time into lyric presentation time. A positive offset keeps
    /// every timestamp on screen longer, so the lyric appears later.
    static func presentationPosition(
        _ position: TimeInterval,
        offsetSeconds: TimeInterval
    ) -> TimeInterval {
        guard position.isFinite else { return 0 }
        let offset = offsetSeconds.isFinite ? offsetSeconds : 0
        return max(0, position - offset)
    }

    /// Converts a lyric timestamp back into a playback target. Used when the listener
    /// clicks a line while browsing: seeking to `start + offset` makes that line appear
    /// at `start` after the presentation offset is applied again.
    static func playbackPosition(
        forPresentationTime presentationPosition: TimeInterval,
        offsetSeconds: TimeInterval
    ) -> TimeInterval {
        guard presentationPosition.isFinite else { return 0 }
        let offset = offsetSeconds.isFinite ? offsetSeconds : 0
        return max(0, presentationPosition + offset)
    }

    static func canSeek(to line: LyricsLine, isSeekSupported: Bool) -> Bool {
        guard isSeekSupported, let start = line.startSeconds else { return false }
        return start.isFinite && start >= 0
    }

    static func activeLineIndex(in lines: [LyricsLine], at position: TimeInterval) -> Int? {
        guard position.isFinite else { return nil }
        return lines.lastIndex { line in
            guard let start = line.startSeconds, start.isFinite else { return false }
            return start <= position
        }
    }

    /// A long instrumental break between two timed lines. The previous line stays on
    /// screen, but the stage marks the wait with breathing dots instead of pretending
    /// the ended line is still being sung.
    static func isInterlude(
        in lines: [LyricsLine],
        activeIndex: Int?,
        at position: TimeInterval,
        minimumGap: TimeInterval = 3.0
    ) -> Bool {
        guard let activeIndex,
              lines.indices.contains(activeIndex),
              position.isFinite
        else { return false }
        let line = lines[activeIndex]
        guard let end = line.endSeconds, end.isFinite,
              lines.indices.contains(activeIndex + 1),
              let nextStart = lines[activeIndex + 1].startSeconds,
              nextStart.isFinite
        else { return false }
        let gap = nextStart - end
        guard gap >= minimumGap else { return false }
        return position >= end + 0.8 && position <= nextStart - 0.35
    }

    /// True during a long instrumental intro before the first timed lyric line begins.
    static func isIntroWait(
        in lines: [LyricsLine],
        at position: TimeInterval,
        minimumLead: TimeInterval = 3.0
    ) -> Bool {
        guard position.isFinite, position >= 0 else { return false }
        guard let firstLine = lines.first(where: { ($0.startSeconds ?? .nan).isFinite }),
              let firstStart = firstLine.startSeconds,
              firstStart >= minimumLead
        else { return false }
        return position >= 0.25 && position <= firstStart - 0.35
    }

    /// Normalized progress (0...1) through the active intro or interlude wait window.
    /// Used by the three breathing dots to swell and gather right before singing resumes.
    static func interludeProgress(
        in lines: [LyricsLine],
        activeIndex: Int?,
        at position: TimeInterval,
        minimumGap: TimeInterval = 3.0
    ) -> Double? {
        guard position.isFinite else { return nil }
        if activeIndex == nil {
            guard isIntroWait(in: lines, at: position, minimumLead: minimumGap),
                  let firstStart = lines.first(where: { ($0.startSeconds ?? .nan).isFinite })?.startSeconds
            else { return nil }
            let windowStart = 0.25
            let windowEnd = max(windowStart + 0.01, firstStart - 0.35)
            return min(max((position - windowStart) / (windowEnd - windowStart), 0), 1)
        }
        guard isInterlude(in: lines, activeIndex: activeIndex, at: position, minimumGap: minimumGap),
              let activeIndex,
              let end = lines[activeIndex].endSeconds,
              lines.indices.contains(activeIndex + 1),
              let nextStart = lines[activeIndex + 1].startSeconds
        else { return nil }
        let windowStart = end + 0.8
        let windowEnd = max(windowStart + 0.01, nextStart - 0.35)
        return min(max((position - windowStart) / (windowEnd - windowStart), 0), 1)
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
    static func manualBrowsingOpacity(isFocused: Bool) -> Double {
        isFocused ? 1 : 0.52
    }

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

    /// Smooth sinusoidal arch (-sin(progress * pi)) so the active word lifts and settles
    /// continuously instead of snapping on a boolean boundary.
    static func wordLiftOffset(
        progress: Double,
        durationSeconds: TimeInterval,
        reduceMotion: Bool = false
    ) -> Double {
        guard reduceMotion == false,
              progress.isFinite,
              progress > 0,
              progress < 1
        else {
            return 0
        }
        let duration = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        let maxLift = duration >= 0.75 ? 2.6 : 1.85
        return -sin(progress * .pi) * maxLift
    }

    /// Long sustained words (>= 0.75 s) gently bloom in scale at the peak of the vowel,
    /// mirroring Apple Music's emphasized vocal treatment.
    static func wordEmphasisScale(
        progress: Double,
        durationSeconds: TimeInterval,
        reduceMotion: Bool = false
    ) -> Double {
        guard reduceMotion == false,
              progress.isFinite,
              progress > 0,
              progress < 1,
              durationSeconds.isFinite,
              durationSeconds >= 0.75
        else {
            return 1.0
        }
        let extra = min((durationSeconds - 0.60) * 0.045, 0.060)
        return 1.0 + extra * sin(progress * .pi)
    }

    /// Continuous glow envelope that peaks mid-word and fades smoothly to zero at
    /// completion so the trailing edge never flashes off abruptly at progress == 1.
    static func wordGlowOpacity(
        progress: Double,
        durationSeconds: TimeInterval
    ) -> Double {
        guard progress.isFinite, progress > 0, progress < 1 else { return 0 }
        let duration = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        let peak = duration >= 0.75 ? 0.54 : 0.38
        return peak * sin(progress * .pi)
    }

    /// Cascading stagger delay (in seconds) per row distance from the focused line,
    /// producing Apple Music's wave-like spring progression.
    static func staggeredRowDelay(distance: Int, reduceMotion: Bool = false) -> Double {
        guard reduceMotion == false, distance > 0 else { return 0 }
        return Double(min(distance, 7)) * 0.028
    }

    /// Album artwork scale in the Lyrics player column: full size while playing,
    /// recessed while paused, matching Apple Music's spring artwork state.
    static func artworkScale(isPlaying: Bool, reduceMotion: Bool = false) -> Double {
        guard reduceMotion == false else { return 1.0 }
        return isPlaying ? 1.0 : 0.86
    }

    /// Apple Music depth-of-field row opacity curve.
    /// Keeps a full wall of upcoming lines clearly legible on saturated artwork backdrops
    /// while past lines recede faster; blur and viewport masks handle the rest of the depth cue.
    static func rowOpacity(
        distance: Int,
        hasActiveLine: Bool,
        isPast: Bool,
        isWaiting: Bool = false,
        manualMode: Bool = false,
        isHovered: Bool = false
    ) -> Double {
        let safeDistance = max(0, distance)
        let isFocused = safeDistance == 0 && hasActiveLine
        let rawOpacity: Double
        if manualMode {
            rawOpacity = manualBrowsingOpacity(isFocused: isFocused)
        } else if isFocused {
            rawOpacity = isWaiting ? 0.82 : 1.0
        } else if isPast {
            switch safeDistance {
            case 1: rawOpacity = 0.48
            case 2: rawOpacity = 0.34
            case 3: rawOpacity = 0.22
            case 4: rawOpacity = 0.12
            default: rawOpacity = 0.0
            }
        } else {
            switch safeDistance {
            case 0: rawOpacity = 0.72
            case 1: rawOpacity = 0.64
            case 2: rawOpacity = 0.54
            case 3: rawOpacity = 0.44
            case 4: rawOpacity = 0.34
            case 5: rawOpacity = 0.26
            case 6: rawOpacity = 0.18
            case 7: rawOpacity = 0.12
            default: rawOpacity = 0.0
            }
        }
        return isHovered ? max(rawOpacity, 0.92) : rawOpacity
    }

    /// Progressive depth-of-field Gaussian blur radius (in points) for non-focused lyric rows.
    /// Returns zero for invisible rows so off-screen rows never trigger an offscreen pass.
    /// Kept gentler than a heavy DoF wash so mid-distance lines stay readable on bright art.
    static func rowBlurRadius(
        distance: Int,
        hasActiveLine: Bool,
        isPast: Bool,
        manualMode: Bool = false,
        isHovered: Bool = false,
        reduceMotion: Bool = false,
        blurEnabled: Bool = true
    ) -> Double {
        guard manualMode == false,
              isHovered == false,
              reduceMotion == false,
              blurEnabled
        else {
            return 0
        }
        let safeDistance = max(0, distance)
        if hasActiveLine && safeDistance == 0 {
            return 0
        }
        if (isPast && safeDistance >= 5) || (isPast == false && safeDistance >= 8) {
            return 0
        }
        let effectiveDistance = hasActiveLine ? max(1, safeDistance) : min(6, safeDistance + 1)
        let radius = 0.45 + Double(effectiveDistance) * 0.48 + (isPast ? 0.25 : 0.0)
        return min(radius, 3.2)
    }

    /// Leading-anchored visual scale for a lyric row.
    static func rowScale(
        isFocused: Bool,
        manualMode: Bool = false,
        isHovered: Bool = false,
        reduceMotion: Bool = false
    ) -> Double {
        guard reduceMotion == false else { return 1.0 }
        if manualMode {
            return isHovered ? 1.015 : 1.0
        }
        if isFocused {
            return 1.05
        }
        return isHovered ? 0.98 : 0.955
    }

    /// Closed-form second-order spring displacement from `initialOffset` toward `0`.
    /// Each row starts moving after `delay` (derived from `staggeredRowDelay`), producing
    /// Apple Music's accordion wave without mutating per-row `@State` properties.
    static func underdampedSpringDisplacement(
        elapsed: TimeInterval,
        delay: TimeInterval,
        initialOffset: Double,
        response: Double = 0.50,
        dampingFraction: Double = 0.82
    ) -> Double {
        guard elapsed.isFinite,
              delay.isFinite,
              initialOffset.isFinite,
              abs(initialOffset) > 0.001,
              response.isFinite,
              response > 0.01
        else {
            return 0
        }
        let t = elapsed - max(0, delay)
        if t <= 0 {
            return initialOffset
        }
        if t >= response * 3.2 {
            return 0
        }
        let omega0 = (2.0 * .pi) / response
        let zeta = min(max(dampingFraction.isFinite ? dampingFraction : 0.82, 0.1), 1.0)
        if zeta < 1.0 {
            let root = sqrt(1.0 - zeta * zeta)
            let omegaD = omega0 * root
            let envelope = exp(-zeta * omega0 * t)
            let harmonic = cos(omegaD * t) + (zeta / root) * sin(omegaD * t)
            let value = initialOffset * envelope * harmonic
            return abs(value) < 0.05 ? 0 : value
        } else {
            let envelope = exp(-omega0 * t)
            let value = initialOffset * envelope * (1.0 + omega0 * t)
            return abs(value) < 0.05 ? 0 : value
        }
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
    var words: [LyricsWord]? = nil
    /// True when duet metadata (`ttm:agent="v2"`) marks this line for the secondary vocalist.
    var isSecondaryVocal: Bool = false
    /// Optional background vocal text (`ttm:role="x-bg"`).
    var backgroundText: String? = nil
    /// Optional timed words for the background vocal line.
    var backgroundWords: [LyricsWord]? = nil

    init(
        id: Int,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil,
        text: String,
        translation: String? = nil,
        pronunciation: String? = nil,
        words: [LyricsWord]? = nil,
        isSecondaryVocal: Bool = false,
        backgroundText: String? = nil,
        backgroundWords: [LyricsWord]? = nil
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.translation = translation
        self.pronunciation = pronunciation
        self.words = words
        self.isSecondaryVocal = isSecondaryVocal
        self.backgroundText = backgroundText
        self.backgroundWords = backgroundWords
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startSeconds
        case endSeconds
        case text
        case translation
        case pronunciation
        case words
        case isSecondaryVocal
        case backgroundText
        case backgroundWords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds)
        endSeconds = try container.decodeIfPresent(Double.self, forKey: .endSeconds)
        text = try container.decode(String.self, forKey: .text)
        translation = try container.decodeIfPresent(String.self, forKey: .translation)
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation)
        words = try container.decodeIfPresent([LyricsWord].self, forKey: .words)
        isSecondaryVocal = try container.decodeIfPresent(Bool.self, forKey: .isSecondaryVocal) ?? false
        backgroundText = try container.decodeIfPresent(String.self, forKey: .backgroundText)
        backgroundWords = try container.decodeIfPresent([LyricsWord].self, forKey: .backgroundWords)
    }
}

/// How precisely a document can follow playback. Derived from the data, never guessed.
nonisolated enum LyricsSynchronization: String, Codable, Equatable, Sendable {
    case unsynced
    case lineSynced
    case wordSynced
    case syllableSynced
}

nonisolated struct LyricsSourceInfo: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Equatable, Sendable {
        case localImport
        case lrclib
        case online
        /// User-picked lyrics remembered for a track. Independent from Auto/provider match results.
        case custom
    }

    /// Stable id for user-custom selections in ranking / filter UIs.
    static let customProviderID = "custom"

    var kind: Kind
    var providerName: String?
    var providerRecordIdentifier: String?
    var isPersisted: Bool
    /// Stable provider id from LyricsProviderRegistry when known.
    var providerID: String? = nil
    var nodeID: String? = nil
    /// Aggregator upstream attribution only (not a selectable Audune node).
    var upstreamProviderID: String? = nil
    var attributionURL: String? = nil
    var matchConfidence: Double? = nil
    var retrievedAt: Date? = nil

    static let localImport = LyricsSourceInfo(
        kind: .localImport,
        providerName: nil,
        providerRecordIdentifier: nil,
        isPersisted: true
    )

    /// Marks a user-chosen snapshot as Custom while preserving original provider credit.
    static func customSelection(preserving original: LyricsSourceInfo?) -> LyricsSourceInfo {
        let upstream = original?.upstreamProviderID
            ?? original?.providerName
            ?? original?.resolvedProviderID
        return LyricsSourceInfo(
            kind: .custom,
            providerName: original?.providerName,
            providerRecordIdentifier: original?.providerRecordIdentifier,
            isPersisted: true,
            providerID: customProviderID,
            nodeID: original?.nodeID,
            upstreamProviderID: upstream,
            attributionURL: original?.attributionURL,
            matchConfidence: original?.matchConfidence,
            retrievedAt: original?.retrievedAt ?? Date()
        )
    }

    var resolvedProviderID: String? {
        if let providerID, providerID.isEmpty == false { return providerID }
        switch kind {
        case .lrclib: return LyricsProviderID.lrclib.rawValue
        case .custom: return Self.customProviderID
        case .localImport, .online: return nil
        }
    }

    var isCustomSelection: Bool {
        kind == .custom || providerID == Self.customProviderID
    }
}

nonisolated struct LyricsDocument: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var trackKey: LyricsTrackKey
    var language: String?
    var lines: [LyricsLine]
    /// Missing in documents saved before source tracking existed; those are local imports.
    var source: LyricsSourceInfo? = nil
    /// Optional richer sync declaration from a trusted parser/provider (e.g. TTML syllable).
    /// Never raise precision above what `lines` actually contain.
    var declaredSynchronization: LyricsSynchronization? = nil

    var synchronization: LyricsSynchronization {
        guard lines.contains(where: { $0.startSeconds != nil }) else { return .unsynced }
        let hasWords = lines.contains { line in
            line.words?.isEmpty == false
        }
        guard hasWords else { return .lineSynced }
        if declaredSynchronization == .syllableSynced {
            return .syllableSynced
        }
        return .wordSynced
    }

    var isSynchronized: Bool {
        synchronization != .unsynced
    }

    var isPersistedLocally: Bool {
        source?.kind == .localImport
            || source?.kind == .custom
            || source == nil
    }

    var hasTranslations: Bool {
        lines.contains { ($0.translation?.isEmpty == false) }
    }

    var hasPronunciations: Bool {
        lines.contains { ($0.pronunciation?.isEmpty == false) }
    }
}

/// User-selected or offset-tuned lyrics snapshot remembered for a specific song metadata key.
nonisolated struct LyricsSavedBinding: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var trackKey: LyricsTrackKey
    var document: LyricsDocument
    var lyricsOffsetSeconds: Double
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        trackKey: LyricsTrackKey,
        document: LyricsDocument,
        lyricsOffsetSeconds: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.trackKey = trackKey
        self.document = document
        self.lyricsOffsetSeconds = lyricsOffsetSeconds
        self.updatedAt = updatedAt
    }
}

