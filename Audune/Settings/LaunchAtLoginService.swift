#if os(macOS)
import Foundation
import Observation
import ServiceManagement

/// Registration state for launching Audune when the user logs into macOS.
nonisolated enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case unavailable

    var isEnabled: Bool { self == .enabled }
    var needsApproval: Bool { self == .requiresApproval }

    var statusMessage: String? {
        switch self {
        case .enabled, .notRegistered:
            return nil
        case .requiresApproval:
            return String(localized: "Audune is waiting for approval in System Settings > General > Login Items.")
        case .notFound:
            return String(localized: "macOS could not find Audune’s login item. Try turning the option on again.")
        case .unavailable:
            return String(localized: "Launch at login is unavailable in this build. Use a normally installed Audune app.")
        }
    }
}

/// Abstracts `SMAppService.mainApp` so unit tests can map status without touching the system.
@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var status: LaunchAtLoginStatus { get }
    var lastErrorDescription: String? { get }
    func refresh()
    func setEnabled(_ enabled: Bool)
    func openLoginItemsSettings()
}

/// Reads and writes the real `SMAppService.mainApp` registration. Never mirrors status in UserDefaults.
@Observable
@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginControlling {
    private(set) var status: LaunchAtLoginStatus = .notRegistered
    private(set) var lastErrorDescription: String?

    init() {
        refresh()
    }

    func refresh() {
        status = Self.map(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) {
        lastErrorDescription = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastErrorDescription = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    nonisolated static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            return .notRegistered
        @unknown default:
            return .unavailable
        }
    }
}

/// Deterministic stand-in for Settings and unit tests.
@Observable
@MainActor
final class MockLaunchAtLoginService: LaunchAtLoginControlling {
    private(set) var status: LaunchAtLoginStatus
    private(set) var lastErrorDescription: String?
    private(set) var openLoginItemsCallCount = 0
    private(set) var setEnabledHistory: [Bool] = []
    var registerResult: LaunchAtLoginStatus
    var unregisterResult: LaunchAtLoginStatus
    var shouldFailSetEnabled = false

    init(
        status: LaunchAtLoginStatus = .notRegistered,
        registerResult: LaunchAtLoginStatus = .enabled,
        unregisterResult: LaunchAtLoginStatus = .notRegistered
    ) {
        self.status = status
        self.registerResult = registerResult
        self.unregisterResult = unregisterResult
    }

    func refresh() {}

    func setEnabled(_ enabled: Bool) {
        setEnabledHistory.append(enabled)
        lastErrorDescription = nil
        guard shouldFailSetEnabled == false else {
            lastErrorDescription = "mock failure"
            return
        }
        status = enabled ? registerResult : unregisterResult
    }

    func openLoginItemsSettings() {
        openLoginItemsCallCount += 1
    }
}
#endif
