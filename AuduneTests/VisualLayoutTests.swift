import CoreGraphics
import XCTest
@testable import Audune

final class VisualLayoutTests: XCTestCase {
    private let suite = "AuduneVisualLayoutTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testFixedSizeDoesNotChangeWhenTheWindowGrows() {
        let layout = VisualLayoutPreferences.standard
        let small = VisualLayout.frame(in: CGSize(width: 800, height: 500), layout: layout)
        let large = VisualLayout.frame(in: CGSize(width: 1600, height: 1000), layout: layout)

        XCTAssertEqual(small.size, large.size)
        XCTAssertEqual(small.width, 640, accuracy: 0.001)
        XCTAssertEqual(small.height, 400, accuracy: 0.001)
        XCTAssertEqual(large.midX, 800, accuracy: 0.001)
        XCTAssertEqual(large.midY, 500, accuracy: 0.001)
    }

    func testScaleAndAspectChangeTheFrame() {
        var layout = VisualLayoutPreferences.standard
        layout.scale = 0.5
        layout.aspect = .square
        let frame = VisualLayout.frame(in: CGSize(width: 1000, height: 800), layout: layout)
        XCTAssertEqual(frame.width, 320, accuracy: 0.001)
        XCTAssertEqual(frame.height, 320, accuracy: 0.001)
    }

    func testFrameShrinksToFitSmallWindowKeepingAspect() {
        var layout = VisualLayoutPreferences.standard
        layout.scale = 2
        layout.aspect = .ultrawide
        let container = CGSize(width: 400, height: 300)
        let frame = VisualLayout.frame(in: container, layout: layout)
        XCTAssertLessThanOrEqual(frame.width, container.width + 0.001)
        XCTAssertLessThanOrEqual(frame.height, container.height + 0.001)
        XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.001)
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(frame))
    }

    func testFillModeUsesTheWholeWindow() {
        var layout = VisualLayoutPreferences.standard
        layout.mode = .fill
        let container = CGSize(width: 700, height: 420)
        XCTAssertEqual(VisualLayout.frame(in: container, layout: layout), CGRect(origin: .zero, size: container))
    }

    func testInvalidInputsStaySafe() {
        XCTAssertEqual(VisualLayout.frame(in: .zero, layout: .standard), .zero)
        XCTAssertEqual(VisualLayout.frame(in: CGSize(width: CGFloat.nan, height: 100), layout: .standard), .zero)
        var layout = VisualLayoutPreferences.standard
        layout.scale = .nan
        let frame = VisualLayout.frame(in: CGSize(width: 900, height: 600), layout: layout)
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite)
        XCTAssertEqual(frame.width, 640, accuracy: 0.001)
    }

    func testLayoutPersistsAndOldDataGetsDefaults() {
        XCTAssertEqual(StudioPreferences.load(from: defaults).layout, .standard)

        var prefs = StudioPreferences.standard
        prefs.layout = VisualLayoutPreferences(mode: .fill, scale: 1.5, aspect: .standard)
        prefs.save(to: defaults)
        XCTAssertEqual(StudioPreferences.load(from: defaults).layout, prefs.layout)

        defaults.set(99.0, forKey: StudioPreferenceKey.layoutScale)
        XCTAssertEqual(StudioPreferences.load(from: defaults).layout.scale, 2)
        defaults.set("nonsense", forKey: StudioPreferenceKey.layoutMode)
        XCTAssertEqual(StudioPreferences.load(from: defaults).layout.mode, .fixed)
    }

    func testLayoutDoesNotTouchWindowSizeLimits() {
        var prefs = StudioPreferences.standard
        let window = prefs.window
        prefs.layout.scale = 0.3
        XCTAssertEqual(prefs.normalized().window, window)
    }
}
