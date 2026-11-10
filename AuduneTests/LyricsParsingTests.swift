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

    func testYRCParserReadsStyledWordTimings() throws {
        let contents = """
        [54260,3090](54260,900,0)Stop (55160,480,0)and (55640,1710,0)stare
        [57380,1500](57380,150,0)I (57530,600,0)think
        """
        let document = try YRCLyricsParser.parse(contents, trackKey: trackKey)
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertEqual(document.lines[0].text, "Stop and stare")
        XCTAssertEqual(try XCTUnwrap(document.lines[0].startSeconds), 54.26, accuracy: 0.001)
        XCTAssertEqual(document.lines[0].words?.map(\.text), ["Stop", "and", "stare"])
        XCTAssertEqual(document.synchronization, .wordSynced)
    }

    func testYRCParserReadsJSONLines() throws {
        let contents = #"{"t":1000,"c":[{"tx":"Hello","tr":[0,400]},{"tx":" ","tr":[400,50]},{"tx":"world","tr":[450,500]}]}"#
        let document = try YRCLyricsParser.parse(contents, trackKey: trackKey)
        XCTAssertEqual(document.lines.first?.text.replacingOccurrences(of: " ", with: ""), "Helloworld")
        XCTAssertEqual(document.lines.first?.words?.count, 3)
    }

    func testQRCParserReadsWordTimings() throws {
        let contents = "[0,1230](0,240)词(240,180)语(420,300)测试"
        let document = try QRCLyricsParser.parse(contents, trackKey: trackKey)
        XCTAssertEqual(document.lines.first?.text, "词语测试")
        XCTAssertEqual(document.lines.first?.words?.count, 3)
        XCTAssertEqual(document.synchronization, .wordSynced)
    }

    func testKRCParserReadsPlaintextAndRejectsEncrypted() throws {
        let contents = "[1000,2000]<0,500,0>你<500,700,0>好"
        let document = try KRCLyricsParser.parse(contents, trackKey: trackKey)
        XCTAssertEqual(document.lines.first?.text, "你好")
        XCTAssertEqual(document.lines.first?.words?.map(\.text), ["你", "好"])

        XCTAssertThrowsError(try KRCLyricsParser.parse("krc1\u{0000}encrypted", trackKey: trackKey)) {
            XCTAssertEqual($0 as? AdvancedLyricsParserError, .unsupportedEncryptedKRC)
        }
    }

    func testDeclaredSyllableSyncDoesNotInventWordData() {
        var document = LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: nil,
            lines: [
                LyricsLine(id: 0, startSeconds: 1, endSeconds: 2, text: "Hi", translation: nil, words: nil)
            ],
            source: nil,
            declaredSynchronization: .syllableSynced
        )
        XCTAssertEqual(document.synchronization, .lineSynced)

        document.lines[0].words = [
            LyricsWord(id: 0, text: "H", startSeconds: 1, durationSeconds: 0.2),
            LyricsWord(id: 1, text: "i", startSeconds: 1.2, durationSeconds: 0.3),
        ]
        XCTAssertEqual(document.synchronization, .syllableSynced)
    }

    func testFormatDetectorRoutesTTMLAndYRC() throws {
        let ttml = #"<tt><body><div><p begin="1.0" end="2.0"><span begin="1.0" end="1.4">A</span> <span begin="1.4" end="2.0">B</span></p></div></body></tt>"#
        let ttmlDocument = try LyricsFormatDetector.parse(ttml, trackKey: trackKey)
        XCTAssertEqual(ttmlDocument.lines.first?.words?.count, 2)

        let yrc = "[1000,800](1000,400,0)你(1400,400,0)好"
        let yrcDocument = try LyricsFormatDetector.parse(yrc, trackKey: trackKey)
        XCTAssertEqual(yrcDocument.lines.first?.text, "你好")
    }

    func testTTMLParserReadsDuetAgentsBackgroundVocalsTranslationsAndRomanization() throws {
        let ttml = """
        <tt xml:lang="ja" itunes:timing="Word">
          <body>
            <div>
              <p begin="00:10.000" end="00:14.000" ttm:agent="v1">
                <span begin="00:10.000" end="00:11.500">夜に</span>
                <span begin="00:11.500" end="00:13.000">駆ける</span>
                <span ttm:role="x-bg" begin="00:12.000" end="00:14.000">
                  <span begin="00:12.000" end="00:13.000">Run</span>
                  <span begin="00:13.000" end="00:14.000">away</span>
                </span>
                <span ttm:role="x-translation">奔向夜晚</span>
                <span ttm:role="x-roman">yoru ni kakeru</span>
              </p>
              <p begin="00:14.500" end="00:18.000" ttm:agent="v2">
                <span begin="00:14.500" end="00:16.000">君の声</span>
              </p>
            </div>
          </body>
        </tt>
        """
        let document = try LyricsFormatDetector.parse(ttml, trackKey: trackKey)
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertTrue(document.hasTranslations)
        XCTAssertTrue(document.hasPronunciations)

        let first = document.lines[0]
        XCTAssertFalse(first.isSecondaryVocal)
        XCTAssertEqual(first.text, "夜に 駆ける")
        XCTAssertEqual(first.words?.map(\.text), ["夜に", "駆ける"])
        XCTAssertEqual(first.backgroundText, "Run away")
        XCTAssertEqual(first.backgroundWords?.map(\.text), ["Run", "away"])
        XCTAssertEqual(first.translation, "奔向夜晚")
        XCTAssertEqual(first.pronunciation, "yoru ni kakeru")

        let second = document.lines[1]
        XCTAssertTrue(second.isSecondaryVocal)
        XCTAssertEqual(second.text, "君の声")
    }

    func testLRCParserReadsThreeLineTimestampsAsTextTranslationAndPronunciation() throws {
        let lrc = """
        [00:05.00]夜に駆ける
        [00:05.00]奔向夜晚
        [00:05.00]yoru ni kakeru
        """
        let document = try LRCParser.parse(lrc, trackKey: trackKey)
        XCTAssertEqual(document.lines.count, 1)
        XCTAssertEqual(document.lines[0].text, "夜に駆ける")
        XCTAssertEqual(document.lines[0].translation, "奔向夜晚")
        XCTAssertEqual(document.lines[0].pronunciation, "yoru ni kakeru")
    }
}
