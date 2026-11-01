import Foundation

/// Loads synced lyrics when the user enables network search. Never uploads artwork or PCM.
@MainActor
@Observable
final class LyricsService {
    private(set) var status: LyricsLoadStatus = .idle
    private(set) var lines: [LyricLine] = []
    private(set) var activeTrackKey: String?

    private let fetcher: any LyricsFetching
    private var cache: [String: [LyricLine]] = [:]
    private var inFlight: Task<Void, Never>?
    private let maxCacheEntries = 32

    init(fetcher: any LyricsFetching = LRCLIBClient()) {
        self.fetcher = fetcher
    }

    func reset() {
        inFlight?.cancel()
        inFlight = nil
        status = .idle
        lines = []
        activeTrackKey = nil
    }

    /// Update lyrics for the current Now Playing snapshot. No network when `networkEnabled` is false.
    func sync(snapshot: NowPlayingSnapshot, networkEnabled: Bool) {
        guard networkEnabled else {
            inFlight?.cancel()
            inFlight = nil
            status = .disabled
            lines = []
            activeTrackKey = nil
            return
        }
        guard snapshot.hasTrack else {
            inFlight?.cancel()
            inFlight = nil
            status = .empty
            lines = []
            activeTrackKey = nil
            return
        }

        let query = LyricsQuery(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            durationSeconds: snapshot.durationSeconds
        )
        let key = query.cacheKey
        if key == activeTrackKey, status == .ready || status == .loading || status == .empty || status.isFailure {
            return
        }
        activeTrackKey = key

        if let cached = cache[key] {
            lines = cached
            status = cached.isEmpty ? .empty : .ready
            return
        }

        inFlight?.cancel()
        status = .loading
        lines = []
        let trackKey = key
        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await fetcher.fetchSyncedLyrics(for: query)
                guard Task.isCancelled == false else { return }
                let parsed = LRCParser.parse(raw)
                await MainActor.run {
                    guard self.activeTrackKey == trackKey else { return }
                    self.storeCache(parsed, for: trackKey)
                    self.lines = parsed
                    self.status = parsed.isEmpty ? .empty : .ready
                }
            } catch let error as LyricsFetchError {
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    guard self.activeTrackKey == trackKey else { return }
                    self.lines = []
                    switch error {
                    case .disabled:
                        self.status = .disabled
                    case .emptyQuery, .notFound:
                        self.status = .empty
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
                    self.status = .failed(String(localized: "Lyrics network error"))
                }
            }
        }
    }

    private func storeCache(_ lines: [LyricLine], for key: String) {
        if cache.count >= maxCacheEntries, cache[key] == nil {
            if let first = cache.keys.first {
                cache.removeValue(forKey: first)
            }
        }
        cache[key] = lines
    }
}
