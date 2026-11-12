import AppKit
import SwiftUI
import XCTest
@testable import Audune

@MainActor
final class LyricsManualPreviewTests: XCTestCase {
    func testManualPreviewSnapshot() throws {
        setenv("AUDUNE_LYRICS_MANUAL_PREVIEW", "1", 1)
        defer { unsetenv("AUDUNE_LYRICS_MANUAL_PREVIEW") }

        let model = IslandModel()
        model.nowPlaying = NowPlayingSnapshot(
            availability: .listening,
            title: "夜に駆ける",
            artist: "YOASOBI",
            album: "THE BOOK",
            isPlaying: true,
            elapsedSeconds: 30,
            durationSeconds: 257,
            playbackRate: 1,
            bundleIdentifier: "com.apple.Music",
            artwork: nil,
            seekSupported: true,
            lastUpdated: Date()
        )
        model.lyricsState = .found(Self.document())
        model.lyricsPositionSeconds = 30
        model.lyricsDisplayPositionSeconds = 30
        model.activeLyricsLineIndex = 3

        let view = IslandFullscreenLyricsView(
            model: model,
            importLyrics: {},
            chooseCandidate: { _ in },
            deleteLyrics: { _ in },
            retryLyrics: {},
            seek: { _ in },
            togglePlay: {},
            previousTrack: {},
            nextTrack: {},
            setLyricsOffset: { _ in },
            searchCandidates: { _, _, _, _ in [] },
            applyCandidate: { _, _ in }
        )
        .frame(width: 1296, height: 841)
        .background(
            LinearGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.36), Color(red: 0.20, green: 0.28, blue: 0.46)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipped()

        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 1296, height: 841), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])!
        let dir = URL(fileURLWithPath: "/tmp/lyrics-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("manual-preview.png"))
        window.orderOut(nil)
    }

    private static func document() -> LyricsDocument {
        let texts = [
            ("この瞬間を閉じ込めて", "把这一刻封存"),
            ("Rush away like an avalanche", "像雪崩来临般勇敢地往前冲"),
            ("世界はまだ知らない", "世界还不知道"),
            ("This is a deliberately long lyric line that should keep the same wrap in every focus state", "这一行应该在任何状态下都保持同样的换行"),
            ("僕らだけの歌を", "只属于我们的歌"),
            ("何度でも歌うよ", "无论多少次都会歌唱"),
            ("夜が明けるまで踊ろう", "一起跳舞到天亮"),
            ("もう一度、君に会えたら", "如果能再见你一面"),
            ("この夜を抱きしめて", "拥抱这个夜晚"),
            ("朝が来るまで", "直到清晨来临"),
        ]
        let lines = texts.enumerated().map { index, pair in
            LyricsLine(
                id: index,
                startSeconds: Double(index) * 6,
                endSeconds: Double(index) * 6 + 5.2,
                text: pair.0,
                translation: pair.1,
                pronunciation: nil,
                words: nil
            )
        }
        return LyricsDocument(
            id: UUID(),
            trackKey: LyricsTrackKey(isrc: nil, title: "夜に駆ける", artist: "YOASOBI", album: "THE BOOK", durationSeconds: 257),
            language: "ja",
            lines: lines,
            source: .localImport
        )
    }
}
