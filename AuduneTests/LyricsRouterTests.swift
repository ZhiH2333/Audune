import Foundation
import XCTest
@testable import Audune

final class LyricsRouterTests: XCTestCase {
    private let trackKey = LyricsTrackKey(
        isrc: nil,
        title: "Track",
        artist: "Artist",
        album: "Album",
        durationSeconds: 180
    )

    func testRankerRejectsMismatchedTracksAndPrefersHigherSync() {
        let goodLine = makeDocument(title: "Track", artist: "Artist", sync: .lineSynced, text: "A")
        let betterWord = makeDocument(title: "Track", artist: "Artist", sync: .wordSynced, text: "A")
        let wrong = makeDocument(title: "Other", artist: "Artist", sync: .syllableSynced, text: "A")

        XCTAssertNil(
            LyricsCandidateRanker.score(
                document: wrong,
                expected: trackKey,
                providerID: "x",
                nodeID: nil,
                latencySeconds: 0.1,
                reliabilityScore: 1
            )
        )

        let scored = [
            LyricsCandidateRanker.score(
                document: goodLine,
                expected: trackKey,
                providerID: "a",
                nodeID: nil,
                latencySeconds: 0.2,
                reliabilityScore: 1
            )!,
            LyricsCandidateRanker.score(
                document: betterWord,
                expected: trackKey,
                providerID: "b",
                nodeID: nil,
                latencySeconds: 0.8,
                reliabilityScore: 1
            )!,
        ]
        XCTAssertEqual(LyricsCandidateRanker.best(of: scored)?.providerID, "b")
    }

