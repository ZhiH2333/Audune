import Foundation

/// Loads synced lyrics when the user enables network search.
/// Fan-out across LRCLIB + domestic providers (NetEase / QQ / Kugou), pick by quality.
/// Never uploads artwork or PCM.
@MainActor
@Observable
final class LyricsService {
    private(set) var status: LyricsLoadStatus = .idle
    private(set) var lines: [LyricLine] = []
    private(set) var activeTrackKey: String?
    private(set) var sourceID: LyricsSourceID?
    private(set) var matchedTitle: String = ""
    private(set) var matchedArtist: String = ""

    private let fetcher: any LyricsFetching
    private let group: LyricsProviderGroup?
    private var cache: [String: CachedHit] = [:]
    private var lastAttemptAt: [String: Date] = [:]
    private var inFlight: Task<Void, Never>?
    private let maxCacheEntries = 32
    /// Empty/failure is not permanent — providers like LRCLIB 503 should be retried.
    private let retryCooldown: TimeInterval = 3

    private struct CachedHit {
        var lines: [LyricLine]
        var sourceID: LyricsSourceID?
        var matchedTitle: String
        var matchedArtist: String
        var rawLRC: String
    }

    init(fetcher: any LyricsFetching = LyricsProviderGroup()) {
        self.fetcher = fetcher
        self.group = fetcher as? LyricsProviderGroup
    }

    func reset() {
        inFlight?.cancel()
        inFlight = nil
        status = .idle
        lines = []
        activeTrackKey = nil
        sourceID = nil
        matchedTitle = ""
        matchedArtist = ""
    }

    /// Update lyrics for the current Now Playing snapshot. No network when `networkEnabled` is false.
    func sync(
        snapshot: NowPlayingSnapshot,
        networkEnabled: Bool,
        sourceSelection: LyricsSourceSelection = .automatic
    ) {
        guard networkEnabled else {
            inFlight?.cancel()
            inFlight = nil
            status = .disabled
            lines = []
            activeTrackKey = nil
            sourceID = nil
            matchedTitle = ""
            matchedArtist = ""
            return
        }
        guard snapshot.hasTrack else {
            inFlight?.cancel()
            inFlight = nil
            status = .empty
            lines = []
            activeTrackKey = nil
            sourceID = nil
            matchedTitle = ""
            matchedArtist = ""
            return
        }

        let query = LyricsQuery(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            durationSeconds: snapshot.durationSeconds
        )
        let key = "\(query.cacheKey)|\(sourceSelection.rawValue)"
        if key == activeTrackKey {
            if status == .ready || status == .loading {
                return
            }
            if (status == .empty || status.isFailure),
               let last = lastAttemptAt[key],
               Date().timeIntervalSince(last) < retryCooldown {
                return
            }
        }
        activeTrackKey = key

        if let cached = cache[key], cached.lines.isEmpty == false {
            lines = cached.lines
            sourceID = cached.sourceID
            matchedTitle = cached.matchedTitle
            matchedArtist = cached.matchedArtist
            status = .ready
            return
        }

        inFlight?.cancel()
        status = .loading
        lines = []
        sourceID = nil
        matchedTitle = ""
        matchedArtist = ""
        lastAttemptAt[key] = Date()
        let trackKey = key
        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                if let group {
                    let hit = try await group.search(
                        for: LyricsSearchRequest(query),
                        selection: sourceSelection
                    )
                    guard Task.isCancelled == false else { return }
                    await MainActor.run {
                        guard self.activeTrackKey == trackKey else { return }
                        self.apply(hit: hit, cacheKey: trackKey)
                    }
                } else {
                    guard sourceSelection == .automatic else {
                        throw LyricsFetchError.sourceUnavailable
                    }
                    let raw = try await fetcher.fetchSyncedLyrics(for: query)
                    guard Task.isCancelled == false else { return }
                    let parsed = LRCParser.parse(raw)
                    await MainActor.run {
                        guard self.activeTrackKey == trackKey else { return }
                        self.apply(
                            hit: LyricsHit(
                                source: .lrclib,
                                matchedTitle: query.title,
                                matchedArtist: query.artist,
                                durationSeconds: query.durationSeconds,
                                rawLRC: raw,
                                lines: parsed,
                                quality: 1
                            ),
                            cacheKey: trackKey
                        )
                    }
                }
            } catch let error as LyricsFetchError {
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    guard self.activeTrackKey == trackKey else { return }
                    self.lines = []
                    self.sourceID = nil
                    switch error {
                    case .disabled:
                        self.status = .disabled
                    case .emptyQuery, .notFound:
                        self.status = .empty
                    case .sourceUnavailable:
                        self.status = .failed(String(localized: "Selected lyrics source is unavailable"))
                    case .invalidResponse:
                        self.status = .failed(String(localized: "Couldn’t read lyrics"))
                    case .transport:
                        self.status = .failed(String(localized: "Lyrics network error"))
                    }
                }
            } catch {
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    guard self.activeTrackKey == trackKey else { return }
                    self.lines = []
                    self.sourceID = nil
                    self.status = .failed(String(localized: "Lyrics network error"))
                }
            }
        }
    }

    private func apply(hit: LyricsHit, cacheKey: String) {
        storeCache(
            CachedHit(
                lines: hit.lines,
                sourceID: hit.source,
                matchedTitle: hit.matchedTitle,
                matchedArtist: hit.matchedArtist,
                rawLRC: hit.rawLRC
            ),
            for: cacheKey
        )
        lines = hit.lines
        sourceID = hit.source
        matchedTitle = hit.matchedTitle
        matchedArtist = hit.matchedArtist
        status = hit.lines.isEmpty ? .empty : .ready
    }

    private func storeCache(_ hit: CachedHit, for key: String) {
        if cache.count >= maxCacheEntries, cache[key] == nil {
            if let first = cache.keys.first {
                cache.removeValue(forKey: first)
            }
        }
        cache[key] = hit
    }
}
