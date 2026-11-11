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
        XCTAssertEqual(standard.spectrum.attackMs, 35)
        XCTAssertEqual(standard.spectrum.releaseMs, 260)
        XCTAssertEqual(standard.spectrum.floorDecibels, -60, accuracy: 0.000_1)
        XCTAssertEqual(standard.waveform.smoothing, 0.4, accuracy: 0.000_1)
        XCTAssertEqual(standard.waveform.amplitude, 0.55, accuracy: 0.000_1)
        XCTAssertEqual(standard.waveform.verticalRange, 0.7, accuracy: 0.000_1)
        XCTAssertEqual(standard.waveform.lineWidth, 1.25, accuracy: 0.000_1)
        XCTAssertEqual(standard.waveform.fillStrength, 0.32, accuracy: 0.000_1)
        XCTAssertEqual(standard.waveform.style, .line)
    }

    func testAttackAndReleasePersistIndependentlyOfSmoothing() {
        var stored = StudioPreferences.standard
        stored.spectrum.attackMs = 15
        stored.spectrum.releaseMs = 800
        stored.spectrum.smoothing = 0.1
        stored.save(to: defaults)

        let loaded = StudioPreferences.load(from: defaults).spectrum
        XCTAssertEqual(loaded.attackMs, 15)
        XCTAssertEqual(loaded.releaseMs, 800)
        XCTAssertEqual(loaded.smoothing, 0.1, accuracy: 0.000_1)
        XCTAssertEqual(loaded.dynamics.attackSeconds, 0.015, accuracy: 0.000_001)
        XCTAssertEqual(loaded.dynamics.releaseSeconds, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(loaded.dynamics.neighborSmoothing, 0.1, accuracy: 0.000_001)
    }

    func testSilenceGatePersistsAndMissingKeysUseDefaults() {
        XCTAssertTrue(StudioPreferences.standard.spectrum.silenceGateEnabled)
        XCTAssertEqual(
            StudioPreferences.standard.spectrum.silenceThreshold,
            Double(SilenceGateSettings.standard.enterRMS),
            accuracy: 0.000_000_1
        )

        var stored = StudioPreferences.standard
        stored.spectrum.silenceGateEnabled = false
        stored.spectrum.silenceThreshold = 0.0025
        stored.save(to: defaults)
        let loaded = StudioPreferences.load(from: defaults).spectrum
        XCTAssertFalse(loaded.silenceGateEnabled)
        XCTAssertEqual(loaded.silenceThreshold, 0.0025, accuracy: 0.000_000_1)
        XCTAssertFalse(loaded.silenceGate.enabled)
        XCTAssertEqual(loaded.silenceGate.enterRMS, 0.0025, accuracy: 0.000_000_1)
        XCTAssertGreaterThan(loaded.silenceGate.exitRMS, loaded.silenceGate.enterRMS)

        defaults.removePersistentDomain(forName: suite)
        let missing = StudioPreferences.load(from: defaults).spectrum
        XCTAssertTrue(missing.silenceGateEnabled)
        XCTAssertEqual(missing.silenceThreshold, SpectrumPreferences.standard.silenceThreshold, accuracy: 0.000_000_1)
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
        stored.window = WindowPreferences(
            allowsDrag: false,
            allowsResize: false,
            restorePosition: false,
            hideDelaySeconds: 1.2,
            animatesChrome: false,
            followsReduceMotion: false,
            passesMouseThrough: true,
            autoHidesControls: false,
            summonRegion: .grip,
            width: 720,
            height: 480,
            minWidth: 400,
            minHeight: 280,
            maxWidth: 1200,
            maxHeight: 800
        )
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
            colorMode: .frequency,
            sensitivity: 0.8,
            amplitude: 1.5,
            smoothing: 0.2,
            attackMs: 20,
            releaseMs: 400,
            peakHold: true,
            peakHoldSeconds: 1.2,
            peakFallPerSecond: 1.4,
            silenceGateEnabled: true,
            silenceThreshold: 0.001
        )
        stored.waveform = WaveformPreferences(
            lineWidth: 2.5,
            amplitude: 1.2,
            verticalRange: 0.85,
            smoothing: 0.6,
            density: 128,
            style: .softFill,
            fillStrength: 0.5,
            customColor: StudioColor(red: 0.5, green: 0.25, blue: 0.75)
        )
        stored.orbit = OrbitPreferences(
            barCount: 16,
            inner: 0.4,
            outerScale: 0.8,
            gapDegrees: 4,
            mirrored: false,
            stroke: true,
            lineWidth: 2,
            amplitude: 1.2,
            smoothing: 0.1,
            layerMode: .dualBand,
            pulseStrength: 0.2,
            customColor: StudioColor(red: 0.1, green: 0.8, blue: 0.3)
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
        defaults.set(9.0, forKey: StudioPreferenceKey.spectrumPeakFallPerSecond)
        XCTAssertEqual(
            StudioPreferences.load(from: defaults).spectrum.peakFallPerSecond,
            StudioPreferences.peakFallPerSecondRange.upperBound
        )
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
        XCTAssertEqual(loaded.waveform.fillStrength, 0.32, accuracy: 0.000_1)
        XCTAssertEqual(loaded.waveform.customColor, StudioColor(red: 0, green: 0, blue: 1))
        defaults.set("filled", forKey: StudioPreferenceKey.waveformStyle)
        XCTAssertEqual(StudioPreferences.load(from: defaults).waveform.style, .softFill)
        defaults.set(0.7, forKey: StudioPreferenceKey.waveformFillStrength)
        defaults.set(0.2, forKey: StudioPreferenceKey.waveformAmplitude)
        let motion = StudioPreferences.load(from: defaults).waveform
        XCTAssertEqual(motion.fillStrength, 0.7, accuracy: 0.000_1)
        XCTAssertEqual(motion.amplitude, 0.2, accuracy: 0.000_1)
        XCTAssertEqual(motion.verticalRange, 0.7, accuracy: 0.000_1)
        loaded.waveform.customColor = nil
        loaded.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: StudioPreferenceKey.waveformColor))
        XCTAssertNil(StudioPreferences.load(from: defaults).waveform.customColor)
    }

    func testWaveformVerticalRangePersistsAndClamps() {
        defaults.set(0.45, forKey: StudioPreferenceKey.waveformVerticalRange)
        XCTAssertEqual(StudioPreferences.load(from: defaults).waveform.verticalRange, 0.45, accuracy: 0.000_1)

        defaults.set(1.5, forKey: StudioPreferenceKey.waveformVerticalRange)
        XCTAssertEqual(
            StudioPreferences.load(from: defaults).waveform.verticalRange,
            StudioPreferences.waveformVerticalRangeRange.upperBound,
            accuracy: 0.000_1
        )
        defaults.set(0.05, forKey: StudioPreferenceKey.waveformVerticalRange)
        XCTAssertEqual(
            StudioPreferences.load(from: defaults).waveform.verticalRange,
            StudioPreferences.waveformVerticalRangeRange.lowerBound,
            accuracy: 0.000_1
        )
        defaults.set(Double.nan, forKey: StudioPreferenceKey.waveformVerticalRange)
        XCTAssertEqual(
            StudioPreferences.load(from: defaults).waveform.verticalRange,
            WaveformPreferences.standard.verticalRange,
            accuracy: 0.000_1
        )
    }

    func testOrbitDefaultsAndRangesNormalize() {
        let standard = StudioPreferences.standard.orbit
        XCTAssertEqual(standard.barCount, 48)
        XCTAssertTrue(standard.mirrored)
        XCTAssertEqual(standard.bandCount, 24)
        XCTAssertNil(standard.customColor)

        defaults.set(5.0, forKey: StudioPreferenceKey.orbitOuterScale)
        defaults.set(-3.0, forKey: StudioPreferenceKey.orbitGapDegrees)
        defaults.set(false, forKey: StudioPreferenceKey.orbitMirrored)
        let loaded = StudioPreferences.load(from: defaults).orbit
        XCTAssertEqual(loaded.outerScale, 1)
        XCTAssertEqual(loaded.gapDegrees, 0)
        XCTAssertFalse(loaded.mirrored)
        XCTAssertEqual(loaded.bandCount, loaded.barCount)
    }

    func testWindowDefaultsAndRangesNormalize() {
        let standard = StudioPreferences.standard.window
        XCTAssertTrue(standard.allowsDrag)
        XCTAssertTrue(standard.allowsResize)
        XCTAssertTrue(standard.restorePosition)
        XCTAssertEqual(standard.hideDelaySeconds, 0.8, accuracy: 0.000_1)
        XCTAssertTrue(standard.animatesChrome)
        XCTAssertTrue(standard.followsReduceMotion)
        XCTAssertTrue(standard.passesMouseThrough)
        XCTAssertTrue(standard.autoHidesControls)
        XCTAssertEqual(standard.summonRegion, .bottomEdge)
        XCTAssertEqual(standard.width, 640, accuracy: 0.000_1)
        XCTAssertEqual(standard.height, 400, accuracy: 0.000_1)
        XCTAssertEqual(standard.minWidth, 360, accuracy: 0.000_1)
        XCTAssertEqual(standard.minHeight, 240, accuracy: 0.000_1)
        XCTAssertEqual(standard.maxWidth, 1600, accuracy: 0.000_1)
        XCTAssertEqual(standard.maxHeight, 1000, accuracy: 0.000_1)

        defaults.set(99.0, forKey: StudioPreferenceKey.windowHideDelay)
        XCTAssertEqual(StudioPreferences.load(from: defaults).window.hideDelaySeconds, 3)
        defaults.set(0.0, forKey: StudioPreferenceKey.windowHideDelay)
        XCTAssertEqual(StudioPreferences.load(from: defaults).window.hideDelaySeconds, 0.2, accuracy: 0.000_1)
        defaults.set(Double.nan, forKey: StudioPreferenceKey.windowHideDelay)
        XCTAssertEqual(StudioPreferences.load(from: defaults).window.hideDelaySeconds, 0.8, accuracy: 0.000_1)
        defaults.removeObject(forKey: StudioPreferenceKey.windowHideDelay)
        defaults.set(false, forKey: StudioPreferenceKey.windowAllowsDrag)
        let missing = StudioPreferences.load(from: defaults).window
        XCTAssertEqual(missing.hideDelaySeconds, 0.8, accuracy: 0.000_1)
        XCTAssertTrue(missing.autoHidesControls)
        XCTAssertEqual(missing.summonRegion, .bottomEdge)
        XCTAssertFalse(missing.allowsDrag)
        XCTAssertEqual(missing.width, 640, accuracy: 0.000_1)
        XCTAssertEqual(missing.height, 400, accuracy: 0.000_1)
        XCTAssertEqual(missing.minWidth, 360, accuracy: 0.000_1)
        XCTAssertEqual(missing.maxWidth, 1600, accuracy: 0.000_1)
        defaults.set("sideways", forKey: StudioPreferenceKey.windowSummonRegion)
        defaults.set(false, forKey: StudioPreferenceKey.windowAutoHidesControls)
        defaults.set(false, forKey: StudioPreferenceKey.windowPassesMouseThrough)
        let stored = StudioPreferences.load(from: defaults).window
        XCTAssertEqual(stored.summonRegion, .bottomEdge)
        XCTAssertFalse(stored.autoHidesControls)
        XCTAssertTrue(stored.passesMouseThrough)

        defaults.set(900.0, forKey: StudioPreferenceKey.windowMinWidth)
        defaults.set(100.0, forKey: StudioPreferenceKey.windowMinHeight)
        defaults.set(500.0, forKey: StudioPreferenceKey.windowMaxWidth)
        defaults.set(10_000.0, forKey: StudioPreferenceKey.windowMaxHeight)
        let sized = StudioPreferences.load(from: defaults).window
        XCTAssertEqual(sized.minWidth, 800, accuracy: 0.000_1)
        XCTAssertEqual(sized.minHeight, 240, accuracy: 0.000_1)
        XCTAssertEqual(sized.maxWidth, 800, accuracy: 0.000_1)
        XCTAssertEqual(sized.maxHeight, 2160, accuracy: 0.000_1)

        defaults.set(800.0, forKey: StudioPreferenceKey.windowWidth)
        defaults.set(500.0, forKey: StudioPreferenceKey.windowHeight)
        let preferred = StudioPreferences.load(from: defaults).window
        XCTAssertEqual(preferred.width, 800, accuracy: 0.000_1)
        XCTAssertEqual(preferred.height, 500, accuracy: 0.000_1)
        defaults.set(50.0, forKey: StudioPreferenceKey.windowWidth)
        defaults.set(9_000.0, forKey: StudioPreferenceKey.windowHeight)
        let clampedSize = StudioPreferences.load(from: defaults).window
        XCTAssertEqual(clampedSize.width, StudioPreferences.windowWidthRange.lowerBound, accuracy: 0.000_1)
        XCTAssertEqual(clampedSize.height, StudioPreferences.windowHeightRange.upperBound, accuracy: 0.000_1)
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

        let picked = StudioColor(red: 0.3, green: 0.6, blue: 0.9)
        appearance.setFillColor(picked)
        XCTAssertEqual(appearance.color, picked)
        XCTAssertEqual(appearance.strokeColor, picked.blended(towardWhite: 0.35))

        let customStroke = StudioColor(red: 0.8, green: 0.2, blue: 0.2)
        appearance.strokeColor = customStroke
        appearance.setFillColor(StudioColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(appearance.strokeColor, customStroke)
        XCTAssertNil(StudioAccent.matching(color: appearance.color, strokeColor: appearance.strokeColor))

        var orbit = OrbitPreferences.standard
        XCTAssertEqual(orbit.effectiveStrokeColor(fallback: StudioAccent.amber.strokeColor), StudioAccent.amber.strokeColor)
        orbit.customColor = picked
        XCTAssertEqual(orbit.effectiveStrokeColor(fallback: StudioAccent.amber.strokeColor), picked.blended(towardWhite: 0.35))
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
