import XCTest
@testable import Audune

final class LyricsPresentationTimingTests: XCTestCase {
    func testTranslationRevealFollowsPlaybackPosition() {
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 9.9),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 10.12),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 10.20),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: 10, positionSeconds: 30),
            1,
            accuracy: 0.0001
        )
    }

    func testTranslationRevealFreezesWithPlaybackAndHandlesMissingTiming() {
        let frozen = LyricsPresentationTiming.translationOpacity(
            lineStartSeconds: 10,
            positionSeconds: 10.20
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(
                lineStartSeconds: 10,
                positionSeconds: 10.20
            ),
            frozen,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: nil, positionSeconds: 10),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LyricsPresentationTiming.translationOpacity(lineStartSeconds: .nan, positionSeconds: 10),
            1,
            accuracy: 0.0001
        )
    }
}
