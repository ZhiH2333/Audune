import Foundation

/// Aggregator adapter for LRC Mux. `meta.source` is attribution, not a selectable Audune node.
nonisolated struct LRCMuxLyricsProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    private let transport: any LyricsHTTPTransport
    private let baseURL: URL
    private let nodeID: String
    private let userAgent: String

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        baseURL: URL = LyricsProviderRegistry.lrcmux.defaultNodes[0].baseURL,
        nodeID: String = LyricsProviderRegistry.lrcmux.defaultNodes[0].id,
        userAgent: String = LyricsHTTPMapping.defaultUserAgent()
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.nodeID = nodeID
        self.userAgent = userAgent
        self.descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.lrcmux)
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }
        guard Task.isCancelled == false else { return .cancelled }
        guard let url = Self.requestURL(baseURL: baseURL, trackKey: trackKey) else { return .notFound }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
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
            case 400:
                // Format/min-level mismatch or bad query — treat as no usable lyrics.
                return .notFound
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

    static func requestURL(baseURL: URL, trackKey: LyricsTrackKey) -> URL? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "artist", value: trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "title", value: trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }

    private func parse(_ data: Data, for trackKey: LyricsTrackKey) -> OnlineLyricsLookup {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .parseError
        }
        if let detail = object["detail"] as? String,
           detail.lowercased().contains("no lyrics")
        {
            return .notFound
        }

        let meta = object["meta"] as? [String: Any] ?? [:]
        if meta["instrumental"] as? Bool == true {
            return .instrumental
        }

        let sourceMeta = meta["source"] as? [String: Any]
        let upstreamID = sourceMeta?["id"] as? String
        let upstreamName = sourceMeta?["name"] as? String
        let attribution = (sourceMeta?["url"] as? String)
            ?? LyricsProviderRegistry.lrcmux.attributionURL?.absoluteString

        let source = LyricsSourceInfo(
            kind: .online,
            providerName: descriptor.displayName,
            providerRecordIdentifier: upstreamID,
            isPersisted: false,
            providerID: LyricsProviderID.lrcmux.rawValue,
            nodeID: nodeID,
            upstreamProviderID: upstreamName ?? upstreamID,
            attributionURL: attribution,
            matchConfidence: nil,
            retrievedAt: Date()
        )

        let linesPayload = object["lines"] as? [[String: Any]] ?? []
        let timedLines: [TimedLyricsDocumentBuilder.TimedLine] = linesPayload.compactMap { line in
            let text = (line["text"] as? String) ?? ""
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
            let wordsPayload = line["words"] as? [[String: Any]] ?? []
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
                translation: nil,
                pronunciation: nil,
                words: words
            )
        }

        if let document = TimedLyricsDocumentBuilder.document(
            trackKey: trackKey,
            lines: timedLines,
            source: source
        ), document.lines.isEmpty == false {
            return .found(document)
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
