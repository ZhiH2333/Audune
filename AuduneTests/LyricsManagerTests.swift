import Foundation
import XCTest
@testable import Audune

private let testProviderDescriptor = LyricsProviderDescriptor(
    kind: .lrclib,
    displayName: "LRCLIB",
    websiteURL: URL(string: "https://lrclib.net")!,
    queryFields: [.title, .artist, .album, .duration]
)

private actor ImmediateLyricsProvider: OnlineLyricsProviding {
    nonisolated let descriptor = testProviderDescriptor
    private var results: [OnlineLyricsLookup]
    private(set) var callCount = 0

    init(results: [OnlineLyricsLookup]) {
        self.results = results
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        callCount += 1
        return results.isEmpty ? .notFound : results.removeFirst()
    }
}

private actor ControlledLyricsProvider: OnlineLyricsProviding {
    nonisolated let descriptor = testProviderDescriptor
    private var pending: [(key: LyricsTrackKey, continuation: CheckedContinuation<OnlineLyricsLookup, Never>)] = []
    private(set) var callCount = 0

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        callCount += 1
        return await withCheckedContinuation { continuation in
            pending.append((trackKey, continuation))
        }
    }

    func pendingKeys() -> [LyricsTrackKey] {
        pending.map(\.key)
    }

    func resumeNext(with result: OnlineLyricsLookup) {
        guard pending.isEmpty == false else { return }
        let item = pending.removeFirst()
        item.continuation.resume(returning: result)
    }
}

