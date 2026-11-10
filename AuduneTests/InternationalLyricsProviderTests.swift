import Foundation
import XCTest
@testable import Audune

final class InternationalLyricsProviderTests: XCTestCase {
    private let trackKey = LyricsTrackKey(
        isrc: "USUG11904206",
        title: "Blinding Lights",
        artist: "The Weeknd",
        album: "After Hours",
        durationSeconds: 200
    )

    func testTTMLParserExtractsWordTimings() throws {
        let xml = """
        <tt xml:lang="en" itunes:timing="Word">
          <body>
            <div>
              <p begin="27.395" end="28.960">
                <span begin="27.395" end="27.549">I</span>
                <span begin="27.549" end="27.740">been</span>
              </p>
            </div>
          </body>
        </tt>
        """
        let document = try TTMLLyricsParser.parse(xml, trackKey: trackKey)
        XCTAssertEqual(document.lines.count, 1)
        XCTAssertEqual(document.lines[0].text, "I been")
        XCTAssertEqual(document.lines[0].startSeconds, 27.395)
        XCTAssertEqual(document.lines[0].words?.count, 2)
        XCTAssertEqual(document.synchronization, .wordSynced)
    }

    func testBetterLyricsBuildsQueryAndParsesTTML() async throws {
        let url = try XCTUnwrap(
            BetterLyricsProvider.requestURL(
                baseURL: URL(string: "https://api.betterlyrics.org")!,
                trackKey: trackKey
            )
        )
        let query = queryItems(url)
        XCTAssertEqual(query["s"], "Blinding Lights")
        XCTAssertEqual(query["a"], "The Weeknd")
        XCTAssertEqual(query["al"], "After Hours")
        XCTAssertEqual(query["d"], "200")

        let payload = [
            "ttml": """
            <tt xml:lang="en"><body><div><p begin="1.0" end="2.0"><span begin="1.0" end="1.5">Hello</span> <span begin="1.5" end="2.0">world</span></p></div></body></tt>
            """
        ]
        let transport = IntlStubTransport([
            .http(status: 200, body: json(payload), headers: ["Content-Type": "application/json"]),
        ])
        let result = await BetterLyricsProvider(transport: transport).lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.betterLyrics.rawValue)
        XCTAssertEqual(document.lines.first?.words?.count, 2)
    }

    func testBetterLyricsMapsUnauthorizedWithoutFakingSuccess() async {
        let transport = IntlStubTransport([.http(status: 401, body: Data())])
        let result = await BetterLyricsProvider(transport: transport).lookup(for: trackKey)
        XCTAssertEqual(result, .unauthorized)
    }

    func testLrcRedSearchThenFetchByISRC() async throws {
        let search = [
            "hits": [
                [
                    "isrc": "USUG11904206",
                    "title": "Blinding Lights",
                    "artist": "The Weeknd",
                    "album": "After Hours",
                    "duration": 200.0,
                ]
            ]
        ]
        let lrc = "[00:01.00]First\n[00:05.00]Second"
        let keyWithoutISRC = LyricsTrackKey(
            isrc: nil,
            title: "Blinding Lights",
            artist: "The Weeknd",
            album: "After Hours",
            durationSeconds: 200
        )
        let transport = IntlStubTransport([
            .http(status: 200, body: json(search), headers: ["Content-Type": "application/json"]),
            .http(status: 404, body: Data()), // ttml miss
            .http(status: 200, body: Data(lrc.utf8), headers: ["Content-Type": "text/plain"]),
        ])
        let result = await LrcRedLyricsProvider(transport: transport).lookup(for: keyWithoutISRC)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.lines.map(\.text), ["First", "Second"])
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.lrcRed.rawValue)
        XCTAssertEqual(document.source?.attributionURL, "https://lrc.red")
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.requests[0].url?.path.hasSuffix("/search.json") == true)
        XCTAssertTrue(transport.requests[1].url?.path.contains("/s/USUG11904206.ttml") == true)
        XCTAssertTrue(transport.requests[2].url?.path.contains("/s/USUG11904206.lrc") == true)
    }

    func testLyricsOvhReturnsUnsyncedOnly() async throws {
        let transport = IntlStubTransport([
            .http(
                status: 200,
                body: json(["lyrics": "Line one\nLine two"]),
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let result = await LyricsOvhProvider(transport: transport).lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.synchronization, .unsynced)
        XCTAssertTrue(document.lines.allSatisfy { $0.startSeconds == nil })
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.lyricsOvh.rawValue)
    }

    func testLRCLIBSourceIncludesRegistryIdentity() async throws {
        let record: [String: Any] = [
            "id": 7,
            "trackName": "Blinding Lights",
            "artistName": "The Weeknd",
            "albumName": "After Hours",
            "duration": 200,
            "instrumental": false,
            "hasWordSync": false,
            "plainLyrics": NSNull(),
            "syncedLyrics": "[00:01.00]Hello",
            "lyricsfile": NSNull(),
            "name": "Blinding Lights",
        ]
        let transport = IntlStubTransport([
            .http(
                status: 200,
                body: try JSONSerialization.data(withJSONObject: record),
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let result = await LRCLIBLyricsProvider(transport: transport, requestSpacing: 0).lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.source?.kind, .lrclib)
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.lrclib.rawValue)
        XCTAssertEqual(document.source?.nodeID, "lrclib-official")
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func queryItems(_ url: URL) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") }
        )
    }
}

private final class IntlStubTransport: LyricsHTTPTransport, @unchecked Sendable {
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
