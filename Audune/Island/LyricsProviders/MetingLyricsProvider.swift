import Foundation

nonisolated enum MetingServer: String, Equatable, Sendable, CaseIterable {
    case netease
    case tencent
    case kugou
}

/// Public Meting mirror adapter. Nodes are interchangeable endpoints for the same provider.
nonisolated struct MetingLyricsProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    private let transport: any LyricsHTTPTransport
    private let node: LyricsNodeDescriptor
    private let server: MetingServer
    private let userAgent: String
    private let attributedProviderID: String
    private let attributedDisplayName: String

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        node: LyricsNodeDescriptor = LyricsProviderRegistry.meting.defaultNodes[0],
        server: MetingServer = .tencent,
        userAgent: String = LyricsHTTPMapping.defaultUserAgent(),
        attributedProviderID: String = LyricsProviderID.meting.rawValue,
        attributedDisplayName: String = LyricsProviderRegistry.meting.displayName
    ) {
        self.transport = transport
        self.node = node
        self.server = server
        self.userAgent = userAgent
        self.attributedProviderID = attributedProviderID
        self.attributedDisplayName = attributedDisplayName
        var descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.meting)
        if attributedProviderID != LyricsProviderID.meting.rawValue,
           let kind = LyricsProviderDescriptor.Kind(rawValue: attributedProviderID)
        {
            descriptor = LyricsProviderDescriptor(
                kind: kind,
                displayName: attributedDisplayName,
                websiteURL: descriptor.websiteURL,
                queryFields: descriptor.queryFields
            )
        }
        self.descriptor = descriptor
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }
        guard Task.isCancelled == false else { return .cancelled }
        guard let searchURL = Self.searchURL(node: node, server: server, trackKey: trackKey) else {
            return .notFound
        }

        do {
            let (searchData, searchResponse) = try await send(searchURL)
            guard Task.isCancelled == false else { return .cancelled }
            if let early = mapStatus(searchResponse, data: searchData) { return early }

            guard let candidate = Self.bestCandidate(in: searchData, for: trackKey),
                  let lrcURLString = candidate.lrcURL,
                  let lrcURL = URL(string: lrcURLString)
            else {
                return .notFound
            }

            let (lrcData, lrcResponse) = try await send(lrcURL)
            guard Task.isCancelled == false else { return .cancelled }
            if let early = mapStatus(lrcResponse, data: lrcData) { return early }

            let text = String(decoding: lrcData, as: UTF8.self)
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return .notFound
            }
            // Some mirrors return HTML/JSON error bodies with HTTP 200.
            if text.first == "<" || text.first == "{" {
                return .parseError
            }
            guard var document = try? LRCParser.parse(text, trackKey: trackKey) else {
                // Fall back to plain if the payload has no timestamps.
                guard var plain = try? LRCParser.parsePlain(text, trackKey: trackKey) else {
                    return .parseError
                }
                plain.source = sourceInfo(recordID: candidate.id)
                return .found(plain)
            }
            document.source = sourceInfo(recordID: candidate.id)
            return .found(document)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError {
            return LyricsHTTPMapping.mapURLError(error)
        } catch {
            return .networkError
        }
    }

    static func searchURL(
        node: LyricsNodeDescriptor,
        server: MetingServer,
        trackKey: LyricsTrackKey
    ) -> URL? {
        guard var components = URLComponents(url: node.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let query = [
            trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines),
            trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: " ")
        components.queryItems = [
            URLQueryItem(name: "server", value: server.rawValue),
            URLQueryItem(name: "type", value: "search"),
            URLQueryItem(name: "id", value: query),
        ]
        return components.url
    }

    struct Candidate: Equatable {
        var id: String
        var title: String
        var artist: String
        var lrcURL: String?
    }

    static func bestCandidate(in data: Data, for trackKey: LyricsTrackKey) -> Candidate? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              array.isEmpty == false
        else {
            return nil
        }
        let wantedTitle = LyricsTrackMatcher.normalized(trackKey.title)
        let wantedArtist = LyricsTrackMatcher.normalized(trackKey.artist)
        let wantedBase = LyricsTrackMatcher.baseTitle(wantedTitle)

        let scored: [(Candidate, Double)] = array.compactMap { item in
            let title = (item["title"] as? String) ?? ""
            let artist = (item["author"] as? String) ?? (item["artist"] as? String) ?? ""
            let lrc = item["lrc"] as? String
            guard title.isEmpty == false, artist.isEmpty == false else { return nil }

            let normalizedTitle = LyricsTrackMatcher.normalized(title)
            let normalizedArtist = LyricsTrackMatcher.normalized(artist)
            var score = 0.0
            if normalizedTitle == wantedTitle { score += 4 }
            else if LyricsTrackMatcher.baseTitle(normalizedTitle) == wantedBase { score += 3 }
            else if normalizedTitle.contains(wantedTitle) || wantedTitle.contains(normalizedTitle) {
                score += 1
            } else {
                return nil
            }
            if normalizedArtist == wantedArtist { score += 5 }
            else if normalizedArtist.contains(wantedArtist) || wantedArtist.contains(normalizedArtist) {
                score += 2
            } else {
                // Cover / karaoke rankings are common on NetEase mirrors; reject weak artist match.
                return nil
            }

            let id: String = {
                if let lrc, let url = URL(string: lrc),
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let value = components.queryItems?.first(where: { $0.name == "id" })?.value
                {
                    return value
                }
                return normalizedTitle + "|" + normalizedArtist
            }()

            return (
                Candidate(id: id, title: title, artist: artist, lrcURL: lrc),
                score
            )
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private func send(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return try await transport.data(for: request)
    }

    private func mapStatus(_ response: HTTPURLResponse, data: Data) -> OnlineLyricsLookup? {
        switch response.statusCode {
        case 200..<300:
            return nil
        case 404:
            return .notFound
        case 401, 403:
            return .unauthorized
        case 429:
            return .rateLimited(
                retryAfterSeconds: LyricsHTTPMapping.retryAfterSeconds(from: response, data: data)
            )
        case 500..<600:
            return .serverError(statusCode: response.statusCode)
        default:
            return .serverError(statusCode: response.statusCode)
        }
    }

    private func sourceInfo(recordID: String) -> LyricsSourceInfo {
        LyricsSourceInfo(
            kind: .online,
            providerName: attributedDisplayName,
            providerRecordIdentifier: recordID,
            isPersisted: false,
            providerID: attributedProviderID,
            nodeID: node.id,
            upstreamProviderID: server.rawValue,
            attributionURL: node.attributionURL?.absoluteString
                ?? LyricsProviderRegistry.meting.attributionURL?.absoluteString,
            matchConfidence: nil,
            retrievedAt: Date()
        )
    }
}

