import Foundation

nonisolated enum LyricsImportError: Error, Equatable {
    case noTimedLines
    case invalidEncoding
    case emptyFile
    case unreadableFile
    case storageUnavailable
    case documentNotFound
}

nonisolated enum LyricsResolution: Equatable {
    case local(LyricsDocument)
    case ambiguous([LyricsDocument])
    case noLocalMatch
}

/// Query fields an online provider may send. Keep this list in sync with what the UI discloses.
nonisolated enum LyricsQueryField: String, CaseIterable, Equatable, Sendable {
    case title
    case artist
    case album
    case duration
    case isrc
}

nonisolated struct LyricsProviderDescriptor: Equatable, Sendable {
    /// Stable provider id. Legacy `.lrclib` remains for existing call sites and tests.
    nonisolated enum Kind: String, Equatable, Sendable {
        case lrclib
        case liriqo
        case lrcmux
        case betterlyrics
        case lrcred
        case lyricsovh
        case meting
        case netease
        case qqmusic
        case kugou
        case lrcshare
        case lrcapi
        case vvhan
        case router
    }

    var kind: Kind
    var displayName: String
    var websiteURL: URL
    var queryFields: [LyricsQueryField]

    var providerID: String {
        switch kind {
        case .router: return "router"
        default: return kind.rawValue
        }
    }

    init(
        kind: Kind,
        displayName: String,
        websiteURL: URL,
        queryFields: [LyricsQueryField]
    ) {
        self.kind = kind
        self.displayName = displayName
        self.websiteURL = websiteURL
        self.queryFields = queryFields
    }

    init(capability: LyricsProviderCapability) {
        let kind = Kind(rawValue: capability.id) ?? .lrclib
        self.kind = kind
        self.displayName = capability.displayName
        self.websiteURL = capability.documentationURL
            ?? capability.attributionURL
            ?? capability.termsURL
            ?? URL(string: "https://example.invalid")!
        var fields: [LyricsQueryField] = []
        if capability.supportsSearchByTitle { fields.append(contentsOf: [.title, .artist]) }
        if capability.supportsAlbum { fields.append(.album) }
        if capability.supportsDuration { fields.append(.duration) }
        if capability.supportsISRC { fields.append(.isrc) }
        self.queryFields = fields
    }
}

/// Every failure is distinct so the UI can explain what actually happened.
nonisolated enum OnlineLyricsLookup: Equatable, Sendable {
    case found(LyricsDocument)
    case instrumental
    case notFound
    case rateLimited(retryAfterSeconds: TimeInterval?)
    case offline
    case timedOut
    case networkError
    case unauthorized
    case providerUnavailable
    case serverError(statusCode: Int)
    case parseError
    case cancelled
}

nonisolated protocol OnlineLyricsProviding: Sendable {
    var descriptor: LyricsProviderDescriptor { get }
    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup
    func searchCandidates(for trackKey: LyricsTrackKey) async -> [LyricsDocument]
}

extension OnlineLyricsProviding {
    func searchCandidates(for trackKey: LyricsTrackKey) async -> [LyricsDocument] {
        if case .found(let document) = await lookup(for: trackKey) {
            return [document]
        }
        return []
    }
}

nonisolated enum LyricsTrackMatch: Equatable {
    case exact(LyricsDocument)
    case ambiguous([LyricsDocument])
    case none
}

