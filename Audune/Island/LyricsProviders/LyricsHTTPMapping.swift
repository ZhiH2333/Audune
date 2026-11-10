import Foundation

nonisolated enum LyricsHTTPMapping {
    static func mapURLError(_ error: URLError) -> OnlineLyricsLookup {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
            return .providerUnavailable
        default:
            return .networkError
        }
    }

    static func retryAfterSeconds(from response: HTTPURLResponse, data: Data) -> TimeInterval? {
        if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
           header.isEmpty == false
        {
            if let seconds = TimeInterval(header) {
                return max(0, seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header) {
                return max(0, date.timeIntervalSinceNow)
            }
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let number = object["retryAfter"] as? Double { return max(0, number) }
            if let number = object["retry_after"] as? Double { return max(0, number) }
            if let number = object["retryAfter"] as? Int { return max(0, TimeInterval(number)) }
            if let number = object["retry_after"] as? Int { return max(0, TimeInterval(number)) }
        }
        return nil
    }

    static func defaultUserAgent() -> String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           version.isEmpty == false
        {
            return "Audune/\(version) (macOS lyrics client)"
        }
        return "Audune/1.0 (macOS lyrics client)"
    }
}

/// Shared builder for timed JSON lyrics used by aggregators (milliseconds → seconds).
nonisolated enum TimedLyricsDocumentBuilder {
    struct TimedWord {
        var text: String
        var startMilliseconds: Double
        var endMilliseconds: Double
    }

    struct TimedLine {
        var text: String
        var startMilliseconds: Double?
        var endMilliseconds: Double?
        var translation: String?
        var pronunciation: String?
        var words: [TimedWord]
    }

    static func document(
        trackKey: LyricsTrackKey,
        lines: [TimedLine],
        language: String? = nil,
        source: LyricsSourceInfo,
        preferSyllable: Bool = false
    ) -> LyricsDocument? {
        let cleaned = lines.compactMap { line -> LyricsLine? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { return nil }
            let start = seconds(fromMilliseconds: line.startMilliseconds)
            let end = seconds(fromMilliseconds: line.endMilliseconds)
            let words: [LyricsWord]? = {
                let mapped = line.words.compactMap { word -> LyricsWord? in
                    let wordText = word.text
                    guard wordText.isEmpty == false else { return nil }
                    let wordStart = word.startMilliseconds / 1000.0
                    let wordEnd = word.endMilliseconds / 1000.0
                    guard wordStart.isFinite, wordEnd.isFinite, wordEnd >= wordStart else { return nil }
                    return LyricsWord(
                        id: 0,
                        text: wordText,
                        startSeconds: wordStart,
                        durationSeconds: max(0, wordEnd - wordStart)
                    )
                }
                guard mapped.count >= 2 || (mapped.count == 1 && mapped[0].durationSeconds > 0) else {
                    return nil
                }
                return mapped.enumerated().map { index, word in
                    LyricsWord(
                        id: index,
                        text: word.text,
                        startSeconds: word.startSeconds,
                        durationSeconds: word.durationSeconds
                    )
                }
            }()
            return LyricsLine(
                id: 0,
                startSeconds: start,
                endSeconds: end,
                text: text,
                translation: emptyToNil(line.translation),
                pronunciation: emptyToNil(line.pronunciation),
                words: words
            )
        }
        guard cleaned.isEmpty == false else { return nil }
        let numbered = cleaned.enumerated().map { index, line in
            LyricsLine(
                id: index,
                startSeconds: line.startSeconds,
                endSeconds: line.endSeconds,
                text: line.text,
                translation: line.translation,
                pronunciation: line.pronunciation,
                words: line.words
            )
        }
        var document = LyricsDocument(
            id: UUID(),
            trackKey: trackKey,
            language: language,
            lines: numbered,
            source: source
        )
        if preferSyllable,
           document.synchronization == .wordSynced,
           numbered.contains(where: { ($0.words?.count ?? 0) > 0 })
        {
            // Preserve richer sync metadata for later UI; computed property stays data-driven.
            _ = document
        }
        return document
    }

    private static func seconds(fromMilliseconds value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value / 1000.0
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
