import XCTest
@testable import Audune

final class CaptureFailureTests: XCTestCase {
    private let allFailures: [CaptureFailure] = [.noOutputDevice, .captureUnavailable, .deviceNotReady, .unsupportedFormat]

    func testEveryFailureHasUserMessageAndShortSummary() {
        for failure in allFailures {
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertFalse(failure.summary.isEmpty)
            XCTAssertLessThan(failure.summary.count, failure.message.count)
        }
    }

    func testUserTextHidesDeveloperTerms() {
        let developerTerms = ["OSStatus", "AudioHardware", "AudioDevice", "aggregate", "IOProc", "tapautostart"]
        for failure in allFailures {
            for term in developerTerms {
                XCTAssertFalse(failure.message.localizedCaseInsensitiveContains(term), "\(failure) message mentions \(term)")
                XCTAssertFalse(failure.summary.localizedCaseInsensitiveContains(term), "\(failure) summary mentions \(term)")
            }
        }
    }

    @MainActor
    func testFallbackUserMessageBeforeAnyFailure() {
        let spike = ProcessTapSpike()
        XCTAssertNil(spike.failure)
        XCTAssertFalse(spike.userFailureMessage.isEmpty)
        XCTAssertFalse(spike.userFailureSummary.isEmpty)
    }
}
