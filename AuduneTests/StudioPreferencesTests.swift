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
        let standard = StudioPreferences.standard
        XCTAssertEqual(StudioPreferences.load(from: defaults), standard)
        XCTAssertEqual(standard.windowMode, .onTop)
        XCTAssertEqual(standard.mode, .spectrum)
        XCTAssertEqual(standard.appearance.color, StudioAccent.warm.color)
        XCTAssertEqual(standard.appearance.opacity, 0.92)
        XCTAssertEqual(standard.appearance.lineWidth, 1.5)
        XCTAssertEqual(standard.spectrum.barCount, 32)
        XCTAssertEqual(standard.spectrum.scale, .log)
        XCTAssertEqual(standard.spectrum.amplitude, 1)
        XCTAssertFalse(standard.spectrum.stroke)
        XCTAssertFalse(standard.spectrum.peakHold)
        XCTAssertEqual(standard.spectrum.floorDecibels, -60, accuracy: 0.000_1)
        XCTAssertEqual(standard.waveform.smoothing, 0.35)
    }

    func testInvalidValuesNormalize() {
        defaults.set("nope", forKey: StudioPreferenceKey.mode)
        defaults.set("purple", forKey: StudioPreferenceKey.accent)
        defaults.set("#zzzzzz", forKey: StudioPreferenceKey.color)
        defaults.set(4.0, forKey: StudioPreferenceKey.backgroundOpacity)
        defaults.set(false, forKey: StudioPreferenceKey.alwaysOnTop)
        defaults.set("nope", forKey: StudioPreferenceKey.windowMode)
        let loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.mode, .spectrum)
        XCTAssertEqual(loaded.appearance.color, StudioAccent.warm.color)
        XCTAssertEqual(loaded.appearance.opacity, 1)
        XCTAssertEqual(loaded.windowMode, .asWindow)
    }

    func testLowAndNonFiniteOpacityClamp() {
        defaults.set(0.01, forKey: StudioPreferenceKey.backgroundOpacity)
        XCTAssertEqual(StudioPreferences.load(from: defaults).appearance.opacity, 0.35)

        XCTAssertEqual(StudioPreferences.clampedOpacity(.nan), StudioPreferences.standard.appearance.opacity)
        XCTAssertEqual(StudioPreferences.clampedOpacity(.infinity), StudioPreferences.standard.appearance.opacity)
    }

    func testSaveRoundTrip() {
        var stored = StudioPreferences.standard
        stored.mode = .orbit
        stored.windowMode = .onDesktop
        stored.appearance = AppearancePreferences(
            color: StudioColor(red: 0.2, green: 0.4, blue: 0.6),
            strokeColor: StudioColor(red: 0.9, green: 0.1, blue: 0.3),
            opacity: 0.5,
            lineWidth: 3
        )
        stored.spectrum = SpectrumPreferences(
            barCount: 48,
            scale: .linear,
            minHz: 80,
            maxHz: 12_000,
            barGap: 4,
            cornerRadius: 3,
            stroke: true,
            sensitivity: 0.8,
            amplitude: 1.5,
            smoothing: 0.2,
            attackMs: 20,
            releaseMs: 400,
            peakHold: true,
            peakHoldSeconds: 1.2
        )
        stored.waveform = WaveformPreferences(
            lineWidth: 2.5,
            amplitude: 2,
            smoothing: 0.6,
            density: 128,
            style: .filled,
            customColor: StudioColor(red: 0.5, green: 0.25, blue: 0.75)
        )
        stored.orbit = OrbitPreferences(barCount: 16, inner: 0.4, lineWidth: 2, amplitude: 1.2, smoothing: 0.1)
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

    func testLegacySharedKeysSeedPerModeValuesUntilNewKeysExist() {
        defaults.set("sea", forKey: StudioPreferenceKey.accent)
        defaults.set(48, forKey: StudioPreferenceKey.barCount)
        defaults.set(3.0, forKey: StudioPreferenceKey.lineWidth)
        defaults.set(2.0, forKey: StudioPreferenceKey.amplitude)
        defaults.set(0.6, forKey: StudioPreferenceKey.smoothing)
        defaults.set(5.0, forKey: StudioPreferenceKey.barGap)
        defaults.set(true, forKey: StudioPreferenceKey.spectrumStroke)
        defaults.set(0.7, forKey: StudioPreferenceKey.orbitInner)
        let loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.appearance.color, StudioAccent.sea.color)
        XCTAssertEqual(loaded.appearance.strokeColor, StudioAccent.sea.strokeColor)
        XCTAssertEqual(loaded.spectrum.barCount, 48)
        XCTAssertEqual(loaded.orbit.barCount, 48)
        XCTAssertEqual(loaded.appearance.lineWidth, 3)
        XCTAssertEqual(loaded.waveform.lineWidth, 3)
        XCTAssertEqual(loaded.orbit.lineWidth, 3)
        XCTAssertEqual(loaded.spectrum.amplitude, 2)
        XCTAssertEqual(loaded.waveform.amplitude, 2)
        XCTAssertEqual(loaded.orbit.amplitude, 2)
        XCTAssertEqual(loaded.spectrum.smoothing, 0.6, accuracy: 0.000_1)
        XCTAssertEqual(loaded.spectrum.barGap, 5)
        XCTAssertTrue(loaded.spectrum.stroke)
        XCTAssertEqual(loaded.orbit.inner, 0.7)

        defaults.set(12, forKey: StudioPreferenceKey.spectrumBarCount)
        defaults.set(1.0, forKey: StudioPreferenceKey.waveformLineWidth)
        let split = StudioPreferences.load(from: defaults)
        XCTAssertEqual(split.spectrum.barCount, 12)
        XCTAssertEqual(split.orbit.barCount, 48)
        XCTAssertEqual(split.waveform.lineWidth, 1)
        XCTAssertEqual(split.orbit.lineWidth, 3)
    }

    func testEveryValueClampsIntoItsRange() {
        defaults.set(10_000.0, forKey: StudioPreferenceKey.spectrumMinHz)
        defaults.set(10.0, forKey: StudioPreferenceKey.spectrumMaxHz)
        defaults.set(9.0, forKey: StudioPreferenceKey.spectrumSensitivity)
        defaults.set(0.0, forKey: StudioPreferenceKey.spectrumAttackMs)
        defaults.set(99_999.0, forKey: StudioPreferenceKey.spectrumReleaseMs)
        defaults.set(Double.nan, forKey: StudioPreferenceKey.spectrumPeakHoldSeconds)
        defaults.set("spiral", forKey: StudioPreferenceKey.spectrumScale)
        defaults.set(9, forKey: StudioPreferenceKey.spectrumBarCount)
        let spectrum = StudioPreferences.load(from: defaults).spectrum

        XCTAssertEqual(spectrum.minHz, 500)
        XCTAssertEqual(spectrum.maxHz, 2_000)
        XCTAssertLessThan(spectrum.minHz, spectrum.maxHz)
        XCTAssertEqual(spectrum.sensitivity, 1)
        XCTAssertEqual(spectrum.attackMs, 5)
        XCTAssertEqual(spectrum.releaseMs, 1_000)
        XCTAssertEqual(spectrum.peakHoldSeconds, SpectrumPreferences.standard.peakHoldSeconds)
        XCTAssertEqual(spectrum.scale, .log)
        XCTAssertEqual(spectrum.barCount, 32)
        XCTAssertEqual(spectrum.floorDecibels, -80, accuracy: 0.000_1)
    }

    func testWaveformChoicesNormalizeAndCustomColorCanBeCleared() {
        defaults.set(50, forKey: StudioPreferenceKey.waveformDensity)
        defaults.set("ribbon", forKey: StudioPreferenceKey.waveformStyle)
        defaults.set("#0000FF", forKey: StudioPreferenceKey.waveformColor)
        var loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.waveform.density, 64)
        XCTAssertEqual(loaded.waveform.style, .line)
        XCTAssertEqual(loaded.waveform.customColor, StudioColor(red: 0, green: 0, blue: 1))
        loaded.waveform.customColor = nil
        loaded.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: StudioPreferenceKey.waveformColor))
        XCTAssertNil(StudioPreferences.load(from: defaults).waveform.customColor)
    }

    func testStudioColorRoundTripsThroughHex() {
        let color = StudioColor(red: 0.123, green: 0.456, blue: 0.789)
        XCTAssertEqual(StudioColor(hex: color.hex), color)
        XCTAssertEqual(StudioColor(hex: "#FF0080")?.hex, "#FF0080")
        XCTAssertNil(StudioColor(hex: "#12"))
        XCTAssertEqual(StudioColor(red: .nan, green: 4, blue: -1), StudioColor(red: 0, green: 1, blue: 0))
    }

    func testPresetsAreRecognizedAndAppliedTogether() {
        var appearance = AppearancePreferences.standard
        XCTAssertEqual(StudioAccent.matching(color: appearance.color, strokeColor: appearance.strokeColor), .warm)
        appearance.apply(.amber)
        XCTAssertEqual(appearance.color, StudioAccent.amber.color)
        XCTAssertEqual(appearance.strokeColor, StudioAccent.amber.strokeColor)
        XCTAssertEqual(StudioAccent.matching(color: appearance.color, strokeColor: appearance.strokeColor), .amber)
        appearance.color = StudioColor(red: 0, green: 0, blue: 0)
        XCTAssertNil(StudioAccent.matching(color: appearance.color, strokeColor: appearance.strokeColor))
    }

    func testSectionResetRestoresOnlyThatSection() {
        var prefs = StudioPreferences.standard
        prefs.spectrum.barGap = 7
        prefs.appearance.opacity = 0.4
        prefs.spectrum = .standard

        XCTAssertEqual(prefs.spectrum, SpectrumPreferences.standard)
        XCTAssertEqual(prefs.appearance.opacity, 0.4)
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

    func testRetiredKeysAreClearedOnSave() {
        defaults.set(7, forKey: StudioPreferenceKey.barCount)
        defaults.set(true, forKey: StudioPreferenceKey.cleanCanvas)
        defaults.set("sea", forKey: StudioPreferenceKey.accent)
        let loaded = StudioPreferences.load(from: defaults)

        XCTAssertEqual(loaded.spectrum.barCount, 32)
        loaded.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: StudioPreferenceKey.cleanCanvas))
        XCTAssertNil(defaults.object(forKey: StudioPreferenceKey.accent))

        defaults.set("many", forKey: StudioPreferenceKey.spectrumBarCount)
        XCTAssertEqual(StudioPreferences.load(from: defaults).spectrum.barCount, 32)
        XCTAssertEqual(StudioPreferences.normalizedBarCount(64), 64)
        XCTAssertEqual(StudioPreferences.normalizedBarCount(0), 32)

        defaults.set(9.0, forKey: StudioPreferenceKey.lineWidth)
        defaults.set(Double.nan, forKey: StudioPreferenceKey.smoothing)
        XCTAssertEqual(StudioPreferences.load(from: defaults).appearance.lineWidth, 4)
        XCTAssertEqual(StudioPreferences.load(from: defaults).spectrum.smoothing, StudioPreferences.standard.spectrum.smoothing)
    }
}
