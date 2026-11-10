import Foundation

/// LrcShare requires an API key and catalog session. Without credentials it stays blocked.
nonisolated struct LrcShareLyricsProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    private let transport: any LyricsHTTPTransport
    private let baseURL: URL
    private let nodeID: String
    private let userAgent: String
    private let apiKey: String?

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        baseURL: URL = LyricsProviderRegistry.lrcShare.defaultNodes[0].baseURL,
        nodeID: String = LyricsProviderRegistry.lrcShare.defaultNodes[0].id,
        userAgent: String = LyricsHTTPMapping.defaultUserAgent(),
        apiKey: String? = LyricsAPIKeyStore().apiKey(for: LyricsProviderID.lrcShare.rawValue)
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.nodeID = nodeID
        self.userAgent = userAgent
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.lrcShare)
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }
        guard let apiKey, apiKey.isEmpty == false else { return .unauthorized }
        guard Task.isCancelled == false else { return .cancelled }

        // Catalog/session flow is documented but key-gated. Until a user supplies a key,
        // this provider never enters Auto. With a key we attempt a minimal authenticated probe
        // and map failures truthfully instead of fabricating lyrics.
        guard let url = Self.catalogURL(baseURL: baseURL, trackKey: trackKey) else {
            return .notFound
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

            let (data, response) = try await transport.data(for: request)
            guard Task.isCancelled == false else { return .cancelled }

            switch response.statusCode {
            case 200..<300:
                // A successful catalog response still needs a documented lyrics fetch.
                // Without a verified response schema for lyric bodies, refuse to invent content.
                if data.isEmpty { return .notFound }
                return .providerUnavailable
            case 401, 403:
                return .unauthorized
            case 404:
                return .notFound
            case 429:
                return .rateLimited(
                    retryAfterSeconds: LyricsHTTPMapping.retryAfterSeconds(from: response, data: data)
                )
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

    static func catalogURL(baseURL: URL, trackKey: LyricsTrackKey) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/catalog"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: trackKey.title),
            URLQueryItem(name: "artist", value: trackKey.artist),
        ]
        return components.url
    }
}
