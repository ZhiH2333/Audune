import XCTest
@testable import Audune

final class SpectrumDynamicsTests: XCTestCase {
    private let settings = SpectrumDynamicsSettings(
        attackSeconds: 0.04,
        releaseSeconds: 0.3,
        neighborSmoothing: 0,
        peakHoldSeconds: nil
    )

    func testAttackIsFasterThanRelease() {
        let rising = SpectrumDynamics.step(state: SpectrumDynamicsState(), target: [1], dt: 0.033, settings: settings)
        let start = SpectrumDynamicsState(levels: [1], peaks: [1], peakAge: [0])
        let falling = SpectrumDynamics.step(state: start, target: [0], dt: 0.033, settings: settings)

        XCTAssertGreaterThan(rising.levels[0], 0.5)
        XCTAssertGreaterThan(falling.levels[0], 0.8)
        XCTAssertGreaterThan(rising.levels[0], 1 - falling.levels[0])
    }

    func testMotionDependsOnTimeNotFrameCount() {
        var fine = SpectrumDynamicsState()
        for _ in 0..<10 {
            fine = SpectrumDynamics.step(state: fine, target: [1], dt: 0.01, settings: settings)
        }
        let coarse = SpectrumDynamics.step(state: SpectrumDynamicsState(), target: [1], dt: 0.1, settings: settings)

        XCTAssertEqual(fine.levels[0], coarse.levels[0], accuracy: 0.001)
    }

    func testZeroStepKeepsLevelsAndSilenceDecaysToZero() {
        let hold = SpectrumDynamicsState(levels: [0.6, 0.2], peaks: [0.6, 0.2], peakAge: [0, 0])
        XCTAssertEqual(SpectrumDynamics.step(state: hold, target: [1, 1], dt: 0, settings: settings).levels, [0.6, 0.2])

        var state = hold
        for _ in 0..<120 {
            state = SpectrumDynamics.step(state: state, target: [0, 0], dt: 1.0 / 30, settings: settings)
        }
        XCTAssertTrue(state.levels.allSatisfy { $0 < 0.001 })
    }

    func testPeakHoldKeepsThePeakThenFalls() {
        var held = settings
        held.peakHoldSeconds = 0.5
        var state = SpectrumDynamics.step(state: SpectrumDynamicsState(), target: [1], dt: 0.25, settings: held)
        let peak = state.peaks[0]
        for _ in 0..<10 {
            state = SpectrumDynamics.step(state: state, target: [0], dt: 0.03, settings: held)
        }

        XCTAssertEqual(state.peaks[0], peak, accuracy: 0.000_1, "still inside the hold time")
        XCTAssertLessThan(state.levels[0], state.peaks[0])
        for _ in 0..<60 {
            state = SpectrumDynamics.step(state: state, target: [0], dt: 0.03, settings: held)
        }
        XCTAssertLessThan(state.peaks[0], peak)
        XCTAssertGreaterThanOrEqual(state.peaks[0], state.levels[0])
    }

    func testNeighborSmoothingSpreadsOnlyBetweenBars() {
        var spread = settings
        spread.neighborSmoothing = 1
        let state = SpectrumDynamics.step(state: SpectrumDynamicsState(), target: [0, 1, 0], dt: 10, settings: spread)

        XCTAssertGreaterThan(state.levels[0], 0)
        XCTAssertEqual(state.levels[1], 1.0 / 3, accuracy: 0.01)
        XCTAssertEqual(state.levels[0], state.levels[2], accuracy: 0.000_1)
    }

    func testInvalidInputStaysFiniteAndInRange() {
        let state = SpectrumDynamics.step(
            state: SpectrumDynamicsState(levels: [.nan], peaks: [.infinity], peakAge: [.nan]),
            target: [.nan, .infinity, -1, 2],
            dt: .nan,
            settings: SpectrumDynamicsSettings(attackSeconds: 0, releaseSeconds: .nan, neighborSmoothing: .nan, peakHoldSeconds: .infinity)
        )

        XCTAssertEqual(state.levels.count, 4)
        XCTAssertEqual(state.peaks.count, 4)
        XCTAssertTrue((state.levels + state.peaks).allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(SpectrumDynamics.step(state: state, target: [], dt: 0.03, settings: settings), SpectrumDynamicsState())
    }

    func testPreferencesMapIndependentAttackAndRelease() {
        var prefs = SpectrumPreferences.standard
        prefs.attackMs = 10
        prefs.releaseMs = 500
        prefs.smoothing = 0.8
        prefs.peakHold = false

        let mapped = prefs.dynamics
        XCTAssertEqual(mapped.attackSeconds, 0.01, accuracy: 0.000_001)
        XCTAssertEqual(mapped.releaseSeconds, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(mapped.neighborSmoothing, 0.8, accuracy: 0.000_001)
        XCTAssertNil(mapped.peakHoldSeconds)

        let rising = SpectrumDynamics.step(
            state: SpectrumDynamicsState(),
            target: [1],
            dt: 0.05,
            settings: mapped
        )
        let falling = SpectrumDynamics.step(
            state: SpectrumDynamicsState(levels: [1], peaks: [1], peakAge: [0]),
            target: [0],
            dt: 0.05,
            settings: mapped
        )
        XCTAssertGreaterThan(rising.levels[0], 0.9)
        XCTAssertGreaterThan(falling.levels[0], 0.85)
    }
}
