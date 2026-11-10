import Foundation

/// Better Lyrics adapter. Cache hits may succeed without a key; uncached 401 is reported honestly.
nonisolated struct BetterLyricsProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    private let transport: any LyricsHTTPTransport
    private let baseURL: URL
    private let nodeID: String
    private let userAgent: String
    private let apiKey: String?

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        baseURL: URL = LyricsProviderRegistry.betterLyrics.defaultNodes[0].baseURL,
        nodeID: String = LyricsProviderRegistry.betterLyrics.defaultNodes[0].id,
        userAgent: String = LyricsHTTPMapping.defaultUserAgent(),
        apiKey: String? = nil
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.nodeID = nodeID
        self.userAgent = userAgent
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.betterLyrics)
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
            if let apiKey, apiKey.isEmpty == false {
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            }

            let (data, response) = try await transport.data(for: request)
            guard Task.isCancelled == false else { return .cancelled }

            switch response.statusCode {
            case 200..<300:
                return parse(data, for: trackKey)
            case 401, 403:
                return .unauthorized
            case 404:
                return .notFound
            case 429:
                return .rateLimited(
                    retryAfterSeconds: LyricsHTTPMapping.retryAfterSeconds(from: response, data: data)
                )
            case 422:
                return .notFound
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
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("getLyrics"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        var items = [
            URLQueryItem(name: "s", value: trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "a", value: trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        let album = trackKey.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        items.append(URLQueryItem(name: "al", value: album))
        if let duration = LyricsTrackMatcher.validDuration(trackKey.durationSeconds) {
            items.append(URLQueryItem(name: "d", value: String(Int(duration.rounded()))))
        } else {
            items.append(URLQueryItem(name: "d", value: "0"))
        }
        components.queryItems = items
        return components.url
    }

    private func parse(_ data: Data, for trackKey: LyricsTrackKey) -> OnlineLyricsLookup {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .parseError
        }
        guard let ttml = object["ttml"] as? String,
              ttml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return .notFound
        }
        do {
            var document = try TTMLLyricsParser.parse(ttml, trackKey: trackKey)
            document.source = LyricsSourceInfo(
                kind: .online,
                providerName: descriptor.displayName,
                providerRecordIdentifier: nil,
                isPersisted: false,
                providerID: LyricsProviderID.betterLyrics.rawValue,
                nodeID: nodeID,
                upstreamProviderID: nil,
                attributionURL: LyricsProviderRegistry.betterLyrics.attributionURL?.absoluteString,
                matchConfidence: nil,
                retrievedAt: Date()
            )
            return .found(document)
        } catch {
            return .parseError
        }
    }
}
