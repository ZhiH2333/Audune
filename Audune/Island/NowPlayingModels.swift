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

    /// Display elapsed time, advancing locally while playing.
    func displayElapsed(at date: Date = Date()) -> Double {
        guard durationSeconds > 0 else { return max(0, elapsedSeconds) }
        guard isPlaying, playbackRate > 0, lastUpdated != .distantPast else {
            return min(max(0, elapsedSeconds), durationSeconds)
        }
        let advanced = elapsedSeconds + date.timeIntervalSince(lastUpdated) * playbackRate
        return min(max(0, advanced), durationSeconds)
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
    var elapsedSeconds: Double
    var durationSeconds: Double
    var playbackRate: Double
    var bundleIdentifier: String
    var artwork: NSImage?
    var timestamp: Date
}
