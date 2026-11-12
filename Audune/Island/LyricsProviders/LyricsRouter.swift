import Foundation

nonisolated struct LyricsProviderInvocation: Sendable {
    var providerID: String
    var nodeID: String?
    var provider: any OnlineLyricsProviding
}

typealias LyricsProviderFactory = @Sendable (String, String?) -> (any OnlineLyricsProviding)?

/// Multi-source online lyrics facade used by `LyricsManager`.
nonisolated struct LyricsRouter: OnlineLyricsProviding {
    let descriptor = LyricsProviderDescriptor(
        kind: .router,
        displayName: "Audune Lyrics Router",
        websiteURL: URL(string: "https://github.com/Audune")!,
        queryFields: [.title, .artist, .album, .duration, .isrc]
    )

    private let selection: LyricsRoutingSelection
    private let healthStore: LyricsNodeHealthStore
    private let factory: LyricsProviderFactory
    private let maxConcurrent: Int
    private let qualityUpgradeWindowNanoseconds: UInt64

    init(
        selection: LyricsRoutingSelection = .standard,
        healthStore: LyricsNodeHealthStore = LyricsNodeHealthStore(),
        maxConcurrent: Int = 3,
        qualityUpgradeWindowSeconds: TimeInterval = 0.85,
        factory: LyricsProviderFactory? = nil
    ) {
        self.selection = selection
        self.healthStore = healthStore
        self.maxConcurrent = max(1, maxConcurrent)
        self.qualityUpgradeWindowNanoseconds = UInt64(max(0, qualityUpgradeWindowSeconds) * 1_000_000_000)
        self.factory = factory ?? LyricsRouter.defaultFactory
    }

    func lookup(for trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        guard Task.isCancelled == false else { return .cancelled }
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, artist.isEmpty == false else { return .notFound }

        switch selection.mode {
        case .manual:
            return await lookupManual(trackKey)
        case .autoFastestReliable, .autoBestMatch:
            return await lookupAuto(trackKey)
        }
    }

    func searchCandidates(for trackKey: LyricsTrackKey) async -> [LyricsDocument] {
        let scored = await searchScoredCandidates(for: trackKey, providerFilter: nil)
        return scored.map(\.document)
    }

    func searchScoredCandidates(
        for trackKey: LyricsTrackKey,
        providerFilter: String? = nil
    ) async -> [LyricsScoredCandidate] {
        guard Task.isCancelled == false else { return [] }
        let title = trackKey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trackKey.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false || artist.isEmpty == false else { return [] }

        var plan: [PlanItem] = []
        if let providerFilter,
           let capability = LyricsProviderRegistry.capability(id: providerFilter),
           let item = await planItem(for: capability)
        {
            plan = [item]
        } else if selection.mode == .manual,
                  let providerID = selection.providerID,
                  let capability = LyricsProviderRegistry.capability(id: providerID)
        {
            let nodeID = selection.nodeID
                ?? capability.defaultNodes.first(where: \.enabled)?.id
            plan = [PlanItem(providerID: providerID, nodeID: nodeID)]
        } else {
            plan = await autoPlan()
        }
        guard plan.isEmpty == false else { return [] }

        var collected: [LyricsScoredCandidate] = []
        await withTaskGroup(of: (PlanItem, TimeInterval, [LyricsDocument]).self) { group in
            for item in plan {
                group.addTask {
                    guard Task.isCancelled == false,
                          let provider = self.factory(item.providerID, item.nodeID)
                    else {
                        return (item, 0, [])
                    }
                    let started = Date()
                    let docs = await provider.searchCandidates(for: trackKey)
                    let latency = Date().timeIntervalSince(started)
                    return (item, latency, docs)
                }
            }
            for await (item, latency, docs) in group {
                guard Task.isCancelled == false else { break }
                if docs.isEmpty == false {
                    await healthStore.recordSuccess(
                        providerID: item.providerID,
                        nodeID: item.nodeID ?? item.providerID,
                        latencySeconds: latency
                    )
                }
                let reliability = await healthStore.reliabilityScore(
                    nodeID: item.nodeID ?? item.providerID
                )
                for doc in docs {
                    if let scored = LyricsCandidateRanker.scoreLenient(
                        document: doc,
                        expected: trackKey,
                        providerID: item.providerID,
                        nodeID: item.nodeID,
                        latencySeconds: latency,
                        reliabilityScore: reliability
                    ) {
                        collected.append(scored)
                    }
                }
            }
        }

        return LyricsCandidateRanker.sorted(collected)
    }

    // MARK: - Manual

    private func lookupManual(_ trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        guard let providerID = selection.providerID,
              let capability = LyricsProviderRegistry.capability(id: providerID),
              capability.enablement == .enabled || capability.enablement == .experimental
        else {
            return .providerUnavailable
        }

        let preferredNode = await healthStore.preferredNode(
            among: capability.defaultNodes.filter(\.enabled)
        )
        let nodeID = selection.nodeID
            ?? preferredNode?.id
            ?? capability.defaultNodes.first(where: \.enabled)?.id

        guard let provider = factory(providerID, nodeID) else {
            return .providerUnavailable
        }

        let started = Date()
        let result = await provider.lookup(for: trackKey)
        let latency = Date().timeIntervalSince(started)
        await record(result: result, providerID: providerID, nodeID: nodeID, latency: latency)

        switch result {
        case .found(let document):
            guard LyricsCandidateRanker.passesTrackMatch(document, trackKey: trackKey) else {
                return .notFound
            }
            return .found(document)
        default:
            return result
        }
    }

    // MARK: - Auto

    private func lookupAuto(_ trackKey: LyricsTrackKey) async -> OnlineLyricsLookup {
        let plan = await autoPlan()
        guard plan.isEmpty == false else { return .providerUnavailable }

        var collected: [LyricsScoredCandidate] = []
        var firstUsable: LyricsScoredCandidate?
        var sawInstrumental = false
        var lastFailure: OnlineLyricsLookup = .notFound
        var seenUpstreams = Set<String>()

        await withTaskGroup(of: AutoAttempt?.self) { group in
            var nextIndex = 0
            var inFlight = 0

            func enqueueAvailable() async {
                while inFlight < maxConcurrent, nextIndex < plan.count {
                    let item = plan[nextIndex]
                    nextIndex += 1
                    // Skip direct providers that an earlier aggregator already attributed.
                    if item.providerID != LyricsProviderID.liriqo.rawValue,
                       item.providerID != LyricsProviderID.lrcmux.rawValue,
                       seenUpstreams.contains(item.providerID)
                    {
                        continue
                    }
                    inFlight += 1
                    group.addTask {
                        guard Task.isCancelled == false else { return nil }
                        guard let provider = self.factory(item.providerID, item.nodeID) else {
                            return AutoAttempt(
                                providerID: item.providerID,
                                nodeID: item.nodeID,
                                latency: 0,
                                result: .providerUnavailable
                            )
                        }
                        let started = Date()
                        let result = await provider.lookup(for: trackKey)
                        let latency = Date().timeIntervalSince(started)
                        return AutoAttempt(
                            providerID: item.providerID,
                            nodeID: item.nodeID,
                            latency: latency,
                            result: result
                        )
                    }
                }
            }

            await enqueueAvailable()

            for await attempt in group {
                inFlight = max(0, inFlight - 1)
                guard let attempt, Task.isCancelled == false else {
                    await enqueueAvailable()
                    continue
                }

                await record(
                    result: attempt.result,
                    providerID: attempt.providerID,
                    nodeID: attempt.nodeID,
                    latency: attempt.latency
                )

                switch attempt.result {
                case .found(let document):
                    if let upstream = document.source?.upstreamProviderID?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       upstream.isEmpty == false
                    {
                        seenUpstreams.insert(normalizedUpstream(upstream))
                    }
                    let reliability = await healthStore.reliabilityScore(nodeID: attempt.nodeID ?? attempt.providerID)
                    if let scored = LyricsCandidateRanker.score(
                        document: document,
                        expected: trackKey,
                        providerID: attempt.providerID,
                        nodeID: attempt.nodeID,
                        latencySeconds: attempt.latency,
                        reliabilityScore: reliability
                    ) {
                        collected.append(scored)
                        if firstUsable == nil {
                            firstUsable = scored
                            // Keep a short window open for higher-quality late arrivals.
                            if qualityUpgradeWindowNanoseconds > 0 {
                                group.addTask {
                                    try? await Task.sleep(nanoseconds: self.qualityUpgradeWindowNanoseconds)
                                    return nil
                                }
                            }
                        }
                    } else {
                        lastFailure = .notFound
                    }
                case .instrumental:
                    sawInstrumental = true
                case .cancelled:
                    lastFailure = .cancelled
                default:
                    lastFailure = attempt.result
                }

                await enqueueAvailable()

                if selection.mode == .autoFastestReliable,
                   let first = firstUsable,
                   first.syncScore >= LyricsCandidateRanker.scoreSync(.lineSynced)
                {
                    // Fastest-reliable can settle once a healthy line-or-better match exists
                    // and the upgrade window task has been scheduled.
                    break
                }
            }
        }

        guard Task.isCancelled == false else { return .cancelled }

        let ranked: LyricsScoredCandidate?
        switch selection.mode {
        case .autoFastestReliable:
            ranked = LyricsCandidateRanker.best(of: collected) ?? firstUsable
        case .autoBestMatch:
            ranked = LyricsCandidateRanker.best(of: collected)
        case .manual:
            ranked = nil
        }

        if let ranked {
            return .found(ranked.document)
        }
        if sawInstrumental { return .instrumental }
        return lastFailure
    }

    private func autoPlan() async -> [PlanItem] {
        var items: [PlanItem] = []
        let autoProviders = LyricsProviderRegistry.defaultAutoProviders

        // First wave: aggregators + LRCLIB.
        let firstWaveIDs = [
            LyricsProviderID.liriqo.rawValue,
            LyricsProviderID.lrcmux.rawValue,
            LyricsProviderID.lrclib.rawValue,
        ]
        for id in firstWaveIDs {
            guard let capability = autoProviders.first(where: { $0.id == id }) else { continue }
            if let item = await planItem(for: capability) {
                items.append(item)
            }
        }

        // Second wave: remaining default-enabled directs (e.g. lrc.red, Meting).
        for capability in autoProviders where firstWaveIDs.contains(capability.id) == false {
            if let item = await planItem(for: capability) {
                items.append(item)
            }
        }

        if selection.mode == .autoFastestReliable {
            // Prefer historically faster nodes earlier in the queue.
            var decorated: [(PlanItem, TimeInterval)] = []
            for item in items {
                let latency = await healthStore.ewmaLatency(nodeID: item.nodeID ?? item.providerID)
                    ?? .greatestFiniteMagnitude
                decorated.append((item, latency))
            }
            return decorated.sorted { $0.1 < $1.1 }.map(\.0)
        }
        return items
    }

    private func planItem(for capability: LyricsProviderCapability) async -> PlanItem? {
        let nodes = capability.defaultNodes.filter(\.enabled)
        let node = await healthStore.preferredNode(among: nodes) ?? nodes.first
        return PlanItem(providerID: capability.id, nodeID: node?.id)
    }

    private func record(
        result: OnlineLyricsLookup,
        providerID: String,
        nodeID: String?,
        latency: TimeInterval
    ) async {
        let id = nodeID ?? providerID
        switch result {
        case .found:
            await healthStore.recordSuccess(providerID: providerID, nodeID: id, latencySeconds: latency)
        case .rateLimited:
            await healthStore.recordFailure(providerID: providerID, nodeID: id, rateLimited: true)
        case .networkError, .timedOut, .providerUnavailable, .serverError, .unauthorized, .parseError:
            await healthStore.recordFailure(providerID: providerID, nodeID: id, rateLimited: false)
        case .notFound, .instrumental, .offline, .cancelled:
            break
        }
    }

    private func normalizedUpstream(_ value: String) -> String {
        let lowered = value.lowercased()
        if lowered.contains("netease") { return LyricsProviderID.netease.rawValue }
        if lowered.contains("qq") { return LyricsProviderID.qqMusic.rawValue }
        if lowered.contains("kugou") { return LyricsProviderID.kugou.rawValue }
        if lowered.contains("lrclib") { return LyricsProviderID.lrclib.rawValue }
        if lowered.contains("deezer") { return "deezer" }
        if lowered.contains("apple") { return "apple_music" }
        return LyricsTrackMatcher.normalized(value)
    }

    // MARK: - Defaults

    static let defaultFactory: LyricsProviderFactory = { providerID, nodeID in
        let node = LyricsProviderRegistry.capability(id: providerID)?
            .defaultNodes
            .first(where: { $0.id == nodeID })
            ?? LyricsProviderRegistry.capability(id: providerID)?
            .defaultNodes
            .first(where: \.enabled)

        switch providerID {
        case LyricsProviderID.lrclib.rawValue:
            return LRCLIBLyricsProvider()
        case LyricsProviderID.liriqo.rawValue:
            if let node {
                return LiriQoLyricsProvider(baseURL: node.baseURL, nodeID: node.id)
            }
            return LiriQoLyricsProvider()
        case LyricsProviderID.lrcmux.rawValue:
            if let node {
                return LRCMuxLyricsProvider(baseURL: node.baseURL, nodeID: node.id)
            }
            return LRCMuxLyricsProvider()
        case LyricsProviderID.betterLyrics.rawValue:
            let key = LyricsAPIKeyStore().apiKey(for: providerID)
            if let node {
                return BetterLyricsProvider(baseURL: node.baseURL, nodeID: node.id, apiKey: key)
            }
            return BetterLyricsProvider(apiKey: key)
        case LyricsProviderID.lrcRed.rawValue:
            if let node {
                return LrcRedLyricsProvider(baseURL: node.baseURL, nodeID: node.id)
            }
            return LrcRedLyricsProvider()
        case LyricsProviderID.lyricsOvh.rawValue:
            if let node {
                return LyricsOvhProvider(baseURL: node.baseURL, nodeID: node.id)
            }
            return LyricsOvhProvider()
        case LyricsProviderID.meting.rawValue:
            let selected = node ?? LyricsProviderRegistry.meting.defaultNodes.first(where: \.enabled)
            guard let selected else { return nil }
            return MetingLyricsProvider(node: selected, server: .tencent)
        case LyricsProviderID.netease.rawValue:
            let selected = node ?? LyricsProviderRegistry.meting.defaultNodes.first(where: \.enabled)
            guard let selected else { return nil }
            return NetEaseMetingLyricsProvider(node: selected)
        case LyricsProviderID.qqMusic.rawValue:
            let selected = node ?? LyricsProviderRegistry.meting.defaultNodes.first(where: \.enabled)
            guard let selected else { return nil }
            return QQMusicMetingLyricsProvider(node: selected)
        case LyricsProviderID.kugou.rawValue:
            return KuGouLyricsProvider()
        case LyricsProviderID.lrcShare.rawValue:
            return LrcShareLyricsProvider()
        default:
            return nil
        }
    }

    private struct PlanItem: Sendable {
        var providerID: String
        var nodeID: String?
    }

    private struct AutoAttempt: Sendable {
        var providerID: String
        var nodeID: String?
        var latency: TimeInterval
        var result: OnlineLyricsLookup
    }
}
