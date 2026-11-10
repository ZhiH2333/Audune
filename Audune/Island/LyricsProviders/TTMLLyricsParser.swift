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
        parser.shouldProcessNamespaces = false
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
                pronunciation: line.pronunciation,
                words: line.words.isEmpty
                    ? nil
                    : line.words.enumerated().map { wordIndex, word in
                        LyricsWord(
                            id: wordIndex,
                            text: word.text,
                            startSeconds: word.startSeconds,
                            durationSeconds: word.durationSeconds
                        )
                    },
                isSecondaryVocal: line.isSecondaryVocal,
                backgroundText: line.backgroundText,
                backgroundWords: line.backgroundWords.isEmpty
                    ? nil
                    : line.backgroundWords.enumerated().map { wordIndex, word in
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
        var pronunciation: String?
        var words: [DraftWord]
        var isSecondaryVocal: Bool
        var backgroundText: String?
        var backgroundWords: [DraftWord]
    }

    private enum SpanRole {
        case word
        case background
        case translation
        case roman
    }

    private struct ActiveSpan {
        var role: SpanRole
        var startSeconds: Double?
        var endSeconds: Double?
        var text: String = ""
        var hadChildWords: Bool = false
    }

    private(set) var lines: [DraftLine] = []
    private(set) var language: String?

    private var primaryAgent: String?
    private var currentLineStart: Double?
    private var currentLineEnd: Double?
    private var currentLineText = ""
    private var currentTranslation: String?
    private var currentPronunciation: String?
    private var currentBackgroundText = ""
    private var currentWords: [DraftWord] = []
    private var currentBackgroundWords: [DraftWord] = []
    private var currentIsSecondaryVocal = false
    private var spanStack: [ActiveSpan] = []
    private var insideParagraph = false
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
            currentTranslation = nil
            currentPronunciation = nil
            currentBackgroundText = ""
            currentWords = []
            currentBackgroundWords = []
            spanStack = []
            currentLineStart = TTMLLyricsParser.parseClock(attributeDict["begin"])
            currentLineEnd = TTMLLyricsParser.parseClock(attributeDict["end"])
            let agent = (attributeDict["ttm:agent"] ?? attributeDict["agent"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let agent, agent.isEmpty == false {
                if primaryAgent == nil {
                    primaryAgent = agent
                }
                let lower = agent.lowercased()
                currentIsSecondaryVocal = lower == "v2" || lower == "duet" || agent != primaryAgent
            } else {
                currentIsSecondaryVocal = false
            }
        case "span":
            guard insideParagraph else { return }
            let roleAttr = (attributeDict["ttm:role"] ?? attributeDict["role"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let role: SpanRole = {
                switch roleAttr {
                case "x-bg", "bg": return .background
                case "x-translation", "translation": return .translation
                case "x-roman", "roman", "pronunciation": return .roman
                default: return .word
                }
            }()
            spanStack.append(
                ActiveSpan(
                    role: role,
                    startSeconds: TTMLLyricsParser.parseClock(attributeDict["begin"]),
                    endSeconds: TTMLLyricsParser.parseClock(attributeDict["end"])
                )
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if spanStack.isEmpty == false {
            spanStack[spanStack.count - 1].text += string
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
            guard let span = spanStack.popLast() else { return }
            let insideBg = spanStack.contains(where: { $0.role == .background })
            let text = collapseWhitespace(span.text)
            switch span.role {
            case .translation:
                if insideBg == false, text.isEmpty == false {
                    currentTranslation = text
                }
            case .roman:
                if insideBg == false, text.isEmpty == false {
                    currentPronunciation = text
                }
            case .background:
                if span.hadChildWords == false, text.isEmpty == false {
                    if let start = span.startSeconds, let end = span.endSeconds, end >= start {
                        currentBackgroundWords.append(
                            DraftWord(
                                text: text,
                                startSeconds: start,
                                durationSeconds: max(0, end - start)
                            )
                        )
                    }
                    if currentBackgroundText.isEmpty == false, currentBackgroundText.hasSuffix(" ") == false {
                        currentBackgroundText += " "
                    }
                    currentBackgroundText += text
                }
            case .word:
                guard text.isEmpty == false else { break }
                if insideBg {
                    if let bgIndex = spanStack.lastIndex(where: { $0.role == .background }) {
                        spanStack[bgIndex].hadChildWords = true
                    }
                    if let start = span.startSeconds, let end = span.endSeconds, end >= start {
                        currentBackgroundWords.append(
                            DraftWord(
                                text: text,
                                startSeconds: start,
                                durationSeconds: max(0, end - start)
                            )
                        )
                    }
                    if currentBackgroundText.isEmpty == false, currentBackgroundText.hasSuffix(" ") == false {
                        currentBackgroundText += " "
                    }
                    currentBackgroundText += text
                } else if let start = span.startSeconds,
                          let end = span.endSeconds,
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
                } else {
                    if currentLineText.isEmpty == false, currentLineText.hasSuffix(" ") == false {
                        currentLineText += " "
                    }
                    currentLineText += text
                }
            }
        case "p":
            guard insideParagraph else { return }
            insideParagraph = false
            let text = collapseWhitespace(currentLineText)
            let bgText = collapseWhitespace(currentBackgroundText)
            if text.isEmpty == false {
                lines.append(
                    DraftLine(
                        text: text,
                        startSeconds: currentLineStart,
                        endSeconds: currentLineEnd,
                        translation: currentTranslation,
                        pronunciation: currentPronunciation,
                        words: currentWords,
                        isSecondaryVocal: currentIsSecondaryVocal,
                        backgroundText: bgText.isEmpty ? nil : bgText,
                        backgroundWords: currentBackgroundWords
                    )
                )
            }
            currentLineText = ""
            currentTranslation = nil
            currentPronunciation = nil
            currentBackgroundText = ""
            currentWords = []
            currentBackgroundWords = []
            currentIsSecondaryVocal = false
            currentLineStart = nil
            currentLineEnd = nil
            spanStack = []
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
