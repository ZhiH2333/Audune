import Foundation
import XCTest
@testable import Audune

final class ChinaLyricsProviderTests: XCTestCase {
    private let trackKey = LyricsTrackKey(
        isrc: nil,
        title: "晴天",
        artist: "周杰伦",
        album: "叶惠美",
        durationSeconds: 269
    )

    func testMetingSearchURLUsesNodeAndServer() throws {
        let node = LyricsProviderRegistry.meting.defaultNodes[0]
        let url = try XCTUnwrap(
            MetingLyricsProvider.searchURL(node: node, server: .tencent, trackKey: trackKey)
        )
        let query = queryItems(url)
        XCTAssertEqual(query["server"], "tencent")
        XCTAssertEqual(query["type"], "search")
        XCTAssertEqual(query["id"], "晴天 周杰伦")
        XCTAssertEqual(url.host, "api.i-meto.com")
    }

    func testMetingRejectsWeakArtistCoversAndParsesLRC() async throws {
        let search: [[String: Any]] = [
            [
                "title": "晴天 (原唱 周杰伦)",
                "author": "RyaVocal",
                "lrc": "https://api.i-meto.com/meting/api?server=tencent&type=lrc&id=bad",
            ],
            [
                "title": "晴天",
                "author": "周杰伦",
                "lrc": "https://api.i-meto.com/meting/api?server=tencent&type=lrc&id=0039MnYb0qxYhV&auth=abc",
            ],
        ]
        let transport = ChinaStubTransport([
            .http(status: 200, body: json(search), headers: ["Content-Type": "application/json"]),
            .http(
                status: 200,
                body: Data("[00:01.00]故事的小黄花\n[00:05.00]从出生那年就飘着".utf8),
                headers: ["Content-Type": "text/plain"]
            ),
        ])
        let result = await MetingLyricsProvider(transport: transport, server: .tencent).lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.lines.first?.text, "故事的小黄花")
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.meting.rawValue)
        XCTAssertEqual(document.source?.upstreamProviderID, "tencent")
        XCTAssertEqual(document.source?.nodeID, "meting-i-meto")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests[1].url?.absoluteString.contains("0039MnYb0qxYhV") == true)
    }

    func testQQMusicWrapperUsesTencentServerAttribution() async throws {
        let search: [[String: Any]] = [
            [
                "title": "晴天",
                "author": "周杰伦",
                "lrc": "https://example.test/lrc",
            ]
        ]
        let transport = ChinaStubTransport([
            .http(status: 200, body: json(search)),
            .http(status: 200, body: Data("[00:01.00]一行".utf8)),
        ])
        let result = await QQMusicMetingLyricsProvider(transport: transport).lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.source?.providerID, LyricsProviderID.qqMusic.rawValue)
        XCTAssertEqual(document.source?.providerName, "QQ Music")
    }

    func testKuGouCandidateStaysUnavailable() async {
        let result = await KuGouLyricsProvider().lookup(for: trackKey)
        XCTAssertEqual(result, .providerUnavailable)
        XCTAssertEqual(LyricsProviderRegistry.kugou.enablement, .candidate)
    }

    func testLrcShareWithoutKeyIsUnauthorized() async {
        let result = await LrcShareLyricsProvider(apiKey: nil).lookup(for: trackKey)
        XCTAssertEqual(result, .unauthorized)
    }

    func testLrcShareWithKeyMapsAuthFailureTruthfully() async {
        let transport = ChinaStubTransport([.http(status: 403, body: Data())])
        let result = await LrcShareLyricsProvider(transport: transport, apiKey: "test-key").lookup(for: trackKey)
        XCTAssertEqual(result, .unauthorized)
        XCTAssertEqual(
            transport.requests.first?.value(forHTTPHeaderField: "X-API-Key"),
            "test-key"
        )
    }

    func testAPIKeyStoreRoundTripInIsolatedService() {
        let store = LyricsAPIKeyStore(service: "com.audune.lyrics.api-keys.tests.\(UUID().uuidString)")
        XCTAssertNil(store.apiKey(for: "demo"))
        XCTAssertTrue(store.setAPIKey("secret-value", for: "demo"))
        XCTAssertEqual(store.apiKey(for: "demo"), "secret-value")
        XCTAssertTrue(store.setAPIKey(nil, for: "demo"))
        XCTAssertNil(store.apiKey(for: "demo"))
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func queryItems(_ url: URL) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") }
        )
    }
}

private final class ChinaStubTransport: LyricsHTTPTransport, @unchecked Sendable {
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
            return (
                body,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!
            )
        }
    }
}
