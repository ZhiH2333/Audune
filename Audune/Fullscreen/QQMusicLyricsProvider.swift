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
            guard let song = try await searchSong(request) else { return nil }
            guard let raw = try await fetchLyric(songmid: song.songmid) else { return nil }
            let lines = LRCParser.parse(raw)
            guard lines.isEmpty == false else { return nil }
            let quality = LyricsQuality.score(
                request: request,
                title: song.name,
                artist: song.artist,
                durationSeconds: song.durationSeconds,
                lineCount: lines.count
            )
            return LyricsHit(
                source: .qq,
                matchedTitle: song.name,
                matchedArtist: song.artist,
                durationSeconds: song.durationSeconds,
                rawLRC: raw,
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

    private func searchSong(_ request: LyricsSearchRequest) async throws -> SongHit? {
        var components = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")
        components?.queryItems = [
            URLQueryItem(name: "w", value: request.keyword),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "n", value: "8")
        ]
        guard let url = components?.url else { return nil }
        let (data, _) = try await session.data(from: url)
        let jsonData = unwrapJSONP(data) ?? data
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let list = ((root["data"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [[String: Any]]
        else { return nil }

        for item in list {
            guard let songmid = item["songmid"] as? String, songmid.isEmpty == false else { continue }
            let name = (item["songname"] as? String) ?? ""
            let singers = item["singer"] as? [[String: Any]] ?? []
            let artist = singers.compactMap { $0["name"] as? String }.joined(separator: "/")
            let interval = (item["interval"] as? Int).map(Double.init)
                ?? (item["interval"] as? Double)
            return SongHit(songmid: songmid, name: name, artist: artist, durationSeconds: interval)
        }
        return nil
    }

    private func fetchLyric(songmid: String) async throws -> String? {
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
        return text
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
