import Foundation

nonisolated struct LyricsQuery: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var durationSeconds: Double

    var cacheKey: String {
        let durationKey = durationSeconds > 0 ? String(format: "%.0f", durationSeconds) : "-"
        return "\(title.lowercased())|\(artist.lowercased())|\(album.lowercased())|\(durationKey)"
    }

    var isSearchable: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

nonisolated enum LyricsFetchError: Error, Equatable, Sendable {
    case disabled
    case emptyQuery
    case notFound
    case invalidResponse
    case transport(String)
}

nonisolated protocol LyricsFetching: Sendable {
    func fetchSyncedLyrics(for query: LyricsQuery) async throws -> String
}

/// HTTPS client for lrclib.net. Sends only title/artist/album/duration — never artwork or PCM.
nonisolated struct LRCLIBClient: LyricsFetching {
    var session: URLSession
    var baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://lrclib.net")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchSyncedLyrics(for query: LyricsQuery) async throws -> String {
        guard query.isSearchable else { throw LyricsFetchError.emptyQuery }
        if let exact = try await fetchExact(query) {
            return exact
        }
        return try await fetchSearch(query)
    }

    private func fetchExact(_ query: LyricsQuery) async throws -> String? {
        var components = URLComponents(url: baseURL.appending(path: "/api/get"), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist)
        ]
        if query.album.isEmpty == false {
            items.append(URLQueryItem(name: "album_name", value: query.album))
        }
        if query.durationSeconds > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(query.durationSeconds.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw LyricsFetchError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw LyricsFetchError.invalidResponse }
        if http.statusCode == 404 {
            return nil
        }
        guard (200...299).contains(http.statusCode) else {
            throw LyricsFetchError.transport("HTTP \(http.statusCode)")
        }
        return try decodeSynced(from: data)
    }

    private func fetchSearch(_ query: LyricsQuery) async throws -> String {
        var components = URLComponents(url: baseURL.appending(path: "/api/search"), resolvingAgainstBaseURL: false)
        let q = [query.artist, query.title].filter { $0.isEmpty == false }.joined(separator: " ")
        components?.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = components?.url else { throw LyricsFetchError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LyricsFetchError.transport("search failed")
        }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LyricsFetchError.invalidResponse
        }
        for row in rows {
            if let synced = row["syncedLyrics"] as? String, synced.isEmpty == false {
                return synced
            }
        }
        throw LyricsFetchError.notFound
    }

    private func decodeSynced(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LyricsFetchError.invalidResponse
        }
        if let synced = object["syncedLyrics"] as? String, synced.isEmpty == false {
            return synced
        }
        throw LyricsFetchError.notFound
    }
}

/// Test double that records queries and never hits the network unless configured.
nonisolated final class RecordingLyricsFetcher: LyricsFetching, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var queries: [LyricsQuery] = []
    var result: Result<String, LyricsFetchError> = .failure(.notFound)

    func fetchSyncedLyrics(for query: LyricsQuery) async throws -> String {
        lock.lock()
        queries.append(query)
        let current = result
        lock.unlock()
        switch current {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }

    var queryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return queries.count
    }
}
