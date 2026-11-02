import Foundation

/// Domestic source inspired by LyricsX/LyricsKit NetEase endpoints (rewritten async; MPL research reference).
/// Sends only title/artist search text — never artwork or PCM.
nonisolated struct NetEaseLyricsProvider: LyricsProvider {
    var id: LyricsSourceID { .netease }
    var session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(request: LyricsSearchRequest) async -> LyricsHit? {
        do {
            guard let song = try await searchSong(request) else { return nil }
            guard let raw = try await fetchLyric(songID: song.id) else { return nil }
            let normalized = LyricsHTTP.normalizeNetEaseTimeTags(raw)
            let lines = LRCParser.parse(normalized)
            guard lines.isEmpty == false else { return nil }
            let quality = LyricsQuality.score(
                request: request,
                title: song.name,
                artist: song.artist,
                durationSeconds: song.durationSeconds,
                lineCount: lines.count
            )
            return LyricsHit(
                source: .netease,
                matchedTitle: song.name,
                matchedArtist: song.artist,
                durationSeconds: song.durationSeconds,
                rawLRC: normalized,
                lines: lines,
                quality: quality
            )
        } catch {
            return nil
        }
    }

    private struct SongHit {
        var id: Int
        var name: String
        var artist: String
        var durationSeconds: Double?
    }

    private func searchSong(_ request: LyricsSearchRequest) async throws -> SongHit? {
        let queries = [request.keyword, request.title].filter { $0.isEmpty == false }
        var best: (SongHit, Double)?
        for query in queries {
            guard let songs = try await searchList(query: query) else { continue }
            for song in songs {
                let score = LyricsQuality.score(
                    request: request,
                    title: song.name,
                    artist: song.artist,
                    durationSeconds: song.durationSeconds,
                    lineCount: 8
                )
                if let current = best {
                    if score > current.1 { best = (song, score) }
                } else {
                    best = (song, score)
                }
            }
        }
        guard let best, best.1 >= 0.55 else { return nil }
        return best.0
    }

    private func searchList(query: String) async throws -> [SongHit]? {
        var components = URLComponents(string: "http://music.163.com/api/search/pc")
        components?.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "type", value: "1")
        ]
        guard let url = components?.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("http://music.163.com/", forHTTPHeaderField: "Referer")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse,
           let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"),
           setCookie.isEmpty == false {
            let cookie = setCookie.split(separator: ";").first.map(String.init) ?? setCookie
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
            let (retryData, _) = try await session.data(for: req)
            return parseSearch(retryData)
        }
        return parseSearch(data)
    }

    private func parseSearch(_ data: Data) -> [SongHit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        // NetEase anti-bot responses use code != 200 and no songs.
        if let code = root["code"] as? Int, code != 200, root["result"] == nil {
            return []
        }
        let songs = (root["result"] as? [String: Any])?["songs"] as? [[String: Any]]
            ?? root["songs"] as? [[String: Any]]
            ?? []
        var hits: [SongHit] = []
        for song in songs {
            guard let id = song["id"] as? Int else { continue }
            let name = (song["name"] as? String) ?? ""
            let artists = song["artists"] as? [[String: Any]] ?? []
            let artist = artists.compactMap { $0["name"] as? String }.joined(separator: "/")
            let durationMs = (song["duration"] as? Int) ?? (song["duration"] as? Double).map(Int.init)
            let durationSeconds = durationMs.map { Double($0) / 1000 }
            hits.append(SongHit(id: id, name: name, artist: artist, durationSeconds: durationSeconds))
        }
        return hits
    }

    private func fetchLyric(songID: Int) async throws -> String? {
        var components = URLComponents(string: "http://music.163.com/api/song/lyric")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1")
        ]
        guard let url = components?.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("http://music.163.com/", forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: req)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let lrc = (root["lrc"] as? [String: Any])?["lyric"] as? String, lrc.isEmpty == false {
            return lrc
        }
        if let klyric = (root["klyric"] as? [String: Any])?["lyric"] as? String, klyric.isEmpty == false {
            return klyric
        }
        return nil
    }
}
