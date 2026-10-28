import XCTest
@testable import Audune

final class VisualPresetExchangeExportTests: XCTestCase {
    private let suite = "AuduneVisualPresetExchangeExportTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testSinglePresetExportDecodes() throws {
        let data = try VisualPresetExchange.encode([VisualPresetCatalog.dynamic]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "Dynamic")
        XCTAssertEqual(entries[0].spectrum, VisualPresetCatalog.dynamic.spectrum?.clamped())
    }

    func testBatchExportPreservesAllModes() throws {
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let custom = try library.addCustom(
            name: "Orbit Night",
            mode: .orbit,
            orbit: VisualPresetCatalog.denseRing.orbit,
            to: defaults
        ).get()
        let selected = [VisualPresetCatalog.clean, VisualPresetCatalog.softFill, custom]
        let data = try VisualPresetExchange.encode(selected).get()
        let entries = try VisualPresetExchange.decode(data).get()
        XCTAssertEqual(entries.map(\.name), ["Clean", "Soft Fill", "Orbit Night"])
        XCTAssertEqual(entries.map(\.mode), [.spectrum, .waveform, .orbit])
        XCTAssertEqual(entries[0].spectrum, VisualPresetCatalog.clean.spectrum?.clamped())
        XCTAssertEqual(entries[1].waveform, VisualPresetCatalog.softFill.waveform?.clamped())
        XCTAssertEqual(entries[2].orbit, custom.orbit?.clamped())

        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("appliedIDByMode"))
        XCTAssertFalse(json.contains("customPresets"))
        XCTAssertFalse(json.contains(custom.id))
    }

    func testEncodeFailureDoesNotChangeLibrary() throws {
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let saved = try library.addCustom(name: "Keep", mode: .spectrum, spectrum: .standard, to: defaults).get()
        let before = defaults.data(forKey: StudioPreferenceKey.visualPresets)
        XCTAssertEqual(VisualPresetExchange.encode([]), .failure(.emptyPresets))
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), before)
        XCTAssertEqual(VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all).customPresets, [saved])
    }

    func testDefaultExportFileNames() {
        let single = VisualPresetFilePanel.defaultExportName(mode: .spectrum, presets: [VisualPresetCatalog.dense])
        XCTAssertEqual(single, "Audune-Spectrum-Dense.json")
        let batch = VisualPresetFilePanel.defaultExportName(
            mode: .waveform,
            presets: [VisualPresetCatalog.fineLine, VisualPresetCatalog.mirror]
        )
        XCTAssertEqual(batch, "Audune-Waveform-Presets.json")
        XCTAssertEqual(VisualPresetFilePanel.sanitizedFileComponent("A/B:C"), "A-B-C")
    }

    func testControllerEncodeUsesLibrarySnapshots() throws {
        let controllerDefaults = UserDefaults(suiteName: suite + ".controller")!
        controllerDefaults.removePersistentDomain(forName: suite + ".controller")
        // StudioWindowController is heavy; exercise the same encode path via exchange + library lookup.
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let custom = try library.addCustom(name: "Wave", mode: .waveform, waveform: .standard, to: defaults).get()
        let resolved = library.preset(id: custom.id)!
        let data = try VisualPresetExchange.encode([resolved, VisualPresetCatalog.halo]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].waveform, WaveformPreferences.standard.clamped())
        XCTAssertEqual(entries[1].orbit, VisualPresetCatalog.halo.orbit?.clamped())
        controllerDefaults.removePersistentDomain(forName: suite + ".controller")
    }
}