nonisolated enum LyricsTrackMatcher {
    static func match(_ trackKey: LyricsTrackKey, in documents: [LyricsDocument]) -> LyricsTrackMatch {
        let exact = documents.filter { isExactMatch(trackKey, $0.trackKey) }
        if exact.count == 1, let document = exact.first {
            return .exact(document)
        }
        if exact.count > 1 {
            return .ambiguous(exact)
        }

        let currentTitle = normalized(trackKey.title)
        let currentArtist = normalized(trackKey.artist)
        let currentBaseTitle = baseTitle(currentTitle)
        let sameRecording = documents.filter {
            let storedTitle = normalized($0.trackKey.title)
            guard normalized($0.trackKey.artist) == currentArtist,
                  currentArtist.isEmpty == false,
                  storedTitle.isEmpty == false
            else {
                return false
            }
            if storedTitle == currentTitle {
                return true
            }
            return currentBaseTitle.isEmpty == false && baseTitle(storedTitle) == currentBaseTitle
        }
        return sameRecording.isEmpty ? .none : .ambiguous(sameRecording)
    }

    static func normalized(_ value: String?) -> String {
        guard let value else { return "" }
        let folded = value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Removes a trailing edition qualifier such as "(Remastered 2011)" for loose comparison only.
    static func baseTitle(_ value: String) -> String {
        let normalizedValue = normalized(value)
        if let open = normalizedValue.lastIndex(where: { $0 == "(" || $0 == "[" }) {
            let suffix = normalizedValue[open...].lowercased()
            if baseTitleQualifiers.contains(where: { suffix.contains($0) }) {
                return String(normalizedValue[..<open]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let separator = normalizedValue.range(of: " - ", options: .backwards) {
            let suffix = normalizedValue[separator.upperBound...].lowercased()
            if baseTitleQualifiers.contains(where: { suffix.contains($0) }) {
                return String(normalizedValue[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return normalizedValue
    }

    private static let baseTitleQualifiers = [
        "remaster", "live", "acoustic", "radio edit", "demo", "instrumental",
        "deluxe", "edit", "version", "mix", "mono", "stereo",
    ]

    /// Players can report slightly different track lengths for the same recording.
    static let durationTolerance: Double = 2

    private static func isExactMatch(_ current: LyricsTrackKey, _ stored: LyricsTrackKey) -> Bool {
        if let currentISRC = normalizedISRC(current.isrc),
           let storedISRC = normalizedISRC(stored.isrc)
        {
            return currentISRC == storedISRC
        }

        guard normalized(current.title).isEmpty == false,
              normalized(current.title) == normalized(stored.title),
              normalized(current.artist).isEmpty == false,
              normalized(current.artist) == normalized(stored.artist)
        else {
            return false
        }

        if let currentAlbum = normalizedOptional(current.album),
           let storedAlbum = normalizedOptional(stored.album),
           currentAlbum != storedAlbum
        {
            return false
        }

        if let currentDuration = validDuration(current.durationSeconds),
           let storedDuration = validDuration(stored.durationSeconds),
           abs(currentDuration - storedDuration) > durationTolerance
        {
            return false
        }

        return true
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let result = normalized(value)
        return result.isEmpty ? nil : result
    }

    static func normalizedISRC(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.uppercased().filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? nil : normalized
    }

    static func validDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

nonisolated enum LRCParser {
    static func parse(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let sourceLines = normalize(contents)
        let offsetMilliseconds = sourceLines.compactMap(parseOffset).last ?? 0
        let offsetSeconds = Double(offsetMilliseconds) / 1_000
        let language = parseMetadata(sourceLines, tag: "la")
        var entries: [(time: TimeInterval, text: String, order: Int, words: [WordTiming]?)] = []

        for (lineIndex, line) in sourceLines.enumerated() {
            var remainder = Substring(line)
            var timestamps: [TimeInterval] = []
            while let timestamp = takeTimestamp(from: &remainder) {
                timestamps.append(timestamp)
            }
            guard timestamps.isEmpty == false else { continue }
            let parsed = parseEnhancedText(remainder)
            guard parsed.text.isEmpty == false else { continue }
            for timestamp in timestamps {
                entries.append((
                    max(0, timestamp + offsetSeconds),
                    parsed.text,
                    lineIndex,
                    parsed.words
                ))
            }
        }

        guard entries.isEmpty == false else { throw LyricsImportError.noTimedLines }
        entries.sort {
            if $0.time == $1.time { return $0.order < $1.order }
            return $0.time < $1.time
        }

        var rawGrouped: [(time: TimeInterval, texts: [String], words: [WordTiming]?)] = []
        for entry in entries {
            if rawGrouped.last?.time == entry.time {
                rawGrouped[rawGrouped.count - 1].texts.append(entry.text)
            } else {
                rawGrouped.append((entry.time, [entry.text], entry.words))
            }
        }

        let grouped = coalesceTypewriterRuns(rawGrouped, offsetSeconds: offsetSeconds)

        let parsedLines = grouped.enumerated().map { index, group -> LyricsLine in
            let lineEnd = grouped.indices.contains(index + 1) ? grouped[index + 1].time : nil
            let translation: String?
            let pronunciation: String?
            if group.texts.count >= 3 {
                translation = group.texts[1]
                pronunciation = group.texts.dropFirst(2).joined(separator: " ")
            } else if group.texts.count == 2 {
                translation = group.texts[1]
                pronunciation = nil
            } else {
                translation = nil
                pronunciation = nil
            }
            return LyricsLine(
                id: index,
                startSeconds: group.time,
                endSeconds: lineEnd,
                text: group.texts[0],
                translation: translation,
                pronunciation: pronunciation,
                words: makeWords(
                    group.words,
                    offsetSeconds: offsetSeconds,
                    lineStart: group.time,
                    lineEnd: lineEnd
                )
            )
        }

        return LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: language,
            lines: parsedLines,
            source: nil
        )
    }

    /// Plain provider lyrics have no timing at all. Store them as unsynchronized lines.
    static func parsePlain(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let sourceLines = normalize(contents)
        let language = parseMetadata(sourceLines, tag: "la")
        let textLines = sourceLines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, isMetadataLine(trimmed) == false else { return nil }
            return trimmed
        }
        guard textLines.isEmpty == false else { throw LyricsImportError.emptyFile }
        let lines = textLines.enumerated().map { index, text in
            LyricsLine(
                id: index,
                startSeconds: nil,
                endSeconds: nil,
                text: text,
                translation: nil,
                words: nil
            )
        }
        return LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: language,
            lines: lines,
            source: nil
        )
    }

    // MARK: - Enhanced (word) timestamps

    private struct WordTiming {
        var startSeconds: TimeInterval
        var text: String
    }

    private struct ParsedText {
        var text: String
        var words: [WordTiming]?
    }

    /// Parses `<mm:ss.xx>` word markers. Their timing is real data; nothing is inferred from text.
    private static func parseEnhancedText(_ remainder: Substring) -> ParsedText {
        guard remainder.contains("<") else {
            return ParsedText(
                text: remainder.trimmingCharacters(in: .whitespacesAndNewlines),
                words: nil
            )
        }

        var preamble = ""
        var tokens: [(time: TimeInterval, text: String)] = []
        var currentTime: TimeInterval?
        var textStart = remainder.startIndex
        var cursor = remainder.startIndex

        while cursor < remainder.endIndex {
            guard remainder[cursor] == "<",
                  let parsed = takeAngleTimestamp(from: remainder, at: cursor)
            else {
                cursor = remainder.index(after: cursor)
                continue
            }
            let segment = String(remainder[textStart..<cursor])
            if let currentTime {
                tokens.append((currentTime, segment))
            } else {
                preamble += segment
            }
            currentTime = parsed.timestamp
            cursor = parsed.nextIndex
            textStart = parsed.nextIndex
        }

        let tail = String(remainder[textStart...])
        if let currentTime {
            tokens.append((currentTime, tail))
        } else {
            preamble += tail
        }

        let displayText = (preamble + tokens.map(\.text).joined())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wordTimings = tokens
            .map { (time: $0.time, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.text.isEmpty == false }
        let ordered = zip(wordTimings, wordTimings.dropFirst()).allSatisfy { current, next in
            next.time > current.time
        }
        guard wordTimings.count >= 2, ordered else {
            return ParsedText(text: displayText, words: nil)
        }
        return ParsedText(
            text: displayText,
            words: wordTimings.map { WordTiming(startSeconds: $0.time, text: $0.text) }
        )
    }

    private static func makeWords(
        _ timings: [WordTiming]?,
        offsetSeconds: TimeInterval,
        lineStart: TimeInterval,
        lineEnd: TimeInterval?
    ) -> [LyricsWord]? {
        guard let timings, timings.count >= 2 else { return nil }
        var words: [LyricsWord] = []
        for (index, timing) in timings.enumerated() {
            let start = max(lineStart, max(0, timing.startSeconds + offsetSeconds))
            let rawEnd: TimeInterval
            if timings.indices.contains(index + 1) {
                rawEnd = max(0, timings[index + 1].startSeconds + offsetSeconds)
            } else if let lineEnd {
                rawEnd = lineEnd
            } else {
                rawEnd = start
            }
            let end = max(start, rawEnd)
            words.append(LyricsWord(
                id: index,
                text: timing.text,
                startSeconds: start,
                durationSeconds: end - start
            ))
        }
        return words
    }

    /// Folds rapid typewriter-style LRC progressions (e.g. `[00:32.44]Fun`, `[00:32.61]Funding`,
    /// `[00:32.78]Funding for`, `[00:32.95]Funding for this`) into a single word-timed line so
    /// high-frequency syllable/character builds animate in-place instead of re-scrolling the list.
    private static func coalesceTypewriterRuns(
        _ groups: [(time: TimeInterval, texts: [String], words: [WordTiming]?)],
        offsetSeconds: TimeInterval
    ) -> [(time: TimeInterval, texts: [String], words: [WordTiming]?)] {
        guard groups.count >= 2 else { return groups }
        var result: [(time: TimeInterval, texts: [String], words: [WordTiming]?)] = []
        var index = 0

        while index < groups.count {
            let startGroup = groups[index]
            guard startGroup.texts.count == 1, startGroup.words == nil else {
                result.append(startGroup)
                index += 1
                continue
            }

            var run = [startGroup]
            var nextIndex = index + 1
            while nextIndex < groups.count {
                let previous = run[run.count - 1]
                let candidate = groups[nextIndex]
                guard candidate.texts.count == 1,
                      candidate.words == nil,
                      isTypewriterStep(from: previous, to: candidate)
                else {
                    break
                }
                run.append(candidate)
                nextIndex += 1
            }

            if run.count >= 2,
               let coalesced = buildTypewriterGroup(from: run, offsetSeconds: offsetSeconds)
            {
                result.append(coalesced)
            } else {
                result.append(contentsOf: run)
            }
            index = nextIndex
        }

        return result
    }

    private static func isTypewriterStep(
        from previous: (time: TimeInterval, texts: [String], words: [WordTiming]?),
        to candidate: (time: TimeInterval, texts: [String], words: [WordTiming]?)
    ) -> Bool {
        let delta = candidate.time - previous.time
        guard delta > 0, delta <= 0.45 else { return false }
        let prevText = previous.texts[0]
        let nextText = candidate.texts[0]
        guard prevText.isEmpty == false, nextText.isEmpty == false else { return false }

        if nextText.hasPrefix(prevText), nextText.count > prevText.count {
            return true
        }
        let prevBase = stripRepeatCounterSuffix(prevText)
        let nextBase = stripRepeatCounterSuffix(nextText)
        guard prevBase.isEmpty == false else { return false }
        if prevBase == nextBase, prevText != nextText {
            return true
        }
        if nextBase.hasPrefix(prevBase), nextBase.count > prevBase.count {
            return true
        }
        return false
    }

    private static func buildTypewriterGroup(
        from run: [(time: TimeInterval, texts: [String], words: [WordTiming]?)],
        offsetSeconds: TimeInterval
    ) -> (time: TimeInterval, texts: [String], words: [WordTiming]?)? {
        guard let first = run.first, let last = run.last else { return nil }
        let finalText = last.texts[0]
        guard finalText.isEmpty == false else { return nil }

        var matchedCount = 0
        var wordTimings: [WordTiming] = []
        var pendingSuffixTime: TimeInterval?

        for step in run {
            let text = step.texts[0]
            let base = stripRepeatCounterSuffix(text)
            let rawTime = step.time - offsetSeconds

            if finalText.hasPrefix(text), text.count > matchedCount {
                let segment = slice(finalText, from: matchedCount, to: text.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if segment.isEmpty == false {
                    wordTimings.append(WordTiming(startSeconds: rawTime, text: segment))
                }
                matchedCount = text.count
                pendingSuffixTime = nil
            } else if base.isEmpty == false, finalText.hasPrefix(base), base.count > matchedCount {
                let segment = slice(finalText, from: matchedCount, to: base.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if segment.isEmpty == false {
                    wordTimings.append(WordTiming(startSeconds: rawTime, text: segment))
                }
                matchedCount = base.count
                if text.count > base.count, pendingSuffixTime == nil {
                    pendingSuffixTime = rawTime
                }
            } else if base.isEmpty == false,
                      finalText.hasPrefix(base),
                      base.count == matchedCount,
                      text.count > base.count,
                      pendingSuffixTime == nil
            {
                pendingSuffixTime = rawTime
            }
        }

        if matchedCount < finalText.count {
            let segment = slice(finalText, from: matchedCount, to: finalText.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if segment.isEmpty == false {
                let rawTime = pendingSuffixTime ?? (last.time - offsetSeconds)
                wordTimings.append(WordTiming(startSeconds: rawTime, text: segment))
            }
        }

        return (
            time: first.time,
            texts: [finalText],
            words: wordTimings.count >= 2 ? wordTimings : nil
        )
    }

    private static func stripRepeatCounterSuffix(_ text: String) -> String {
        guard text.hasSuffix(")"),
              let openParen = text.lastIndex(of: "(")
        else {
            return text
        }
        let inner = text[text.index(after: openParen)..<text.index(before: text.endIndex)]
        guard inner.first == "x" || inner.first == "X" else { return text }
        let digits = inner.dropFirst()
        guard digits.isEmpty == false, digits.allSatisfy(\.isNumber) else { return text }

        var prefixEnd = openParen
        while prefixEnd > text.startIndex {
            let prev = text.index(before: prefixEnd)
            let char = text[prev]
            if char.isWhitespace || char == "↓" || char == "↑" {
                prefixEnd = prev
            } else {
                break
            }
        }
        return String(text[..<prefixEnd])
    }

    private static func slice(_ text: String, from startOffset: Int, to endOffset: Int) -> String {
        let clampedStart = min(max(0, startOffset), text.count)
        let clampedEnd = min(max(clampedStart, endOffset), text.count)
        let start = text.index(text.startIndex, offsetBy: clampedStart)
        let end = text.index(text.startIndex, offsetBy: clampedEnd)
        return String(text[start..<end])
    }

    private static func takeAngleTimestamp(
        from text: Substring,
        at index: String.Index
    ) -> (timestamp: TimeInterval, nextIndex: String.Index)? {
        guard text[index] == "<",
              let closing = text[index...].firstIndex(of: ">")
        else {
            return nil
        }
        let content = text[text.index(after: index)..<closing]
        guard let timestamp = parseTimeValue(content) else { return nil }
        return (timestamp, text.index(after: closing))
    }

    // MARK: - Line timestamps

    private static func normalize(_ contents: String) -> [String] {
        contents
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func isMetadataLine(_ line: String) -> Bool {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return false }
        let tag = line.dropFirst().dropLast()
        guard let colon = tag.firstIndex(of: ":") else { return false }
        let name = tag[..<colon].lowercased()
        return ["ti", "ar", "al", "by", "offset", "re", "ve", "la", "length", "au"].contains(name)
    }

    private static func parseMetadata(_ lines: [String], tag: String) -> String? {
        let prefix = "[\(tag.lowercased()):"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix(prefix), trimmed.hasSuffix("]") else { continue }
            let value = trimmed.dropFirst(prefix.count).dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false { return value }
        }
        return nil
    }

    private static func parseOffset(_ line: String) -> Int? {
        let prefix = "[offset:"
        guard line.lowercased().hasPrefix(prefix), line.hasSuffix("]") else { return nil }
        let value = line.dropFirst(prefix.count).dropLast()
        return Int(value.trimmingCharacters(in: .whitespaces))
    }

    private static func takeTimestamp(from remainder: inout Substring) -> TimeInterval? {
        guard remainder.first == "[",
              let closingBracket = remainder.firstIndex(of: "]")
        else {
            return nil
        }
        let tagStart = remainder.index(after: remainder.startIndex)
        let tag = remainder[tagStart..<closingBracket]
        guard let timestamp = parseTimeValue(tag) else { return nil }
        remainder = remainder[remainder.index(after: closingBracket)...]
        return timestamp
    }

    private static func parseTimeValue(_ tag: Substring) -> TimeInterval? {
        guard let colon = tag.firstIndex(of: ":") else { return nil }
        let minuteText = tag[..<colon]
        let timeText = tag[tag.index(after: colon)...]
        guard let minutes = Int(minuteText),
              minutes >= 0,
              minutes <= (Int.max - 59) / 60
        else {
            return nil
        }

        let timeParts = timeText.split(whereSeparator: { $0 == "." || $0 == ":" })
        guard let secondsText = timeParts.first,
              let seconds = Int(secondsText),
              (0..<60).contains(seconds),
              timeParts.count <= 2
        else {
            return nil
        }

        var fraction: TimeInterval = 0
        if timeParts.count == 2 {
            let fractionText = timeParts[1]
            guard fractionText.allSatisfy(\.isNumber), fractionText.count <= 3,
                  let fractionValue = Int(fractionText)
            else {
                return nil
            }
            let denominator = pow(10, Double(fractionText.count))
            fraction = Double(fractionValue) / denominator
        }

        return Double(minutes * 60 + seconds) + fraction
    }
}

struct LocalLyricsStore: Sendable {
    let fileURL: URL

    var bindingsFileURL: URL {
        fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("lyrics-bindings.json")
    }

    static func applicationStore() throws -> LocalLyricsStore {
        guard let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        else {
            throw LyricsImportError.storageUnavailable
        }
        return LocalLyricsStore(
            fileURL: supportDirectory
                .appendingPathComponent("Audune", isDirectory: true)
                .appendingPathComponent("imported-lyrics.json")
        )
    }

    func load() throws -> [LyricsDocument] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([LyricsDocument].self, from: data)
    }

    func save(_ document: LyricsDocument) throws {
        var documents = try load()
        if let index = documents.firstIndex(where: { exactStoredVersion($0.trackKey, document.trackKey) }) {
            documents[index] = document
        } else {
            documents.append(document)
        }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(documents).write(to: fileURL, options: .atomic)
    }

    func delete(documentID: UUID) throws {
        var documents = try load()
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else {
            throw LyricsImportError.documentNotFound
        }
        documents.remove(at: index)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(documents).write(to: fileURL, options: .atomic)
    }

    // MARK: - Saved Track Bindings & Cache

    func loadBindings() throws -> [LyricsSavedBinding] {
        guard FileManager.default.fileExists(atPath: bindingsFileURL.path) else { return [] }
        let data = try Data(contentsOf: bindingsFileURL)
        let decoded = try JSONDecoder().decode([LyricsSavedBinding].self, from: data)
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveBinding(_ binding: LyricsSavedBinding) throws {
        var bindings = (try? loadBindings()) ?? []
        if let index = bindings.firstIndex(where: { exactStoredVersion($0.trackKey, binding.trackKey) }) {
            var updated = binding
            updated.id = bindings[index].id
            bindings[index] = updated
        } else {
            bindings.insert(binding, at: 0)
        }
        bindings.sort { $0.updatedAt > $1.updatedAt }
        try writeBindings(bindings)
    }

    func resolveBinding(trackKey: LyricsTrackKey) throws -> LyricsSavedBinding? {
        let bindings = try loadBindings()
        if let exact = bindings.first(where: { exactStoredVersion($0.trackKey, trackKey) }) {
            return exact
        }
        let currentTitle = LyricsTrackMatcher.normalized(trackKey.title)
        let currentArtist = LyricsTrackMatcher.normalized(trackKey.artist)
        guard currentTitle.isEmpty == false, currentArtist.isEmpty == false else {
            return nil
        }
        let looseMatches = bindings.filter {
            LyricsTrackMatcher.normalized($0.trackKey.title) == currentTitle
                && LyricsTrackMatcher.normalized($0.trackKey.artist) == currentArtist
        }
        return looseMatches.count == 1 ? looseMatches.first : nil
    }

    func updateBindingOffset(
        _ offsetSeconds: Double,
        for trackKey: LyricsTrackKey,
        fallbackDocument: LyricsDocument?
    ) throws {
        var bindings = (try? loadBindings()) ?? []
        if let index = bindings.firstIndex(where: { exactStoredVersion($0.trackKey, trackKey) }) {
            bindings[index].lyricsOffsetSeconds = offsetSeconds
            bindings[index].updatedAt = Date()
            if let fallbackDocument {
                bindings[index].document = fallbackDocument
            }
            bindings.sort { $0.updatedAt > $1.updatedAt }
            try writeBindings(bindings)
        } else if let fallbackDocument {
            let binding = LyricsSavedBinding(
                trackKey: trackKey,
                document: fallbackDocument,
                lyricsOffsetSeconds: offsetSeconds,
                updatedAt: Date()
            )
            bindings.insert(binding, at: 0)
            try writeBindings(bindings)
        }
    }

    func deleteBinding(id: UUID) throws {
        var bindings = try loadBindings()
        bindings.removeAll { $0.id == id }
        try writeBindings(bindings)
    }

    func deleteBinding(for trackKey: LyricsTrackKey) throws {
        var bindings = try loadBindings()
        bindings.removeAll { exactStoredVersion($0.trackKey, trackKey) }
        try writeBindings(bindings)
    }

    func clearAllBindings() throws {
        if FileManager.default.fileExists(atPath: bindingsFileURL.path) {
            try FileManager.default.removeItem(at: bindingsFileURL)
        }
    }

    private func writeBindings(_ bindings: [LyricsSavedBinding]) throws {
        let directory = bindingsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(bindings).write(to: bindingsFileURL, options: .atomic)
    }

    func resolve(trackKey: LyricsTrackKey) throws -> LyricsResolution {
        switch LyricsTrackMatcher.match(trackKey, in: try load()) {
        case .exact(let document):
            return .local(document)
        case .ambiguous(let documents):
            return .ambiguous(documents)
        case .none:
            return .noLocalMatch
        }
    }

    func importLRC(at url: URL, for trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LyricsImportError.unreadableFile
        }
        guard data.isEmpty == false else { throw LyricsImportError.emptyFile }
        guard let contents = decodeText(data) else {
            throw LyricsImportError.invalidEncoding
        }
        var document = try LRCParser.parse(contents, trackKey: trackKey)
        document.source = .localImport
        try save(document)
        return document
    }

    private func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16BigEndian)
        }
        return String(data: data, encoding: .utf8)
    }

    private func exactStoredVersion(_ lhs: LyricsTrackKey, _ rhs: LyricsTrackKey) -> Bool {
        if let leftISRC = LyricsTrackMatcher.normalizedISRC(lhs.isrc),
           let rightISRC = LyricsTrackMatcher.normalizedISRC(rhs.isrc)
        {
            return leftISRC == rightISRC
        }

        let leftTitle = LyricsTrackMatcher.normalized(lhs.title)
        let rightTitle = LyricsTrackMatcher.normalized(rhs.title)
        let leftArtist = LyricsTrackMatcher.normalized(lhs.artist)
        let rightArtist = LyricsTrackMatcher.normalized(rhs.artist)
        guard leftTitle.isEmpty == false,
              leftTitle == rightTitle,
              leftArtist.isEmpty == false,
              leftArtist == rightArtist
        else {
            return false
        }

        let leftAlbum = LyricsTrackMatcher.normalized(lhs.album)
        let rightAlbum = LyricsTrackMatcher.normalized(rhs.album)
        if leftAlbum.isEmpty == false, rightAlbum.isEmpty == false, leftAlbum != rightAlbum {
            return false
        }

        if let leftDuration = LyricsTrackMatcher.validDuration(lhs.durationSeconds),
           let rightDuration = LyricsTrackMatcher.validDuration(rhs.durationSeconds),
           abs(leftDuration - rightDuration) > LyricsTrackMatcher.durationTolerance
        {
            return false
        }
        return true
    }
}
