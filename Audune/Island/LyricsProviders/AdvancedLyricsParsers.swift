import Foundation

nonisolated enum AdvancedLyricsParserError: Error, Equatable {
    case empty
    case noTimedLines
    case unsupportedEncryptedKRC
    case invalidFormat
}

/// NetEase YRC: LRC-style `[start,duration](start,duration,0)word...` and JSON lines.
nonisolated enum YRCLyricsParser {
    static func parse(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AdvancedLyricsParserError.empty }

        var draft: [TimedLyricsDocumentBuilder.TimedLine] = []
        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }
            if line.hasPrefix("{"), let jsonLine = parseJSONLine(line) {
                draft.append(jsonLine)
                continue
            }
            if let styled = parseStyledLine(line) {
                draft.append(styled)
            }
        }
        guard let document = TimedLyricsDocumentBuilder.document(
            trackKey: trackKey,
            lines: draft,
            source: LyricsSourceInfo(
                kind: .online,
                providerName: "YRC",
                providerRecordIdentifier: nil,
                isPersisted: false
            )
        ), document.lines.isEmpty == false else {
            throw AdvancedLyricsParserError.noTimedLines
        }
        return document
    }

    private static func parseJSONLine(_ line: String) -> TimedLyricsDocumentBuilder.TimedLine? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let start = doubleValue(object["t"])
        else {
            return nil
        }
        let chunks = object["c"] as? [[String: Any]] ?? []
        var words: [TimedLyricsDocumentBuilder.TimedWord] = []
        var cursor = start
        var text = ""
        for chunk in chunks {
            guard let tx = chunk["tx"] as? String, tx.isEmpty == false else { continue }
            let timing = chunk["tr"] as? [Any]
            let offset = timing.flatMap { doubleValue($0.first) } ?? 0
            let duration = timing.flatMap { doubleValue($0.dropFirst().first) } ?? 500
            let wordStart = start + offset
            let wordEnd = wordStart + duration
            words.append(.init(text: tx, startMilliseconds: wordStart, endMilliseconds: wordEnd))
            cursor = wordEnd
            text += tx
        }
        guard text.isEmpty == false else { return nil }
        return .init(
            text: text,
            startMilliseconds: start,
            endMilliseconds: cursor,
            translation: nil,
            pronunciation: nil,
            words: words.count >= 2 ? words : []
        )
    }

    private static func parseStyledLine(_ line: String) -> TimedLyricsDocumentBuilder.TimedLine? {
        // [start,duration](start,duration,0)word...
        guard line.hasPrefix("["),
              let close = line.firstIndex(of: "]")
        else {
            return nil
        }
        let header = String(line[line.index(after: line.startIndex)..<close])
        let parts = header.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2 else { return nil }
        let lineStart = parts[0]
        let lineDuration = parts[1]
        var remainder = String(line[line.index(after: close)...])
        var words: [TimedLyricsDocumentBuilder.TimedWord] = []
        let pattern = #"^\(([-+]?\d+(?:\.\d+)?),([-+]?\d+(?:\.\d+)?),0\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        while remainder.isEmpty == false {
            let range = NSRange(remainder.startIndex..., in: remainder)
            guard let match = regex.firstMatch(in: remainder, range: range),
                  let full = Range(match.range, in: remainder),
                  let startRange = Range(match.range(at: 1), in: remainder),
                  let durRange = Range(match.range(at: 2), in: remainder),
                  let wordStart = Double(remainder[startRange]),
                  let wordDuration = Double(remainder[durRange])
            else {
                break
            }
            remainder = String(remainder[full.upperBound...])
            var wordText = ""
            while remainder.isEmpty == false, remainder.first != "(" {
                wordText.append(remainder.removeFirst())
            }
            let cleaned = wordText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.isEmpty == false else { continue }
            words.append(
                .init(
                    text: cleaned,
                    startMilliseconds: wordStart,
                    endMilliseconds: wordStart + wordDuration
                )
            )
        }
        let joined = words.map(\.text).joined()
        let needsSpaces = words.contains { word in
            word.text.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.isASCII }
        }
        let text = needsSpaces ? words.map(\.text).joined(separator: " ") : joined
        guard text.isEmpty == false else { return nil }
        return .init(
            text: text,
            startMilliseconds: lineStart,
            endMilliseconds: lineStart + lineDuration,
            translation: nil,
            pronunciation: nil,
            words: words.count >= 2 ? words : []
        )
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}

