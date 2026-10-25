import Foundation
#if os(macOS)
import AppKit
#endif

/// Trackpad pattern choice. macOS exposes three patterns, not an amplitude control.
nonisolated enum IslandHapticStrength: String, CaseIterable, Identifiable, Sendable {
    case off
    case light
    case medium
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }

    #if os(macOS)
    /// Light, Medium, and Strong map to Alignment, Generic, and Level Change.
    /// Those patterns feel different; they do not set a hardware amplitude.
    var feedbackPattern: NSHapticFeedbackManager.FeedbackPattern? {
        switch self {
        case .off:
            return nil
        case .light:
            return .alignment
        case .medium:
            return .generic
        case .strong:
            return .levelChange
        }
    }
    #endif
}

nonisolated enum IslandHapticCue {
    #if os(macOS)
    static func pattern(
        from previous: IslandPresentationState,
        to next: IslandPresentationState,
        strength: IslandHapticStrength
    ) -> NSHapticFeedbackManager.FeedbackPattern? {
        guard previous == .compact, next == .expanded else { return nil }
        return strength.feedbackPattern
    }
    #endif
}

#if os(macOS)
protocol IslandHapticPerforming: AnyObject {
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern)
}

/// Calls the public performer. Hardware without a Force Touch trackpad ignores it.
final class SystemIslandHaptics: IslandHapticPerforming {
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
#endif
