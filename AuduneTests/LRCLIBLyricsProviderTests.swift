import Foundation
import XCTest
@testable import Audune

final class LRCLIBLyricsProviderTests: XCTestCase {
    private let trackKey = LyricsTrackKey(
        isrc: nil,
        title: "Track",
        artist: "Artist",
        album: "Album",
        durationSeconds: 180
    )

    func testProviderParsesSyncedLyricsFromGetResponse() async throws {
        let transport = StubLyricsTransport([
            jsonResponse(record(syncedLyrics: "[00:01.00]First\n[00:05.00]Second")),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let result = await provider.lookup(for: trackKey)

        guard case .found(let document) = result else {
            return XCTFail("Expected a lyrics document, got \(result)")
        }
        XCTAssertEqual(document.lines.map(\.text), ["First", "Second"])
        XCTAssertEqual(document.lines.first?.startSeconds, 1)
        XCTAssertEqual(document.synchronization, .lineSynced)
        XCTAssertEqual(document.source?.kind, .lrclib)
        XCTAssertEqual(document.source?.providerName, "LRCLIB")
        XCTAssertEqual(document.source?.isPersisted, false)

        let request = try XCTUnwrap(transport.requests.first)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/api/get")
        let query = queryItems(url)
        XCTAssertEqual(query["track_name"], "Track")
        XCTAssertEqual(query["artist_name"], "Artist")
        XCTAssertEqual(query["album_name"], "Album")
        XCTAssertEqual(query["duration"], "180")
        XCTAssertNil(query["q"])
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Audune/") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testProviderFallsBackToSearchWhenGetReturnsNotFound() async throws {
        let transport = StubLyricsTransport([
            .http(status: 404, body: Data("Not Found".utf8)),
            jsonArrayResponse([record(id: 9, syncedLyrics: "[00:01.00]Found by search")]),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let result = await provider.lookup(for: trackKey)

        guard case .found(let document) = result else {
            return XCTFail("Expected a lyrics document, got \(result)")
        }
        XCTAssertEqual(document.lines.first?.text, "Found by search")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.last?.url?.path, "/api/search")
    }

    func testProviderReturnsNotFoundWhenSearchHasNoMatch() async throws {
        let transport = StubLyricsTransport([
            .http(status: 404, body: Data()),
            jsonArrayResponse([]),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let result = await provider.lookup(for: trackKey)

        XCTAssertEqual(result, .notFound)
    }

    func testProviderRejectsWrongDurationVersion() async throws {
        let transport = StubLyricsTransport([
            .http(status: 404, body: Data()),
            jsonArrayResponse([record(duration: 240, syncedLyrics: "[00:01.00]Wrong version")]),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let outcome = await provider.lookup(for: trackKey)
        XCTAssertEqual(outcome, .notFound)
    }

    func testProviderMapsInstrumentalRecord() async throws {
        let transport = StubLyricsTransport([
            jsonResponse(record(instrumental: true)),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let outcome = await provider.lookup(for: trackKey)
        XCTAssertEqual(outcome, .instrumental)
    }

    func testProviderUsesPlainLyricsAsUnsynced() async throws {
        let transport = StubLyricsTransport([
            jsonResponse(record(plainLyrics: "First plain line\nSecond plain line", syncedLyrics: nil)),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let result = await provider.lookup(for: trackKey)

        guard case .found(let document) = result else {
            return XCTFail("Expected plain lyrics, got \(result)")
        }
        XCTAssertEqual(document.synchronization, .unsynced)
        XCTAssertEqual(document.lines.map(\.startSeconds), [nil, nil])
    }

    func testProviderPrefersWordSyncLyricsfile() async throws {
        let transport = StubLyricsTransport([
            jsonResponse(record(
                hasWordSync: true,
                syncedLyrics: "[00:01.00]Hello world",
                lyricsfile: wordSyncedLyricsfile
            )),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let result = await provider.lookup(for: trackKey)

        guard case .found(let document) = result else {
            return XCTFail("Expected word-synced lyrics, got \(result)")
        }
        XCTAssertEqual(document.synchronization, .wordSynced)
        let words = try XCTUnwrap(document.lines.first?.words)
        XCTAssertEqual(words.map(\.text), ["Hello", "world"])
        XCTAssertEqual(words[0].startSeconds, 1)
        XCTAssertEqual(words[0].durationSeconds, 0.8, accuracy: 0.001)
    }

    func testProviderMapsRateLimitWithRetryAfter() async throws {
        let transport = StubLyricsTransport([
            .http(status: 429, body: Data(), headers: ["Retry-After": "7"]),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let outcome = await provider.lookup(for: trackKey)
        XCTAssertEqual(outcome, .rateLimited(retryAfterSeconds: 7))
    }

    func testProviderRetriesServerOverloadOnce() async throws {
        let transport = StubLyricsTransport([
            .http(status: 503, body: Data(), headers: ["Retry-After": "0"]),
            jsonResponse(record(syncedLyrics: "[00:01.00]Recovered")),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let result = await provider.lookup(for: trackKey)

        guard case .found = result else {
            return XCTFail("Expected the retry to succeed, got \(result)")
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testProviderMapsProviderAndServerFailures() async throws {
        let unauthorized = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([.http(status: 401, body: Data())]),
            requestSpacing: 0
        )
        let unauthorizedOutcome = await unauthorized.lookup(for: trackKey)
        XCTAssertEqual(unauthorizedOutcome, .providerUnavailable)

        let serverError = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([.http(status: 500, body: Data())]),
            requestSpacing: 0
        )
        let serverOutcome = await serverError.lookup(for: trackKey)
        XCTAssertEqual(serverOutcome, .serverError(statusCode: 500))

        let overloaded = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([
                .http(status: 503, body: Data(), headers: ["Retry-After": "30"]),
            ]),
            requestSpacing: 0
        )
        let overloadedOutcome = await overloaded.lookup(for: trackKey)
        XCTAssertEqual(overloadedOutcome, .providerUnavailable)
    }

    func testProviderMapsNetworkFailuresAndInvalidPayloads() async throws {
        let timedOut = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([.failure(URLError(.timedOut))]),
            requestSpacing: 0
        )
        let timeoutOutcome = await timedOut.lookup(for: trackKey)
        XCTAssertEqual(timeoutOutcome, .timedOut)

        let offline = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([.failure(URLError(.notConnectedToInternet))]),
            requestSpacing: 0
        )
        let offlineOutcome = await offline.lookup(for: trackKey)
        XCTAssertEqual(offlineOutcome, .offline)

        let cancelled = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([.failure(URLError(.cancelled))]),
            requestSpacing: 0
        )
        let cancelledOutcome = await cancelled.lookup(for: trackKey)
        XCTAssertEqual(cancelledOutcome, .cancelled)

        let badJSON = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([
                .http(
                    status: 200,
                    body: Data("not json".utf8),
                    headers: ["Content-Type": "application/json"]
                ),
            ]),
            requestSpacing: 0
        )
        let badJSONOutcome = await badJSON.lookup(for: trackKey)
        XCTAssertEqual(badJSONOutcome, .parseError)

        let html = LRCLIBLyricsProvider(
            transport: StubLyricsTransport([
                .http(status: 200, body: Data("<html></html>".utf8), headers: ["Content-Type": "text/html"]),
            ]),
            requestSpacing: 0
        )
        let htmlOutcome = await html.lookup(for: trackKey)
        XCTAssertEqual(htmlOutcome, .parseError)
    }

    func testProviderDoesNotTreatRecordWithoutLyricsAsSuccess() async throws {
        let transport = StubLyricsTransport([
            jsonResponse(record(plainLyrics: nil, syncedLyrics: nil)),
        ])
        let provider = LRCLIBLyricsProvider(transport: transport, requestSpacing: 0)

        let outcome = await provider.lookup(for: trackKey)
        XCTAssertEqual(outcome, .parseError)
    }

    // MARK: - Fixtures

    private var wordSyncedLyricsfile: String {
        """
        version: '1.0'
        metadata:
          title: Track
          artist: Artist
        lines:
          - text: 'Hello world'
            start_ms: 1000
            end_ms: 3000
            words:
              - text: 'Hello '
                start_ms: 1000
                end_ms: 1800
              - text: 'world'
                start_ms: 1800
                end_ms: 3000
        """
    }

    private func record(
        id: Int = 1,
        duration: Double = 180,
        instrumental: Bool = false,
        hasWordSync: Bool = false,
        plainLyrics: String? = nil,
        syncedLyrics: String? = "[00:01.00]Line",
        lyricsfile: String? = nil
    ) -> [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "trackName": "Track",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": duration,
            "instrumental": instrumental,
            "hasWordSync": hasWordSync,
            "plainLyrics": plainLyrics ?? NSNull(),
            "syncedLyrics": syncedLyrics ?? NSNull(),
            "lyricsfile": lyricsfile ?? NSNull(),
        ]
        object["name"] = "Track"
        return object
    }

    private func jsonResponse(_ object: [String: Any]) -> StubLyricsTransport.Response {
        .http(
            status: 200,
            body: try! JSONSerialization.data(withJSONObject: object),
            headers: ["Content-Type": "application/json"]
        )
    }

    private func jsonArrayResponse(_ objects: [[String: Any]]) -> StubLyricsTransport.Response {
        .http(
            status: 200,
            body: try! JSONSerialization.data(withJSONObject: objects),
            headers: ["Content-Type": "application/json"]
        )
    }

    private func queryItems(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )
    }
}

private final class StubLyricsTransport: LyricsHTTPTransport, @unchecked Sendable {
    enum Response {
        case http(status: Int, body: Data, headers: [String: String] = [:])
        case failure(URLError)
    }

    private let lock = NSLock()
    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        requests.append(request)
        let response = responses.isEmpty
            ? Response.failure(URLError(.unknown))
            : responses.removeFirst()
        lock.unlock()

        switch response {
        case .failure(let error):
            throw error
        case .http(let status, let body, let headers):
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (body, http)
        }
    }
}
