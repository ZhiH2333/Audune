import Foundation

nonisolated struct LyricLine: Equatable, Sendable, Identifiable {
    var id: Double { timeSeconds }
    var timeSeconds: Double
    var text: String
    var translation: String? = nil

    init(timeSeconds: Double, text: String, translation: String? = nil) {
        self.timeSeconds = timeSeconds
        self.text = text
        self.translation = translation
    }
}

nonisolated enum LyricsLoadStatus: Equatable, Sendable {
    case idle
    case disabled
    case loading
    case ready
    case empty
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

nonisolated struct LyricsFollowState: Equatable, Sendable {
    private(set) var followsPlayback = true

    mutating func beginManualBrowsing() {
        followsPlayback = false
    }

    mutating func resumeFollowing() {
        followsPlayback = true
    }
}

/// Parses synced LRC text into timed lines. Ignores metadata tags and unsynced plain text.
nonisolated enum LRCParser {
    private static let linePattern = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)/

    static func parse(_ raw: String, translationRaw: String? = nil) -> [LyricLine] {
        var lines = parseSingle(raw)
        guard lines.isEmpty == false else { return [] }
        if let translationRaw, translationRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let transLines = parseSingle(translationRaw)
            if transLines.isEmpty == false {
                lines = mergeTranslations(primary: lines, translations: transLines)
            }
        } else {
            lines = detectInlineTranslations(lines)
        }
        return lines
    }

    private static func parseSingle(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        lines.reserveCapacity(64)
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false else { continue }
            guard let match = trimmed.wholeMatch(of: linePattern) else { continue }
            let minutes = Double(match.1) ?? 0
            let seconds = Double(match.2) ?? 0
            let fraction: Double
            if let fracText = match.3 {
                let padded = fracText.count == 1 ? "\(fracText)0" : String(fracText.prefix(3))
                let denom: Double
                switch padded.count {
                case 3: denom = 1_000
                default: denom = 100
                }
                fraction = (Double(padded) ?? 0) / denom
            } else {
                fraction = 0
            }
            let text = String(match.4).trimmingCharacters(in: .whitespaces)
            guard text.isEmpty == false else { continue }
            lines.append(LyricLine(timeSeconds: minutes * 60 + seconds + fraction, text: text))
        }
        return lines.sorted { $0.timeSeconds < $1.timeSeconds }
    }

    static func mergeTranslations(primary: [LyricLine], translations: [LyricLine]) -> [LyricLine] {
        return primary.map { line in
            if let match = translations.min(by: { abs($0.timeSeconds - line.timeSeconds) < abs($1.timeSeconds - line.timeSeconds) }),
               abs(match.timeSeconds - line.timeSeconds) <= 0.85 {
                let transText = match.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if transText.isEmpty == false {
                    return LyricLine(timeSeconds: line.timeSeconds, text: line.text, translation: transText)
                }
            }
            return line
        }
    }

    static func detectInlineTranslations(_ lines: [LyricLine]) -> [LyricLine] {
        guard lines.count >= 2 else { return lines }
        var result: [LyricLine] = []
        result.reserveCapacity(lines.count)
        var i = 0
        while i < lines.count {
            let current = lines[i]
            if i + 1 < lines.count {
                let next = lines[i + 1]
                if abs(next.timeSeconds - current.timeSeconds) <= 0.25 {
                    result.append(LyricLine(timeSeconds: current.timeSeconds, text: current.text, translation: next.text))
                    i += 2
                    continue
                }
            }
            result.append(current)
            i += 1
        }
        return result
    }

    static func activeIndex(in lines: [LyricLine], at elapsed: Double) -> Int? {
        guard lines.isEmpty == false else { return nil }
        var result: Int?
        for (index, line) in lines.enumerated() {
            if line.timeSeconds <= elapsed {
                result = index
            } else {
                break
            }
        }
        return result
    }
}
