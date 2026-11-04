import XCTest
@testable import Audune

final class LyricsSourceTests: XCTestCase {
    private let trackKey = LyricsTrackKey(
        isrc: nil,
        title: "Track",
        artist: "Artist",
        album: "Album",
        durationSeconds: 180
    )

    func testParsesSortedTimestampsOffsetAndDuplicateTranslationLines() throws {
        let contents = """
        [offset:500]
        [ar:Artist]
        [00:02.00]Second line
        [00:00.10]First line
        [00:00.10]First translation
        [00:03.5][00:04.25]Repeat
        """

        let document = try LRCParser.parse(contents, trackKey: trackKey)

        XCTAssertEqual(document.lines.map(\.startSeconds), [0.6, 2.5, 4, 4.75])
        XCTAssertEqual(document.lines[0].text, "First line")
        XCTAssertEqual(document.lines[0].translation, "First translation")
        XCTAssertEqual(document.lines[0].endSeconds, 2.5)
        XCTAssertEqual(document.lines[1].text, "Second line")
        XCTAssertNil(document.lines[0].words)
        XCTAssertNil(document.lines.last?.endSeconds)
    }

    func testClampsNegativeOffsetAndRejectsDocumentsWithoutTimedLyrics() throws {
        let document = try LRCParser.parse(
            "[offset:-2000]\n[00:01.00]Line",
            trackKey: trackKey
        )
        XCTAssertEqual(document.lines.first?.startSeconds, 0)
        XCTAssertThrowsError(try LRCParser.parse("[ti:No timed lines]\nplain text", trackKey: trackKey)) {
            XCTAssertEqual($0 as? LyricsImportError, .noTimedLines)
        }
    }

    func testLyricsTrackMatcherUsesCrossPlayerKeyWithDurationTolerance() {
        let imported = document(for: LyricsTrackKey(
            isrc: nil,
            title: "Beyoncé",
            artist: "Artist",
            album: "Album",
            durationSeconds: 180
        ))
        let sameTrackFromAnotherPlayer = LyricsTrackKey(
            isrc: nil,
            title: "Beyonce",
            artist: "Artist",
            album: "Album",
            durationSeconds: 180
        )
        let changedDuration = LyricsTrackKey(
            isrc: nil,
            title: "Beyonce",
            artist: "Artist",
            album: "Album",
            durationSeconds: 180.25
        )

        let differentVersion = LyricsTrackKey(
            isrc: nil,
            title: "Beyonce",
            artist: "Artist",
            album: "Album",
            durationSeconds: 205
        )

        XCTAssertEqual(LyricsTrackMatcher.match(sameTrackFromAnotherPlayer, in: [imported]), .exact(imported))
        XCTAssertEqual(LyricsTrackMatcher.match(changedDuration, in: [imported]), .exact(imported))
        XCTAssertEqual(LyricsTrackMatcher.match(differentVersion, in: [imported]), .ambiguous([imported]))
    }

    func testEditionSuffixRequiresSelectionInsteadOfMatchingSilently() {
        let live = document(for: LyricsTrackKey(
            isrc: nil,
            title: "Track (Live)",
            artist: "Artist",
            album: "Album",
            durationSeconds: 181
        ))
        let current = LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: nil,
            durationSeconds: nil
        )

