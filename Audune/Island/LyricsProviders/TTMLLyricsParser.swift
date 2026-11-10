import Foundation

nonisolated enum TTMLLyricsParserError: Error, Equatable {
    case empty
    case invalidXML
    case noTimedLines
}

/// Parses Apple Music / lrc.red style TTML lyric documents into `LyricsDocument`.
/// Timestamps are expected as TTML clock values (`ss.mmm` or `hh:mm:ss.mmm`).
nonisolated enum TTMLLyricsParser {
    static func parse(_ xml: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw TTMLLyricsParserError.empty }

        let wrapped = """
        <?xml version="1.0" encoding="UTF-8"?>
        \(trimmed)
        """
        guard let data = wrapped.data(using: .utf8) else { throw TTMLLyricsParserError.invalidXML }

        let parser = XMLParser(data: data)
        let delegate = TTMLParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        guard parser.parse() else { throw TTMLLyricsParserError.invalidXML }
        guard delegate.lines.isEmpty == false else { throw TTMLLyricsParserError.noTimedLines }

        let numbered = delegate.lines.enumerated().map { index, line in
            LyricsLine(
                id: index,
                startSeconds: line.startSeconds,
                endSeconds: line.endSeconds,
                text: line.text,
                translation: line.translation,
                pronunciation: nil,
                words: line.words.isEmpty
                    ? nil
                    : line.words.enumerated().map { wordIndex, word in
                        LyricsWord(
                            id: wordIndex,
                            text: word.text,
                            startSeconds: word.startSeconds,
                            durationSeconds: word.durationSeconds
                        )
                    }
            )
        }

        return LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: delegate.language,
            lines: numbered,
            source: nil
        )
    }

    static func parseClock(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map(String.init)
            guard parts.count >= 2, parts.count <= 3 else { return nil }
            let doubles = parts.compactMap(Double.init)
            guard doubles.count == parts.count else { return nil }
            if doubles.count == 3 {
                return doubles[0] * 3600 + doubles[1] * 60 + doubles[2]
            }
            return doubles[0] * 60 + doubles[1]
        }
        return Double(trimmed)
    }
}

private final class TTMLParserDelegate: NSObject, XMLParserDelegate {
    struct DraftWord {
        var text: String
        var startSeconds: Double
        var durationSeconds: Double
    }

    struct DraftLine {
        var text: String
        var startSeconds: Double?
        var endSeconds: Double?
        var translation: String?
        var words: [DraftWord]
    }

    private(set) var lines: [DraftLine] = []
    private(set) var language: String?

    private var currentLineStart: Double?
    private var currentLineEnd: Double?
    private var currentLineText = ""
    private var currentWords: [DraftWord] = []
    private var currentSpanStart: Double?
    private var currentSpanEnd: Double?
    private var currentSpanText = ""
    private var insideParagraph = false
    private var insideSpan = false
    private var timingHint: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = localName(elementName, qualifiedName: qName)
        switch local {
        case "tt":
            language = attributeDict["xml:lang"] ?? attributeDict["lang"]
            timingHint = attributeDict["itunes:timing"]
                ?? attributeDict["lrc:timing"]
                ?? attributeDict["timing"]
        case "p":
            insideParagraph = true
            currentLineText = ""
            currentWords = []
            currentLineStart = TTMLLyricsParser.parseClock(attributeDict["begin"])
            currentLineEnd = TTMLLyricsParser.parseClock(attributeDict["end"])
        case "span":
            guard insideParagraph else { return }
            insideSpan = true
            currentSpanText = ""
            currentSpanStart = TTMLLyricsParser.parseClock(attributeDict["begin"])
            currentSpanEnd = TTMLLyricsParser.parseClock(attributeDict["end"])
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideSpan {
            currentSpanText += string
        } else if insideParagraph {
            currentLineText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = localName(elementName, qualifiedName: qName)
        switch local {
        case "span":
            guard insideSpan else { return }
            insideSpan = false
            let text = collapseWhitespace(currentSpanText)
            if text.isEmpty == false,
               let start = currentSpanStart,
               let end = currentSpanEnd,
               end >= start
            {
                currentWords.append(
                    DraftWord(
                        text: text,
                        startSeconds: start,
                        durationSeconds: max(0, end - start)
                    )
                )
                if currentLineText.isEmpty == false, currentLineText.hasSuffix(" ") == false {
                    currentLineText += " "
                }
                currentLineText += text
            }
            currentSpanText = ""
            currentSpanStart = nil
            currentSpanEnd = nil
        case "p":
            guard insideParagraph else { return }
            insideParagraph = false
            let text = collapseWhitespace(currentLineText)
            if text.isEmpty == false {
                lines.append(
                    DraftLine(
                        text: text,
                        startSeconds: currentLineStart,
                        endSeconds: currentLineEnd,
                        translation: nil,
                        words: currentWords
                    )
                )
            }
            currentLineText = ""
            currentWords = []
            currentLineStart = nil
            currentLineEnd = nil
        default:
            break
        }
    }

    private func localName(_ elementName: String, qualifiedName: String?) -> String {
        if let qualifiedName, let local = qualifiedName.split(separator: ":").last {
            return String(local)
        }
        if let local = elementName.split(separator: ":").last {
            return String(local)
        }
        return elementName
    }

    private func collapseWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
