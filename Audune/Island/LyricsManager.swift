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
    private(set) var activeBindingOffsetSeconds: Double?
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
            activeBindingOffsetSeconds = nil
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
        activeBindingOffsetSeconds = nil
        updateState(.checkingLocal)
        resolveLocal(for: trackKey, generation: generation)
    }

    func deactivate() {
        isActive = false
        generation &+= 1
        lookupTask?.cancel()
        lookupTask = nil
        activeTrackKey = nil
        activeBindingOffsetSeconds = nil
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
        selectCandidate(
            document,
            for: activeTrackKey ?? document.trackKey,
            rememberSelection: false,
            lyricsOffsetSeconds: activeBindingOffsetSeconds ?? 0
        )
    }

    func selectCandidate(
        _ document: LyricsDocument,
        for trackKey: LyricsTrackKey? = nil,
        rememberSelection: Bool,
        lyricsOffsetSeconds: Double = 0
    ) {
        guard isActive else { return }
        let targetKey = trackKey ?? activeTrackKey ?? document.trackKey
        generation &+= 1
        lookupTask?.cancel()
        lookupTask = nil
        activeTrackKey = targetKey
        var normalizedDoc = document
        normalizedDoc.trackKey = targetKey
        if rememberSelection {
            var source = normalizedDoc.source ?? LyricsSourceInfo(
                kind: .online,
                providerName: providerDescriptor.displayName,
                providerRecordIdentifier: nil,
                isPersisted: true
            )
            source.isPersisted = true
            normalizedDoc.source = source
            let binding = LyricsSavedBinding(
                trackKey: targetKey,
                document: normalizedDoc,
                lyricsOffsetSeconds: lyricsOffsetSeconds,
                updatedAt: Date()
            )
            try? store.saveBinding(binding)
            activeBindingOffsetSeconds = lyricsOffsetSeconds
        }
        sessionCache[targetKey] = normalizedDoc
        updateState(presentation(for: normalizedDoc))
    }

    func searchCandidates(
        for queryKey: LyricsTrackKey,
        providerFilter: String? = nil
    ) async -> [LyricsScoredCandidate] {
        var results: [LyricsScoredCandidate] = []
        if providerFilter == nil || providerFilter == "local" {
            let localDocs = (try? store.load()) ?? []
            for doc in localDocs {
                if let scored = LyricsCandidateRanker.scoreLenient(
                    document: doc,
                    expected: queryKey,
                    providerID: "local",
                    nodeID: nil,
                    latencySeconds: 0,
                    reliabilityScore: 1.0
                ) {
                    results.append(scored)
                }
            }
            let boundDocs = (try? store.loadBindings())?.map(\.document) ?? []
            for doc in boundDocs {
                if let scored = LyricsCandidateRanker.scoreLenient(
                    document: doc,
                    expected: queryKey,
                    providerID: doc.source?.resolvedProviderID ?? "saved",
                    nodeID: doc.source?.nodeID,
                    latencySeconds: 0,
                    reliabilityScore: 1.0
                ) {
                    results.append(scored)
                }
            }
        }
        guard providerFilter != "local" else {
            return LyricsCandidateRanker.sorted(results)
        }
        if let router = provider as? LyricsRouter {
            let online = await router.searchScoredCandidates(for: queryKey, providerFilter: providerFilter)
            results.append(contentsOf: online)
        } else {
            let docs = await provider.searchCandidates(for: queryKey)
            for doc in docs {
                if let scored = LyricsCandidateRanker.scoreLenient(
                    document: doc,
                    expected: queryKey,
                    providerID: provider.descriptor.kind.rawValue,
                    nodeID: nil,
                    latencySeconds: 0.2,
                    reliabilityScore: 1.0
                ) {
                    results.append(scored)
                }
            }
        }
        return LyricsCandidateRanker.sorted(results)
    }

    func saveOffsetForActiveTrack(_ offsetSeconds: Double) {
        activeBindingOffsetSeconds = offsetSeconds
        guard let trackKey = activeTrackKey else { return }
        try? store.updateBindingOffset(
            offsetSeconds,
            for: trackKey,
            fallbackDocument: state.document
        )
    }

    func loadSavedBindings() -> [LyricsSavedBinding] {
        (try? store.loadBindings()) ?? []
    }

    func deleteSavedBinding(id: UUID) throws {
        let bindings = (try? store.loadBindings()) ?? []
        let deleted = bindings.first { $0.id == id }
        try store.deleteBinding(id: id)
        if let deleted, let activeTrackKey, deleted.trackKey == activeTrackKey {
            activeBindingOffsetSeconds = nil
            sessionCache.removeValue(forKey: activeTrackKey)
            generation &+= 1
            lookupTask?.cancel()
            lookupTask = nil
            updateState(.checkingLocal)
            resolveLocal(for: activeTrackKey, generation: generation)
        }
    }

    func clearAllSavedBindings() throws {
        try store.clearAllBindings()
        activeBindingOffsetSeconds = nil
        if let activeTrackKey {
            sessionCache.removeValue(forKey: activeTrackKey)
            generation &+= 1
            lookupTask?.cancel()
            lookupTask = nil
            updateState(.checkingLocal)
            resolveLocal(for: activeTrackKey, generation: generation)
        }
    }

    func localDocumentImported(_ document: LyricsDocument) {
        generation &+= 1
        lookupTask?.cancel()
        lookupTask = nil
        isActive = true
        activeTrackKey = document.trackKey
        sessionCache.removeValue(forKey: document.trackKey)
        try? store.saveBinding(
            LyricsSavedBinding(
                trackKey: document.trackKey,
                document: document,
                lyricsOffsetSeconds: activeBindingOffsetSeconds ?? 0,
                updatedAt: Date()
            )
        )
        updateState(.local(document))
    }

    func deleteLocalDocument(_ documentID: UUID) throws {
        try store.delete(documentID: documentID)
        if let trackKey = activeTrackKey {
            try? store.deleteBinding(for: trackKey)
            activeBindingOffsetSeconds = nil
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
        if let binding = try? store.resolveBinding(trackKey: trackKey),
           binding.document.lines.isEmpty == false
        {
            var boundDoc = binding.document
            boundDoc.trackKey = trackKey
            activeBindingOffsetSeconds = binding.lyricsOffsetSeconds
            updateState(presentation(for: boundDoc))
            return
        }

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
        case .unauthorized:
            updateState(.providerUnavailable)
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
