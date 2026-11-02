import XCTest
@testable import Audune

final class LyricsProviderGroupTests: XCTestCase {
    func testQualityPrefersTitleArtistAndDurationMatch() {
        let request = LyricsSearchRequest(
            title: "Uprising",
            artist: "Muse",
            album: "",
            durationSeconds: 305
        )
        let strong = LyricsQuality.score(
            request: request,
            title: "Uprising",
            artist: "Muse",
            durationSeconds: 305,
            lineCount: 20
        )
        let weak = LyricsQuality.score(
            request: request,
            title: "Starlight",
            artist: "Other",
            durationSeconds: 200,
            lineCount: 2
        )
        XCTAssertGreaterThan(strong, weak)
        XCTAssertGreaterThanOrEqual(strong, 0.55)
    }

    func testGroupPicksHighestQualityProvider() async throws {
        let low = StaticLyricsProvider(
            id: .lrclib,
            hit: LyricsHit(
                source: .lrclib,
                matchedTitle: "Wrong",
                matchedArtist: "A",
                durationSeconds: 100,
                rawLRC: "[00:01.00]Low",
                lines: [LyricLine(timeSeconds: 1, text: "Low")],
                quality: 0.6
            )
        )
        let high = StaticLyricsProvider(
            id: .netease,
            hit: LyricsHit(
                source: .netease,
                matchedTitle: "Right",
                matchedArtist: "B",
                durationSeconds: 200,
                rawLRC: "[00:01.00]High",
                lines: [LyricLine(timeSeconds: 1, text: "High")],
                quality: 1.2
            )
        )
        let group = LyricsProviderGroup(providers: [low, high], minimumQuality: 0.55)
        let hit = try await group.searchBest(
            for: LyricsSearchRequest(title: "Right", artist: "B", album: "", durationSeconds: 200)
        )
        XCTAssertEqual(hit.source, .netease)
        XCTAssertEqual(hit.lines.first?.text, "High")
    }

    func testGroupThrowsWhenAllBelowMinimumQuality() async {
        let weak = StaticLyricsProvider(
            id: .qq,
            hit: LyricsHit(
                source: .qq,
                matchedTitle: "Nope",
                matchedArtist: "X",
                durationSeconds: nil,
                rawLRC: "[00:01.00]Weak",
                lines: [LyricLine(timeSeconds: 1, text: "Weak")],
                quality: 0.2
            )
        )
        let group = LyricsProviderGroup(providers: [weak], minimumQuality: 0.55)
        do {
            _ = try await group.searchBest(
                for: LyricsSearchRequest(title: "Song", artist: "Artist", album: "", durationSeconds: 180)
            )
            XCTFail("expected notFound")
        } catch let error as LyricsFetchError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

nonisolated struct StaticLyricsProvider: LyricsProvider {
    var id: LyricsSourceID
    var hit: LyricsHit?

    func search(request: LyricsSearchRequest) async -> LyricsHit? {
        _ = request
        return hit
    }
}
