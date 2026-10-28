import XCTest
@testable import Audune

/// Checks the String Catalogs and that translated text never reaches stored identifiers.
/// The scheme runs tests in English; the Simplified Chinese checks read the compiled `zh-Hans.lproj` directly.
final class LocalizationTests: XCTestCase {
    private struct Catalog {
        var strings: [String: [String: Any]]

        init(fileName: String) throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let data = try Data(contentsOf: root.appendingPathComponent("Audune").appendingPathComponent(fileName))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["sourceLanguage"] as? String, "en")
            strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        }

        func chinese(for key: String) -> String? {
            let localizations = strings[key]?["localizations"] as? [String: Any]
            let unit = (localizations?["zh-Hans"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard unit?["state"] as? String == "translated" else { return nil }
            return unit?["value"] as? String
        }
    }

    private func placeholders(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:@|lld|d|f)")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).map { match in
            let token = String(text[Range(match.range, in: text)!])
            return token.replacingOccurrences(of: "\\d+\\$", with: "", options: .regularExpression)
        }.sorted()
    }

    /// Reads the compiled `zh-Hans.lproj` table once; `Bundle.localizedString` per key is very slow here.
    private func chineseTable(_ name: String) throws -> [String: String] {
        let folder = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"), "zh-Hans.lproj is not in the app bundle")
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).strings")
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(name).strings is missing")
        return table
    }

    func testEveryCatalogKeyHasATranslatedChineseValueWithMatchingPlaceholders() throws {
        let catalog = try Catalog(fileName: "Localizable.xcstrings")
        XCTAssertGreaterThan(catalog.strings.count, 250)
        for key in catalog.strings.keys {
            let zh = try XCTUnwrap(catalog.chinese(for: key), "\(key) has no translated zh-Hans value")
            XCTAssertFalse(zh.trimmingCharacters(in: .whitespaces).isEmpty, key)
            XCTAssertEqual(placeholders(in: zh), placeholders(in: key), "placeholders differ for \(key)")
        }
    }

    func testCompiledChineseTableMatchesTheCatalog() throws {
        let catalog = try Catalog(fileName: "Localizable.xcstrings")
        let table = try chineseTable("Localizable")
        for key in catalog.strings.keys {
            XCTAssertEqual(table[key], catalog.chinese(for: key), "\(key) was not compiled into zh-Hans")
        }
    }

    func testCoreMenuAndSettingsTitlesDifferFromEnglishInChinese() throws {
        let table = try chineseTable("Localizable")
        let keys = [
            "Start", "Stop", "Quit Audune", "Open Studio", "Hide Studio", "Settings…",
            "Capture failed", "Not listening", "Listening", "No audio",
            "Appearance", "Layout", "Spectrum", "Waveform", "Orbit", "Window",
            "Reset Appearance", "Save", "Cancel", "Delete",
        ]
        for key in keys {
            let value = try XCTUnwrap(table[key], "\(key) is missing from zh-Hans")
            XCTAssertNotEqual(value, key, "\(key) is not translated")
        }
    }

    func testPermissionDescriptionsAreTranslated() throws {
        let catalog = try Catalog(fileName: "InfoPlist.xcstrings")
        let table = try chineseTable("InfoPlist")
        for key in ["NSAudioCaptureUsageDescription"] {
            XCTAssertFalse((catalog.chinese(for: key) ?? "").isEmpty, key)
            XCTAssertEqual(table[key], catalog.chinese(for: key), key)
        }
        XCTAssertNil(catalog.chinese(for: "NSAppleEventsUsageDescription"))
    }

    func testStoredIdentifiersDoNotDependOnTheLanguage() {
        XCTAssertEqual(StudioVisualMode.allCases.map(\.rawValue), ["spectrum", "waveform", "orbit"])
        XCTAssertEqual(StudioWindowMode.allCases.map(\.rawValue), ["onDesktop", "onTop", "asWindow"])
        XCTAssertEqual(SettingsCategory.allCases.map(\.rawValue), ["appearance", "layout", "spectrum", "waveform", "orbit", "window", "island"])
        XCTAssertEqual(
            VisualPresetCatalog.all.map(\.id),
            [
                "builtin.spectrum.clean", "builtin.spectrum.dense", "builtin.spectrum.dynamic",
                "builtin.waveform.fineLine", "builtin.waveform.softFill", "builtin.waveform.mirror",
                "builtin.orbit.compact", "builtin.orbit.halo", "builtin.orbit.denseRing",
            ]
        )
        XCTAssertEqual(
            VisualPresetCatalog.all.map(\.name),
            ["Clean", "Dense", "Dynamic", "Fine Line", "Soft Fill", "Mirror", "Compact", "Halo", "Dense Ring"]
        )
    }

    func testBuiltInPresetsHaveDisplayNamesAndCustomNamesAreUntouched() {
        for preset in VisualPresetCatalog.all {
            XCTAssertNotNil(VisualPresetCatalog.localizedName(forBuiltInID: preset.id), preset.id)
            XCTAssertFalse(preset.displayName.isEmpty)
        }
        var custom = VisualPresetCatalog.clean
        custom.id = "custom-id"
        custom.kind = .custom
        custom.name = "Evening"
        XCTAssertEqual(custom.displayName, "Evening")
    }
}
