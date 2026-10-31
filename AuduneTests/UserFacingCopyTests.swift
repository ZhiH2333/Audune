import XCTest
@testable import Audune

/// Release users should not read developer vocabulary in Settings, menus, or errors.
final class UserFacingCopyTests: XCTestCase {
    private let developerTerms = [
        "PCM", "FFT", "RMS", "OSStatus", "dB floor", "hysteresis", "normalized",
        "not confirmed", "not been verified", "real Mac yet", "tapautostart", "AUD-0", "spike",
    ]

    private func catalogKeys() throws -> [String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Audune/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Array(try XCTUnwrap(json["strings"] as? [String: Any]).keys)
    }

    func testCatalogHasNoDeveloperVocabulary() throws {
        for key in try catalogKeys() {
            for term in developerTerms {
                XCTAssertFalse(key.localizedCaseInsensitiveContains(term), "\"\(key)\" mentions \(term)")
            }
        }
    }

    func testCatalogCoversAboutText() throws {
        let keys = try catalogKeys()
        XCTAssertTrue(keys.contains("About Audune"))
        XCTAssertTrue(keys.contains { $0.hasPrefix("Free and open source.") })
    }

    @MainActor
    func testPopoverModelStartsWithoutDetail() {
        let model = MenuBarModel()
        XCTAssertFalse(model.showDetail)
        XCTAssertTrue(model.statusText.isEmpty)
    }
}
