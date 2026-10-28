import XCTest
@testable import Audune

final class VisualPresetExchangeImportTests: XCTestCase {
    private let suite = "AuduneVisualPresetExchangeImportTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testValidFileImportsWithNewIDs() throws {
        let data = try VisualPresetExchange.encode([
            VisualPresetCatalog.dense,
            VisualPresetCatalog.mirror
        ]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let plan = try VisualPresetImportPlanner.plan(
            entries: entries,
            library: library,
            policy: .importAsCopies
        ).get()
        // Built-in names conflict → renamed copies.
        XCTAssertEqual(plan.importCount, 2)
        XCTAssertTrue(plan.items.allSatisfy {
            if case .renamed = $0.status { return true }
            return false
        })

        let created = try library.commitImport(plan, to: defaults).get()
        XCTAssertEqual(created.count, 2)
        XCTAssertTrue(created.allSatisfy { $0.kind == .custom })
        XCTAssertFalse(created.contains { $0.id.hasPrefix("builtin.") })
        XCTAssertEqual(created[0].spectrum, VisualPresetCatalog.dense.spectrum?.clamped())
        XCTAssertEqual(created[1].waveform, VisualPresetCatalog.mirror.waveform?.clamped())
        XCTAssertEqual(VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all).customPresets, created)
        XCTAssertTrue(VisualPresetCatalog.all.allSatisfy { builtin in
            library.builtIns.contains(where: { $0.id == builtin.id && $0.name == builtin.name })
        })
    }

    func testSkipConflictsLeavesLibraryUnchangedForConflictsOnly() throws {
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let existing = try library.addCustom(name: "Mine", mode: .spectrum, spectrum: .standard, to: defaults).get()
        let data = try VisualPresetExchange.encode([
            VisualPreset(
                id: "x",
                name: "Mine",
                mode: .spectrum,
                kind: .custom,
                spectrum: VisualPresetCatalog.dynamic.spectrum
            ),
            VisualPreset(
                id: "y",
                name: "Fresh",
                mode: .spectrum,
                kind: .custom,
                spectrum: .standard
            )
        ]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        let plan = try VisualPresetImportPlanner.plan(entries: entries, library: library, policy: .skipConflicts).get()
        XCTAssertEqual(plan.importCount, 1)
        XCTAssertEqual(plan.skippedCount, 1)
        let created = try library.commitImport(plan, to: defaults).get()
        XCTAssertEqual(created.map(\.name), ["Fresh"])
        XCTAssertEqual(library.customPresets.map(\.name), [existing.name, "Fresh"])
        XCTAssertEqual(library.customPresets.first?.spectrum, existing.spectrum)
    }

    func testUnsupportedVersionDoesNotWrite() {
        let before = defaults.data(forKey: StudioPreferenceKey.visualPresets)
        let json = Data(#"{"format":"audune.visualPresetExchange","schemaVersion":99,"presets":[]}"#.utf8)
        XCTAssertEqual(VisualPresetExchange.decode(json), .failure(.unsupportedSchemaVersion(99)))
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), before)
    }

    func testCapacityLimitBlocksPartialImport() throws {
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        for index in 1...VisualPresetLibrary.maxCustomPresetsPerMode {
            _ = try library.addCustom(
                name: "S\(index)",
                mode: .spectrum,
                spectrum: .standard,
                to: defaults
            ).get()
        }
        let data = try VisualPresetExchange.encode([
            VisualPreset(id: "n", name: "Overflow", mode: .spectrum, kind: .custom, spectrum: .standard)
        ]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        let before = defaults.data(forKey: StudioPreferenceKey.visualPresets)
        XCTAssertEqual(
            VisualPresetImportPlanner.plan(entries: entries, library: library, policy: .importAsCopies),
            .failure(.limitReached)
        )
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), before)
        XCTAssertEqual(library.customPresets.count, VisualPresetLibrary.maxCustomPresetsPerMode)
    }

    func testPersistFailureRollsBack() throws {
        let data = try VisualPresetExchange.encode([
            VisualPreset(id: "a", name: "Alpha", mode: .waveform, kind: .custom, waveform: .standard)
        ]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let plan = try VisualPresetImportPlanner.plan(entries: entries, library: library, policy: .importAsCopies).get()
        let before = defaults.data(forKey: StudioPreferenceKey.visualPresets)
        library.encodeDocument = { _ in .failure(.persistFailed) }
        XCTAssertEqual(library.commitImport(plan, to: defaults), .failure(.persistFailed))
        XCTAssertTrue(library.customPresets.isEmpty)
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), before)
    }

    func testCancelPathNeverNeedsCommit() throws {
        let data = try VisualPresetExchange.encode([VisualPresetCatalog.halo]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let beforeCount = library.customPresets.count
        _ = try VisualPresetImportPlanner.plan(entries: entries, library: library, policy: .importAsCopies).get()
        // User cancel = do not call commitImport.
        XCTAssertEqual(library.customPresets.count, beforeCount)
        XCTAssertNil(defaults.data(forKey: StudioPreferenceKey.visualPresets))
    }

    func testExternalIDsAreIgnored() throws {
        let payload = """
        {
          "format":"audune.visualPresetExchange",
          "schemaVersion":1,
          "presets":[{
            "name":"External",
            "mode":"orbit",
            "id":"builtin.orbit.compact",
            "kind":"builtIn",
            "orbit":\(orbitJSON())
          }]
        }
        """
        let entries = try VisualPresetExchange.decode(Data(payload.utf8)).get()
        XCTAssertEqual(entries.count, 1)
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let plan = try VisualPresetImportPlanner.plan(entries: entries, library: library, policy: .importAsCopies).get()
        let created = try library.commitImport(plan, to: defaults).get()
        XCTAssertEqual(created.count, 1)
        XCTAssertNotEqual(created[0].id, "builtin.orbit.compact")
        XCTAssertEqual(created[0].kind, .custom)
        XCTAssertEqual(library.preset(id: "builtin.orbit.compact")?.kind, .builtIn)
    }

    func testRoundTripCustomPreservesPayload() throws {
        var library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        var wave = WaveformPreferences.standard
        wave.style = .softFill
        wave.customColor = StudioColor(red: 0.1, green: 0.2, blue: 0.3)
        wave.fillStrength = 0.5
        let original = try library.addCustom(name: "Soft Night", mode: .waveform, waveform: wave, to: defaults).get()
        let data = try VisualPresetExchange.encode([original]).get()

        defaults.removePersistentDomain(forName: suite)
        var other = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        let entries = try VisualPresetExchange.decode(data).get()
        let plan = try VisualPresetImportPlanner.plan(entries: entries, library: other, policy: .importAsCopies).get()
        let created = try other.commitImport(plan, to: defaults).get()
        XCTAssertEqual(created.count, 1)
        XCTAssertNotEqual(created[0].id, original.id)
        XCTAssertEqual(created[0].name, "Soft Night")
        XCTAssertEqual(created[0].waveform, wave.clamped())
    }

    func testUnreadableStoreRejectsPlan() throws {
        defaults.set(Data("broken".utf8), forKey: StudioPreferenceKey.visualPresets)
        let library = VisualPresetLibrary.load(from: defaults, builtIns: VisualPresetCatalog.all)
        XCTAssertFalse(library.canPersist)
        let data = try VisualPresetExchange.encode([
            VisualPreset(id: "z", name: "Z", mode: .spectrum, kind: .custom, spectrum: .standard)
        ]).get()
        let entries = try VisualPresetExchange.decode(data).get()
        XCTAssertEqual(
            VisualPresetImportPlanner.plan(entries: entries, library: library, policy: .importAsCopies),
            .failure(.unreadableStore)
        )
        XCTAssertEqual(defaults.data(forKey: StudioPreferenceKey.visualPresets), Data("broken".utf8))
    }

    private func orbitJSON() -> String {
        let prefs = OrbitPreferences.standard.clamped()
        let object: [String: Any] = [
            "barCount": prefs.barCount,
            "inner": prefs.inner,
            "outerScale": prefs.outerScale,
            "gapDegrees": prefs.gapDegrees,
            "mirrored": prefs.mirrored,
            "stroke": prefs.stroke,
            "lineWidth": prefs.lineWidth,
            "amplitude": prefs.amplitude,
            "smoothing": prefs.smoothing,
            "layerMode": prefs.layerMode.rawValue,
            "pulseStrength": prefs.pulseStrength
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }
}
