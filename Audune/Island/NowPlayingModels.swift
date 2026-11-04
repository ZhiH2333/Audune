import AppKit
import Foundation

enum NowPlayingAvailability: String, Equatable, Sendable {
    case idle
    case listening
    case empty
    case unavailable
}

@MainActor
struct NowPlayingSnapshot: Equatable {
    var availability: NowPlayingAvailability
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var elapsedSeconds: Double
    var durationSeconds: Double
    var playbackRate: Double
    var bundleIdentifier: String
    var artwork: NSImage?
    var seekSupported: Bool
    var lastUpdated: Date
    var playbackClockAnchor = PlaybackClockAnchor.zero

    static let idle = NowPlayingSnapshot(
        availability: .idle,
        title: "",
        artist: "",
        album: "",
        isPlaying: false,
        elapsedSeconds: 0,
        durationSeconds: 0,
        playbackRate: 1,
        bundleIdentifier: "",
        artwork: nil,
        seekSupported: true,
        lastUpdated: .distantPast
    )

    var hasTrack: Bool {
        title.isEmpty == false || artist.isEmpty == false || artwork != nil
    }

    var trackIdentity: String {
        // Playback identity intentionally includes the source app; lyric matching does not.
        "\(bundleIdentifier)|\(title)|\(artist)|\(album)"
    }

    /// Display elapsed time, advancing locally while playing from the MediaRemote anchor.
    func displayElapsed(at date: Date = Date()) -> Double {
        let base = max(0, elapsedSeconds)
        guard isPlaying, playbackRate > 0, lastUpdated != .distantPast else {
            if durationSeconds > 0 {
                return min(base, durationSeconds)
            }
            return base
        }
        let advanced = base + date.timeIntervalSince(lastUpdated) * playbackRate
        if durationSeconds > 0 {
            return min(max(0, advanced), durationSeconds)
        }
        return max(0, advanced)
    }
}

/// Testable façade over the MediaRemote adapter controller.
@MainActor
protocol NowPlayingControlling: AnyObject {
    var onTrackReceived: ((NowPlayingTrackPayload?) -> Void)? { get set }
    var onListenerTerminated: (() -> Void)? { get set }
    func startListening()
    func stopListening()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
    func setTime(seconds: Double)
}

@MainActor
struct NowPlayingTrackPayload: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// MediaRemote elapsed at `timestamp` (not already advanced to wall-clock now).
    var elapsedSeconds: Double
    var durationSeconds: Double
    var playbackRate: Double
    var bundleIdentifier: String
    var artwork: NSImage?
    var timestamp: Date

    var trackIdentity: String {
        "\(bundleIdentifier)|\(title)|\(artist)|\(album)"
    }

    func displayElapsed(at date: Date = Date()) -> Double {
        let base = max(0, elapsedSeconds)
        guard isPlaying, playbackRate > 0 else {
            if durationSeconds > 0 { return min(base, durationSeconds) }
            return base
        }
        let advanced = base + date.timeIntervalSince(timestamp) * playbackRate
        if durationSeconds > 0 {
            return min(max(0, advanced), durationSeconds)
        }
        return max(0, advanced)
    }
}
