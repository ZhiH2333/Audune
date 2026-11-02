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

/// International source: https://lrclib.net (no API key). Metadata only — never artwork/PCM.
nonisolated struct LRCLIBProvider: LyricsProvider {
    var id: LyricsSourceID { .lrclib }
    var session: URLSession
    var baseURL: URL

    init(
        session: URLSession = LyricsHTTP.sharedSession,
        baseURL: URL = URL(string: "https://lrclib.net")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func search(request: LyricsSearchRequest) async -> LyricsHit? {
        do {
            let raw: String
            if let exact = try await fetchExact(request) {
                raw = exact
            } else {
                raw = try await fetchSearch(request)
            }
            let lines = LRCParser.parse(raw)
            guard lines.isEmpty == false else { return nil }
            let quality = LyricsQuality.score(
                request: request,
                title: request.title,
                artist: request.artist,
                durationSeconds: request.durationSeconds > 0 ? request.durationSeconds : nil,
                lineCount: lines.count
            )
            return LyricsHit(
                source: .lrclib,
                matchedTitle: request.title,
                matchedArtist: request.artist,
                durationSeconds: request.durationSeconds > 0 ? request.durationSeconds : nil,
                rawLRC: raw,
                lines: lines,
                quality: quality
            )
        } catch {
            return nil
        }
    }

    private func fetchExact(_ request: LyricsSearchRequest) async throws -> String? {
        var components = URLComponents(url: baseURL.appending(path: "/api/get"), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: request.title),
            URLQueryItem(name: "artist_name", value: request.artist)
        ]
        if request.album.isEmpty == false {
            items.append(URLQueryItem(name: "album_name", value: request.album))
        }
        if request.durationSeconds > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(request.durationSeconds.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw LyricsFetchError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw LyricsFetchError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else {
            throw LyricsFetchError.transport("HTTP \(http.statusCode)")
        }
        return try decodeSynced(from: data)
    }

    private func fetchSearch(_ request: LyricsSearchRequest) async throws -> String {
        var components = URLComponents(url: baseURL.appending(path: "/api/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: request.keyword)]
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

/// Backward-compatible alias used by older call sites / tests.
typealias LRCLIBClient = LRCLIBProvider

extension LRCLIBProvider: LyricsFetching {
    func fetchSyncedLyrics(for query: LyricsQuery) async throws -> String {
        guard let hit = await search(request: LyricsSearchRequest(query)) else {
            throw LyricsFetchError.notFound
        }
        return hit.rawLRC
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

nonisolated enum LyricsHTTP {
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        config.waitsForConnectivity = false
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    static func queryString(_ items: [String: String]) -> String {
        items
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    static func decodeBase64Text(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }

    /// NetEase sometimes emits `[mm:ss:xx]` instead of `[mm:ss.xx]`.
    static func normalizeNetEaseTimeTags(_ lrc: String) -> String {
        lrc.replacingOccurrences(
            of: #"(\[\d+:\d+):(\d+\])"#,
            with: "$1.$2",
            options: .regularExpression
        )
    }
}
