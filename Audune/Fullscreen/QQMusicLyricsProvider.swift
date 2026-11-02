import Foundation

/// Domestic source inspired by LyricsX/LyricsKit QQ Music endpoints (rewritten async; research reference).
nonisolated struct QQMusicLyricsProvider: LyricsProvider {
    var id: LyricsSourceID { .qq }
    var session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(request: LyricsSearchRequest) async -> LyricsHit? {
        do {
            guard let song = try await bestSong(for: request) else { return nil }
            guard let payload = try await fetchLyric(songmid: song.songmid) else { return nil }
            let lines = LRCParser.parse(payload.lrc, translationRaw: payload.trans)
            guard lines.isEmpty == false else { return nil }
            let quality = LyricsQuality.score(
                request: request,
                title: song.name,
                artist: song.artist,
                durationSeconds: song.durationSeconds,
                lineCount: lines.count
            )
            guard quality >= 0.55 else { return nil }
            return LyricsHit(
                source: .qq,
                matchedTitle: song.name,
                matchedArtist: song.artist,
                durationSeconds: song.durationSeconds,
                rawLRC: payload.lrc,
                lines: lines,
                quality: quality
            )
        } catch {
            return nil
        }
    }

    private struct SongHit {
        var songmid: String
        var name: String
        var artist: String
        var durationSeconds: Double?
    }

    /// Score every candidate across a few query shapes — never blindly take list[0].
    private func bestSong(for request: LyricsSearchRequest) async throws -> SongHit? {
        var queries: [String] = []
        let keyword = request.keyword
        if keyword.isEmpty == false { queries.append(keyword) }
        if request.title.isEmpty == false { queries.append(request.title) }
        if request.title.isEmpty == false, request.artist.isEmpty == false {
            queries.append("\(request.title) \(request.artist)")
        }
        var seen = Set<String>()
        queries = queries.filter { seen.insert($0).inserted }

        var best: (song: SongHit, score: Double)?
        for query in queries {
            let songs = try await searchList(query: query)
            for song in songs {
                let score = LyricsQuality.score(
                    request: request,
                    title: song.name,
                    artist: song.artist,
                    durationSeconds: song.durationSeconds,
                    lineCount: 8
                )
                if let current = best {
                    if score > current.score {
                        best = (song, score)
                    }
                } else {
                    best = (song, score)
                }
            }
        }
        guard let best, best.score >= 0.55 else { return nil }
        return best.song
    }

    private func searchList(query: String) async throws -> [SongHit] {
        var components = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")
        components?.queryItems = [
            URLQueryItem(name: "w", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "n", value: "10")
        ]
        guard let url = components?.url else { return [] }
        let (data, _) = try await session.data(from: url)
        let jsonData = unwrapJSONP(data) ?? data
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let list = ((root["data"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [[String: Any]]
        else { return [] }

        var songs: [SongHit] = []
        songs.reserveCapacity(list.count)
        for item in list {
            guard let songmid = item["songmid"] as? String, songmid.isEmpty == false else { continue }
            let name = (item["songname"] as? String) ?? ""
            let singers = item["singer"] as? [[String: Any]] ?? []
            let artist = singers.compactMap { $0["name"] as? String }.joined(separator: "/")
            let interval = (item["interval"] as? Int).map(Double.init)
                ?? (item["interval"] as? Double)
            songs.append(SongHit(songmid: songmid, name: name, artist: artist, durationSeconds: interval))
        }
        return songs
    }

    private func fetchLyric(songmid: String) async throws -> (lrc: String, trans: String?)? {
        var components = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")
        components?.queryItems = [
            URLQueryItem(name: "songmid", value: songmid),
            URLQueryItem(name: "g_tk", value: "5381"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "0")
        ]
        guard let url = components?.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("https://y.qq.com/portal/player.html", forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: req)
        let jsonData = unwrapJSONP(data) ?? data
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let lyricB64 = root["lyric"] as? String,
              lyricB64.isEmpty == false,
              let text = LyricsHTTP.decodeBase64Text(lyricB64),
              text.isEmpty == false
        else { return nil }
        let transB64 = root["trans"] as? String
        let transText = transB64.flatMap { LyricsHTTP.decodeBase64Text($0) }
        return (text, transText?.isEmpty == false ? transText : nil)
    }

    /// QQ often wraps payloads as `MusicJsonCallback(...)` / `callback(...)`.
    private func unwrapJSONP(_ data: Data) -> Data? {
        guard var text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false
        else { return nil }
        if text.hasPrefix("{") { return data }
        guard let start = text.firstIndex(of: "("),
              let end = text.lastIndex(of: ")"),
              start < end
        else { return nil }
        text = String(text[text.index(after: start)..<end])
        return text.data(using: .utf8)
    }
}
