import Foundation

nonisolated enum LyricsNodeHealthState: String, Equatable, Sendable {
    case unknown
    case healthy
    case degraded
    case cooldown
    case unavailable
}

nonisolated struct LyricsNodeHealthSnapshot: Equatable, Sendable {
    var nodeID: String
    var providerID: String
    var state: LyricsNodeHealthState
    var ewmaLatencySeconds: TimeInterval?
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var failureCount: Int
    var successCount: Int
    var cooldownUntil: Date?
}

/// Records real HTTPS request latency/health. Never uses ICMP ping.
actor LyricsNodeHealthStore {
    private var snapshots: [String: LyricsNodeHealthSnapshot] = [:]
    private let ewmaAlpha: Double
    private let cooldownSeconds: TimeInterval
    private let rateLimitCooldownSeconds: TimeInterval

    init(
        ewmaAlpha: Double = 0.35,
        cooldownSeconds: TimeInterval = 45,
        rateLimitCooldownSeconds: TimeInterval = 90
    ) {
        self.ewmaAlpha = min(max(ewmaAlpha, 0.05), 1)
        self.cooldownSeconds = max(5, cooldownSeconds)
        self.rateLimitCooldownSeconds = max(cooldownSeconds, rateLimitCooldownSeconds)
    }

    func snapshot(nodeID: String) -> LyricsNodeHealthSnapshot? {
        refreshState(for: nodeID)
        return snapshots[nodeID]
    }

    func allSnapshots() -> [LyricsNodeHealthSnapshot] {
        for id in snapshots.keys {
            refreshState(for: id)
        }
        return Array(snapshots.values).sorted { $0.nodeID < $1.nodeID }
    }

    func reliabilityScore(nodeID: String) -> Double {
        refreshState(for: nodeID)
        guard let snap = snapshots[nodeID] else { return 0.55 }
        if snap.state == .cooldown || snap.state == .unavailable { return 0.05 }
        let total = snap.successCount + snap.failureCount
        guard total > 0 else { return 0.55 }
        let ratio = Double(snap.successCount) / Double(total)
        if snap.state == .degraded { return ratio * 0.7 }
        return ratio
    }

    func ewmaLatency(nodeID: String) -> TimeInterval? {
        refreshState(for: nodeID)
        return snapshots[nodeID]?.ewmaLatencySeconds
    }

    func isAvailable(_ nodeID: String, now: Date = Date()) -> Bool {
        refreshState(for: nodeID, now: now)
        guard let snap = snapshots[nodeID] else { return true }
        return snap.state != .cooldown && snap.state != .unavailable
    }

    func recordSuccess(
        providerID: String,
        nodeID: String,
        latencySeconds: TimeInterval,
        now: Date = Date()
    ) {
        var snap = snapshots[nodeID] ?? LyricsNodeHealthSnapshot(
            nodeID: nodeID,
            providerID: providerID,
            state: .unknown,
            ewmaLatencySeconds: nil,
            lastSuccessAt: nil,
            lastFailureAt: nil,
            failureCount: 0,
            successCount: 0,
            cooldownUntil: nil
        )
        snap.providerID = providerID
        snap.successCount += 1
        snap.lastSuccessAt = now
        snap.failureCount = max(0, snap.failureCount - 1)
        snap.cooldownUntil = nil
        if let existing = snap.ewmaLatencySeconds {
            snap.ewmaLatencySeconds = existing * (1 - ewmaAlpha) + latencySeconds * ewmaAlpha
        } else {
            snap.ewmaLatencySeconds = latencySeconds
        }
        snap.state = .healthy
        snapshots[nodeID] = snap
    }

    func recordFailure(
        providerID: String,
        nodeID: String,
        rateLimited: Bool,
        now: Date = Date()
    ) {
        var snap = snapshots[nodeID] ?? LyricsNodeHealthSnapshot(
            nodeID: nodeID,
            providerID: providerID,
            state: .unknown,
            ewmaLatencySeconds: nil,
            lastSuccessAt: nil,
            lastFailureAt: nil,
            failureCount: 0,
            successCount: 0,
            cooldownUntil: nil
        )
        snap.providerID = providerID
        snap.failureCount += 1
        snap.lastFailureAt = now
        let cooldown = rateLimited ? rateLimitCooldownSeconds : cooldownSeconds
        if snap.failureCount >= 2 || rateLimited {
            snap.cooldownUntil = now.addingTimeInterval(cooldown)
            snap.state = .cooldown
        } else {
            snap.state = .degraded
        }
        snapshots[nodeID] = snap
    }

    /// Prefer the fastest healthy node for a provider; fall back to first enabled.
    func preferredNode(
        among nodes: [LyricsNodeDescriptor],
        now: Date = Date()
    ) -> LyricsNodeDescriptor? {
        let enabled = nodes.filter(\.enabled)
        guard enabled.isEmpty == false else { return nil }
        let available = enabled.filter { isAvailable($0.id, now: now) }
        let pool = available.isEmpty ? enabled : available
        return pool.min { lhs, rhs in
            let left = ewmaLatency(nodeID: lhs.id) ?? .greatestFiniteMagnitude
            let right = ewmaLatency(nodeID: rhs.id) ?? .greatestFiniteMagnitude
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    private func refreshState(for nodeID: String, now: Date = Date()) {
        guard var snap = snapshots[nodeID] else { return }
        if let until = snap.cooldownUntil, until <= now {
            snap.cooldownUntil = nil
            snap.state = snap.failureCount > 0 ? .degraded : .healthy
            snapshots[nodeID] = snap
        }
    }
}
