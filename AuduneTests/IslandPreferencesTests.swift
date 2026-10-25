import XCTest
@testable import Audune

final class IslandPreferencesTests: XCTestCase {
    private let suite = "AuduneIslandPreferencesTests"
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
        let loaded = IslandPreferences.load(from: defaults)
        XCTAssertEqual(loaded, .standard)
        XCTAssertTrue(loaded.isEnabled)
        XCTAssertEqual(loaded.targetScreenID, "")
        XCTAssertEqual(loaded.targetScreenMode, .automatic)
        XCTAssertEqual(loaded.mode, .spectrum)
        XCTAssertTrue(loaded.hoverToExpand)
        XCTAssertEqual(loaded.collapseDelaySeconds, 0.35, accuracy: 0.000_1)
        XCTAssertEqual(loaded.expandDelaySeconds, 0.35, accuracy: 0.000_1)
        XCTAssertEqual(loaded.compactBarCountPerSide, 5)
        XCTAssertFalse(loaded.showsInFullScreen)
        XCTAssertTrue(loaded.followsReduceMotion)
    }

    func testSaveAndLoadRoundTrip() {
        let custom = IslandPreferences(
            isEnabled: false,
            targetScreenID: "display-2",
            mode: .orbit,
            hoverToExpand: false,
            collapseDelaySeconds: 0.9,
            expandDelaySeconds: 0.2,
            hapticStrength: .strong,
            compactBarCountPerSide: 6,
            showsInFullScreen: true,
            followsReduceMotion: false
        )
        custom.save(to: defaults)

        let loaded = IslandPreferences.load(from: defaults)
        XCTAssertEqual(loaded, custom)
        XCTAssertEqual(loaded.targetScreenMode, .screenID("display-2"))
    }

    func testInvalidValuesClampAndNormalize() {
        defaults.set("invalid-mode", forKey: IslandPreferenceKey.mode)
        defaults.set(99.0, forKey: IslandPreferenceKey.collapseDelaySeconds)
        defaults.set(42, forKey: IslandPreferenceKey.compactBarCountPerSide)
        defaults.set("   display-7   ", forKey: IslandPreferenceKey.targetScreenID)

        let loaded = IslandPreferences.load(from: defaults)
        XCTAssertEqual(loaded.mode, .spectrum)
        XCTAssertEqual(loaded.collapseDelaySeconds, IslandPreferences.collapseDelayRange.upperBound, accuracy: 0.000_1)
        XCTAssertEqual(loaded.compactBarCountPerSide, 5)
        XCTAssertEqual(loaded.targetScreenID, "display-7")

        defaults.set(-5.0, forKey: IslandPreferenceKey.collapseDelaySeconds)
        XCTAssertEqual(
            IslandPreferences.load(from: defaults).collapseDelaySeconds,
            IslandPreferences.collapseDelayRange.lowerBound,
            accuracy: 0.000_1
        )

        defaults.set(Double.nan, forKey: IslandPreferenceKey.collapseDelaySeconds)
        XCTAssertEqual(
            IslandPreferences.load(from: defaults).collapseDelaySeconds,
            IslandPreferences.standard.collapseDelaySeconds,
            accuracy: 0.000_1
        )

        defaults.set(4.0, forKey: IslandPreferenceKey.expandDelaySeconds)
        XCTAssertEqual(
            IslandPreferences.load(from: defaults).expandDelaySeconds,
            IslandPreferences.expandDelayRange.upperBound,
            accuracy: 0.000_1
        )
        defaults.set(0.01, forKey: IslandPreferenceKey.expandDelaySeconds)
        XCTAssertEqual(
            IslandPreferences.load(from: defaults).expandDelaySeconds,
            IslandPreferences.expandDelayRange.lowerBound,
            accuracy: 0.000_1
        )
        defaults.set(Double.nan, forKey: IslandPreferenceKey.expandDelaySeconds)
        XCTAssertEqual(
            IslandPreferences.load(from: defaults).expandDelaySeconds,
            IslandPreferences.standard.expandDelaySeconds,
            accuracy: 0.000_1
        )

        defaults.set("huge", forKey: IslandPreferenceKey.hapticStrength)
        XCTAssertEqual(IslandPreferences.load(from: defaults).hapticStrength, .off)
        defaults.set(IslandHapticStrength.light.rawValue, forKey: IslandPreferenceKey.hapticStrength)
        XCTAssertEqual(IslandPreferences.load(from: defaults).hapticStrength, .light)
    }

    func testResetRestoresDefaultsWithoutTouchingStudioPreferences() {
        var studio = StudioPreferences.standard
        studio.mode = .waveform
        studio.appearance.opacity = 0.65
        studio.save(to: defaults)

        var island = IslandPreferences.standard
        island.mode = .orbit
        island.isEnabled = false
        island.collapseDelaySeconds = 1.2
        island.save(to: defaults)

        IslandPreferences.reset(in: defaults)

        XCTAssertEqual(IslandPreferences.load(from: defaults), .standard)
        let reloadedStudio = StudioPreferences.load(from: defaults)
        XCTAssertEqual(reloadedStudio.mode, .waveform)
        XCTAssertEqual(reloadedStudio.appearance.opacity, 0.65, accuracy: 0.000_1)
    }
}