/// QQ Music QRC (plaintext / Lyric_1 style). Encrypted QRC binaries are unsupported.
nonisolated enum QRCLyricsParser {
    static func parse(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AdvancedLyricsParserError.empty }
        if trimmed.hasPrefix("<?xml") || trimmed.contains("<LyricContent>") {
            if let extracted = extractLyricContent(trimmed) {
                return try parsePlain(extracted, trackKey: trackKey)
            }
        }
        return try parsePlain(trimmed, trackKey: trackKey)
    }

    private static func parsePlain(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        // Reuse YRC styled parser: [start,duration](start,duration)word or (start,duration,0)
        var normalized = contents
        // Convert (start,duration)word → (start,duration,0)word for the shared YRC styled parser.
        if let regex = try? NSRegularExpression(pattern: #"\((\d+),(\d+)\)(?!,)"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: range,
                withTemplate: "($1,$2,0)"
            )
        }
        let document = try YRCLyricsParser.parse(normalized, trackKey: trackKey)
        var result = document
        result.source = LyricsSourceInfo(
            kind: .online,
            providerName: "QRC",
            providerRecordIdentifier: nil,
            isPersisted: false
        )
        return result
    }

    private static func extractLyricContent(_ xml: String) -> String? {
        guard let start = xml.range(of: "<LyricContent>"),
              let end = xml.range(of: "</LyricContent>")
        else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "&#10;", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// KuGou KRC. Public plaintext samples with `[start,duration]<start,duration,0>word` are parsed;
/// encrypted `krc` blobs remain unsupported.
nonisolated enum KRCLyricsParser {
    static func parse(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AdvancedLyricsParserError.empty }
        if trimmed.hasPrefix("krc1") || trimmed.contains("\u{0000}") {
            throw AdvancedLyricsParserError.unsupportedEncryptedKRC
        }

        var draft: [TimedLyricsDocumentBuilder.TimedLine] = []
        let linePattern = #"^\[(\d+),(\d+)\](.*)$"#
        let wordPattern = #"<(\d+),(\d+),0>([^<]*)"#
        guard let lineRegex = try? NSRegularExpression(pattern: linePattern),
              let wordRegex = try? NSRegularExpression(pattern: wordPattern)
        else {
            throw AdvancedLyricsParserError.invalidFormat
        }

        for raw in trimmed.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = lineRegex.firstMatch(in: line, range: range),
                  let startRange = Range(match.range(at: 1), in: line),
                  let durRange = Range(match.range(at: 2), in: line),
                  let bodyRange = Range(match.range(at: 3), in: line),
                  let lineStart = Double(line[startRange]),
                  let lineDuration = Double(line[durRange])
            else {
                continue
            }
            let body = String(line[bodyRange])
            let wordMatches = wordRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
            var words: [TimedLyricsDocumentBuilder.TimedWord] = []
            for wordMatch in wordMatches {
                guard let wStart = Range(wordMatch.range(at: 1), in: body),
                      let wDur = Range(wordMatch.range(at: 2), in: body),
                      let wText = Range(wordMatch.range(at: 3), in: body),
                      let startOffset = Double(body[wStart]),
                      let duration = Double(body[wDur])
                else {
                    continue
                }
                let text = String(body[wText])
                guard text.isEmpty == false else { continue }
                let absolute = lineStart + startOffset
                words.append(.init(text: text, startMilliseconds: absolute, endMilliseconds: absolute + duration))
            }
            let text = words.map(\.text).joined()
            guard text.isEmpty == false else { continue }
            draft.append(
                .init(
                    text: text,
                    startMilliseconds: lineStart,
                    endMilliseconds: lineStart + lineDuration,
                    translation: nil,
                    pronunciation: nil,
                    words: words.count >= 2 ? words : []
                )
            )
        }

        guard let document = TimedLyricsDocumentBuilder.document(
            trackKey: trackKey,
            lines: draft,
            source: LyricsSourceInfo(
                kind: .online,
                providerName: "KRC",
                providerRecordIdentifier: nil,
                isPersisted: false
            )
        ), document.lines.isEmpty == false else {
            throw AdvancedLyricsParserError.noTimedLines
        }
        return document
    }
}

nonisolated enum LyricsFormatDetector {
    static func parse(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AdvancedLyricsParserError.empty }

        if trimmed.hasPrefix("<") || trimmed.contains("<tt") {
            var document = try TTMLLyricsParser.parse(trimmed, trackKey: trackKey)
            if trimmed.lowercased().contains("timing=\"syllable\"")
                || trimmed.lowercased().contains("timing=\"character\"")
            {
                document.declaredSynchronization = .syllableSynced
            }
            return document
        }
        if trimmed.contains("[") && trimmed.contains(",0)") {
            // Prefer YRC/QRC styled word formats before plain LRC.
            if let yrc = try? YRCLyricsParser.parse(trimmed, trackKey: trackKey),
               yrc.lines.contains(where: { $0.words?.isEmpty == false })
            {
                return yrc
            }
            if let qrc = try? QRCLyricsParser.parse(trimmed, trackKey: trackKey),
               qrc.lines.contains(where: { $0.words?.isEmpty == false })
            {
                return qrc
            }
        }
        if trimmed.contains("<") && trimmed.contains(",0>") {
            return try KRCLyricsParser.parse(trimmed, trackKey: trackKey)
        }
        if trimmed.hasPrefix("krc1") {
            throw AdvancedLyricsParserError.unsupportedEncryptedKRC
        }
        if trimmed.contains("lines:") || trimmed.contains("start_ms:") {
            return try LyricsfileParser.parse(trimmed, trackKey: trackKey)
        }
        return try LRCParser.parse(trimmed, trackKey: trackKey)
    }
}
