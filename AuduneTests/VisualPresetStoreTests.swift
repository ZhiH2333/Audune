import XCTest
@testable import Audune

final class VisualPresetStoreTests: XCTestCase {
    private let suite = "AuduneVisualPresetStoreTests"
    private var defaults: UserDefaults!

    private func expectFailure<T>(
        _ result: Result<T, VisualPresetEditError>,
        _ error: VisualPresetEditError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("expected \(error)", file: file, line: line)
        case .failure(let actual):
            XCTAssertEqual(actual, error, file: file, line: line)
        }
    }

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testPartialModePayloadFillsAndClamps() throws {
        let spectrum = try JSONDecoder().decode(SpectrumPreferences.self, from: Data(#"{"smoothing":9,"barCount":3}"#.utf8))
        XCTAssertEqual(spectrum.barCount, SpectrumPreferences.standard.barCount)
        XCTAssertEqual(spectrum.smoothing, 1)
        XCTAssertEqual(spectrum.amplitude, SpectrumPreferences.standard.amplitude)
        XCTAssertEqual(spectrum.scale, .log)
        XCTAssertEqual(spectrum.attackMs, SpectrumPreferences.standard.attackMs)
        XCTAssertEqual(spectrum.peakFallPerSecond, SpectrumPreferences.standard.peakFallPerSecond)
        XCTAssertFalse(spectrum.peakHold)
        XCTAssertTrue(spectrum.silenceGateEnabled)
        XCTAssertEqual(spectrum.silenceThreshold, SpectrumPreferences.standard.silenceThreshold, accuracy: 0.000_000_1)
        XCTAssertEqual(spectrum.colorMode, .solid)

        let waveform = try JSONDecoder().decode(WaveformPreferences.self, from: Data(#"{"density":32}"#.utf8))
        XCTAssertEqual(waveform.density, 32)
        XCTAssertEqual(waveform.style, .line)
        XCTAssertNil(waveform.customColor)
        XCTAssertEqual(waveform.lineWidth, WaveformPreferences.standard.lineWidth)
        XCTAssertEqual(waveform.amplitude, WaveformPreferences.standard.amplitude, accuracy: 0.000_1)
        XCTAssertEqual(waveform.fillStrength, WaveformPreferences.standard.fillStrength, accuracy: 0.000_1)

        let legacyFilled = try JSONDecoder().decode(
            WaveformPreferences.self,
            from: Data(#"{"style":"filled","amplitude":1.8}"#.utf8)
        )
        XCTAssertEqual(legacyFilled.style, .softFill)
        XCTAssertEqual(legacyFilled.amplitude, 1.8, accuracy: 0.000_1)
        XCTAssertEqual(legacyFilled.verticalRange, WaveformPreferences.standard.verticalRange, accuracy: 0.000_1)
        XCTAssertEqual(legacyFilled.fillStrength, WaveformPreferences.standard.fillStrength, accuracy: 0.000_1)

        let appearance = try JSONDecoder().decode(AppearancePreferences.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(appearance, .standard)

        let color = try JSONDecoder().decode(StudioColor.self, from: Data("\"#1A2B3C\"".utf8))
        XCTAssertEqual(color, StudioColor(red: 26.0 / 255, green: 43.0 / 255, blue: 60.0 / 255))
        let encoded = try JSONDecoder().decode(StudioColor.self, from: try JSONEncoder().encode(color))
        XCTAssertEqual(encoded, color)
    }

    func testCustomPresetSurvivesReloadAndIDsStayUnique() throws {
        var library = VisualPresetLibrary.load(from: defaults)
        var waveform = WaveformPreferences.standard
        waveform.customColor = StudioColor(red: 0.2, green: 0.4, blue: 0.6)
        waveform.density = 128
        let first = try library.addCustom(name: "  Night  ", mode: .waveform, waveform: waveform, to: defaults).get()
        let second = try library.addCustom(name: "Day", mode: .waveform, waveform: .standard, to: defaults).get()

        XCTAssertEqual(first.name, "Night")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(first.id.isEmpty)
        XCTAssertEqual(first.kind, .custom)
        XCTAssertEqual(first.waveform?.customColor, waveform.customColor)
        XCTAssertNil(first.spectrum)
        XCTAssertNil(first.orbit)

        let reloaded = VisualPresetLibrary.load(from: defaults)
        XCTAssertTrue(reloaded.canPersist)
        XCTAssertEqual(reloaded.customPresets, [first, second])
        XCTAssertEqual(reloaded.presets(for: .waveform).map(\.id), [first.id, second.id])
        XCTAssertTrue(reloaded.presets(for: .spectrum).isEmpty)
    }

    func testNameRules() throws {
        var library = VisualPresetLibrary.load(from: defaults)
        XCTAssertEqual(library.addCustom(name: "   ", mode: .spectrum, spectrum: .standard, to: defaults), .failure(.emptyName))
        XCTAssertEqual(
            library.addCustom(name: String(repeating: "字", count: 41), mode: .spectrum, spectrum: .standard, to: defaults),
            .failure(.nameTooLong)
        )
        let edge = try library.addCustom(
            name: String(repeating: "字", count: 40),
            mode: .spectrum,
            spectrum: .standard,
            to: defaults
        ).get()
        XCTAssertEqual(edge.name.count, 40)
        XCTAssertEqual(library.addCustom(name: edge.name, mode: .spectrum, spectrum: .standard, to: defaults), .failure(.duplicateName))

        let saved = try library.addCustom(name: "Clean", mode: .orbit, orbit: .standard, to: defaults).get()
        XCTAssertEqual(library.addCustom(name: "clean", mode: .orbit, orbit: .standard, to: defaults), .failure(.duplicateName))
        let otherMode = try library.addCustom(name: "Clean", mode: .waveform, waveform: .standard, to: defaults).get()
        XCTAssertEqual(otherMode.name, "Clean")
        XCTAssertNotEqual(otherMode.id, saved.id)
        XCTAssertEqual(library.customPresets.count, 3)
    }

    func testBuiltInNamesAndEditsStayLocked() throws {
        let builtIn = VisualPreset(
            id: "builtin.spectrum.clean",
            name: "Clean",
            mode: .spectrum,
            kind: .builtIn,
            spectrum: .standard
        )
        var library = VisualPresetLibrary.load(from: defaults, builtIns: [builtIn])
        XCTAssertEqual(library.addCustom(name: "clean", mode: .spectrum, spectrum: .standard, to: defaults), .failure(.duplicateName))
        let copy = try library.addCustom(name: "Clean", mode: .waveform, waveform: .standard, to: defaults).get()
        expectFailure(library.rename(id: builtIn.id, to: "Other", in: defaults), .builtInLocked)
        expectFailure(library.delete(id: builtIn.id, in: defaults), .builtInLocked)
        XCTAssertEqual(library.customPresets.map(\.id), [copy.id])
        XCTAssertEqual(library.builtIns, [builtIn])
    }

    func testCorruptAndUnsupportedDataAreNotOverwritten() throws {
        let corrupt = Data("not json".utf8)
        defaults.set(corrupt, forKey: StudioPreferenceKey.visualPresets)
        var library = VisualPresetLibrary.load(from: defaults)
        XCTAssertFalse(library.canPersist)
        XCTAssertTrue(library.customPresets.isEmpty)
        XCTAssertFalse(library.save(to: defaults))
        XCTAssertEqual(library.addCustom(name: "Night", mode: .spectrum, spectrum: .standard, to: defaults), .failure(.unreadableStore))
        expectFailure(library.rename(id: "x", to: "Y", in: defaults), .unreadableStore)
        expectFailure(library.delete(id: "x", in: defaults), .unreadableStore)
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), corrupt)

        let future = Data(#"{"schemaVersion":2,"customPresets":[],"appliedIDByMode":{}}"#.utf8)
        defaults.set(future, forKey: StudioPreferenceKey.visualPresets)
        library = VisualPresetLibrary.load(from: defaults)
        XCTAssertFalse(library.canPersist)
        XCTAssertFalse(library.save(to: defaults))
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), future)

        let duplicated = Data(#"""
        {"schemaVersion":1,"customPresets":[
          {"id":"same","name":"One","mode":"spectrum","kind":"custom","spectrum":{"barCount":32}},
          {"id":"same","name":"Two","mode":"spectrum","kind":"custom","spectrum":{"barCount":48}}
        ],"appliedIDByMode":{}}
        """#.utf8)
        defaults.set(duplicated, forKey: StudioPreferenceKey.visualPresets)
        library = VisualPresetLibrary.load(from: defaults)
        XCTAssertFalse(library.canPersist)
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), duplicated)
    }

    func testRenameDeleteAndFailedWrite() throws {
        var library = VisualPresetLibrary.load(from: defaults)
        let preset = try library.addCustom(name: "Night", mode: .spectrum, spectrum: .standard, to: defaults).get()
        try library.setAppliedID(preset.id, for: .spectrum, in: defaults).get()
        try library.rename(id: preset.id, to: "Evening", in: defaults).get()
        XCTAssertEqual(VisualPresetLibrary.load(from: defaults).customPresets.first?.name, "Evening")
        expectFailure(library.rename(id: preset.id, to: " ", in: defaults), .emptyName)
        XCTAssertEqual(library.customPresets.first?.name, "Evening")

        let stored = try XCTUnwrap(defaults.data(forKey: StudioPreferenceKey.visualPresets))
        library.encodeDocument = { _ in .failure(.persistFailed) }
        expectFailure(library.rename(id: preset.id, to: "Later", in: defaults), .persistFailed)
        XCTAssertEqual(library.customPresets.first?.name, "Evening")
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), stored)

        library.encodeDocument = VisualPresetLibrary.load(from: defaults).encodeDocument
        try library.delete(id: preset.id, in: defaults).get()
        let reloaded = VisualPresetLibrary.load(from: defaults)
        XCTAssertTrue(reloaded.customPresets.isEmpty)
        XCTAssertNil(reloaded.appliedID(for: .spectrum))
        expectFailure(library.delete(id: preset.id, in: defaults), .notFound)
    }

    func testExplicitResetReplacesUnreadableData() throws {
        defaults.set(Data("not json".utf8), forKey: StudioPreferenceKey.visualPresets)
        var library = VisualPresetLibrary.load(from: defaults)
        XCTAssertTrue(library.resetLibrary(in: defaults))
        var reloaded = VisualPresetLibrary.load(from: defaults)
        XCTAssertTrue(reloaded.canPersist)
        XCTAssertTrue(reloaded.customPresets.isEmpty)
        let preset = try reloaded.addCustom(name: "After reset", mode: .orbit, orbit: .standard, to: defaults).get()
        XCTAssertEqual(preset.mode, .orbit)
    }

    func testModeMismatchAndLimitDoNotDropExistingPresets() throws {
        var library = VisualPresetLibrary.load(from: defaults)
        XCTAssertEqual(
            library.addCustom(name: "Wrong", mode: .spectrum, waveform: .standard, to: defaults),
            .failure(.modeMismatch)
        )
        XCTAssertNil(defaults.data(forKey: StudioPreferenceKey.visualPresets))

        for index in 0..<VisualPresetLibrary.maxCustomPresetsPerMode {
            _ = try library.addCustom(name: "Preset \(index)", mode: .spectrum, spectrum: .standard, to: defaults).get()
        }
        XCTAssertEqual(
            library.addCustom(name: "One more", mode: .spectrum, spectrum: .standard, to: defaults),
            .failure(.limitReached)
        )
        XCTAssertEqual(library.customPresets.count, VisualPresetLibrary.maxCustomPresetsPerMode)
        let extraMode = try library.addCustom(name: "Orbit", mode: .orbit, orbit: .standard, to: defaults).get()
        XCTAssertEqual(extraMode.mode, .orbit)
    }
}
