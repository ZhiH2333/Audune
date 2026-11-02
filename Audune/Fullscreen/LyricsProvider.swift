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
nonisolated enum LyricsQuality {
    static func score(
        request: LyricsSearchRequest,
        title: String,
        artist: String,
        durationSeconds: Double?,
        lineCount: Int
    ) -> Double {
        var quality = 0.4
        if fuzzyMatch(title, request.title) { quality += 0.35 }
        if fuzzyMatch(artist, request.artist) { quality += 0.30 }
        if let durationSeconds, request.durationSeconds > 0 {
            let delta = abs(durationSeconds - request.durationSeconds)
            if delta <= 2 { quality += 0.15 }
            else if delta <= 5 { quality += 0.08 }
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

    private static func normalize(_ value: String) -> String {
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
                if let hit { collected.append(hit) }
            }
            return collected
        }
        guard let best = hits.max(by: { $0.quality < $1.quality }), best.quality >= minimumQuality else {
            throw LyricsFetchError.notFound
        }
        return best
    }
}
