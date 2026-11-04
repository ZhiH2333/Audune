import Foundation
import XCTest
@testable import Audune

final class LyricsParsingTests: XCTestCase {
    private let trackKey = LyricsTrackKey(
        isrc: nil,
        title: "Track",
        artist: "Artist",
        album: "Album",
        durationSeconds: 180
    )

    func testParsesBOMCRLFAndMultipleTimestampsPerLine() throws {
        let contents = "\u{feff}[00:01.00]One\r\n[00:02.00][00:03.00]Two\r\n"

        let document = try LRCParser.parse(contents, trackKey: trackKey)

        XCTAssertEqual(document.lines.map(\.text), ["One", "Two", "Two"])
        XCTAssertEqual(document.lines.map(\.startSeconds), [1, 2, 3])
        XCTAssertEqual(document.lines[1].endSeconds, 3)
    }

    func testIgnoresInvalidTimestampsAndRequiresAtLeastOneTimedLine() throws {
        let document = try LRCParser.parse(
            "[00:99.00]Invalid seconds\n[00:01.00]Valid\n[not a timestamp]",
            trackKey: trackKey
        )
        XCTAssertEqual(document.lines.map(\.text), ["Valid"])

        XCTAssertThrowsError(try LRCParser.parse("[00:01.00]\n", trackKey: trackKey)) {
            XCTAssertEqual($0 as? LyricsImportError, .noTimedLines)
        }
    }

    func testParsesEnhancedWordTimestampsAsRealWordData() throws {
        let contents = """
        [00:10.00]<00:10.00>Hello <00:10.50>world
        [00:12.00]Next line
        """

        let document = try LRCParser.parse(contents, trackKey: trackKey)
        let words = try XCTUnwrap(document.lines.first?.words)

        XCTAssertEqual(document.synchronization, .wordSynced)
        XCTAssertEqual(words.map(\.text), ["Hello", "world"])
        XCTAssertEqual(words[0].startSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(words[0].durationSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(words[1].durationSeconds, 1.5, accuracy: 0.001)
    }

    func testDoesNotInventWordTimingsFromPlainText() throws {
        let document = try LRCParser.parse(
            "[00:01.00]<00:01.00>Only one word",
            trackKey: trackKey
        )
        XCTAssertNil(document.lines.first?.words)
        XCTAssertEqual(document.synchronization, .lineSynced)
    }

    func testParsesPlainLyricsAsUnsyncedLinesWithoutMetadata() throws {
        let document = try LRCParser.parsePlain(
            "[ti:Track]\nFirst line\n\nSecond line\n[ar:Artist]",
            trackKey: trackKey
        )

        XCTAssertEqual(document.lines.map(\.text), ["First line", "Second line"])
        XCTAssertEqual(document.lines.map(\.startSeconds), [nil, nil])
        XCTAssertEqual(document.synchronization, .unsynced)
    }

    func testRejectsEmptyPlainLyrics() {
        XCTAssertThrowsError(try LRCParser.parsePlain("[ti:Track]\n\n", trackKey: trackKey)) {
            XCTAssertEqual($0 as? LyricsImportError, .emptyFile)
        }
    }

    func testLyricsfileParserReadsLinesAndWordTimings() throws {
        let contents = """
        version: '1.0'
        metadata:
          title: Track
          artist: Artist
        lines:
          - text: 'First line'
            start_ms: 1000
            end_ms: 2500
          - text: 'Second line'
            start_ms: 2500
            end_ms: 4000
        """

        let document = try LyricsfileParser.parse(contents, trackKey: trackKey)

        XCTAssertEqual(document.lines.map(\.text), ["First line", "Second line"])
        XCTAssertEqual(document.lines.map(\.startSeconds), [1, 2.5])
        XCTAssertEqual(document.lines.first?.endSeconds, 2.5)
        XCTAssertEqual(document.synchronization, .lineSynced)
    }

    func testLyricsfileParserReadsNestedWordsAndRejectsBadOrdering() throws {
        let contents = """
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

        let document = try LyricsfileParser.parse(contents, trackKey: trackKey)
        let words = try XCTUnwrap(document.lines.first?.words)
        XCTAssertEqual(words.map(\.text), ["Hello", "world"])
        XCTAssertEqual(document.synchronization, .wordSynced)

        let unordered = """
        lines:
          - text: 'Hello world'
            start_ms: 1000
            words:
              - text: 'Hello'
                start_ms: 2000
              - text: 'world'
                start_ms: 1500
        """
        let unorderedDocument = try LyricsfileParser.parse(unordered, trackKey: trackKey)
        XCTAssertNil(unorderedDocument.lines.first?.words)
    }

    func testLyricsfileParserRequiresATimedLinesSection() {
        XCTAssertThrowsError(
            try LyricsfileParser.parse("version: '1.0'\nmetadata:\n  title: Track", trackKey: trackKey)
        ) {
            XCTAssertEqual($0 as? LyricsImportError, .noTimedLines)
        }
    }

    func testLyricsfileParserDetectsInstrumentalFlag() {
        XCTAssertTrue(LyricsfileParser.isInstrumental("version: '1.0'\ninstrumental: true\nlines: []"))
        XCTAssertFalse(LyricsfileParser.isInstrumental("version: '1.0'\nlines: []"))
    }
}
