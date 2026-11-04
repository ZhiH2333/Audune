import Foundation

nonisolated enum LyricsImportError: Error, Equatable {
    case noTimedLines
    case invalidEncoding
    case storageUnavailable
    case documentNotFound
}

nonisolated enum LyricsResolution: Equatable {
    case local(LyricsDocument)
    case ambiguous([LyricsDocument])
    case onlineUnavailable
}

nonisolated enum OnlineLyricsLookup: Equatable, Sendable {
    case found(LyricsDocument)
    case notFound
    case unavailable
}

protocol OnlineLyricsProviding: Sendable {
    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup
}

struct UnconfiguredOnlineLyricsProvider: OnlineLyricsProviding {
    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        .unavailable
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

        let sameRecording = documents.filter {
            normalized($0.trackKey.title) == normalized(trackKey.title)
                && normalized($0.trackKey.artist) == normalized(trackKey.artist)
                && normalized(trackKey.title).isEmpty == false
                && normalized(trackKey.artist).isEmpty == false
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
           currentDuration != storedDuration
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

    private static func validDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

nonisolated enum LRCParser {
    static func parse(_ contents: String, trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let lines = contents
            .replacingOccurrences(of: "\u{feff}", with: "")
            .components(separatedBy: .newlines)
        let offsetMilliseconds = lines.compactMap(parseOffset).last ?? 0
        let offsetSeconds = Double(offsetMilliseconds) / 1_000
        var entries: [(time: TimeInterval, text: String, order: Int)] = []

        for (lineIndex, line) in lines.enumerated() {
            var remainder = Substring(line)
            var timestamps: [TimeInterval] = []
            while let timestamp = takeTimestamp(from: &remainder) {
                timestamps.append(timestamp)
            }
            guard timestamps.isEmpty == false else { continue }
            let text = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { continue }
            for timestamp in timestamps {
                entries.append((max(0, timestamp + offsetSeconds), text, lineIndex))
            }
        }

        guard entries.isEmpty == false else { throw LyricsImportError.noTimedLines }
        entries.sort {
            if $0.time == $1.time { return $0.order < $1.order }
            return $0.time < $1.time
        }

        var grouped: [(time: TimeInterval, texts: [String])] = []
        for entry in entries {
            if grouped.last?.time == entry.time {
                grouped[grouped.count - 1].texts.append(entry.text)
            } else {
                grouped.append((entry.time, [entry.text]))
            }
        }

        let parsedLines = grouped.enumerated().map { index, group in
            LyricsLine(
                id: index,
                startSeconds: group.time,
                endSeconds: grouped.indices.contains(index + 1) ? grouped[index + 1].time : nil,
                text: group.texts[0],
                translation: group.texts.count > 1
                    ? group.texts.dropFirst().joined(separator: "\n")
                    : nil,
                words: nil
            )
        }

        return LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: nil,
            lines: parsedLines
        )
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

        remainder = remainder[remainder.index(after: closingBracket)...]
        return Double(minutes * 60 + seconds) + fraction
    }
}

struct LocalLyricsStore {
    let fileURL: URL

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

    func resolve(trackKey: LyricsTrackKey) throws -> LyricsResolution {
        switch LyricsTrackMatcher.match(trackKey, in: try load()) {
        case .exact(let document):
            return .local(document)
        case .ambiguous(let documents):
            return .ambiguous(documents)
        case .none:
            return .onlineUnavailable
        }
    }

    func importLRC(at url: URL, for trackKey: LyricsTrackKey) throws -> LyricsDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let contents = String(data: data, encoding: .utf8) else {
            throw LyricsImportError.invalidEncoding
        }
        let document = try LRCParser.parse(contents, trackKey: trackKey)
        try save(document)
        return document
    }

    private func exactStoredVersion(_ lhs: LyricsTrackKey, _ rhs: LyricsTrackKey) -> Bool {
        if let leftISRC = LyricsTrackMatcher.normalizedISRC(lhs.isrc),
           let rightISRC = LyricsTrackMatcher.normalizedISRC(rhs.isrc)
        {
            return leftISRC == rightISRC
        }

        return LyricsTrackMatcher.normalized(lhs.title) == LyricsTrackMatcher.normalized(rhs.title)
            && LyricsTrackMatcher.normalized(lhs.artist) == LyricsTrackMatcher.normalized(rhs.artist)
            && LyricsTrackMatcher.normalized(lhs.album) == LyricsTrackMatcher.normalized(rhs.album)
            && validDuration(lhs.durationSeconds) == validDuration(rhs.durationSeconds)
    }

    private func validDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
