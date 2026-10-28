import XCTest
@testable import Audune

final class VisualPresetExchangeCodecTests: XCTestCase {
    func testSinglePresetRoundTrip() throws {
        let source = VisualPresetCatalog.dense
        let data = try VisualPresetExchange.encode([source]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "Dense")
        XCTAssertEqual(entries[0].mode, .spectrum)
        XCTAssertEqual(entries[0].spectrum, source.spectrum?.clamped())
        XCTAssertNil(entries[0].waveform)
        XCTAssertNil(entries[0].orbit)
        assertExchangeEnvelope(data)
        assertNoInternalStorageKeys(data)
    }

    func testBatchRoundTripAcrossModes() throws {
        var customWave = WaveformPreferences.standard
        customWave.customColor = StudioColor(red: 0.2, green: 0.4, blue: 0.6)
        customWave.style = .mirror
        let custom = VisualPreset(
            id: "ignored-on-export",
            name: "Night",
            mode: .waveform,
            kind: .custom,
            waveform: customWave
        )
        let sources = [VisualPresetCatalog.dense, custom, VisualPresetCatalog.halo]
        let data = try VisualPresetExchange.encode(sources).get()
        let entries = try VisualPresetExchange.decode(data).get()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].spectrum, VisualPresetCatalog.dense.spectrum?.clamped())
        XCTAssertEqual(entries[1].name, "Night")
        XCTAssertEqual(entries[1].waveform?.customColor, customWave.customColor)
        XCTAssertEqual(entries[1].waveform?.style, .mirror)
        XCTAssertEqual(entries[2].orbit, VisualPresetCatalog.halo.orbit?.clamped())
        assertExchangeEnvelope(data)
        assertNoInternalStorageKeys(data)
    }

    func testBuiltInSnapshotHasNoKindOrID() throws {
        let data = try VisualPresetExchange.encode([VisualPresetCatalog.fineLine]).get()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("\"id\""))
        XCTAssertFalse(json.contains("\"kind\""))
        XCTAssertFalse(json.contains("builtIn"))
        XCTAssertFalse(json.contains("builtin.waveform"))
        let entries = try VisualPresetExchange.decode(data).get()
        let imported = entries[0].asCustomPreset(id: UUID().uuidString)
        XCTAssertEqual(imported.kind, .custom)
        XCTAssertEqual(imported.waveform, VisualPresetCatalog.fineLine.waveform?.clamped())
    }

    func testExportOmitsAppearanceWindowAndAppliedIDs() throws {
        let data = try VisualPresetExchange.encode([
            VisualPresetCatalog.clean,
            VisualPresetCatalog.softFill,
            VisualPresetCatalog.compact
        ]).get()
        assertNoInternalStorageKeys(data)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("appearance"))
        XCTAssertFalse(json.contains("window"))
        XCTAssertFalse(json.contains("appliedID"))
        XCTAssertFalse(json.contains("opacity"))
        XCTAssertFalse(json.contains("hideDelay"))
    }

    func testEmptyEncodeFailsWithoutTouchingDefaults() {
        let defaults = UserDefaults(suiteName: "AuduneExchangeEmptyEncode")!
        defaults.removePersistentDomain(forName: "AuduneExchangeEmptyEncode")
        defaults.set(Data("keep-me".utf8), forKey: StudioPreferenceKey.visualPresets)
        XCTAssertEqual(VisualPresetExchange.encode([]), .failure(.emptyPresets))
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), Data("keep-me".utf8))
        defaults.removePersistentDomain(forName: "AuduneExchangeEmptyEncode")
    }

    func testRejectsUnsupportedSchemaVersion() {
        let json = """
        {"format":"audune.visualPresetExchange","schemaVersion":2,"presets":[\(spectrumJSON(name: "A"))]}
        """
        XCTAssertEqual(
            VisualPresetExchange.decode(Data(json.utf8)),
            .failure(.unsupportedSchemaVersion(2))
        )
    }

    func testRejectsWrongFormat() {
        let json = """
        {"format":"not-audune","schemaVersion":1,"presets":[\(spectrumJSON(name: "A"))]}
        """
        XCTAssertEqual(
            VisualPresetExchange.decode(Data(json.utf8)),
            .failure(.unsupportedFormat("not-audune"))
        )
    }

    func testRejectsInvalidJSON() {
        XCTAssertEqual(VisualPresetExchange.decode(Data("not-json".utf8)), .failure(.invalidJSON))
    }

    func testRejectsMissingRequiredField() {
        var object = spectrumObject(name: "A")
        object["spectrum"] = partialSpectrumMissingSmoothing()
        let data = try! JSONSerialization.data(withJSONObject: [
            "format": VisualPresetExchange.formatIdentifier,
            "schemaVersion": 1,
            "presets": [object]
        ])
        switch VisualPresetExchange.decode(data) {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            guard case .invalidPreset(_, let reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(reason.contains("smoothing"))
        }
    }

    func testRejectsUnknownMode() {
        let json = """
        {"format":"audune.visualPresetExchange","schemaVersion":1,"presets":[{
          "name":"X","mode":"particles","spectrum":null
        }]}
        """
        switch VisualPresetExchange.decode(Data(json.utf8)) {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            guard case .invalidPreset = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testRejectsNonFiniteAndOutOfRange() throws {
        var high = spectrumObject(name: "Hot")
        var spectrum = try XCTUnwrap(high["spectrum"] as? [String: Any])
        spectrum["amplitude"] = 99
        high["spectrum"] = spectrum
        let highData = try JSONSerialization.data(withJSONObject: envelope([high]))
        switch VisualPresetExchange.decode(highData) {
        case .success:
            XCTFail("expected range failure")
        case .failure(let error):
            guard case .invalidPreset(_, let reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(reason.contains("outside the allowed range"))
        }

        var nanObject = spectrumObject(name: "NaN")
        var nanSpectrum = try XCTUnwrap(nanObject["spectrum"] as? [String: Any])
        // JSON has no NaN; inject via a number then mutate after encode is not possible.
        // Use a string that our parser will reject as non-double.
        nanSpectrum["amplitude"] = "NaN"
        nanObject["spectrum"] = nanSpectrum
        let nanData = try JSONSerialization.data(withJSONObject: envelope([nanObject]))
        switch VisualPresetExchange.decode(nanData) {
        case .success:
            XCTFail("expected non-finite/invalid failure")
        case .failure(let error):
            guard case .invalidPreset = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testRejectsUnknownWaveformStyleIncludingLegacyFilled() throws {
        var object: [String: Any] = [
            "name": "Filled",
            "mode": "waveform",
            "waveform": waveformObject(style: "filled")
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope([object]))
        switch VisualPresetExchange.decode(data) {
        case .success:
            XCTFail("legacy filled must be rejected in exchange files")
        case .failure(let error):
            guard case .invalidPreset(_, let reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(reason.contains("style"))
        }

        object["waveform"] = waveformObject(style: "ribbon")
        let unknown = try JSONSerialization.data(withJSONObject: envelope([object]))
        switch VisualPresetExchange.decode(unknown) {
        case .success:
            XCTFail("unknown style must be rejected")
        case .failure(let error):
            guard case .invalidPreset = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testRejectsDuplicateNamesInFile() throws {
        let data = try JSONSerialization.data(withJSONObject: envelope([
            spectrumObject(name: "Same"),
            spectrumObject(name: "same")
        ]))
        XCTAssertEqual(
            VisualPresetExchange.decode(data),
            .failure(.duplicateNameInFile("Same"))
        )
    }

    func testRejectsFileTooLarge() {
        let huge = Data(repeating: UInt8(ascii: "a"), count: VisualPresetExchange.maximumFileSizeBytes + 1)
        XCTAssertEqual(VisualPresetExchange.decode(huge), .failure(.fileTooLarge))
    }

    func testRejectsTooManyPresets() throws {
        let presets = (1...VisualPresetExchange.maximumPresetsPerFile + 1).map { index in
            spectrumObject(name: "P\(index)")
        }
        // Names must be unique within mode; P1..P73 are unique.
        let data = try JSONSerialization.data(withJSONObject: envelope(presets))
        XCTAssertEqual(VisualPresetExchange.decode(data), .failure(.tooManyPresets))
    }

    // MARK: - Helpers

    private func assertExchangeEnvelope(_ data: Data) {
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["format"] as? String, VisualPresetExchange.formatIdentifier)
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(json["exportedAt"] as? String)
        XCTAssertNotNil(json["presets"] as? [Any])
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\n"), "export should be pretty-printed")
    }

    private func assertNoInternalStorageKeys(_ data: Data) {
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains("customPresets"))
        XCTAssertFalse(text.contains("appliedIDByMode"))
        XCTAssertFalse(text.contains("studio.visualPresets"))
    }

    private func envelope(_ presets: [[String: Any]]) -> [String: Any] {
        [
            "format": VisualPresetExchange.formatIdentifier,
            "schemaVersion": 1,
            "presets": presets
        ]
    }

    private func spectrumJSON(name: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: spectrumObject(name: name))
        return String(data: data, encoding: .utf8)!
    }

    private func spectrumObject(name: String) -> [String: Any] {
        let prefs = SpectrumPreferences.standard.clamped()
        return [
            "name": name,
            "mode": "spectrum",
            "spectrum": [
                "barCount": prefs.barCount,
                "scale": prefs.scale.rawValue,
                "minHz": prefs.minHz,
                "maxHz": prefs.maxHz,
                "barGap": prefs.barGap,
                "cornerRadius": prefs.cornerRadius,
                "stroke": prefs.stroke,
                "colorMode": prefs.colorMode.rawValue,
                "sensitivity": prefs.sensitivity,
                "amplitude": prefs.amplitude,
                "smoothing": prefs.smoothing,
                "attackMs": prefs.attackMs,
                "releaseMs": prefs.releaseMs,
                "peakHold": prefs.peakHold,
                "peakHoldSeconds": prefs.peakHoldSeconds,
                "peakFallPerSecond": prefs.peakFallPerSecond,
                "silenceGateEnabled": prefs.silenceGateEnabled,
                "silenceThreshold": prefs.silenceThreshold
            ] as [String: Any]
        ]
    }

    private func partialSpectrumMissingSmoothing() -> [String: Any] {
        var spectrum = spectrumObject(name: "A")["spectrum"] as! [String: Any]
        spectrum.removeValue(forKey: "smoothing")
        return spectrum
    }

    private func waveformObject(style: String) -> [String: Any] {
        let prefs = WaveformPreferences.standard.clamped()
        return [
            "lineWidth": prefs.lineWidth,
            "amplitude": prefs.amplitude,
            "verticalRange": prefs.verticalRange,
            "smoothing": prefs.smoothing,
            "density": prefs.density,
            "style": style,
            "fillStrength": prefs.fillStrength
        ]
    }
}
