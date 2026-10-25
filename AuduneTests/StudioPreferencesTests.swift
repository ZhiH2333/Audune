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
        XCTAssertEqual(StudioPreferences.standard.windowMode, .onTop)
        XCTAssertEqual(StudioPreferences.standard.mode, .spectrum)
        XCTAssertEqual(StudioPreferences.standard.accent, .warm)
        XCTAssertEqual(StudioPreferences.standard.backgroundOpacity, 0.92)
        XCTAssertEqual(StudioPreferences.standard.barCount, 16)
    }

    func testInvalidValuesNormalize() {
        defaults.set("nope", forKey: StudioPreferenceKey.mode)
        defaults.set("purple", forKey: StudioPreferenceKey.accent)
        defaults.set(4.0, forKey: StudioPreferenceKey.backgroundOpacity)
        defaults.set(false, forKey: StudioPreferenceKey.alwaysOnTop)
        defaults.set("nope", forKey: StudioPreferenceKey.windowMode)
        let loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.mode, .spectrum)
        XCTAssertEqual(loaded.accent, .warm)
        XCTAssertEqual(loaded.backgroundOpacity, 1)
        XCTAssertEqual(loaded.windowMode, .asWindow)
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
            windowMode: .onDesktop,
            backgroundOpacity: 0.5,
            accent: .sea,
            barCount: 48
        )
        stored.save(to: defaults)
        XCTAssertEqual(StudioPreferences.load(from: defaults), stored)
        XCTAssertFalse(defaults.bool(forKey: StudioPreferenceKey.alwaysOnTop))
    }

    func testLegacyAlwaysOnTopMigratesUntilWindowModeIsStored() {
        defaults.set(false, forKey: StudioPreferenceKey.alwaysOnTop)
        XCTAssertEqual(StudioPreferences.load(from: defaults).windowMode, .asWindow)

        defaults.set(true, forKey: StudioPreferenceKey.alwaysOnTop)
        XCTAssertEqual(StudioPreferences.load(from: defaults).windowMode, .onTop)

        defaults.set(StudioWindowMode.onDesktop.rawValue, forKey: StudioPreferenceKey.windowMode)
        defaults.set(false, forKey: StudioPreferenceKey.alwaysOnTop)
        XCTAssertEqual(StudioPreferences.load(from: defaults).windowMode, .onDesktop)
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

    func testRetiredCleanCanvasKeyIsClearedOnSave() {
        defaults.set(7, forKey: StudioPreferenceKey.barCount)
        defaults.set(true, forKey: StudioPreferenceKey.cleanCanvas)
        let loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.barCount, 16)
        loaded.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: StudioPreferenceKey.cleanCanvas))

        defaults.set("many", forKey: StudioPreferenceKey.barCount)
        XCTAssertEqual(StudioPreferences.load(from: defaults).barCount, 16)
        XCTAssertEqual(StudioPreferences.normalizedBarCount(64), 64)
        XCTAssertEqual(StudioPreferences.normalizedBarCount(0), 16)
    }
}
