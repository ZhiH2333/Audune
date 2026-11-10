import XCTest
@testable import Audune

final class LyricsSourceSelectorTests: XCTestCase {
    func testSelectableProvidersExcludeCandidatesAndDisabled() {
        let selectable = Set(LyricsProviderRegistry.selectableProviders.map(\.id))
        XCTAssertTrue(selectable.contains(LyricsProviderID.liriqo.rawValue))
        XCTAssertTrue(selectable.contains(LyricsProviderID.lrclib.rawValue))
        XCTAssertTrue(selectable.contains(LyricsProviderID.betterLyrics.rawValue))
        XCTAssertFalse(selectable.contains(LyricsProviderID.lrcAPI.rawValue))
        XCTAssertFalse(selectable.contains(LyricsProviderID.vvhan.rawValue))
        XCTAssertFalse(selectable.contains(LyricsProviderID.kugou.rawValue))
    }

    func testRoutingSelectionPersistenceRoundTrip() {
        let suite = "Audune.LyricsSourceSelectorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var prefs = IslandPreferences.standard
        prefs.lyricsRoutingMode = .manual
        prefs.lyricsManualProviderID = LyricsProviderID.lrcmux.rawValue
        prefs.lyricsManualNodeID = "lrcmux-public"
        prefs.save(to: defaults)

        let loaded = IslandPreferences.load(from: defaults)
        XCTAssertEqual(loaded.lyricsRoutingSelection.mode, .manual)
        XCTAssertEqual(loaded.lyricsRoutingSelection.providerID, LyricsProviderID.lrcmux.rawValue)
        XCTAssertEqual(loaded.lyricsRoutingSelection.nodeID, "lrcmux-public")
    }
}