    func testDeduplicatesIdenticalContentFingerprints() {
        let first = makeDocument(title: "Track", artist: "Artist", sync: .lineSynced, text: "Same")
        var secondDoc = makeDocument(title: "Track", artist: "Artist", sync: .wordSynced, text: "Same")
        // Fingerprint currently uses line start + text, so identical line text/start collapses.
        let a = LyricsCandidateRanker.score(
            document: first,
            expected: trackKey,
            providerID: "a",
            nodeID: nil,
            latencySeconds: 1,
            reliabilityScore: 1
        )!
        secondDoc.lines[0].words = [
            LyricsWord(id: 0, text: "Sa", startSeconds: 1, durationSeconds: 0.2),
            LyricsWord(id: 1, text: "me", startSeconds: 1.2, durationSeconds: 0.3),
        ]
        let b = LyricsCandidateRanker.score(
            document: secondDoc,
            expected: trackKey,
            providerID: "b",
            nodeID: nil,
            latencySeconds: 1,
            reliabilityScore: 1
        )!
        let deduped = LyricsCandidateRanker.deduplicated([a, b])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.providerID, "b")
    }

    func testManualModeDoesNotFallBackToOtherProviders() async {
        let health = LyricsNodeHealthStore()
        let router = LyricsRouter(
            selection: LyricsRoutingSelection(
                mode: .manual,
                providerID: LyricsProviderID.lrclib.rawValue,
                nodeID: "lrclib-official"
            ),
            healthStore: health,
            factory: { providerID, _ in
                StubOnlineProvider(
                    id: providerID,
                    result: providerID == LyricsProviderID.lrclib.rawValue
                        ? .notFound
                        : .found(self.makeDocument(title: "Track", artist: "Artist", sync: .wordSynced, text: "Nope"))
                )
            }
        )
        let result = await router.lookup(for: trackKey)
        XCTAssertEqual(result, .notFound)
    }

    func testAutoModeCancelsDoNotLeakAndBoundedProvidersCompete() async {
        let health = LyricsNodeHealthStore()
        let slow = StubOnlineProvider(
            id: "slow",
            result: .found(makeDocument(title: "Track", artist: "Artist", sync: .lineSynced, text: "Slow")),
            delayNanoseconds: 200_000_000
        )
        let fast = StubOnlineProvider(
            id: "fast",
            result: .found(makeDocument(title: "Track", artist: "Artist", sync: .wordSynced, text: "Fast")),
            delayNanoseconds: 20_000_000
        )
        let router = LyricsRouter(
            selection: LyricsRoutingSelection(mode: .autoBestMatch, providerID: nil, nodeID: nil),
            healthStore: health,
            maxConcurrent: 2,
            qualityUpgradeWindowSeconds: 0.25,
            factory: { providerID, _ in
                switch providerID {
                case LyricsProviderID.liriqo.rawValue: return fast
                case LyricsProviderID.lrcmux.rawValue: return slow
                case LyricsProviderID.lrclib.rawValue: return StubOnlineProvider(id: "lrclib", result: .notFound)
                default: return StubOnlineProvider(id: providerID, result: .notFound)
                }
            }
        )
        let result = await router.lookup(for: trackKey)
        guard case .found(let document) = result else {
            return XCTFail("Expected lyrics, got \(result)")
        }
        XCTAssertEqual(document.lines.first?.text, "Fast")
        XCTAssertEqual(document.synchronization, .wordSynced)
    }

    func testHealthStoreCooldownAndPreferredFastNode() async {
        let health = LyricsNodeHealthStore(cooldownSeconds: 1, rateLimitCooldownSeconds: 1)
        let nodes = [
            LyricsNodeDescriptor(
                id: "slow-node",
                providerID: "demo",
                displayName: "Slow",
                baseURL: URL(string: "https://example.invalid/slow")!
            ),
            LyricsNodeDescriptor(
                id: "fast-node",
                providerID: "demo",
                displayName: "Fast",
                baseURL: URL(string: "https://example.invalid/fast")!
            ),
        ]
        await health.recordSuccess(providerID: "demo", nodeID: "slow-node", latencySeconds: 2.0)
        await health.recordSuccess(providerID: "demo", nodeID: "fast-node", latencySeconds: 0.4)
        let preferred = await health.preferredNode(among: nodes)
        XCTAssertEqual(preferred?.id, "fast-node")

        await health.recordFailure(providerID: "demo", nodeID: "fast-node", rateLimited: true)
        let fastAvailable = await health.isAvailable("fast-node")
        XCTAssertFalse(fastAvailable)
        let fallback = await health.preferredNode(among: nodes)
        XCTAssertEqual(fallback?.id, "slow-node")
    }

    private func makeDocument(
        title: String,
        artist: String,
        sync: LyricsSynchronization,
        text: String
    ) -> LyricsDocument {
        var words: [LyricsWord]? = nil
        if sync == .wordSynced || sync == .syllableSynced {
            words = [
                LyricsWord(id: 0, text: text, startSeconds: 1, durationSeconds: 0.5),
                LyricsWord(id: 1, text: "x", startSeconds: 1.5, durationSeconds: 0.5),
            ]
        }
        var document = LyricsDocument(
            id: UUID(),
            trackKey: LyricsTrackKey(
                isrc: nil,
                title: title,
                artist: artist,
                album: "Album",
                durationSeconds: 180
            ),
            language: nil,
            lines: [
                LyricsLine(
                    id: 0,
                    startSeconds: sync == .unsynced ? nil : 1,
                    endSeconds: sync == .unsynced ? nil : 2,
                    text: text,
                    translation: nil,
                    words: words
                ),
            ],
            source: LyricsSourceInfo(
                kind: .online,
                providerName: "Test",
                providerRecordIdentifier: nil,
                isPersisted: false,
                providerID: "test",
                nodeID: nil,
                upstreamProviderID: nil,
                attributionURL: nil,
                matchConfidence: nil,
                retrievedAt: Date()
            ),
            declaredSynchronization: sync == .syllableSynced ? .syllableSynced : nil
        )
        return document
    }
}

private struct StubOnlineProvider: OnlineLyricsProviding {
    let descriptor: LyricsProviderDescriptor
    let result: OnlineLyricsLookup
    let delayNanoseconds: UInt64

    init(id: String, result: OnlineLyricsLookup, delayNanoseconds: UInt64 = 0) {
        self.descriptor = LyricsProviderDescriptor(
            kind: .lrclib,
            displayName: id,
            websiteURL: URL(string: "https://example.invalid")!,
            queryFields: [.title, .artist]
        )
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        _ = trackKey
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if Task.isCancelled { return .cancelled }
        return result
    }
}
