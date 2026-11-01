import Foundation

nonisolated struct LyricLine: Equatable, Sendable, Identifiable {
    var id: Double { timeSeconds }
    var timeSeconds: Double
    var text: String
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

/// Parses synced LRC text into timed lines. Ignores metadata tags and unsynced plain text.
nonisolated enum LRCParser {
    private static let linePattern = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)/

    static func parse(_ raw: String) -> [LyricLine] {
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
