import Foundation

/// LyricsX / LyricsKit–style search request built from Now Playing metadata only.
nonisolated struct LyricsSearchRequest: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var durationSeconds: Double

    var keyword: String {
        [artist, title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    var isSearchable: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    init(title: String, artist: String, album: String, durationSeconds: Double) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        self.durationSeconds = max(0, durationSeconds)
    }

    init(_ query: LyricsQuery) {
        self.init(
            title: query.title,
            artist: query.artist,
            album: query.album,
            durationSeconds: query.durationSeconds
        )
    }
}

nonisolated enum LyricsSourceID: String, Equatable, Sendable, CaseIterable {
    case lrclib
    case netease
    case qq
    case kugou

    var displayName: String {
        switch self {
        case .lrclib: return "LRCLIB"
        case .netease: return "NetEase"
        case .qq: return "QQ Music"
        case .kugou: return "Kugou"
        }
    }
}

nonisolated enum LyricsSourceSelection: String, Equatable, Sendable, CaseIterable, Identifiable {
    case automatic
    case lrclib
    case netease
    case qq
    case kugou

    var id: String { rawValue }

    var sourceID: LyricsSourceID? {
        LyricsSourceID(rawValue: rawValue)
    }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic (fastest)")
        case .lrclib: return LyricsSourceID.lrclib.displayName
        case .netease: return LyricsSourceID.netease.displayName
        case .qq: return LyricsSourceID.qq.displayName
        case .kugou: return LyricsSourceID.kugou.displayName
        }
    }
}

nonisolated struct LyricsHit: Equatable, Sendable {
    var source: LyricsSourceID
    var matchedTitle: String
    var matchedArtist: String
    var durationSeconds: Double?
    var rawLRC: String
    var lines: [LyricLine]
    var quality: Double
}

/// Quality scoring inspired by LyricsKit: prefer title/artist/duration match and timed lines.
/// Title + duration can carry a hit when artist is romanized differently (e.g. kakizaki vs 柿崎).
nonisolated enum LyricsQuality {
    static func score(
        request: LyricsSearchRequest,
        title: String,
        artist: String,
        durationSeconds: Double?,
        lineCount: Int
    ) -> Double {
        var quality = 0.35
        let titleNorm = normalize(title)
        let requestTitle = normalize(request.title)
        if titleNorm.isEmpty == false, requestTitle.isEmpty == false {
            if titleNorm == requestTitle {
                quality += 0.45
            } else if fuzzyMatch(title, request.title) {
                quality += 0.28
            }
        }
        if fuzzyMatch(artist, request.artist) {
            quality += 0.28
        }
        if let durationSeconds, request.durationSeconds > 0 {
            let delta = abs(durationSeconds - request.durationSeconds)
            if delta <= 2 { quality += 0.18 }
            else if delta <= 5 { quality += 0.10 }
        }
        if lineCount >= 8 { quality += 0.12 }
        else if lineCount >= 3 { quality += 0.08 }
        else if lineCount >= 1 { quality += 0.04 }
        return quality
    }

    static func fuzzyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalize(lhs)
        let b = normalize(rhs)
        guard a.isEmpty == false, b.isEmpty == false else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

nonisolated protocol LyricsProvider: Sendable {
    var id: LyricsSourceID { get }
    /// Returns a synced hit or nil when this source has nothing usable.
    func search(request: LyricsSearchRequest) async -> LyricsHit?
}

/// Fan-out across domestic + international providers; pick the highest-quality synced hit.
nonisolated struct LyricsProviderGroup: LyricsFetching {
    var providers: [any LyricsProvider]
    /// Minimum quality to accept a hit (avoids wildly mismatched lyrics).
    var minimumQuality: Double

    init(
        providers: [any LyricsProvider] = LyricsProviderGroup.defaultProviders,
        minimumQuality: Double = 0.55
    ) {
        self.providers = providers
        self.minimumQuality = minimumQuality
    }

    static var defaultProviders: [any LyricsProvider] {
        [
            LRCLIBProvider(),
            NetEaseLyricsProvider(),
            QQMusicLyricsProvider(),
            KugouLyricsProvider()
        ]
    }

    func fetchSyncedLyrics(for query: LyricsQuery) async throws -> String {
        let hit = try await searchBest(for: LyricsSearchRequest(query))
        return hit.rawLRC
    }

    func searchBest(for request: LyricsSearchRequest) async throws -> LyricsHit {
        guard request.isSearchable else { throw LyricsFetchError.emptyQuery }
        let hits: [LyricsHit] = await withTaskGroup(of: LyricsHit?.self, returning: [LyricsHit].self) { group in
            for provider in providers {
                group.addTask {
                    await provider.search(request: request)
                }
            }
            var collected: [LyricsHit] = []
            for await hit in group {
                if let hit {
                    collected.append(hit)
                    // High-confidence short circuit: if exact/strong match is found,
                    // cancel slower pending providers to return immediately.
                    if hit.quality >= 0.85 {
                        group.cancelAll()
                        return [hit]
                    }
                }
            }
            return collected
        }
        guard let best = hits.max(by: { $0.quality < $1.quality }), best.quality >= minimumQuality else {
            throw LyricsFetchError.notFound
        }
        return best
    }

    func search(
        for request: LyricsSearchRequest,
        selection: LyricsSourceSelection
    ) async throws -> LyricsHit {
        guard request.isSearchable else { throw LyricsFetchError.emptyQuery }

        if let sourceID = selection.sourceID {
            guard let provider = providers.first(where: { $0.id == sourceID }) else {
                throw LyricsFetchError.sourceUnavailable
            }
            guard let hit = await provider.search(request: request), hit.quality >= minimumQuality else {
                throw LyricsFetchError.notFound
            }
            return hit
        }

        let fastestHit = await withTaskGroup(of: LyricsHit?.self, returning: LyricsHit?.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.search(request: request)
                }
            }

            var bestFallback: LyricsHit?
            for await hit in group {
                guard let hit else { continue }
                if hit.quality >= minimumQuality {
                    group.cancelAll()
                    return hit
                }
                if bestFallback == nil || hit.quality > bestFallback!.quality {
                    bestFallback = hit
                }
            }
            return bestFallback
        }

        guard let fastestHit, fastestHit.quality >= minimumQuality else {
            throw LyricsFetchError.notFound
        }
        return fastestHit
    }
}