        XCTAssertEqual(LyricsTrackMatcher.match(current, in: [live]), .ambiguous([live]))
    }

    func testISRCTakesPriorityOverDisplayMetadata() {
        let imported = document(for: LyricsTrackKey(
            isrc: "US-ABC-12-34567",
            title: "Stored title",
            artist: "Stored artist",
            album: "Stored album",
            durationSeconds: 180
        ))
        let current = LyricsTrackKey(
            isrc: "usabc1234567",
            title: "Different metadata",
            artist: "Different artist",
            album: nil,
            durationSeconds: 200
        )

        XCTAssertEqual(LyricsTrackMatcher.match(current, in: [imported]), .exact(imported))
    }

    func testAlbumDifferenceIsNeverAnExactMatch() {
        let imported = document(for: LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: "Studio Album",
            durationSeconds: 180
        ))
        let current = LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: "Deluxe Album",
            durationSeconds: 180
        )

        XCTAssertEqual(LyricsTrackMatcher.match(current, in: [imported]), .ambiguous([imported]))
    }

    func testAmbiguousVersionsRequireSelection() {
        let shorter = document(for: trackKey)
        let alternate = document(for: LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: "Deluxe Album",
            durationSeconds: 205
        ))
        let current = LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: nil,
            durationSeconds: nil
        )

        XCTAssertEqual(
            LyricsTrackMatcher.match(current, in: [shorter, alternate]),
            .ambiguous([shorter, alternate])
        )
    }

    func testStorePersistsReplacesAndDeletesOnlySelectedDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuduneLyricsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))
        let first = document(for: trackKey)
        let secondKey = LyricsTrackKey(
            isrc: nil,
            title: "Other",
            artist: "Artist",
            album: "Album",
            durationSeconds: 200
        )
        let second = document(for: secondKey)

        try store.save(first)
        try store.save(second)
        XCTAssertEqual(try store.load(), [first, second])
        XCTAssertEqual(try store.resolve(trackKey: trackKey), .local(first))

        let replacement = LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: "en",
            lines: first.lines
        )
        try store.save(replacement)
        XCTAssertEqual(try store.load(), [replacement, second])

        try store.delete(documentID: replacement.id)
        XCTAssertEqual(try store.load(), [second])
        XCTAssertEqual(try store.resolve(trackKey: trackKey), .noLocalMatch)
        XCTAssertThrowsError(try store.delete(documentID: replacement.id)) {
            XCTAssertEqual($0 as? LyricsImportError, .documentNotFound)
        }
    }

    func testImportReadsSelectedLRCAndPersistsParsedDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuduneLyricsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("track.lrc")
        try Data("[00:01.00]Imported line".utf8).write(to: sourceURL)
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))

        let imported = try store.importLRC(at: sourceURL, for: trackKey)

        XCTAssertEqual(imported.lines.first?.text, "Imported line")
        XCTAssertEqual(imported.source?.kind, .localImport)
        XCTAssertTrue(imported.isPersistedLocally)
        XCTAssertEqual(try store.load(), [imported])
    }

    func testReimportReplacesTheStoredSongEvenWhenPlayerDurationDrifts() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))
        let sourceURL = directory.appendingPathComponent("track.lrc")
        try Data("[00:01.00]First import".utf8).write(to: sourceURL)
        let first = try store.importLRC(at: sourceURL, for: trackKey)

        try Data("[00:01.00]Second import".utf8).write(to: sourceURL)
        let driftedKey = LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: "Album",
            durationSeconds: 180.5
        )
        let second = try store.importLRC(at: sourceURL, for: driftedKey)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try store.load().count, 1)
        XCTAssertEqual(try store.load().first?.lines.first?.text, "Second import")
    }

    func testDifferentAlbumIsStoredSeparately() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))
        let first = document(for: trackKey)
        let deluxe = document(for: LyricsTrackKey(
            isrc: nil,
            title: "Track",
            artist: "Artist",
            album: "Deluxe Album",
            durationSeconds: 180
        ))

        try store.save(first)
        try store.save(deluxe)

        XCTAssertEqual(try store.load(), [first, deluxe])
    }

    func testImportHandlesUTF16BOMAndCRLF() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))
        let sourceURL = directory.appendingPathComponent("track.lrc")
        var data = Data([0xFF, 0xFE])
        data.append("[00:01.00]UTF16 line".data(using: .utf16LittleEndian)!)

        try data.write(to: sourceURL)
        let document = try store.importLRC(at: sourceURL, for: trackKey)

        XCTAssertEqual(document.lines.first?.text, "UTF16 line")
    }

    func testImportHandlesUTF8BOMAndCRLF() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))
        let sourceURL = directory.appendingPathComponent("track.lrc")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("[00:02.00]Windows line\r\n[00:03.00]Next line\r\n".data(using: .utf8)!)
        try data.write(to: sourceURL)

        let document = try store.importLRC(at: sourceURL, for: trackKey)

        XCTAssertEqual(document.lines.map(\.text), ["Windows line", "Next line"])
        XCTAssertEqual(document.lines.first?.startSeconds, 2)
    }

    func testImportRejectsEmptyInvalidAndUntimedFilesWithoutSaving() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))
        let sourceURL = directory.appendingPathComponent("track.lrc")

        try Data().write(to: sourceURL)
        XCTAssertThrowsError(try store.importLRC(at: sourceURL, for: trackKey)) {
            XCTAssertEqual($0 as? LyricsImportError, .emptyFile)
        }

        try Data([0xFF, 0x00]).write(to: sourceURL)
        XCTAssertThrowsError(try store.importLRC(at: sourceURL, for: trackKey)) {
            XCTAssertEqual($0 as? LyricsImportError, .invalidEncoding)
        }

        try Data("[ti:Only metadata]\nplain text".utf8).write(to: sourceURL)
        XCTAssertThrowsError(try store.importLRC(at: sourceURL, for: trackKey)) {
            XCTAssertEqual($0 as? LyricsImportError, .noTimedLines)
        }

        XCTAssertEqual(try store.load(), [])
    }

    func testImportReportsMissingFileInsteadOfCreatingLyrics() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLyricsStore(fileURL: directory.appendingPathComponent("lyrics.json"))

        XCTAssertThrowsError(
            try store.importLRC(at: directory.appendingPathComponent("missing.lrc"), for: trackKey)
        ) {
            XCTAssertEqual($0 as? LyricsImportError, .unreadableFile)
        }
        XCTAssertEqual(try store.load(), [])
    }

    func testCorruptStoreFailsInsteadOfSilentlyReplacingUserData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuduneLyricsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("lyrics.json")
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: fileURL)
        let store = LocalLyricsStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.save(document(for: trackKey)))
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuduneLyricsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func document(for key: LyricsTrackKey) -> LyricsDocument {
        LyricsDocument(
            id: UUID(),
            trackKey: key,
            language: nil,
            lines: [
                LyricsLine(id: 0, startSeconds: 0, endSeconds: 2, text: "Line", translation: nil, words: nil)
            ]
        )
    }
}
