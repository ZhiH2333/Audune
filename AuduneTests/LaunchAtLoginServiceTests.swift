import ServiceManagement
import XCTest
@testable import Audune

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    func testMapEnabled() {
        XCTAssertEqual(SystemLaunchAtLoginService.map(.enabled), .enabled)
        XCTAssertTrue(SystemLaunchAtLoginService.map(.enabled).isEnabled)
    }

    func testMapNotRegistered() {
        XCTAssertEqual(SystemLaunchAtLoginService.map(.notRegistered), .notRegistered)
        XCTAssertFalse(SystemLaunchAtLoginService.map(.notRegistered).isEnabled)
    }

    func testMapRequiresApproval() {
        let status = SystemLaunchAtLoginService.map(.requiresApproval)
        XCTAssertEqual(status, .requiresApproval)
        XCTAssertTrue(status.needsApproval)
        XCTAssertFalse(status.isEnabled)
        XCTAssertNotNil(status.statusMessage)
    }

    func testMapNotFound() {
        let status = SystemLaunchAtLoginService.map(.notFound)
        XCTAssertEqual(status, .notFound)
        XCTAssertFalse(status.isEnabled)
        XCTAssertNotNil(status.statusMessage)
    }

    func testMockSetEnabledUpdatesStatusFromServiceTruth() {
        let service = MockLaunchAtLoginService(status: .notRegistered, registerResult: .enabled)
        service.setEnabled(true)
        XCTAssertEqual(service.setEnabledHistory, [true])
        XCTAssertEqual(service.status, .enabled)
        XCTAssertTrue(service.status.isEnabled)

        service.setEnabled(false)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(service.status.isEnabled)
    }

    func testMockRegisterCanLandInRequiresApproval() {
        let service = MockLaunchAtLoginService(
            status: .notRegistered,
            registerResult: .requiresApproval
        )
        service.setEnabled(true)
        XCTAssertEqual(service.status, .requiresApproval)
        XCTAssertFalse(service.status.isEnabled)
        XCTAssertTrue(service.status.needsApproval)
    }

    func testMockFailedSetEnabledDoesNotPretendEnabled() {
        let service = MockLaunchAtLoginService(status: .notRegistered)
        service.shouldFailSetEnabled = true
        service.setEnabled(true)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertEqual(service.lastErrorDescription, "mock failure")
    }

    func testMockOpenLoginItemsSettingsIsCallable() {
        let service = MockLaunchAtLoginService(status: .requiresApproval)
        service.openLoginItemsSettings()
        XCTAssertEqual(service.openLoginItemsCallCount, 1)
    }

    func testStatusMessagesExistForNonIdleStates() {
        XCTAssertNil(LaunchAtLoginStatus.enabled.statusMessage)
        XCTAssertNil(LaunchAtLoginStatus.notRegistered.statusMessage)
        XCTAssertNotNil(LaunchAtLoginStatus.requiresApproval.statusMessage)
        XCTAssertNotNil(LaunchAtLoginStatus.notFound.statusMessage)
        XCTAssertNotNil(LaunchAtLoginStatus.unavailable.statusMessage)
    }
}
