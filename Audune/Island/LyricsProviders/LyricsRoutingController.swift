import Foundation

/// Shared routing/health surface for Lyrics Manager wiring and the Fullscreen selector UI.
@MainActor
@Observable
final class LyricsRoutingController {
    static let shared = LyricsRoutingController()

    private(set) var selection: LyricsRoutingSelection
    private(set) var healthSnapshots: [LyricsNodeHealthSnapshot] = []

    let healthStore: LyricsNodeHealthStore
    private var defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        healthStore: LyricsNodeHealthStore = LyricsNodeHealthStore()
    ) {
        self.defaults = defaults
        self.healthStore = healthStore
        self.selection = IslandPreferences.load(from: defaults).lyricsRoutingSelection
    }

    func makeProvider() -> LyricsRouter {
        LyricsRouter(selection: selection, healthStore: healthStore)
    }

    func apply(_ selection: LyricsRoutingSelection) {
        var prefs = IslandPreferences.load(from: defaults)
        prefs.lyricsRoutingMode = selection.mode
        switch selection.mode {
        case .manual:
            prefs.lyricsManualProviderID = selection.providerID ?? ""
            prefs.lyricsManualNodeID = selection.nodeID ?? ""
        case .autoFastestReliable, .autoBestMatch:
            // Preserve last manual ids so the selector can restore them later.
            break
        }
        prefs.save(to: defaults)
        self.selection = prefs.lyricsRoutingSelection
    }

    func selectAutoFastestReliable() {
        apply(LyricsRoutingSelection(mode: .autoFastestReliable, providerID: nil, nodeID: nil))
    }

    func selectAutoBestMatch() {
        apply(LyricsRoutingSelection(mode: .autoBestMatch, providerID: nil, nodeID: nil))
    }

    func selectManual(providerID: String, nodeID: String?) {
        apply(
            LyricsRoutingSelection(
                mode: .manual,
                providerID: providerID,
                nodeID: nodeID
            )
        )
    }

    func refreshHealthSnapshots() async {
        healthSnapshots = await healthStore.allSnapshots()
    }

    func latencyText(for nodeID: String?) -> String? {
        guard let nodeID,
              let snap = healthSnapshots.first(where: { $0.nodeID == nodeID }),
              let latency = snap.ewmaLatencySeconds,
              latency.isFinite
        else {
            return nil
        }
        if latency < 1 {
            return String(format: "%.0f ms", latency * 1000)
        }
        return String(format: "%.1f s", latency)
    }
}