@MainActor
final class LyricsManagerTests: XCTestCase {
    private var directory: URL!
    private var store: LocalLyricsStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuduneLyricsManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testLocalMatchTakesPriorityAndSkipsProvider() async throws {
        let key = makeKey(title: "Song")
        try store.save(makeDocument(key: key, text: "Saved locally", source: .localImport))
        let provider = ImmediateLyricsProvider(results: [.found(makeDocument(key: key, text: "Online"))])
        let manager = LyricsManager(store: store, provider: provider)

        manager.activate(trackKey: key)

        guard case .local(let document) = manager.state else {
            return XCTFail("Expected local lyrics, got \(manager.state)")
        }
        XCTAssertEqual(document.lines.first?.text, "Saved locally")
        XCTAssertEqual(document.trackKey, key)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 0)
    }

    func testAutomaticOnlineDisabledShowsTruthfulState() async {
        let key = makeKey(title: "Song")
        let provider = ImmediateLyricsProvider(results: [.found(makeDocument(key: key, text: "Online"))])
        let manager = LyricsManager(store: store, provider: provider, automaticOnlineEnabled: false)

        manager.activate(trackKey: key, automaticOnlineEnabled: false)
        XCTAssertEqual(manager.state, .onlineDisabled)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 0)
    }

    func testOnlineFoundIsCachedForTheSessionOnly() async throws {
        let key = makeKey(title: "Song")
        let online = makeDocument(key: key, text: "Online")
        let provider = ImmediateLyricsProvider(results: [.found(online)])
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)

        await waitUntil("online result") { if case .found = manager.state { return true }; return false }
        XCTAssertEqual(manager.state, .found(online))
        let callsAfterFirst = await provider.callCount
        XCTAssertEqual(callsAfterFirst, 1)
        XCTAssertEqual(try store.load(), [])

        manager.deactivate()
        manager.activate(trackKey: key)
        XCTAssertEqual(manager.state, .found(online))
        let callsAfterSecond = await provider.callCount
        XCTAssertEqual(callsAfterSecond, 1)
    }

    func testFailureIsNotCachedAndRetrySendsANewRequest() async {
        let key = makeKey(title: "Song")
        let online = makeDocument(key: key, text: "Online")
        let provider = ImmediateLyricsProvider(results: [.notFound, .found(online)])
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)

        await waitUntil("notFound") { manager.state == .notFound }
        let firstCalls = await provider.callCount
        XCTAssertEqual(firstCalls, 1)

        manager.retry()
        await waitUntil("retry result") { if case .found = manager.state { return true }; return false }
        XCTAssertEqual(manager.state, .found(online))
        let calls = await provider.callCount
        XCTAssertEqual(calls, 2)
    }

    func testStaleResponseForThePreviousSongIsIgnored() async {
        let firstKey = makeKey(title: "First")
        let secondKey = makeKey(title: "Second")
        let provider = ControlledLyricsProvider()
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: firstKey)
        await waitUntil("first request") { await provider.pendingKeys().contains(firstKey) }

        manager.activate(trackKey: secondKey)
        await waitUntil("second request") { await provider.pendingKeys().contains(secondKey) }

        let first = makeDocument(key: firstKey, text: "First lyrics")
        let second = makeDocument(key: secondKey, text: "Second lyrics")
        await provider.resumeNext(with: .found(first))
        await Task.yield()
        XCTAssertEqual(manager.activeTrackKey, secondKey)
        XCTAssertNotEqual(manager.state, .found(first))

        await provider.resumeNext(with: .found(second))
        await waitUntil("second result") { manager.state == .found(second) }
        XCTAssertEqual(manager.state, .found(second))
    }

    func testDeactivateCancelsAndDropsLateResponse() async {
        let key = makeKey(title: "Song")
        let provider = ControlledLyricsProvider()
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)
        await waitUntil("request") { await provider.pendingKeys().contains(key) }

        manager.deactivate()
        XCTAssertEqual(manager.state, .idle)
        await provider.resumeNext(with: .found(makeDocument(key: key, text: "Late")))
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(manager.state, .idle)
    }

    func testDeletingLocalLyricsSearchesAgain() async throws {
        let key = makeKey(title: "Song")
        let local = makeDocument(key: key, text: "Local", source: .localImport)
        try store.save(local)
        let provider = ControlledLyricsProvider()
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)
        XCTAssertEqual(manager.state, .local(local))

        try manager.deleteLocalDocument(local.id)
        XCTAssertEqual(manager.state, .searchingOnline)
        await waitUntil("search after delete") { await provider.callCount == 1 }
        await provider.resumeNext(with: .notFound)
        await waitUntil("notFound after delete") { manager.state == .notFound }
    }

    func testImportOverridesAnInFlightSearch() async throws {
        let key = makeKey(title: "Song")
        let provider = ControlledLyricsProvider()
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)
        await waitUntil("request") { await provider.callCount == 1 }

        let local = makeDocument(key: key, text: "Imported", source: .localImport)
        manager.localDocumentImported(local)
        XCTAssertEqual(manager.state, .local(local))

        await provider.resumeNext(with: .found(makeDocument(key: key, text: "Online")))
        await Task.yield()
        XCTAssertEqual(manager.state, .local(local))
    }

    func testProviderErrorsMapToDistinctStates() async {
        let cases: [(OnlineLyricsLookup, LyricsPresentationState)] = [
            (.instrumental, .instrumental),
            (.offline, .offline),
            (.timedOut, .networkError),
            (.networkError, .networkError),
            (.providerUnavailable, .providerUnavailable),
            (.serverError(statusCode: 500), .providerUnavailable),
            (.parseError, .parseError),
            (.rateLimited(retryAfterSeconds: 12), .rateLimited(retryAfterSeconds: 12)),
            (.cancelled, .cancelled)
        ]

        for (result, expected) in cases {
            let key = makeKey(title: "Song-\(UUID().uuidString)")
            let provider = ImmediateLyricsProvider(results: [result])
            let manager = LyricsManager(store: store, provider: provider)
            manager.activate(trackKey: key)
            await waitUntil("state \(expected)") { manager.state == expected }
            XCTAssertEqual(manager.state, expected)
            manager.deactivate()
        }
    }

    func testProviderDocumentForAnotherSongIsRejected() async {
        let key = makeKey(title: "Requested")
        let wrong = makeDocument(key: makeKey(title: "Other"), text: "Wrong song")
        let provider = ImmediateLyricsProvider(results: [.found(wrong)])
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)

        await waitUntil("parse error") { manager.state == .parseError }
        XCTAssertEqual(manager.state, .parseError)
    }

    func testActivatingTheSameTrackDoesNotRestartTheLookup() async {
        let key = makeKey(title: "Song")
        let provider = ControlledLyricsProvider()
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)
        await waitUntil("request") { await provider.callCount == 1 }

        manager.activate(trackKey: key)
        manager.activate(trackKey: key, automaticOnlineEnabled: true)
        await Task.yield()

        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
    }

    func testRateLimitStoresRetryDelayForTheInterface() async {
        let key = makeKey(title: "Song")
        let provider = ImmediateLyricsProvider(results: [.rateLimited(retryAfterSeconds: 9)])
        let manager = LyricsManager(store: store, provider: provider)
        manager.activate(trackKey: key)

        await waitUntil("rate limited") {
            manager.state == .rateLimited(retryAfterSeconds: 9)
        }
    }

    func testRememberedCandidatePersistsSnapshotAndPerTrackOffsetAcrossSessions() async throws {
        let key = makeKey(title: "Remembered Song")
        let chosen = makeDocument(key: key, text: "Selected lyric line")
        let provider = ImmediateLyricsProvider(results: [.notFound])
        let firstManager = LyricsManager(store: store, provider: provider)

        firstManager.activate(trackKey: key)
        firstManager.selectCandidate(
            chosen,
            for: key,
            rememberSelection: true,
            lyricsOffsetSeconds: 0.7
        )
        XCTAssertEqual(firstManager.activeBindingOffsetSeconds, 0.7)
        XCTAssertEqual(firstManager.loadSavedBindings().count, 1)
        XCTAssertEqual(firstManager.state.document?.source?.kind, .custom)
        XCTAssertEqual(
            firstManager.loadSavedBindings().first?.document.source?.kind,
            .custom
        )

        // Adjusting offset updates the stored per-track binding.
        firstManager.saveOffsetForActiveTrack(-0.4)
        XCTAssertEqual(firstManager.loadSavedBindings().first?.lyricsOffsetSeconds, -0.4)

        // A brand-new manager session resolves the remembered snapshot immediately without hitting online.
        let secondProvider = ImmediateLyricsProvider(results: [.notFound])
        let secondManager = LyricsManager(store: store, provider: secondProvider)
        secondManager.activate(trackKey: key)

        XCTAssertEqual(secondManager.activeBindingOffsetSeconds, -0.4)
        XCTAssertEqual(secondManager.state.document?.lines.first?.text, "Selected lyric line")
        let onlineCalls = await secondProvider.callCount
        XCTAssertEqual(onlineCalls, 0)

        // Deleting the binding clears the remembered offset and falls back to online lookup.
        let bindingID = try XCTUnwrap(secondManager.loadSavedBindings().first?.id)
        try secondManager.deleteSavedBinding(id: bindingID)
        XCTAssertTrue(secondManager.loadSavedBindings().isEmpty)
        await waitUntil("notFound after deleting binding") { secondManager.state == .notFound }
    }

    // MARK: - Helpers

    private func makeKey(title: String) -> LyricsTrackKey {
        LyricsTrackKey(
            isrc: nil,
            title: title,
            artist: "Artist",
            album: "Album",
            durationSeconds: 180
        )
    }

    private func makeDocument(
        key: LyricsTrackKey,
        text: String,
        source: LyricsSourceInfo = LyricsSourceInfo(
            kind: .lrclib,
            providerName: "LRCLIB",
            providerRecordIdentifier: "1",
            isPersisted: false
        )
    ) -> LyricsDocument {
        LyricsDocument(
            id: UUID(),
            trackKey: key,
            language: "en",
            lines: [LyricsLine(id: 0, startSeconds: 0, endSeconds: 4, text: text)],
            source: source
        )
    }

    private func waitUntil(
        _ label: String,
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for \(label).")
    }
}
