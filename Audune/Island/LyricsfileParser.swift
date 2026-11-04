import Foundation

/// A deliberately small reader for the LRCLIB `lyricsfile` field (Lyricsfile 1.0 draft).
/// It understands the subset Audune needs: timed lines, optional end times, and optional word times.
/// Malformed content throws; callers then fall back to `syncedLyrics` or `plainLyrics`.
nonisolated enum LyricsfileParser {
    private struct RawWord {
        var text: String
        var startMilliseconds: Double?
        var endMilliseconds: Double?
    }

    private struct RawLine {
        var text: String = ""
        var startMilliseconds: Double?
        var endMilliseconds: Double?
        var words: [RawWord] = []
    }

    static func parse(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let sourceLines = contents
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var rawLines: [RawLine] = []
        var currentLine: RawLine?
        var currentWord: RawWord?
        var currentLineHasWords = false
        var currentLineIndentation = 0
        var inLinesSection = false
        var sawLinesKey = false

        func finishWord() {
            if let currentWord, currentWord.text.isEmpty == false {
                currentLine?.words.append(currentWord)
            }
            currentWord = nil
        }

        func finishLine() {
            finishWord()
            if let currentLine, currentLine.text.isEmpty == false {
                rawLines.append(currentLine)
            }
            currentLine = nil
            currentLineHasWords = false
            currentLineIndentation = 0
        }

        for rawLine in sourceLines {
            let indentation = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, trimmed.hasPrefix("#") == false else { continue }

            if trimmed.hasPrefix("lines:") {
                inLinesSection = true
                sawLinesKey = true
                continue
            }
            guard inLinesSection else { continue }

            // A new top-level key ends the lines section.
            if indentation == 0, trimmed.hasPrefix("- ") == false {
                break
            }

            if trimmed.hasPrefix("- ") {
                let body = String(trimmed.dropFirst(2))
                guard let keyValue = keyValue(from: body) else { continue }
                if currentLineHasWords, indentation > currentLineIndentation {
                    if keyValue.key.lowercased() == "text" {
                        finishWord()
                        currentWord = RawWord(
                            text: scalar(keyValue.value),
                            startMilliseconds: nil,
                            endMilliseconds: nil
                        )
                    } else {
                        apply(keyValue, to: &currentLine, word: &currentWord)
                    }
                    continue
                }
                finishLine()
                currentLine = RawLine()
                currentLineIndentation = indentation
                apply(keyValue, to: &currentLine, word: &currentWord)
                continue
            }

            guard let keyValue = keyValue(from: trimmed) else { continue }
            if keyValue.key.lowercased() == "words" {
                finishWord()
                currentLineHasWords = true
                continue
            }
            apply(keyValue, to: &currentLine, word: &currentWord)
        }
        finishLine()

        guard sawLinesKey else { throw LyricsImportError.noTimedLines }
        guard rawLines.isEmpty == false else { throw LyricsImportError.noTimedLines }

        var lines: [LyricsLine] = []
        for (index, rawLine) in rawLines.enumerated() {
            let start = rawLine.startMilliseconds.map { max(0, $0 / 1_000) }
            let nextStart = rawLines.indices.contains(index + 1)
                ? rawLines[index + 1].startMilliseconds.map { max(0, $0 / 1_000) }
                : nil
            let lineEnd = rawLine.endMilliseconds.map { max(0, $0 / 1_000) }
                ?? nextStart
            let lineStart = start ?? 0
            let words = makeWords(
                rawLine.words,
                lineStart: lineStart,
                lineEnd: start == nil ? nil : lineEnd
            )
            lines.append(LyricsLine(
                id: index,
                startSeconds: start,
                endSeconds: lineEnd,
                text: rawLine.text,
                translation: nil,
                words: words
            ))
        }

        guard lines.contains(where: { $0.startSeconds != nil }) else {
            throw LyricsImportError.noTimedLines
        }
        return LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: nil,
            lines: lines,
            source: nil
        )
    }

    static func isInstrumental(_ contents: String) -> Bool {
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("instrumental:") else { continue }
            return scalar(String(trimmed.dropFirst("instrumental:".count))).lowercased() == "true"
        }
        return false
    }

    // MARK: - Conversion

    private static func makeWords(
        _ rawWords: [RawWord],
        lineStart: TimeInterval,
        lineEnd: TimeInterval?
    ) -> [LyricsWord]? {
        let usable = rawWords.compactMap { word -> (text: String, start: TimeInterval, end: TimeInterval?)? in
            guard let startMilliseconds = word.startMilliseconds,
                  startMilliseconds.isFinite
            else {
                return nil
            }
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { return nil }
            return (
                text,
                max(lineStart, max(0, startMilliseconds / 1_000)),
                word.endMilliseconds.map { max(0, $0 / 1_000) }
            )
        }
        guard usable.count >= 2 else { return nil }
        guard zip(usable, usable.dropFirst()).allSatisfy({ pair in pair.0.start <= pair.1.start }) else { return nil }

        return usable.enumerated().map { index, word in
            let rawEnd = word.end ?? (usable.indices.contains(index + 1) ? usable[index + 1].start : lineEnd)
            let end = max(word.start, rawEnd ?? word.start)
            return LyricsWord(
                id: index,
                text: word.text,
                startSeconds: word.start,
                durationSeconds: end - word.start
            )
        }
    }

    // MARK: - YAML subset

    private static func apply(
        _ keyValue: (key: String, value: String),
        to line: inout RawLine?,
        word: inout RawWord?
    ) {
        let key = keyValue.key.lowercased()
        if word != nil {
            switch key {
            case "text":
                word?.text = scalar(keyValue.value)
            case "start_ms", "start":
                word?.startMilliseconds = number(keyValue.value)
            case "end_ms", "end":
                word?.endMilliseconds = number(keyValue.value)
            default:
                break
            }
            return
        }

        guard line != nil else { return }
        switch key {
        case "text":
            line?.text = scalar(keyValue.value)
        case "start_ms", "start":
            line?.startMilliseconds = number(keyValue.value)
        case "end_ms", "end":
            line?.endMilliseconds = number(keyValue.value)
        default:
            break
        }
    }

    private static func keyValue(from text: String) -> (key: String, value: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let key = text[..<colon].trimmingCharacters(in: .whitespaces)
        guard key.isEmpty == false else { return nil }
        let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func scalar(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
            return String(trimmed.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            let inner = trimmed.dropFirst().dropLast()
            return inner
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if trimmed == "~" || trimmed.lowercased() == "null" { return "" }
        if let comment = trimmed.range(of: " #") {
            return String(trimmed[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private static func number(_ raw: String) -> Double? {
        let value = scalar(raw)
        guard value.isEmpty == false else { return nil }
        return Double(value)
    }
}
