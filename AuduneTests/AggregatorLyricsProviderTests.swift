import Foundation
import XCTest
@testable import Audune

final class AggregatorLyricsProviderTests: XCTestCase {
    private let trackKey = LyricsTrackKey(
        isrc: "USUG11904206",
        title: "Blinding Lights",
        artist: "The Weeknd",
        album: "After Hours",
        durationSeconds: 200
    )

    func testLiriQoBuildsRequestWithMetadataAndFastFlag() throws {
        let url = try XCTUnwrap(
            LiriQoLyricsProvider.requestURL(
                baseURL: URL(string: "https://api.liriqo-alfarrizi.my.id/v1")!,
                trackKey: trackKey,
                preferFast: true
            )
        )
        let query = queryItems(url)
        XCTAssertTrue(url.path.hasSuffix("/lyrics"))
        XCTAssertEqual(query["title"], "Blinding Lights")
        XCTAssertEqual(query["artist"], "The Weeknd")
        XCTAssertEqual(query["album"], "After Hours")
        XCTAssertEqual(query["duration"], "200")
        XCTAssertEqual(query["isrc"], "USUG11904206")
        XCTAssertEqual(query["fast"], "1")
    }

    func testLiriQoParsesPrimaryTimedWordsAndUpstreamAttribution() async throws {
        let payload: [String: Any] = [
            "matchScore": 1,
            "primary": [
                "title": "Blinding Lights",
                "artist": "The Weeknd",
                "syncLevel": "syllable",
                "provider": "apple_music_liriqo",
                "upstreamProvider": "Apple Music",
                "source": "Apple Music",
                "timed": [
                    [
                        "id": 0,
                        "text": "I been tryna call",
                        "start": 27395,
                        "end": 28960,
                        "words": [
                            ["text": "I", "start": 27395, "end": 27549],
                            ["text": "been", "start": 27549, "end": 27740],
                            ["text": "tryna", "start": 27740, "end": 28077],
                            ["text": "call", "start": 28077, "end": 28960],
                        ],
                    ],
                ],
            ],
        ]
        let transport = AggregatorStubTransport([
            .http(status: 200, body: json(payload), headers: ["Content-Type": "application/json"]),
        ])
        let provider = LiriQoLyricsProvider(transport: transport)

        let result = await provider.lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.lines.first?.text, "I been tryna call")
        XCTAssertEqual(document.lines.first?.startSeconds, 27.395)
        XCTAssertEqual(document.lines.first?.words?.count, 4)
        XCTAssertEqual(document.synchronization, .syllableSynced)
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.liriqo.rawValue)
        XCTAssertEqual(document.source?.upstreamProviderID, "Apple Music")
        XCTAssertEqual(document.source?.kind, .online)
        XCTAssertEqual(document.source?.isPersisted, false)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Audune/"), true)
    }

    func testLiriQoMapsEmbeddedJSONErrorOnHTTP200() async {
        let transport = AggregatorStubTransport([
            .http(
                status: 200,
                body: json(["error": "no lyrics found"]),
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let provider = LiriQoLyricsProvider(transport: transport)
        let result = await provider.lookup(for: trackKey)
        XCTAssertEqual(result, .notFound)
    }

    func testLRCMuxBuildsGetJSONRequest() throws {
        let url = try XCTUnwrap(
            LRCMuxLyricsProvider.requestURL(
                baseURL: URL(string: "https://api.lrcmux.dev")!,
                trackKey: trackKey
            )
        )
        let query = queryItems(url)
        XCTAssertTrue(url.path.hasSuffix("/get"))
        XCTAssertEqual(query["artist"], "The Weeknd")
        XCTAssertEqual(query["title"], "Blinding Lights")
        XCTAssertEqual(query["format"], "json")
    }

    func testLRCMuxParsesWordSyncedJSONAndSourceAttribution() async throws {
        let payload: [String: Any] = [
            "meta": [
                "level": "word",
                "source": [
                    "id": "deezer",
                    "name": "Deezer",
                    "url": "https://www.deezer.com",
                ],
            ],
            "lines": [
                [
                    "text": "Yeah",
                    "start": 13747,
                    "end": 13922,
                    "words": [
                        ["text": "Yeah", "start": 13747, "end": 13922],
                    ],
                ],
                [
                    "text": "I've been tryna call",
                    "start": 27395,
                    "end": 28960,
                    "words": [
                        ["text": "I've", "start": 27395, "end": 27549],
                        ["text": "been", "start": 27549, "end": 27740],
                    ],
                ],
            ],
        ]
        let transport = AggregatorStubTransport([
            .http(status: 200, body: json(payload), headers: ["Content-Type": "application/json"]),
        ])
        let provider = LRCMuxLyricsProvider(transport: transport)

        let result = await provider.lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertEqual(document.lines[1].words?.count, 2)
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.lrcmux.rawValue)
        XCTAssertEqual(document.source?.upstreamProviderID, "Deezer")
        XCTAssertEqual(document.source?.attributionURL, "https://www.deezer.com")
        XCTAssertFalse(document.source?.providerID == "deezer")
    }

    func testLRCMuxMaps404And429() async {
        let notFoundTransport = AggregatorStubTransport([
            .http(status: 404, body: json(["detail": "no lyrics found"])),
        ])
        let limitedTransport = AggregatorStubTransport([
            .http(
                status: 429,
                body: Data(),
                headers: ["Retry-After": "2", "Content-Type": "application/json"]
            ),
        ])

        let missing = await LRCMuxLyricsProvider(transport: notFoundTransport).lookup(for: trackKey)
        XCTAssertEqual(missing, .notFound)

        let limited = await LRCMuxLyricsProvider(transport: limitedTransport).lookup(for: trackKey)
        guard case .rateLimited(let seconds) = limited else {
            return XCTFail("Expected rate limit, got \(limited)")
        }
        XCTAssertEqual(seconds, 2)
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func queryItems(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
    }
}

private final class AggregatorStubTransport: LyricsHTTPTransport, @unchecked Sendable {
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
        let response = responses.isEmpty ? Response.failure(URLError(.unknown)) : responses.removeFirst()
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
