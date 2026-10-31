import XCTest
@testable import Audune

final class LayoutPreviewEnergyStateTests: XCTestCase {
    func testEnterEnergySavingStoresSnapshot() {
        let live = LayoutPreviewSnapshot(
            spectrum: [0.1, 0.2],
            peaks: [0.3],
            waveform: [0.4, 0.5],
            drawsBars: true
        )
        var state = LayoutPreviewEnergyState()

        state.enterEnergySaving(capturing: live)

        XCTAssertTrue(state.isEnergySaving)
        XCTAssertEqual(state.snapshot, live)
    }

    func testResumeClearsEnergySaving() {
        var state = LayoutPreviewEnergyState()
        state.enterEnergySaving(
            capturing: LayoutPreviewSnapshot(spectrum: [1], peaks: [], waveform: [0], drawsBars: false)
        )

        state.resume()

        XCTAssertFalse(state.isEnergySaving)
        XCTAssertNil(state.snapshot)
    }

    func testReenteringEnergySavingReplacesFrozenFrame() {
        var state = LayoutPreviewEnergyState()
        state.enterEnergySaving(
            capturing: LayoutPreviewSnapshot(spectrum: [1], peaks: [], waveform: [0], drawsBars: true)
        )
        let next = LayoutPreviewSnapshot(spectrum: [2, 3], peaks: [4], waveform: [5], drawsBars: false)

        state.enterEnergySaving(capturing: next)

        XCTAssertTrue(state.isEnergySaving)
        XCTAssertEqual(state.snapshot, next)
    }
}