nonisolated struct NetEaseMetingLyricsProvider: OnlineLyricsProviding {
    private let inner: MetingLyricsProvider
    var descriptor: LyricsProviderDescriptor { inner.descriptor }

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        node: LyricsNodeDescriptor = LyricsProviderRegistry.meting.defaultNodes[0]
    ) {
        inner = MetingLyricsProvider(
            transport: transport,
            node: node,
            server: .netease,
            attributedProviderID: LyricsProviderID.netease.rawValue,
            attributedDisplayName: LyricsProviderRegistry.netease.displayName
        )
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        await inner.lookup(for: trackKey)
    }
}

nonisolated struct QQMusicMetingLyricsProvider: OnlineLyricsProviding {
    private let inner: MetingLyricsProvider
    var descriptor: LyricsProviderDescriptor { inner.descriptor }

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        node: LyricsNodeDescriptor = LyricsProviderRegistry.meting.defaultNodes[0]
    ) {
        inner = MetingLyricsProvider(
            transport: transport,
            node: node,
            server: .tencent,
            attributedProviderID: LyricsProviderID.qqMusic.rawValue,
            attributedDisplayName: LyricsProviderRegistry.qqMusic.displayName
        )
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        await inner.lookup(for: trackKey)
    }
}

/// KuGou remains a candidate until a verified public path exists.
nonisolated struct KuGouLyricsProvider: OnlineLyricsProviding {
    let descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.kugou)

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        _ = trackKey
        return .providerUnavailable
    }
}
