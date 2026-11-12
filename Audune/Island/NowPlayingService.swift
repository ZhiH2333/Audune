import AppKit
import Foundation

/// Owns the Experimental Now Playing listener lifecycle for Notch Island.
/// Never starts or stops Process Tap.
@MainActor
@Observable
final class NowPlayingService {
    private(set) var snapshot = NowPlayingSnapshot.idle
    private(set) var isListening = false

    private var controller: (any NowPlayingControlling)?
    private var seekUnsupportedBundles: Set<String> = []
    /// Consecutive ignored-seek strikes per bundle before the scrubber becomes display-only.
    private var seekIgnoreStrikes: [String: Int] = [:]
    private var pendingSeek: (bundleID: String, expectedElapsed: Double, issuedAt: Date)?
    private let makeController: () -> any NowPlayingControlling
    private var preferenceRequestsListening = false
    private var runtimeDemands: Set<UUID> = []

    /// Ignore MediaRemote elapsed corrections smaller than this (seconds) to stop scrubber twitch.
    static let elapsedSmoothingTolerance: TimeInterval = 1.75
    /// MediaRemote often lags real seeks; wait before treating a mismatch as "unsupported".
    static let seekSettleSeconds: TimeInterval = 1.6
    /// Require repeated ignored seeks so a single slow Spotify/Music update does not brick scrubbing.
    static let seekIgnoreStrikesBeforeUnsupported = 2

    init(controllerFactory: (@MainActor () -> any NowPlayingControlling)? = nil) {
        self.makeController = controllerFactory ?? { MediaRemoteNowPlayingController() }
    }

    /// Start or stop based on Island enablement, notch support, and the preference switch.
    func syncDesiredListening(shouldListen: Bool) {
        preferenceRequestsListening = shouldListen
        reconcileListening()
    }

    @discardableResult
    func acquireRuntimeDemand() -> UUID {
        let token = UUID()
        runtimeDemands.insert(token)
        reconcileListening()
        return token
    }

    func releaseRuntimeDemand(_ token: UUID) {
        runtimeDemands.remove(token)
        reconcileListening()
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
        preferenceRequestsListening = false
        runtimeDemands.removeAll()
        stopListening()
    }

    private func reconcileListening() {
        if preferenceRequestsListening || runtimeDemands.isEmpty == false {
            startIfNeeded()
        } else {
            stopListening()
        }
    }

    private func stopListening() {
        guard isListening else {
            pendingSeek = nil
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
        let now = Date()
        snapshot.lastUpdated = now
        snapshot.playbackClockAnchor = PlaybackClockAnchor(
            elapsedSeconds: clamped,
            monotonicUptime: ProcessInfo.processInfo.systemUptime,
            revision: snapshot.playbackClockAnchor.revision &+ 1
        )
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
        seekIgnoreStrikes.removeAll()
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
            seekIgnoreStrikes.removeAll()
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
        let currentPayload = payload.withFreshPlaybackClockAnchor(at: Date())

        evaluatePendingSeek(against: currentPayload)

        let seekOK = seekUnsupportedBundles.contains(currentPayload.bundleIdentifier) == false
        let hasContent = currentPayload.title.isEmpty == false
            || currentPayload.artist.isEmpty == false
            || currentPayload.artwork != nil
        let mergedClock = mergePlaybackClock(with: currentPayload)

        snapshot = NowPlayingSnapshot(
            availability: hasContent ? .listening : .empty,
            title: currentPayload.title,
            artist: currentPayload.artist,
            album: currentPayload.album,
            isPlaying: currentPayload.isPlaying,
            elapsedSeconds: mergedClock.elapsed,
            durationSeconds: currentPayload.durationSeconds,
            playbackRate: currentPayload.playbackRate,
            bundleIdentifier: currentPayload.bundleIdentifier,
            artwork: currentPayload.artwork ?? snapshot.artwork,
            seekSupported: seekOK,
            lastUpdated: mergedClock.anchor,
            playbackClockAnchor: makePlaybackClockAnchor(
                elapsed: mergedClock.elapsed,
                wallClockAnchor: mergedClock.anchor,
                isPlaying: currentPayload.isPlaying,
                playbackRate: currentPayload.playbackRate,
                durationSeconds: currentPayload.durationSeconds
            )
        )
    }

    private func makePlaybackClockAnchor(
        elapsed: Double,
        wallClockAnchor: Date,
        isPlaying: Bool,
        playbackRate: Double,
        durationSeconds: Double
    ) -> PlaybackClockAnchor {
        let now = Date()
        let age = max(0, now.timeIntervalSince(wallClockAnchor))
        let advanced = isPlaying ? elapsed + age * max(0, playbackRate) : elapsed
        let position = durationSeconds > 0 ? min(max(0, advanced), durationSeconds) : max(0, advanced)
        return PlaybackClockAnchor(
            elapsedSeconds: position.isFinite ? position : max(0, elapsed),
            monotonicUptime: ProcessInfo.processInfo.systemUptime,
            revision: snapshot.playbackClockAnchor.revision &+ 1
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

        // Paused → playing: keep the frozen local elapsed unless MediaRemote disagrees
        // substantially, but always refresh the wall-clock anchor. Reusing the pause-time
        // lastUpdated would advance lyrics by the entire pause duration on resume.
        if snapshot.isPlaying == false && payload.isPlaying == true {
            if abs(delta) > Self.elapsedSmoothingTolerance {
                return (incomingElapsed, incomingAnchor)
            }
            return (snapshot.elapsedSeconds, now)
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
        guard Date().timeIntervalSince(pending.issuedAt) >= Self.seekSettleSeconds else { return }
        defer { pendingSeek = nil }
        guard pending.bundleID.isEmpty == false,
              pending.bundleID == payload.bundleIdentifier
        else { return }
        let remoteNow = payload.displayElapsed(at: Date())
        if abs(remoteNow - pending.expectedElapsed) <= 2.5 {
            seekIgnoreStrikes[pending.bundleID] = 0
            return
        }
        let strikes = (seekIgnoreStrikes[pending.bundleID] ?? 0) + 1
        seekIgnoreStrikes[pending.bundleID] = strikes
        if strikes >= Self.seekIgnoreStrikesBeforeUnsupported {
            seekUnsupportedBundles.insert(pending.bundleID)
        }
    }
}
