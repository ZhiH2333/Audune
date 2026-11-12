import Foundation
import CryptoKit

nonisolated struct LyricsScoredCandidate: Equatable, Identifiable, Sendable {
    var id: UUID { document.id }
    var document: LyricsDocument
    var providerID: String
    var nodeID: String?
    var latencySeconds: TimeInterval
    var trackMatchScore: Double
    var syncScore: Double
    var contentScore: Double
    var reliabilityScore: Double
    var totalScore: Double
    var contentFingerprint: String
}

nonisolated enum LyricsCandidateRanker {
    /// Hard gate: reject clearly mismatched lyrics before ranking.
    static func passesTrackMatch(_ document: LyricsDocument, trackKey: LyricsTrackKey) -> Bool {
        scoreTrackMatch(document.trackKey, expected: trackKey) >= 4.5
    }

    static func score(
        document: LyricsDocument,
        expected: LyricsTrackKey,
        providerID: String,
        nodeID: String?,
        latencySeconds: TimeInterval,
        reliabilityScore: Double
    ) -> LyricsScoredCandidate? {
        let trackScore = scoreTrackMatch(document.trackKey, expected: expected)
        guard trackScore >= 4.5 else { return nil }
        guard document.lines.isEmpty == false else { return nil }

        let syncScore = scoreSync(document.synchronization)
        let contentScore = scoreContent(document)
        let latencyScore = scoreLatency(latencySeconds)
        let reliability = min(max(reliabilityScore, 0), 1)
        let total =
            trackScore * 3.0
            + syncScore * 2.2
            + contentScore * 1.4
            + latencyScore * 0.8
            + reliability * 1.0

        return LyricsScoredCandidate(
            document: document,
            providerID: providerID,
            nodeID: nodeID,
            latencySeconds: latencySeconds,
            trackMatchScore: trackScore,
            syncScore: syncScore,
            contentScore: contentScore,
            reliabilityScore: reliability,
            totalScore: total,
            contentFingerprint: fingerprint(document)
        )
    }

    /// Lenient scoring used by the interactive Lyrics Picker so the listener can inspect and
    /// preview alternate editions, covers, or translations returned for a custom search query.
    static func scoreLenient(
        document: LyricsDocument,
        expected: LyricsTrackKey,
        providerID: String,
        nodeID: String?,
        latencySeconds: TimeInterval,
        reliabilityScore: Double
    ) -> LyricsScoredCandidate? {
        guard document.lines.isEmpty == false else { return nil }
        let rawTrackScore = scoreTrackMatch(document.trackKey, expected: expected)
        let trackScore = max(rawTrackScore, 2.0)
        let syncScore = scoreSync(document.synchronization)
        let contentScore = scoreContent(document)
        let latencyScore = scoreLatency(latencySeconds)
        let reliability = min(max(reliabilityScore, 0), 1)
        let total =
            trackScore * 3.0
            + syncScore * 2.2
            + contentScore * 1.4
            + latencyScore * 0.8
            + reliability * 1.0

        return LyricsScoredCandidate(
            document: document,
            providerID: providerID,
            nodeID: nodeID,
            latencySeconds: latencySeconds,
            trackMatchScore: trackScore,
            syncScore: syncScore,
            contentScore: contentScore,
            reliabilityScore: reliability,
            totalScore: total,
            contentFingerprint: fingerprint(document)
        )
    }

    static func sorted(_ candidates: [LyricsScoredCandidate]) -> [LyricsScoredCandidate] {
        deduplicated(candidates).sorted { lhs, rhs in
            if abs(lhs.totalScore - rhs.totalScore) > 0.01 {
                return lhs.totalScore > rhs.totalScore
            }
            if abs(lhs.syncScore - rhs.syncScore) > 0.01 {
                return lhs.syncScore > rhs.syncScore
            }
            if abs(lhs.trackMatchScore - rhs.trackMatchScore) > 0.01 {
                return lhs.trackMatchScore > rhs.trackMatchScore
            }
            return lhs.latencySeconds < rhs.latencySeconds
        }
    }

    static func best(of candidates: [LyricsScoredCandidate]) -> LyricsScoredCandidate? {
        deduplicated(candidates).max(by: { lhs, rhs in
            if abs(lhs.totalScore - rhs.totalScore) > 0.01 {
                return lhs.totalScore < rhs.totalScore
            }
            if abs(lhs.syncScore - rhs.syncScore) > 0.01 {
                return lhs.syncScore < rhs.syncScore
            }
            if abs(lhs.trackMatchScore - rhs.trackMatchScore) > 0.01 {
                return lhs.trackMatchScore < rhs.trackMatchScore
            }
            return lhs.latencySeconds > rhs.latencySeconds
        })
    }

    static func deduplicated(_ candidates: [LyricsScoredCandidate]) -> [LyricsScoredCandidate] {
        var bestByFingerprint: [String: LyricsScoredCandidate] = [:]
        for candidate in candidates {
            if let existing = bestByFingerprint[candidate.contentFingerprint] {
                if candidate.totalScore > existing.totalScore
                    || (abs(candidate.totalScore - existing.totalScore) < 0.01
                        && candidate.syncScore > existing.syncScore)
                {
                    bestByFingerprint[candidate.contentFingerprint] = candidate
                }
            } else {
                bestByFingerprint[candidate.contentFingerprint] = candidate
            }
        }
        return Array(bestByFingerprint.values)
    }

    static func fingerprint(_ document: LyricsDocument) -> String {
        let lines = document.lines
            .map { line in
                let start = line.startSeconds.map { String(format: "%.2f", $0) } ?? "-"
                let text = LyricsTrackMatcher.normalized(line.text)
                return "\(start)|\(text)"
            }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(lines.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func scoreTrackMatch(_ candidate: LyricsTrackKey, expected: LyricsTrackKey) -> Double {
        if let left = LyricsTrackMatcher.normalizedISRC(candidate.isrc),
           let right = LyricsTrackMatcher.normalizedISRC(expected.isrc)
        {
            return left == right ? 10 : 0
        }

        let title = LyricsTrackMatcher.normalized(candidate.title)
        let artist = LyricsTrackMatcher.normalized(candidate.artist)
        let expectedTitle = LyricsTrackMatcher.normalized(expected.title)
        let expectedArtist = LyricsTrackMatcher.normalized(expected.artist)
        guard title.isEmpty == false, artist.isEmpty == false else { return 0 }

        var score = 0.0
        if title == expectedTitle { score += 4 }
        else if LyricsTrackMatcher.baseTitle(title) == LyricsTrackMatcher.baseTitle(expectedTitle) {
            score += 3
        } else if title.contains(expectedTitle) || expectedTitle.contains(title) {
            score += 1.5
        } else {
            return 0
        }

        if artist == expectedArtist { score += 4 }
        else if artist.contains(expectedArtist) || expectedArtist.contains(artist) {
            score += 2
        } else {
            return 0
        }

        if let album = nonEmpty(LyricsTrackMatcher.normalized(candidate.album)),
           let expectedAlbum = nonEmpty(LyricsTrackMatcher.normalized(expected.album))
        {
            if album == expectedAlbum { score += 1 }
        }

        if let duration = LyricsTrackMatcher.validDuration(candidate.durationSeconds),
           let expectedDuration = LyricsTrackMatcher.validDuration(expected.durationSeconds)
        {
            let delta = abs(duration - expectedDuration)
            if delta <= 2 { score += 1.5 }
            else if delta <= 5 { score += 0.5 }
            else { return 0 }
        }

        return score
    }

    static func scoreSync(_ sync: LyricsSynchronization) -> Double {
        switch sync {
        case .syllableSynced: return 4
        case .wordSynced: return 3
        case .lineSynced: return 2
        case .unsynced: return 0.5
        }
    }

    static func scoreContent(_ document: LyricsDocument) -> Double {
        let timed = document.lines.filter { $0.startSeconds != nil }.count
        let total = max(document.lines.count, 1)
        var score = Double(timed) / Double(total) * 2
        if document.lines.contains(where: { $0.translation?.isEmpty == false }) { score += 0.4 }
        if document.lines.contains(where: { $0.pronunciation?.isEmpty == false }) { score += 0.2 }
        if document.lines.contains(where: { ($0.words?.count ?? 0) > 1 }) { score += 0.6 }
        if document.lines.count < 2 { score -= 1 }
        return max(0, score)
    }

    static func scoreLatency(_ seconds: TimeInterval) -> Double {
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        if seconds <= 0.8 { return 1.2 }
        if seconds <= 1.5 { return 1.0 }
        if seconds <= 3.0 { return 0.7 }
        if seconds <= 6.0 { return 0.4 }
        return 0.1
    }
}

private func nonEmpty(_ value: String) -> String? {
    value.isEmpty ? nil : value
}
