import Foundation

/// Plain-text fallback. Results are always unsynced.
nonisolated struct LyricsOvhProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    private let transport: any LyricsHTTPTransport
    private let baseURL: URL
    private let nodeID: String
    private let userAgent: String

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        baseURL: URL = LyricsProviderRegistry.lyricsOvh.defaultNodes[0].baseURL,
        nodeID: String = LyricsProviderRegistry.lyricsOvh.defaultNodes[0].id,
        userAgent: String = LyricsHTTPMapping.defaultUserAgent()
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.nodeID = nodeID
        self.userAgent = userAgent
        self.descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.lyricsOvh)
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }
        guard Task.isCancelled == false else { return .cancelled }
        guard let url = Self.requestURL(baseURL: baseURL, artist: artist, title: title) else {
            return .notFound
        }

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

    static func requestURL(baseURL: URL, artist: String, title: String) -> URL? {
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? artist
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        return baseURL
            .appendingPathComponent(encodedArtist)
            .appendingPathComponent(encodedTitle)
    }

    private func parse(_ data: Data, for trackKey: LyricsTrackKey) -> OnlineLyricsLookup {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lyrics = object["lyrics"] as? String,
              lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return .notFound
        }
        guard var document = try? LRCParser.parsePlain(lyrics, trackKey: trackKey) else {
            return .parseError
        }
        // Plain text must never be marked as synchronized.
        guard document.synchronization == .unsynced else { return .parseError }
        document.source = LyricsSourceInfo(
            kind: .online,
            providerName: descriptor.displayName,
            providerRecordIdentifier: nil,
            isPersisted: false,
            providerID: LyricsProviderID.lyricsOvh.rawValue,
            nodeID: nodeID,
            upstreamProviderID: nil,
            attributionURL: LyricsProviderRegistry.lyricsOvh.attributionURL?.absoluteString,
            matchConfidence: nil,
            retrievedAt: Date()
        )
        return .found(document)
    }
}
