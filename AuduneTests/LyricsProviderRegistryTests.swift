import XCTest
@testable import Audune

final class LyricsProviderRegistryTests: XCTestCase {
    func testDefaultAutoPoolContainsOnlyEnabledProviders() {
        let auto = LyricsProviderRegistry.defaultAutoProviders
        XCTAssertFalse(auto.isEmpty)
        XCTAssertTrue(auto.allSatisfy { $0.enablement == .enabled && $0.enabledByDefault })

        let ids = Set(auto.map(\.id))
        XCTAssertTrue(ids.contains(LyricsProviderID.lrclib.rawValue))
        XCTAssertTrue(ids.contains(LyricsProviderID.liriqo.rawValue))
        XCTAssertTrue(ids.contains(LyricsProviderID.lrcmux.rawValue))
        XCTAssertTrue(ids.contains(LyricsProviderID.lrcRed.rawValue))
        XCTAssertTrue(ids.contains(LyricsProviderID.meting.rawValue))

        XCTAssertFalse(ids.contains(LyricsProviderID.betterLyrics.rawValue))
        XCTAssertFalse(ids.contains(LyricsProviderID.lrcAPI.rawValue))
        XCTAssertFalse(ids.contains(LyricsProviderID.lrcShare.rawValue))
        XCTAssertFalse(ids.contains(LyricsProviderID.vvhan.rawValue))
    }

    func testAggregatorUpstreamAreNotRegisteredAsNodes() {
        let liriqo = LyricsProviderRegistry.liriqo
        XCTAssertEqual(liriqo.providerType, .aggregator)
        XCTAssertEqual(liriqo.defaultNodes.count, 1)
        XCTAssertEqual(liriqo.defaultNodes.first?.id, "liriqo-public")

        let nodeProviderIDs = Set(liriqo.defaultNodes.map(\.providerID))
        XCTAssertEqual(nodeProviderIDs, [LyricsProviderID.liriqo.rawValue])
        XCTAssertFalse(LyricsProviderRegistry.all.contains { $0.id == "apple_music_liriqo" })
        XCTAssertFalse(LyricsProviderRegistry.all.contains { $0.id == "deezer" })
    }

    func testBlockedAndPendingProvidersStayDisabled() {
        XCTAssertEqual(LyricsProviderRegistry.lrcShare.enablement, .disabled)
        XCTAssertTrue(LyricsProviderRegistry.lrcShare.requiresAPIKey)
        XCTAssertEqual(LyricsProviderRegistry.lrcAPI.enablement, .disabled)
        XCTAssertEqual(LyricsProviderRegistry.vvhan.enablement, .candidate)
        XCTAssertEqual(LyricsProviderRegistry.kugou.enablement, .candidate)
    }

    func testMetingExposesReplaceableNodesNotSeparateProviders() {
        let meting = LyricsProviderRegistry.meting
        XCTAssertEqual(meting.providerType, .aggregator)
        XCTAssertFalse(meting.defaultNodes.isEmpty)
        XCTAssertTrue(meting.defaultNodes.allSatisfy { $0.providerID == LyricsProviderID.meting.rawValue })
    }

    func testDescriptorBridgePreservesQueryCapabilities() {
        let descriptor = LyricsProviderDescriptor(capability: LyricsProviderRegistry.liriqo)
        XCTAssertEqual(descriptor.kind, .liriqo)
        XCTAssertEqual(descriptor.providerID, LyricsProviderID.liriqo.rawValue)
        XCTAssertTrue(descriptor.queryFields.contains(.title))
        XCTAssertTrue(descriptor.queryFields.contains(.artist))
        XCTAssertTrue(descriptor.queryFields.contains(.isrc))
        XCTAssertTrue(descriptor.queryFields.contains(.duration))
    }

    func testSourceInfoResolvesLegacyLRCLIBKind() {
        let info = LyricsSourceInfo(
            kind: .lrclib,
            providerName: "LRCLIB",
            providerRecordIdentifier: "1",
            isPersisted: false
        )
        XCTAssertEqual(info.resolvedProviderID, LyricsProviderID.lrclib.rawValue)
    }
}
