import Foundation

/// Domestic source inspired by LyricsX/LyricsKit Kugou endpoints.
/// Prefers plain LRC (`fmt=lrc`); encrypted KRC payloads are skipped rather than reverse-engineered.
nonisolated struct KugouLyricsProvider: LyricsProvider {
    var id: LyricsSourceID { .kugou }
    var session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(request: LyricsSearchRequest) async -> LyricsHit? {
        do {
            guard let candidate = try await searchCandidate(request) else { return nil }
            guard let raw = try await downloadLRC(id: candidate.id, accesskey: candidate.accesskey) else {
                return nil
            }
            let lines = LRCParser.parse(raw)
            guard lines.isEmpty == false else { return nil }
            let quality = LyricsQuality.score(
                request: request,
                title: candidate.song,
                artist: candidate.singer,
                durationSeconds: candidate.durationSeconds,
                lineCount: lines.count
            )
            return LyricsHit(
                source: .kugou,
                matchedTitle: candidate.song,
                matchedArtist: candidate.singer,
                durationSeconds: candidate.durationSeconds,
                rawLRC: raw,
                lines: lines,
                quality: quality
            )
        } catch {
            return nil
        }
    }

    private struct Candidate {
        var id: String
        var accesskey: String
        var song: String
        var singer: String
        var durationSeconds: Double?
    }

    private func searchCandidate(_ request: LyricsSearchRequest) async throws -> Candidate? {
        var components = URLComponents(string: "http://lyrics.kugou.com/search")
        var items = [
            URLQueryItem(name: "keyword", value: request.keyword),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes")
        ]
        if request.durationSeconds > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(request.durationSeconds * 1000))))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        let (data, _) = try await session.data(from: url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]]
        else { return nil }

        for item in candidates {
            let idValue = item["id"]
            let id: String
            if let number = idValue as? Int {
                id = String(number)
            } else if let string = idValue as? String {
                id = string
            } else {
                continue
            }
            guard let accesskey = item["accesskey"] as? String, accesskey.isEmpty == false else { continue }
            let song = (item["song"] as? String) ?? ""
            let singer = (item["singer"] as? String) ?? ""
            let durationMs = (item["duration"] as? Int) ?? (item["duration"] as? Double).map(Int.init)
            return Candidate(
                id: id,
                accesskey: accesskey,
                song: song,
                singer: singer,
                durationSeconds: durationMs.map { Double($0) / 1000 }
            )
        }
        return nil
    }

    private func downloadLRC(id: String, accesskey: String) async throws -> String? {
        var components = URLComponents(string: "http://lyrics.kugou.com/download")
        components?.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "accesskey", value: accesskey),
            URLQueryItem(name: "fmt", value: "lrc"),
            URLQueryItem(name: "charset", value: "utf8"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "ver", value: "1")
        ]
        guard let url = components?.url else { return nil }
        let (data, _) = try await session.data(from: url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? String,
              content.isEmpty == false
        else { return nil }

        if let decoded = LyricsHTTP.decodeBase64Text(content), decoded.contains("[") {
            return decoded
        }
        if content.contains("[") {
            return content
        }
        // Encrypted KRC — skip rather than shipping a proprietary decryptor.
        return nil
    }
}
