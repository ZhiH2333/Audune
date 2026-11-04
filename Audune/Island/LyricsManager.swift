import Foundation

/// Coordinates local-first lyrics resolution and the reviewed online provider.
///
/// The manager owns every lyric request for the Island Fullscreen Lyrics scene. It never
/// polls: callers activate it when the scene opens or when the track changes. A generation
/// check keeps a late response for an old song from replacing the current one.
@MainActor
@Observable
final class LyricsManager {
    private(set) var state: LyricsPresentationState = .idle
    private(set) var activeTrackKey: LyricsTrackKey?
    private(set) var automaticOnlineEnabled: Bool
    let providerDescriptor: LyricsProviderDescriptor

    var onStateChange: (() -> Void)?

    private let store: LocalLyricsStore
    private let provider: any OnlineLyricsProviding
    private var generation: UInt64 = 0
    private var lookupTask: Task<Void, Never>?
    /// Session-only. The reviewed provider's terms do not clearly allow persistent copies.
    private var sessionCache: [LyricsTrackKey: LyricsDocument] = [:]
    private var isActive = false

    init(
        store: LocalLyricsStore,
        provider: any OnlineLyricsProviding,
        automaticOnlineEnabled: Bool = true
    ) {
        self.store = store
        self.provider = provider
        self.providerDescriptor = provider.descriptor
        self.automaticOnlineEnabled = automaticOnlineEnabled
    }

    /// Starts resolution for `trackKey`. Repeated calls for the active song are ignored so
    /// the 30 Hz playback refresh can call this without ever re-triggering a request.
    func activate(trackKey: LyricsTrackKey?, automaticOnlineEnabled: Bool? = nil) {
        if let automaticOnlineEnabled {
            self.automaticOnlineEnabled = automaticOnlineEnabled
        }
        isActive = true

        guard let trackKey else {
            lookupTask?.cancel()
            lookupTask = nil
            generation &+= 1
            activeTrackKey = nil
            updateState(.noTrack)
            return
        }

        // The 30 Hz refresh calls activate continuously; an in-flight or finished lookup for
        // this song must not be restarted.
        if activeTrackKey == trackKey {
            return
        }

        lookupTask?.cancel()
        lookupTask = nil
        generation &+= 1
        activeTrackKey = trackKey
        updateState(.checkingLocal)
        resolveLocal(for: trackKey, generation: generation)
    }

    func deactivate() {
        isActive = false
        generation &+= 1
        lookupTask?.cancel()
        lookupTask = nil
        activeTrackKey = nil
        updateState(.idle)
    }

    /// True retry: bypasses the session cache and starts a new request.
    func retry() {
        guard isActive, let trackKey = activeTrackKey else { return }
        guard automaticOnlineEnabled else {
            updateState(.onlineDisabled)
            return
        }
        lookupTask?.cancel()
        lookupTask = nil
        generation &+= 1
        startOnlineLookup(for: trackKey, generation: generation)
    }

    func updateAutomaticOnlineEnabled(_ enabled: Bool) {
        guard automaticOnlineEnabled != enabled else { return }
        automaticOnlineEnabled = enabled
        guard isActive, let trackKey = activeTrackKey else { return }

        if enabled {
            if case .onlineDisabled = state {
                generation &+= 1
                startOnlineLookup(for: trackKey, generation: generation)
            }
        } else if case .searchingOnline = state {
            generation &+= 1
            lookupTask?.cancel()
            lookupTask = nil
            updateState(.onlineDisabled)
        }
    }

    func selectCandidate(_ document: LyricsDocument) {
        guard isActive else { return }
        generation &+= 1
        lookupTask?.cancel()
        lookupTask = nil
        activeTrackKey = document.trackKey
        updateState(presentation(for: document))
    }

    func localDocumentImported(_ document: LyricsDocument) {
        generation &+= 1
        lookupTask?.cancel()
        lookupTask = nil
        isActive = true
        activeTrackKey = document.trackKey
        sessionCache.removeValue(forKey: document.trackKey)
        updateState(.local(document))
    }

    func deleteLocalDocument(_ documentID: UUID) throws {
        try store.delete(documentID: documentID)
        if let trackKey = activeTrackKey {
            sessionCache.removeValue(forKey: trackKey)
        }
        guard isActive, let trackKey = activeTrackKey else { return }
        generation &+= 1
        lookupTask?.cancel()
        lookupTask = nil
        updateState(.checkingLocal)
        resolveLocal(for: trackKey, generation: generation)
    }

    /// Reads and parses off the main actor, then activates the imported document.
    func importLocal(url: URL, for trackKey: LyricsTrackKey) async throws -> LyricsDocument {
        let store = self.store
        let document = try await Task.detached(priority: .userInitiated) {
            try store.importLRC(at: url, for: trackKey)
        }.value
        localDocumentImported(document)
        return document
    }

    // MARK: - Resolution

    private func resolveLocal(for trackKey: LyricsTrackKey, generation: UInt64) {
        guard isCurrent(generation) else { return }
        do {
            switch try store.resolve(trackKey: trackKey) {
            case .local(let document):
                updateState(.local(document))
                return
            case .ambiguous(let documents):
                updateState(.ambiguous(documents))
                return
            case .noLocalMatch:
                break
            }
        } catch {
            updateState(.error(error.localizedDescription))
            return
        }

        guard automaticOnlineEnabled else {
            updateState(.onlineDisabled)
            return
        }
        if let cached = sessionCache[trackKey] {
            updateState(.found(cached))
            return
        }
        startOnlineLookup(for: trackKey, generation: generation)
    }

    private func startOnlineLookup(for trackKey: LyricsTrackKey, generation: UInt64) {
        guard isCurrent(generation) else { return }
        updateState(.searchingOnline)
        let provider = self.provider
        lookupTask = Task { [weak self] in
            let result = await provider.lookup(for: trackKey)
            guard Task.isCancelled == false else { return }
            self?.apply(result, for: trackKey, generation: generation)
        }
    }

    private func apply(_ result: OnlineLyricsLookup, for trackKey: LyricsTrackKey, generation: UInt64) {
        guard isCurrent(generation), activeTrackKey == trackKey else { return }
        lookupTask = nil

        switch result {
        case .found(let document):
            guard document.trackKey == trackKey, document.lines.isEmpty == false else {
                updateState(.parseError)
                return
            }
            updateState(.loading)
            sessionCache[trackKey] = document
            updateState(presentation(for: document))
        case .instrumental:
            updateState(.instrumental)
        case .notFound:
            updateState(.notFound)
        case .rateLimited(let retryAfterSeconds):
            updateState(.rateLimited(retryAfterSeconds: retryAfterSeconds))
        case .offline:
            updateState(.offline)
        case .timedOut:
            updateState(.networkError)
        case .networkError:
            updateState(.networkError)
        case .providerUnavailable:
            updateState(.providerUnavailable)
        case .serverError:
            updateState(.providerUnavailable)
        case .parseError:
            updateState(.parseError)
        case .cancelled:
            updateState(.cancelled)
        }
    }

    private func presentation(for document: LyricsDocument) -> LyricsPresentationState {
        document.isPersistedLocally ? .local(document) : .found(document)
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        isActive && self.generation == generation
    }

    private func updateState(_ newState: LyricsPresentationState) {
        guard state != newState else { return }
        state = newState
        onStateChange?()
    }
}
