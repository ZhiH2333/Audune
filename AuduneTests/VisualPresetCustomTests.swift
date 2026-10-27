import XCTest
@testable import Audune

@MainActor
final class VisualPresetCustomTests: XCTestCase {
    private let suite = "AuduneVisualPresetCustomTests"
    private var defaults: UserDefaults!
    private var spike: ProcessTapSpike!
    private var studio: StudioWindowController!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        spike = ProcessTapSpike()
        studio = StudioWindowController(spike: spike, defaults: defaults)
    }

    override func tearDown() {
        studio.shutdown()
        studio = nil
        spike = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testSaveDuplicateRenameAndDeleteRoundTrip() throws {
        var waveform = WaveformPreferences.standard
        waveform.customColor = StudioColor(red: 0.2, green: 0.4, blue: 0.8)
        waveform.density = 128
        waveform.style = .softFill
        waveform.lineWidth = 2.5
        studio.model.prefs.waveform = waveform
        studio.model.prefs.spectrum.barCount = 48

        let saved = try studio.saveCurrentVisualPreset(name: "  Glow  ", mode: .waveform).get()
        XCTAssertEqual(saved.name, "Glow")
        XCTAssertEqual(saved.kind, .custom)
        var stored = VisualPresetCatalog.restoring(from: defaults)
        XCTAssertEqual(stored.customPresets.first?.waveform, waveform.clamped())
        XCTAssertEqual(stored.appliedID(for: .waveform), saved.id)
        XCTAssertEqual(stored.match(in: studio.currentPreferences(), mode: .waveform).statusText, "Glow · Custom")
        XCTAssertEqual(studio.currentPreferences().spectrum.barCount, 48)

        try studio.renameVisualPreset(id: saved.id, to: "Glow 2").get()
        stored = VisualPresetCatalog.restoring(from: defaults)
        XCTAssertEqual(stored.customPresets.first?.id, saved.id)
        XCTAssertEqual(stored.customPresets.first?.name, "Glow 2")
        XCTAssertEqual(stored.appliedID(for: .waveform), saved.id)

        studio.model.prefs.waveform.amplitude = 2.4
        XCTAssertEqual(stored.match(in: studio.currentPreferences(), mode: .waveform).statusText, "Glow 2 · Modified")

        let beforeDelete = studio.currentPreferences()
        try studio.deleteVisualPreset(id: saved.id).get()
        XCTAssertEqual(studio.currentPreferences(), beforeDelete)
        stored = VisualPresetCatalog.restoring(from: defaults)
        XCTAssertTrue(stored.customPresets.isEmpty)
        XCTAssertNil(stored.appliedID(for: .waveform))
        XCTAssertEqual(spike.phase, .idle)
    }

    func testRejectedNamesDoNotChangeTheLibrary() throws {
        let first = try studio.saveCurrentVisualPreset(name: String(repeating: "a", count: 40), mode: .spectrum).get()
        expectFailure(studio.saveCurrentVisualPreset(name: " ", mode: .spectrum), .emptyName)
        expectFailure(studio.saveCurrentVisualPreset(name: String(repeating: "a", count: 41), mode: .spectrum), .nameTooLong)
        expectFailure(studio.saveCurrentVisualPreset(name: "clean", mode: .spectrum), .duplicateName)
        expectFailure(studio.saveCurrentVisualPreset(name: first.name, mode: .spectrum), .duplicateName)
        let stored = VisualPresetCatalog.restoring(from: defaults)
        XCTAssertEqual(stored.customPresets.map(\.id), [first.id])

        let copy = try studio.duplicateVisualPreset(id: VisualPresetCatalog.clean.id).get()
        XCTAssertEqual(copy.kind, .custom)
        XCTAssertEqual(copy.name, "Clean Copy")
        XCTAssertEqual(copy.spectrum, VisualPresetCatalog.clean.spectrum)
        XCTAssertEqual(VisualPresetCatalog.clean.name, "Clean")
        XCTAssertNotEqual(copy.id, VisualPresetCatalog.clean.id)
        expectFailure(studio.renameVisualPreset(id: VisualPresetCatalog.clean.id, to: "Nope"), .builtInLocked)
        expectFailure(studio.deleteVisualPreset(id: VisualPresetCatalog.clean.id), .builtInLocked)
        XCTAssertEqual(VisualPresetCatalog.restoring(from: defaults).builtIns.first { $0.id == VisualPresetCatalog.clean.id }, VisualPresetCatalog.clean)
    }

    func testResetClearsTheAppliedPresetAndKeepsCustomOnes() throws {
        studio.model.prefs.spectrum.barCount = 64
        studio.model.prefs.spectrum.barGap = 6
        studio.model.prefs.waveform.density = 32
        let saved = try studio.saveCurrentVisualPreset(name: "Wide", mode: .spectrum).get()
        XCTAssertTrue(studio.applyVisualPreset(VisualPresetCatalog.fineLine))

        studio.model.prefs.spectrum = .standard
        studio.clearAppliedVisualPreset(for: .spectrum)
        XCTAssertEqual(studio.currentPreferences().spectrum, .standard)
        XCTAssertEqual(studio.currentPreferences().waveform, VisualPresetCatalog.fineLine.waveform)

        var stored = VisualPresetCatalog.restoring(from: defaults)
        XCTAssertEqual(stored.customPresets.map(\.id), [saved.id])
        XCTAssertNil(stored.appliedID(for: .spectrum))
        XCTAssertEqual(stored.match(in: studio.currentPreferences(), mode: .spectrum).statusText, "Unsaved settings")
        XCTAssertEqual(stored.appliedID(for: .waveform), VisualPresetCatalog.fineLine.id)

        studio.resetPreferences()
        studio.clearAppliedVisualPresets()
        stored = VisualPresetCatalog.restoring(from: defaults)
        XCTAssertEqual(stored.customPresets.map(\.name), ["Wide"])
        XCTAssertNil(stored.appliedID(for: .spectrum))
        XCTAssertNil(stored.appliedID(for: .waveform))
        XCTAssertNil(stored.appliedID(for: .orbit))
        XCTAssertEqual(studio.currentPreferences(), .standard)
    }

    private func expectFailure<T>(_ result: Result<T, VisualPresetEditError>, _ error: VisualPresetEditError, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("expected \(error)", file: file, line: line)
        case .failure(let actual):
            XCTAssertEqual(actual, error, file: file, line: line)
        }
    }
}
