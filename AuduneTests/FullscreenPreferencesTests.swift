import XCTest
@testable import Audune

final class FullscreenPreferencesTests: XCTestCase {
    private let suite = "AuduneFullscreenPreferencesTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testMissingKeysUseSafeDefaults() {
        let loaded = FullscreenPreferences.load(from: defaults)
        XCTAssertEqual(loaded, .standard)
        XCTAssertFalse(loaded.isEnabled)
        XCTAssertFalse(loaded.lyricsNetworkEnabled)
    }

    func testSaveAndLoadRoundTrip() {
        let stored = FullscreenPreferences(isEnabled: true, lyricsNetworkEnabled: true)
        stored.save(to: defaults)
        XCTAssertEqual(FullscreenPreferences.load(from: defaults), stored)
    }

    func testResetRestoresDefaults() {
        FullscreenPreferences(isEnabled: true, lyricsNetworkEnabled: true).save(to: defaults)
        FullscreenPreferences.reset(in: defaults)
        XCTAssertEqual(FullscreenPreferences.load(from: defaults), .standard)
    }
}
