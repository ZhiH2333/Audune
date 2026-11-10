import Foundation

/// lrc.red adapter. Prefer ISRC when available; otherwise search then fetch by ISRC.
nonisolated struct LrcRedLyricsProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    private let transport: any LyricsHTTPTransport
    private let baseURL: URL
    private let nodeID: String
    private let userAgent: String

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        baseURL: URL = LyricsProviderRegistry.lrcRed.defaultNodes[0].baseURL,
        nodeID: String = LyricsProviderRegistry.lrcRed.defaultNodes[0].id,
        userAgent: String = LyricsHTTPMapping.defaultUserAgent()
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.nodeID = nodeID
        self.userAgent = userAgent
        self.descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.lrcRed)
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }
        guard Task.isCancelled == false else { return .cancelled }

        do {
            if let isrc = LyricsTrackMatcher.normalizedISRC(trackKey.isrc) {
                return try await fetchISRC(isrc, for: trackKey)
            }

            guard let searchURL = Self.searchURL(baseURL: baseURL, trackKey: trackKey) else {
                return .notFound
            }
            let (data, response) = try await send(searchURL)
            guard Task.isCancelled == false else { return .cancelled }
            switch response.statusCode {
            case 200..<300:
                break
            case 404:
                return .notFound
            case 429:
                return .rateLimited(
                    retryAfterSeconds: LyricsHTTPMapping.retryAfterSeconds(from: response, data: data)
                )
            case 401, 403:
                return .unauthorized
            case 500..<600:
                return .serverError(statusCode: response.statusCode)
            default:
                return .serverError(statusCode: response.statusCode)
            }

            guard let isrc = Self.bestISRC(in: data, for: trackKey) else { return .notFound }
            return try await fetchISRC(isrc, for: trackKey)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError {
            return LyricsHTTPMapping.mapURLError(error)
        } catch {
            return .networkError
        }
    }

    static func searchURL(baseURL: URL, trackKey: LyricsTrackKey) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search.json"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let query = [trackKey.title, trackKey.artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    static func resourceURL(baseURL: URL, isrc: String, ext: String) -> URL {
        baseURL.appendingPathComponent("s").appendingPathComponent("\(isrc).\(ext)")
    }

    private func fetchISRC(_ isrc: String, for trackKey: LyricsTrackKey) async throws -> OnlineLyricsLookup {
        // Prefer TTML for word timing; fall back to enhanced LRC.
        let ttmlURL = Self.resourceURL(baseURL: baseURL, isrc: isrc, ext: "ttml")
        let (ttmlData, ttmlResponse) = try await send(ttmlURL)
        guard Task.isCancelled == false else { return .cancelled }
        switch ttmlResponse.statusCode {
        case 200..<300:
            if var document = try? TTMLLyricsParser.parse(
                String(decoding: ttmlData, as: UTF8.self),
                trackKey: trackKey
            ) {
                document.source = sourceInfo(isrc: isrc)
                return .found(document)
            }
        case 404:
            break
        case 429:
            return .rateLimited(
                retryAfterSeconds: LyricsHTTPMapping.retryAfterSeconds(from: ttmlResponse, data: ttmlData)
            )
        case 401, 403:
            return .unauthorized
        case 500..<600:
            return .serverError(statusCode: ttmlResponse.statusCode)
        default:
            break
        }

        let lrcURL = Self.resourceURL(baseURL: baseURL, isrc: isrc, ext: "lrc")
        let (lrcData, lrcResponse) = try await send(lrcURL)
        guard Task.isCancelled == false else { return .cancelled }
        switch lrcResponse.statusCode {
        case 200..<300:
            let text = String(decoding: lrcData, as: UTF8.self)
            guard var document = try? LRCParser.parse(text, trackKey: trackKey) else {
                return .parseError
            }
            document.source = sourceInfo(isrc: isrc)
            return .found(document)
        case 404:
            return .notFound
        case 429:
            return .rateLimited(
                retryAfterSeconds: LyricsHTTPMapping.retryAfterSeconds(from: lrcResponse, data: lrcData)
            )
        case 401, 403:
            return .unauthorized
        case 500..<600:
            return .serverError(statusCode: lrcResponse.statusCode)
        default:
            return .serverError(statusCode: lrcResponse.statusCode)
        }
    }

    private func send(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return try await transport.data(for: request)
    }

    private func sourceInfo(isrc: String) -> LyricsSourceInfo {
        LyricsSourceInfo(
            kind: .online,
            providerName: descriptor.displayName,
            providerRecordIdentifier: isrc,
            isPersisted: false,
            providerID: LyricsProviderID.lrcRed.rawValue,
            nodeID: nodeID,
            upstreamProviderID: nil,
            attributionURL: "https://lrc.red",
            matchConfidence: nil,
            retrievedAt: Date()
        )
    }

    static func bestISRC(in data: Data, for trackKey: LyricsTrackKey) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = object["hits"] as? [[String: Any]],
              hits.isEmpty == false
        else {
            return nil
        }

        let title = LyricsTrackMatcher.normalized(trackKey.title)
        let artist = LyricsTrackMatcher.normalized(trackKey.artist)
        let scored: [(isrc: String, score: Double)] = hits.compactMap { hit in
            guard let isrc = LyricsTrackMatcher.normalizedISRC(hit["isrc"] as? String) else {
                return nil
            }
            let hitTitle = LyricsTrackMatcher.normalized(hit["title"] as? String)
            let hitArtist = LyricsTrackMatcher.normalized(hit["artist"] as? String)
            var score = 0.0
            if hitTitle == title { score += 4 }
            else if hitTitle.contains(title) || title.contains(hitTitle) { score += 2 }
            if hitArtist == artist { score += 4 }
            else if hitArtist.contains(artist) || artist.contains(hitArtist) { score += 2 }
            if let duration = LyricsTrackMatcher.validDuration(trackKey.durationSeconds),
               let hitDuration = LyricsTrackMatcher.validDuration(hit["duration"] as? Double)
            {
                let delta = abs(duration - hitDuration)
                if delta <= 2 { score += 2 }
                else if delta <= 5 { score += 1 }
                else { return nil }
            }
            guard score >= 6 else { return nil }
            return (isrc, score)
        }
        return scored.max(by: { $0.score < $1.score })?.isrc
    }
}
