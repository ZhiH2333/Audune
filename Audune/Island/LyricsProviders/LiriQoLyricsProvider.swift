import Foundation

/// Aggregator adapter for LiriQo. Upstream providers in the response are attribution only.
nonisolated struct LiriQoLyricsProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    private let transport: any LyricsHTTPTransport
    private let baseURL: URL
    private let nodeID: String
    private let userAgent: String
    private let preferFast: Bool

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        baseURL: URL = LyricsProviderRegistry.liriqo.defaultNodes[0].baseURL,
        nodeID: String = LyricsProviderRegistry.liriqo.defaultNodes[0].id,
        userAgent: String = LyricsHTTPMapping.defaultUserAgent(),
        preferFast: Bool = true
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.nodeID = nodeID
        self.userAgent = userAgent
        self.preferFast = preferFast
        self.descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.liriqo)
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }
        guard Task.isCancelled == false else { return .cancelled }
        guard let url = Self.requestURL(baseURL: baseURL, trackKey: trackKey, preferFast: preferFast) else {
            return .notFound
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await transport.data(for: request)
            guard Task.isCancelled == false else { return .cancelled }

            switch response.statusCode {
            case 200..<300:
                return parse(data, for: trackKey)
            case 404:
                return .notFound
            case 429:
                return .rateLimited(
                    retryAfterSeconds: LyricsHTTPMapping.retryAfterSeconds(from: response, data: data)
                )
            case 401, 403:
                return .providerUnavailable
            case 500..<600:
                return .serverError(statusCode: response.statusCode)
            default:
                return .serverError(statusCode: response.statusCode)
            }
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError {
            return LyricsHTTPMapping.mapURLError(error)
        } catch {
            return .networkError
        }
    }

    func searchCandidates(for trackKey: LyricsTrackKey) async -> [LyricsDocument] {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return [] }
        guard Task.isCancelled == false else { return [] }
        guard let url = Self.requestURL(baseURL: baseURL, trackKey: trackKey, preferFast: preferFast) else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await transport.data(for: request)
            guard Task.isCancelled == false, (200..<300).contains(response.statusCode) else {
                return []
            }
            guard let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return []
            }
            let matchScore = dictionary["matchScore"] as? Double
            var payloads: [[String: Any]] = []
            if let primary = dictionary["primary"] as? [String: Any] {
                payloads.append(primary)
            }
            if let tracks = dictionary["tracks"] as? [[String: Any]] {
                payloads.append(contentsOf: tracks)
            }
            var documents: [LyricsDocument] = []
            for payload in payloads {
                let candidateKey = LyricsTrackKey(
                    isrc: (payload["isrc"] as? String) ?? trackKey.isrc,
                    title: (payload["title"] as? String) ?? trackKey.title,
                    artist: (payload["artist"] as? String) ?? trackKey.artist,
                    album: (payload["album"] as? String) ?? trackKey.album,
                    durationSeconds: doubleValue(payload["duration"]) ?? trackKey.durationSeconds
                )
                if case .found(let doc) = document(from: payload, for: candidateKey, matchScore: matchScore) {
                    documents.append(doc)
                }
            }
            return documents
        } catch {
            return []
        }
    }

    static func requestURL(baseURL: URL, trackKey: LyricsTrackKey, preferFast: Bool) -> URL? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("lyrics"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "title", value: trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "artist", value: trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let album = trackKey.album?.trimmingCharacters(in: .whitespacesAndNewlines), album.isEmpty == false {
            items.append(URLQueryItem(name: "album", value: album))
        }
        if let duration = LyricsTrackMatcher.validDuration(trackKey.durationSeconds) {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        if let isrc = LyricsTrackMatcher.normalizedISRC(trackKey.isrc) {
            items.append(URLQueryItem(name: "isrc", value: isrc))
        }
        if preferFast {
            items.append(URLQueryItem(name: "fast", value: "1"))
        }
        components.queryItems = items
        return components.url
    }

    private func parse(_ data: Data, for trackKey: LyricsTrackKey) -> OnlineLyricsLookup {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return .parseError
        }
        if let dictionary = object as? [String: Any] {
            if let error = dictionary["error"] as? String, error.isEmpty == false {
                let lowered = error.lowercased()
                if lowered.contains("not found") || lowered.contains("no lyrics") {
                    return .notFound
                }
                return .providerUnavailable
            }
            if dictionary["instrumental"] as? Bool == true {
                return .instrumental
            }
            if let primary = dictionary["primary"] as? [String: Any] {
                return document(from: primary, for: trackKey, matchScore: dictionary["matchScore"] as? Double)
            }
            if let tracks = dictionary["tracks"] as? [[String: Any]], let first = tracks.first {
                return document(from: first, for: trackKey, matchScore: dictionary["matchScore"] as? Double)
            }
        }
        return .notFound
    }

    private func document(
        from payload: [String: Any],
        for trackKey: LyricsTrackKey,
        matchScore: Double?
    ) -> OnlineLyricsLookup {
        let timedPayload = payload["timed"] as? [[String: Any]] ?? []
        let timedLines: [TimedLyricsDocumentBuilder.TimedLine] = timedPayload.compactMap { line in
            let text = (line["text"] as? String) ?? ""
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
            let wordsPayload = (line["words"] as? [[String: Any]]) ?? []
            let words = wordsPayload.compactMap { word -> TimedLyricsDocumentBuilder.TimedWord? in
                guard let wordText = word["text"] as? String else { return nil }
                let start = doubleValue(word["start"]) ?? 0
                let end = doubleValue(word["end"]) ?? start
                return .init(text: wordText, startMilliseconds: start, endMilliseconds: end)
            }
            return .init(
                text: text,
                startMilliseconds: doubleValue(line["start"]),
                endMilliseconds: doubleValue(line["end"]),
                translation: line["translation"] as? String,
                pronunciation: (line["romanization"] as? String) ?? (line["pronunciation"] as? String),
                words: words
            )
        }

        let syncLevel = (payload["syncLevel"] as? String)?.lowercased()
        let provider = (payload["provider"] as? String) ?? descriptor.displayName
        let upstream = (payload["upstreamProvider"] as? String) ?? (payload["source"] as? String)
        let source = LyricsSourceInfo(
            kind: .online,
            providerName: descriptor.displayName,
            providerRecordIdentifier: provider,
            isPersisted: false,
            providerID: LyricsProviderID.liriqo.rawValue,
            nodeID: nodeID,
            upstreamProviderID: upstream,
            attributionURL: LyricsProviderRegistry.liriqo.attributionURL?.absoluteString,
            matchConfidence: matchScore,
            retrievedAt: Date()
        )

        if var document = TimedLyricsDocumentBuilder.document(
            trackKey: trackKey,
            lines: timedLines,
            source: source,
            preferSyllable: syncLevel == "syllable" || syncLevel == "character"
        ), document.lines.isEmpty == false {
            if syncLevel == "syllable" || syncLevel == "character",
               document.lines.contains(where: { ($0.words?.isEmpty == false) })
            {
                document.declaredSynchronization = .syllableSynced
            }
            return .found(document)
        }

        if let lrc = payload["lrc"] as? String,
           lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           var parsed = try? LRCParser.parse(lrc, trackKey: trackKey)
        {
            parsed.source = source
            return .found(parsed)
        }

        if let plain = payload["plain"] as? String,
           plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           var parsed = try? LRCParser.parsePlain(plain, trackKey: trackKey)
        {
            parsed.source = source
            return .found(parsed)
        }

        return .notFound
    }

    private func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}
