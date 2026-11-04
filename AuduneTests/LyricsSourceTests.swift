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

    func testLyricsTrackMatcherUsesCrossPlayerKeyAndDoesNotGuessDurationTolerance() {
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

        XCTAssertEqual(LyricsTrackMatcher.match(sameTrackFromAnotherPlayer, in: [imported]), .exact(imported))
        XCTAssertEqual(LyricsTrackMatcher.match(changedDuration, in: [imported]), .ambiguous([imported]))
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
        XCTAssertEqual(try store.load(), [imported])
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
