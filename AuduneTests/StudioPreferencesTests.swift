import XCTest
@testable import Audune

final class StudioPreferencesTests: XCTestCase {
    private let suite = "AuduneStudioPreferencesTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testMissingValuesUseDefaults() {
        XCTAssertEqual(StudioPreferences.load(from: defaults), .standard)
        XCTAssertEqual(StudioPreferences.standard.alwaysOnTop, true)
        XCTAssertEqual(StudioPreferences.standard.mode, .spectrum)
        XCTAssertEqual(StudioPreferences.standard.accent, .warm)
        XCTAssertEqual(StudioPreferences.standard.backgroundOpacity, 0.92)
        XCTAssertFalse(StudioPreferences.standard.cleanCanvas)
        XCTAssertEqual(StudioPreferences.standard.barCount, 16)
    }

    func testInvalidValuesNormalize() {
        defaults.set("nope", forKey: StudioPreferenceKey.mode)
        defaults.set("purple", forKey: StudioPreferenceKey.accent)
        defaults.set(4.0, forKey: StudioPreferenceKey.backgroundOpacity)
        defaults.set(false, forKey: StudioPreferenceKey.alwaysOnTop)
        let loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.mode, .spectrum)
        XCTAssertEqual(loaded.accent, .warm)
        XCTAssertEqual(loaded.backgroundOpacity, 1)
        XCTAssertFalse(loaded.alwaysOnTop)
    }

    func testLowAndNonFiniteOpacityClamp() {
        defaults.set(0.01, forKey: StudioPreferenceKey.backgroundOpacity)
        XCTAssertEqual(StudioPreferences.load(from: defaults).backgroundOpacity, 0.35)

        XCTAssertEqual(StudioPreferences.clampedOpacity(.nan), StudioPreferences.standard.backgroundOpacity)
        XCTAssertEqual(StudioPreferences.clampedOpacity(.infinity), StudioPreferences.standard.backgroundOpacity)
    }

    func testSaveRoundTrip() {
        let stored = StudioPreferences(
            mode: .orbit,
            alwaysOnTop: false,
            backgroundOpacity: 0.5,
            accent: .sea,
            cleanCanvas: true,
            barCount: 48
        )
        stored.save(to: defaults)
        XCTAssertEqual(StudioPreferences.load(from: defaults), stored)
    }

    func testResetRestoresVisualDefaultsAndLeavesOtherKeys() {
        defaults.set("orbit", forKey: StudioPreferenceKey.mode)
        defaults.set(0.4, forKey: StudioPreferenceKey.backgroundOpacity)
        defaults.set(false, forKey: StudioPreferenceKey.alwaysOnTop)
        defaults.set("leave-me", forKey: "unrelated")

        StudioPreferences.reset(in: defaults)

        XCTAssertEqual(StudioPreferences.load(from: defaults), .standard)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "leave-me")
        XCTAssertNil(defaults.string(forKey: "studio.frame"))
    }

    func testInvalidBarCountFallsBackToSixteen() {
        defaults.set(7, forKey: StudioPreferenceKey.barCount)
        defaults.set(true, forKey: StudioPreferenceKey.cleanCanvas)
        var loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.barCount, 16)
        XCTAssertTrue(loaded.cleanCanvas)

        defaults.set("many", forKey: StudioPreferenceKey.barCount)
        loaded = StudioPreferences.load(from: defaults)
        XCTAssertEqual(loaded.barCount, 16)
        XCTAssertEqual(StudioPreferences.normalizedBarCount(64), 64)
        XCTAssertEqual(StudioPreferences.normalizedBarCount(0), 16)
    }
}
