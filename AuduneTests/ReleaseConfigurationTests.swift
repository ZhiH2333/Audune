import XCTest
@testable import Audune

/// Guards the parts of the release configuration that code can verify.
/// Signing, notarization, and the real Bundle ID are owner decisions and are listed in `README.md`.
final class ReleaseConfigurationTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testAppRunsAsMenuBarUtilityWithoutDockIcon() {
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
    }

    func testVersionAndDisplayNameAreSet() {
        XCTAssertFalse((info["CFBundleShortVersionString"] as? String ?? "").isEmpty)
        XCTAssertFalse((info["CFBundleVersion"] as? String ?? "").isEmpty)
        XCTAssertEqual(info["CFBundleName"] as? String, "Audune")
    }

    func testOnlySystemAudioCapturePermissionIsDescribed() {
        let usageKeys = info.keys.filter { $0.hasSuffix("UsageDescription") }.sorted()
        XCTAssertEqual(usageKeys, ["NSAudioCaptureUsageDescription"])
        XCTAssertNil(info["NSAppleEventsUsageDescription"])
        XCTAssertNil(info["NSMicrophoneUsageDescription"])
    }

    func testBundleDeclaresEnglishAndSimplifiedChinese() {
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "en")
        XCTAssertTrue(Bundle.main.localizations.contains("zh-Hans"))
    }
}
