import Foundation

/// Small seam over URLSession so provider error mapping is deterministic under test.
protocol LyricsHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionLyricsTransport: LyricsHTTPTransport {
    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    init() {
        self.init(configuration: URLSessionLyricsTransport.makeConfiguration())
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           version.isEmpty == false
        {
            configuration.httpAdditionalHeaders = [
                "User-Agent": "Audune/\(version) (macOS lyrics client)"
            ]
        } else {
            configuration.httpAdditionalHeaders = [
                "User-Agent": "Audune/1.0 (macOS lyrics client)"
            ]
        }
        return configuration
    }
}

/// Reserves sequential request slots. LRCLIB asks clients to space requests out.
private actor LRCLIBRequestGate {
    private let spacing: TimeInterval
    private var nextAvailable: TimeInterval = 0

    init(spacing: TimeInterval) {
        self.spacing = max(0, spacing)
    }

    func waitForTurn() async throws {
        let now = ProcessInfo.processInfo.systemUptime
        let slot = max(now, nextAvailable)
        nextAvailable = slot + spacing
        let delay = slot - now
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

nonisolated struct LRCLIBLyricsProvider: OnlineLyricsProviding {
    static let website = URL(string: "https://lrclib.net")!

    let descriptor = LyricsProviderDescriptor(
        kind: .lrclib,
        displayName: "LRCLIB",
        websiteURL: LRCLIBLyricsProvider.website,
        queryFields: [.title, .artist, .album, .duration]
    )

    private let transport: any LyricsHTTPTransport
    private let gate: LRCLIBRequestGate
    private let userAgent: String

    init(
        transport: any LyricsHTTPTransport = URLSessionLyricsTransport(),
        requestSpacing: TimeInterval = 0.35,
        userAgent: String = "Audune/1.0 (macOS lyrics client)"
    ) {
        self.transport = transport
        self.gate = LRCLIBRequestGate(spacing: requestSpacing)
        self.userAgent = userAgent
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }
        guard Task.isCancelled == false else { return .cancelled }

        do {
            if let getURL = Self.getURL(for: trackKey) {
                switch try await fetch(getURL) {
                case .found(let data):
                    return parseRecord(data, for: trackKey)
                case .outcome(let outcome):
                    return outcome
                case .notFound:
                    break
                }
            }

            // `/api/get` is strict about duration (±2s). Search finds alternate album/version records.
            guard Task.isCancelled == false else { return .cancelled }
            guard let searchURL = Self.searchURL(for: trackKey) else { return .notFound }
            switch try await fetch(searchURL) {
            case .found(let data):
                return parseSearch(data, for: trackKey)
            case .notFound:
                return .notFound
            case .outcome(let outcome):
                return outcome
            }
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError {
            return Self.map(error)
        } catch {
            return .networkError
        }
    }

    // MARK: - Requests

    private enum FetchResult {
        case found(Data)
        case notFound
        case outcome(OnlineLyricsLookup)
    }

    private func fetch(_ url: URL) async throws -> FetchResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        var didRetry = false

        while true {
            guard Task.isCancelled == false else { throw CancellationError() }
            try await gate.waitForTurn()
            let (data, response) = try await transport.data(for: request)
            guard Task.isCancelled == false else { throw CancellationError() }

            switch response.statusCode {
            case 200..<300:
                let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                guard contentType.contains("application/json") else {
                    return .outcome(.parseError)
                }
                return .found(data)
            case 404:
                return .notFound
            case 429:
                return .outcome(
                    .rateLimited(retryAfterSeconds: Self.retryAfter(from: response, data: data))
                )
            case 503:
                let delay = Self.retryAfter(from: response, data: data) ?? 0
                if didRetry == false, delay <= 3 {
                    didRetry = true
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    continue
                }
                return .outcome(.providerUnavailable)
            case 401, 403:
                return .outcome(.providerUnavailable)
            case 500..<600:
                return .outcome(.serverError(statusCode: response.statusCode))
            default:
                return .outcome(.serverError(statusCode: response.statusCode))
            }
        }
    }

    private func parseRecord(_ data: Data, for trackKey: LyricsTrackKey) -> OnlineLyricsLookup {
        guard let record = try? JSONDecoder().decode(LRCLIBRecord.self, from: data) else {
            return .parseError
        }
        return document(from: record, for: trackKey)
    }

    private func parseSearch(_ data: Data, for trackKey: LyricsTrackKey) -> OnlineLyricsLookup {
        guard let records = try? JSONDecoder().decode([LRCLIBRecord].self, from: data) else {
            return .parseError
        }
        guard records.isEmpty == false else { return .notFound }
        guard let best = Self.bestCandidate(in: records, for: trackKey) else { return .notFound }
        return document(from: best, for: trackKey)
    }

    private func document(from record: LRCLIBRecord, for trackKey: LyricsTrackKey) -> OnlineLyricsLookup {
        if record.instrumental { return .instrumental }

        var document: LyricsDocument?
        if record.hasWordSync,
           let lyricsfile = record.lyricsfile,
           lyricsfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           let parsed = try? LyricsfileParser.parse(lyricsfile, trackKey: trackKey),
           parsed.synchronization == .wordSynced
        {
            document = parsed
        }
        if document == nil,
           let synced = record.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           synced.isEmpty == false,
           let parsed = try? LRCParser.parse(synced, trackKey: trackKey)
        {
            document = parsed
        }
        if document == nil,
           let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           plain.isEmpty == false,
           let parsed = try? LRCParser.parsePlain(plain, trackKey: trackKey)
        {
            document = parsed
        }
        guard var result = document, result.lines.isEmpty == false else {
            return .parseError
        }
        result.source = LyricsSourceInfo(
            kind: .lrclib,
            providerName: descriptor.displayName,
            providerRecordIdentifier: String(record.id),
            isPersisted: false,
            providerID: LyricsProviderID.lrclib.rawValue,
            nodeID: LyricsProviderRegistry.lrclib.defaultNodes.first?.id,
            upstreamProviderID: nil,
            attributionURL: LyricsProviderRegistry.lrclib.attributionURL?.absoluteString,
            matchConfidence: nil,
            retrievedAt: Date()
        )
        return .found(result)
    }

    // MARK: - Matching

    private static func bestCandidate(in records: [LRCLIBRecord], for trackKey: LyricsTrackKey) -> LRCLIBRecord? {
        let scored = records.compactMap { record -> (record: LRCLIBRecord, score: Double, durationDelta: Double?)? in
            guard let score = score(record, for: trackKey) else { return nil }
            let delta: Double?
            if let current = LyricsTrackMatcher.validDuration(trackKey.durationSeconds),
               let candidate = LyricsTrackMatcher.validDuration(record.duration)
            {
                delta = abs(current - candidate)
            } else {
                delta = nil
            }
            return (record, score, delta)
        }
        guard let best = scored.max(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            let leftDelta = lhs.durationDelta ?? .greatestFiniteMagnitude
            let rightDelta = rhs.durationDelta ?? .greatestFiniteMagnitude
            if leftDelta != rightDelta { return leftDelta > rightDelta }
            return lhs.record.id > rhs.record.id
        }) else {
            return nil
        }

        let tied = scored.filter { abs($0.score - best.score) < 0.001 }
        if tied.count > 1 {
            if LyricsTrackMatcher.validDuration(trackKey.durationSeconds) == nil {
                let durations = Set(tied.compactMap {
                    LyricsTrackMatcher.validDuration($0.record.duration).map { Int($0.rounded()) }
                })
                if durations.count > 1 { return nil }
            } else if let bestDelta = best.durationDelta {
                let competing = tied.compactMap(\.durationDelta)
                if let closest = competing.min(), bestDelta - closest > 1 { return nil }
            }
        }
        return best.record
    }

    private static func score(_ record: LRCLIBRecord, for trackKey: LyricsTrackKey) -> Double? {
        let title = LyricsTrackMatcher.normalized(trackKey.title)
        let candidateTitle = LyricsTrackMatcher.normalized(record.trackName)
        guard title.isEmpty == false, candidateTitle.isEmpty == false else { return nil }
        let exactTitle = title == candidateTitle
        let baseTitle = LyricsTrackMatcher.baseTitle(title) == LyricsTrackMatcher.baseTitle(candidateTitle)
            && LyricsTrackMatcher.baseTitle(title).isEmpty == false
        guard exactTitle || baseTitle else { return nil }
        guard artistsMatch(trackKey.artist, record.artistName) else { return nil }

        var score = exactTitle ? 50.0 : 24.0
        score += artistScore(trackKey.artist, record.artistName)

        let album = LyricsTrackMatcher.normalized(trackKey.album)
        if album.isEmpty == false, album == LyricsTrackMatcher.normalized(record.albumName) {
            score += 6
        }

        if let current = LyricsTrackMatcher.validDuration(trackKey.durationSeconds),
           let candidate = LyricsTrackMatcher.validDuration(record.duration)
        {
            let delta = abs(current - candidate)
            guard delta <= 10 else { return nil }
            guard exactTitle || delta <= 3 else { return nil }
            score += max(0, 15 - delta * 2)
        } else if baseTitle {
            // A qualifier-stripped title without duration is not enough to pick a version safely.
            return nil
        }

        if record.hasWordSync { score += 4 }
        if record.syncedLyrics?.isEmpty == false { score += 2 }
        if record.instrumental { score += 1 }
        return score
    }

    private static func artistsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = tokens(lhs)
        let right = tokens(rhs)
        guard left.isEmpty == false, right.isEmpty == false else { return false }
        return left.isSubset(of: right) || right.isSubset(of: left)
    }

    private static func artistScore(_ lhs: String, _ rhs: String) -> Double {
        let left = tokens(lhs)
        let right = tokens(rhs)
        if left == right { return 20 }
        return 10
    }

    private static func tokens(_ value: String) -> Set<String> {
        let stop: Set<String> = ["feat", "ft", "featuring", "with", "and", "the"]
        let normalized = LyricsTrackMatcher.normalized(value).lowercased()
        let parts = normalized.split { $0.isLetter == false && $0.isNumber == false }
        let result = Set(parts.map(String.init).filter { $0.isEmpty == false && stop.contains($0) == false })
        return result
    }

    // MARK: - URLs and headers

    private static func getURL(for trackKey: LyricsTrackKey) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "artist_name", value: trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let album = trackKey.album?.trimmingCharacters(in: .whitespacesAndNewlines), album.isEmpty == false {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration = LyricsTrackMatcher.validDuration(trackKey.durationSeconds),
           (1...3600).contains(duration)
        {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        return components?.url
    }

    private static func searchURL(for trackKey: LyricsTrackKey) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "artist_name", value: trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        return components?.url
    }

    private static func retryAfter(from response: HTTPURLResponse, data: Data) -> TimeInterval? {
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)), seconds.isFinite {
                return max(0, seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header) {
                return max(0, date.timeIntervalSinceNow)
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["retry_after", "retryAfter", "retry_after_seconds"] {
            if let value = object[key] as? Double, value.isFinite { return max(0, value) }
            if let value = object[key] as? Int { return max(0, Double(value)) }
            if let value = object[key] as? String, let seconds = TimeInterval(value) { return max(0, seconds) }
        }
        return nil
    }

    private static func map(_ error: URLError) -> OnlineLyricsLookup {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
            return .offline
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .badServerResponse:
            return .networkError
        default:
            return .networkError
        }
    }
}

private nonisolated struct LRCLIBRecord: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let instrumental: Bool
    let hasWordSync: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    let lyricsfile: String?
}
