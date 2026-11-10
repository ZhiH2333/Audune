import Foundation
import XCTest
@testable import Audune

final class LyricsRoutingControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "Audune.LyricsRoutingControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func testManualSelectionPersistsAndAutoModesDoNotClearSavedManualIDs() {
        let controller = LyricsRoutingController(defaults: defaults)
        controller.selectManual(providerID: LyricsProviderID.meting.rawValue, nodeID: "meting-i-meto")
        XCTAssertEqual(controller.selection.mode, .manual)
        XCTAssertEqual(controller.selection.providerID, LyricsProviderID.meting.rawValue)
        XCTAssertEqual(controller.selection.nodeID, "meting-i-meto")

        let loaded = IslandPreferences.load(from: defaults)
        XCTAssertEqual(loaded.lyricsRoutingMode, .manual)
        XCTAssertEqual(loaded.lyricsManualProviderID, LyricsProviderID.meting.rawValue)
        XCTAssertEqual(loaded.lyricsManualNodeID, "meting-i-meto")

        controller.selectAutoFastestReliable()
        XCTAssertEqual(controller.selection.mode, .autoFastestReliable)
        let afterAuto = IslandPreferences.load(from: defaults)
        XCTAssertEqual(afterAuto.lyricsRoutingMode, .autoFastestReliable)
        XCTAssertEqual(afterAuto.lyricsManualProviderID, LyricsProviderID.meting.rawValue)
        XCTAssertEqual(afterAuto.lyricsManualNodeID, "meting-i-meto")
    }

    func testAutoFastestReliablePrefersLowLatencyHealthyNode() async {
        let health = LyricsNodeHealthStore()
        await health.recordSuccess(providerID: "demo", nodeID: "a", latencySeconds: 1.8)
        await health.recordSuccess(providerID: "demo", nodeID: "b", latencySeconds: 0.35)
        let preferred = await health.preferredNode(
            among: [
                LyricsNodeDescriptor(
                    id: "a",
                    providerID: "demo",
                    displayName: "A",
                    baseURL: URL(string: "https://example.invalid/a")!
                ),
                LyricsNodeDescriptor(
                    id: "b",
                    providerID: "demo",
                    displayName: "B",
                    baseURL: URL(string: "https://example.invalid/b")!
                ),
            ]
        )
        XCTAssertEqual(preferred?.id, "b")

        await health.recordFailure(providerID: "demo", nodeID: "b", rateLimited: true)
        let afterCooldown = await health.preferredNode(
            among: [
                LyricsNodeDescriptor(
                    id: "a",
                    providerID: "demo",
                    displayName: "A",
                    baseURL: URL(string: "https://example.invalid/a")!
                ),
                LyricsNodeDescriptor(
                    id: "b",
                    providerID: "demo",
                    displayName: "B",
                    baseURL: URL(string: "https://example.invalid/b")!
                ),
            ]
        )
        XCTAssertEqual(afterCooldown?.id, "a")
    }
}
