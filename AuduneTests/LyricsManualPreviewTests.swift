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
            applyCandidate: { _, _ in },
            isLyricsPickerPresented: .constant(false)
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

    func testAutoFollowDepthStagePreviewSnapshot() throws {
        unsetenv("AUDUNE_LYRICS_MANUAL_PREVIEW")

        let model = IslandModel()
        model.nowPlaying = NowPlayingSnapshot(
            availability: .listening,
            title: "夜に駆ける",
            artist: "YOASOBI",
            album: "THE BOOK",
            isPlaying: true,
            elapsedSeconds: 18.6,
            durationSeconds: 257,
            playbackRate: 1,
            bundleIdentifier: "com.apple.Music",
            artwork: nil,
            seekSupported: true,
            lastUpdated: Date(),
            playbackClockAnchor: PlaybackClockAnchor(
                elapsedSeconds: 18.6,
                monotonicUptime: ProcessInfo.processInfo.systemUptime,
                revision: 1
            )
        )
        var doc = Self.document()
        doc.declaredSynchronization = .wordSynced
        doc.lines[3].words = [
            LyricsWord(id: 0, text: "This ", startSeconds: 18.0, durationSeconds: 0.35),
            LyricsWord(id: 1, text: "is ", startSeconds: 18.35, durationSeconds: 0.30),
            LyricsWord(id: 2, text: "a ", startSeconds: 18.65, durationSeconds: 0.25),
            LyricsWord(id: 3, text: "deliberately ", startSeconds: 18.90, durationSeconds: 0.85),
            LyricsWord(id: 4, text: "long ", startSeconds: 19.75, durationSeconds: 0.50),
            LyricsWord(id: 5, text: "lyric ", startSeconds: 20.25, durationSeconds: 0.45),
            LyricsWord(id: 6, text: "line ", startSeconds: 20.70, durationSeconds: 0.45),
            LyricsWord(id: 7, text: "that ", startSeconds: 21.15, durationSeconds: 0.35),
            LyricsWord(id: 8, text: "should ", startSeconds: 21.50, durationSeconds: 0.40),
            LyricsWord(id: 9, text: "keep ", startSeconds: 21.90, durationSeconds: 0.35),
            LyricsWord(id: 10, text: "the ", startSeconds: 22.25, durationSeconds: 0.25),
            LyricsWord(id: 11, text: "same ", startSeconds: 22.50, durationSeconds: 0.30),
            LyricsWord(id: 12, text: "wrap", startSeconds: 22.80, durationSeconds: 0.40)
        ]
        model.lyricsState = .found(doc)
        model.lyricsPositionSeconds = 18.6
        model.lyricsDisplayPositionSeconds = 18.6
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
            applyCandidate: { _, _ in },
            isLyricsPickerPresented: .constant(false)
        )
        .frame(width: 1296, height: 841)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.34, green: 0.16, blue: 0.38),
                    Color(red: 0.16, green: 0.20, blue: 0.44),
                    Color(red: 0.08, green: 0.10, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipped()

        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: 0, width: 1296, height: 841),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])!
        let dir = URL(fileURLWithPath: "/tmp/lyrics-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("auto-follow-preview.png"))
        window.orderOut(nil)
    }

    func testPickerOverlayPreviewSnapshot() throws {

        let model = IslandModel()
        model.nowPlaying = NowPlayingSnapshot(
            availability: .listening,
            title: "夜に駆ける",
            artist: "YOASOBI",
            album: "THE BOOK",
            isPlaying: true,
            elapsedSeconds: 18,
            durationSeconds: 257,
            playbackRate: 1,
            bundleIdentifier: "com.apple.Music",
            artwork: nil,
            seekSupported: true,
            lastUpdated: Date(),
            playbackClockAnchor: PlaybackClockAnchor(
                elapsedSeconds: 18,
                monotonicUptime: ProcessInfo.processInfo.systemUptime,
                revision: 1
            )
        )
        let currentDoc = Self.document()
        model.lyricsState = .found(currentDoc)
        model.lyricsPositionSeconds = 18
        model.lyricsDisplayPositionSeconds = 18
        model.activeLyricsLineIndex = 3

        let wordDoc: LyricsDocument = {
            var doc = Self.document()
            doc.id = UUID()
            doc.declaredSynchronization = .syllableSynced
            doc.lines[3].words = [
                LyricsWord(id: 0, text: "夜に", startSeconds: 18.0, durationSeconds: 1.0),
                LyricsWord(id: 1, text: "駆ける", startSeconds: 19.0, durationSeconds: 1.4),
            ]
            doc.source = LyricsSourceInfo(
                kind: .online,
                providerName: "LiriQo",
                providerRecordIdentifier: "am-1",
                isPersisted: false,
                providerID: LyricsProviderID.liriqo.rawValue,
                nodeID: "liriqo-public",
                upstreamProviderID: "Apple Music"
            )
            return doc
        }()

        let lrclibDoc: LyricsDocument = {
            var doc = Self.document()
            doc.id = UUID()
            doc.source = LyricsSourceInfo(
                kind: .lrclib,
                providerName: "LRCLIB",
                providerRecordIdentifier: "9021",
                isPersisted: false,
                providerID: LyricsProviderID.lrclib.rawValue
            )
            return doc
        }()

        let candidates: [LyricsScoredCandidate] = [
            LyricsCandidateRanker.scoreLenient(
                document: wordDoc,
                expected: wordDoc.trackKey,
                providerID: LyricsProviderID.liriqo.rawValue,
                nodeID: "liriqo-public",
                latencySeconds: 0.4,
                reliabilityScore: 1
            )!,
            LyricsCandidateRanker.scoreLenient(
                document: lrclibDoc,
                expected: lrclibDoc.trackKey,
                providerID: LyricsProviderID.lrclib.rawValue,
                nodeID: nil,
                latencySeconds: 0.5,
                reliabilityScore: 1
            )!,
        ]

        let view = ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.22, blue: 0.36), Color(red: 0.20, green: 0.28, blue: 0.46)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color.black.opacity(0.45)
            LyricsCandidatePickerOverlay(
                initialTitle: model.nowPlaying.title,
                initialArtist: model.nowPlaying.artist,
                initialAlbum: model.nowPlaying.album,
                trackDurationSeconds: model.nowPlaying.durationSeconds,
                currentDocument: model.lyricsState.document,
                clockAnchor: model.nowPlaying.playbackClockAnchor,
                isPlaying: model.nowPlaying.isPlaying,
                playbackRate: model.nowPlaying.playbackRate,
                lyricsOffsetSeconds: 0,
                canImport: true,
                routingSelection: .standard,
                onSelectRouting: { _ in },
                searchCandidates: { _, _, _, _ in candidates },
                onSelect: { _, _ in },
                onImportLocal: {},
                onDismiss: {}
            )
            .frame(width: 720, height: 480)
            .padding(.leading, 36)
            .padding(.bottom, 40)
        }
        .frame(width: 1296, height: 841)
        .clipped()

        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 1296, height: 841), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])!
        let dir = URL(fileURLWithPath: "/tmp/lyrics-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("picker-preview.png"))
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
