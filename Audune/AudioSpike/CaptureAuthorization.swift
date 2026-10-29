#if os(macOS)
import CoreGraphics
import Foundation

/// Read-only probe for system audio capture permission without presenting a prompt.
protocol CaptureAuthorizationChecking: Sendable {
    /// `true` only when capture is already allowed. Must not trigger a TCC prompt.
    func isCaptureAlreadyAuthorized() -> Bool
}

/// Uses Screen Capture preflight as the public non-prompting check for system-audio-style TCC.
struct ScreenCaptureAuthorizationProbe: CaptureAuthorizationChecking {
    func isCaptureAlreadyAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

struct FixedCaptureAuthorization: CaptureAuthorizationChecking {
    var authorized: Bool
    func isCaptureAlreadyAuthorized() -> Bool { authorized }
}
#endif
