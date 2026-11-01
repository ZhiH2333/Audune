import AppKit
import Foundation
import MediaRemoteAdapter

/// Wraps `ejbills/mediaremote-adapter` `MediaController` behind `NowPlayingControlling`.
@MainActor
final class MediaRemoteNowPlayingController: NowPlayingControlling {
    var onTrackReceived: ((NowPlayingTrackPayload?) -> Void)?
    var onListenerTerminated: (() -> Void)?

    private let media = MediaController()
    private var didWireCallbacks = false

    init() {
        wireCallbacksIfNeeded()
    }

    func startListening() {
        wireCallbacksIfNeeded()
        media.startListening()
    }

    func stopListening() {
        media.stopListening()
    }

    func togglePlayPause() {
        media.togglePlayPause()
    }

    func nextTrack() {
        media.nextTrack()
    }

    func previousTrack() {
        media.previousTrack()
    }

    func setTime(seconds: Double) {
        media.setTime(seconds: seconds)
    }

    private func wireCallbacksIfNeeded() {
        guard didWireCallbacks == false else { return }
        didWireCallbacks = true
        media.onTrackInfoReceived = { [weak self] info in
            Task { @MainActor in
                self?.onTrackReceived?(Self.map(info))
            }
        }
        media.onListenerTerminated = { [weak self] in
            Task { @MainActor in
                self?.onListenerTerminated?()
            }
        }
    }

    /// Use MediaRemote's raw elapsed + media timestamp as the clock anchor.
    /// Do **not** use `currentElapsedTime` here — that already interpolates to "now",
    /// and pairing it with a fresh `Date()` makes the next stale update jump backward.
    private static func map(_ info: TrackInfo?) -> NowPlayingTrackPayload? {
        guard let info else { return nil }
        let payload = info.payload
        let duration = max(0, (payload.durationMicros ?? 0) / 1_000_000)
        let elapsed = max(0, (payload.elapsedTimeMicros ?? 0) / 1_000_000)
        let anchor: Date
        if let micros = payload.timestampEpochMicros, micros > 0 {
            anchor = Date(timeIntervalSince1970: micros / 1_000_000)
        } else {
            anchor = Date()
        }
        let rate: Double
        if let playbackRate = payload.playbackRate {
            rate = max(0, playbackRate)
        } else {
            rate = (payload.isPlaying == true) ? 1 : 0
        }
        return NowPlayingTrackPayload(
            title: payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            artist: payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            album: payload.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            isPlaying: payload.isPlaying == true,
            elapsedSeconds: elapsed,
            durationSeconds: duration,
            playbackRate: rate,
            bundleIdentifier: payload.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            artwork: payload.artwork,
            timestamp: anchor
        )
    }
}
