import AppKit
import Foundation

/// Owns the Experimental Island Now Playing listener lifecycle.
/// Never starts or stops Process Tap.
@MainActor
@Observable
final class NowPlayingService {
    private(set) var snapshot = NowPlayingSnapshot.idle
    private(set) var isListening = false

    private var controller: (any NowPlayingControlling)?
    private var seekUnsupportedBundles: Set<String> = []
    private var pendingSeek: (bundleID: String, expectedElapsed: Double, issuedAt: Date)?
    private let makeController: () -> any NowPlayingControlling

    /// Ignore MediaRemote elapsed corrections smaller than this (seconds) to stop scrubber twitch.
    static let elapsedSmoothingTolerance: TimeInterval = 1.75

    init(controllerFactory: (@MainActor () -> any NowPlayingControlling)? = nil) {
        self.makeController = controllerFactory ?? { MediaRemoteNowPlayingController() }
    }

    /// Start or stop based on Island enablement, notch support, and the preference switch.
    func syncDesiredListening(shouldListen: Bool) {
        if shouldListen {
            startIfNeeded()
        } else {
            stop()
        }
    }

    func startIfNeeded() {
        if isListening { return }
        let controller = ensureController()
        snapshot = NowPlayingSnapshot(
            availability: .listening,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            isPlaying: snapshot.isPlaying,
            elapsedSeconds: snapshot.elapsedSeconds,
            durationSeconds: snapshot.durationSeconds,
            playbackRate: snapshot.playbackRate,
            bundleIdentifier: snapshot.bundleIdentifier,
            artwork: snapshot.artwork,
            seekSupported: snapshot.seekSupported,
            lastUpdated: snapshot.lastUpdated
        )
        isListening = true
        controller.startListening()
    }

    func stop() {
        guard isListening || controller != nil else {
            snapshot = .idle
            return
        }
        controller?.stopListening()
        isListening = false
        pendingSeek = nil
        snapshot = .idle
    }

    func togglePlayPause() {
        controller?.togglePlayPause()
    }

    func nextTrack() {
        controller?.nextTrack()
    }

    func previousTrack() {
        controller?.previousTrack()
    }

    func seek(to seconds: Double) {
        let clamped: Double
        if snapshot.durationSeconds > 0 {
            clamped = min(max(0, seconds), snapshot.durationSeconds)
        } else {
            clamped = max(0, seconds)
        }
        let bundleID = snapshot.bundleIdentifier
        guard snapshot.seekSupported else { return }
        pendingSeek = (bundleID: bundleID, expectedElapsed: clamped, issuedAt: Date())
        snapshot.elapsedSeconds = clamped
        snapshot.lastUpdated = Date()
        snapshot.isPlaying = true
        if snapshot.playbackRate <= 0 {
            snapshot.playbackRate = 1
        }
        controller?.setTime(seconds: clamped)
    }

    private func ensureController() -> any NowPlayingControlling {
        if let controller {
            return controller
        }
        let created = makeController()
        created.onTrackReceived = { [weak self] payload in
            self?.handleTrack(payload)
        }
        created.onListenerTerminated = { [weak self] in
            self?.handleTerminated()
        }
        controller = created
        return created
    }

    private func handleTerminated() {
        isListening = false
        pendingSeek = nil
        snapshot = NowPlayingSnapshot(
            availability: .unavailable,
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
            lastUpdated: Date()
        )
    }

    private func handleTrack(_ payload: NowPlayingTrackPayload?) {
        guard isListening else { return }
        guard let payload else {
            pendingSeek = nil
            snapshot = NowPlayingSnapshot(
                availability: .empty,
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
                lastUpdated: Date()
            )
            return
        }

        evaluatePendingSeek(against: payload)

        let seekOK = seekUnsupportedBundles.contains(payload.bundleIdentifier) == false
        let hasContent = payload.title.isEmpty == false
            || payload.artist.isEmpty == false
            || payload.artwork != nil
        let mergedClock = mergePlaybackClock(with: payload)

        snapshot = NowPlayingSnapshot(
            availability: hasContent ? .listening : .empty,
            title: payload.title,
            artist: payload.artist,
            album: payload.album,
            isPlaying: payload.isPlaying,
            elapsedSeconds: mergedClock.elapsed,
            durationSeconds: payload.durationSeconds,
            playbackRate: payload.playbackRate,
            bundleIdentifier: payload.bundleIdentifier,
            artwork: payload.artwork ?? snapshot.artwork,
            seekSupported: seekOK,
            lastUpdated: mergedClock.anchor
        )
    }

    /// Keep a stable local clock when MediaRemote sends noisy/out-of-order elapsed samples.
    private func mergePlaybackClock(with payload: NowPlayingTrackPayload) -> (elapsed: Double, anchor: Date) {
        let incomingElapsed = payload.elapsedSeconds
        let incomingAnchor = payload.timestamp
        let trackChanged = snapshot.trackIdentity != payload.trackIdentity
        let hasPendingSeek = pendingSeek != nil

        if trackChanged || snapshot.availability != .listening {
            return (incomingElapsed, incomingAnchor)
        }

        // Keep optimistic seek position until MediaRemote settles (or seek-unsupported fires).
        if hasPendingSeek {
            return (snapshot.elapsedSeconds, snapshot.lastUpdated)
        }

        let now = Date()
        let local = snapshot.displayElapsed(at: now)
        let remote = payload.displayElapsed(at: now)
        let delta = remote - local

        // Stay paused: freeze the clock completely so MediaRemote noise cannot twitch the scrubber.
        if snapshot.isPlaying == false && payload.isPlaying == false {
            return (snapshot.elapsedSeconds, snapshot.lastUpdated)
        }

        // Playing → paused: freeze at the locally displayed position (one snap, then hold).
        if snapshot.isPlaying && payload.isPlaying == false {
            return (local, now)
        }

        // Same track, small disagreement → keep local anchor (stops 2:23 → 0:41 style jumps).
        if abs(delta) <= Self.elapsedSmoothingTolerance {
            return (snapshot.elapsedSeconds, snapshot.lastUpdated)
        }

        // Large forward jump (external seek / skip) → trust MediaRemote.
        if delta > Self.elapsedSmoothingTolerance {
            return (incomingElapsed, incomingAnchor)
        }

        // Large backward jump without track change → ignore elapsed, keep local.
        return (snapshot.elapsedSeconds, snapshot.lastUpdated)
    }

    /// If MediaRemote ignores seek, the reported elapsed stays far from the requested value.
    private func evaluatePendingSeek(against payload: NowPlayingTrackPayload) {
        guard let pending = pendingSeek else { return }
        guard Date().timeIntervalSince(pending.issuedAt) >= 0.45 else { return }
        defer { pendingSeek = nil }
        guard pending.bundleID.isEmpty == false,
              pending.bundleID == payload.bundleIdentifier
        else { return }
        let remoteNow = payload.displayElapsed(at: Date())
        if abs(remoteNow - pending.expectedElapsed) > 2.5 {
            seekUnsupportedBundles.insert(pending.bundleID)
        }
    }
}
