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

    private static func map(_ info: TrackInfo?) -> NowPlayingTrackPayload? {
        guard let info else { return nil }
        let payload = info.payload
        let duration = (payload.durationMicros ?? 0) / 1_000_000
        let elapsed: Double
        if let live = payload.currentElapsedTime {
            elapsed = live
        } else if let micros = payload.elapsedTimeMicros {
            elapsed = micros / 1_000_000
        } else {
            elapsed = 0
        }
        let rate = payload.playbackRate ?? ((payload.isPlaying == true) ? 1 : 0)
        return NowPlayingTrackPayload(
            title: payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            artist: payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            album: payload.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            isPlaying: payload.isPlaying == true,
            elapsedSeconds: max(0, elapsed),
            durationSeconds: max(0, duration),
            playbackRate: max(0, rate),
            bundleIdentifier: payload.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            artwork: payload.artwork,
            timestamp: Date()
        )
    }
}
