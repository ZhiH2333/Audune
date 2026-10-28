#if os(macOS)
import AppKit
import Foundation

/// Controls one external player. This is not `MPRemoteCommandCenter`:
/// that API only lets the current app receive remote commands.
enum PlayerAvailability: Equatable {
    case noSelection
    case ready
    case notInstalled
    case notRunning
    /// Installed and running; the Automation permission is still being looked up off the main thread.
    case checking
    /// macOS has not asked yet. The user has to choose "Request Access"; polling never prompts.
    case automationNotRequested
    case automationDenied
    case failed(String)
}

enum PlayerPlaybackState: Equatable {
    case playing
    case paused
    case stopped
    case unknown
}

enum PlayerCommandResult: Equatable {
    case state(PlayerPlaybackState)
    case unavailable(PlayerAvailability)
    case failed(String)
}

struct PlayerChoice: Identifiable, Equatable {
    var id: String
    var title: String
}

enum PlayerSelectionKey {
    static let selected = "studio.player"
}

enum AppleEventFailure {
    static let automationDenied = -1743
    static let wouldRequireConsent = -1744
    static let applicationNotRunning = -600
    static let timedOut = -1712

    static func availability(status: Int) -> PlayerAvailability {
        switch status {
        case automationDenied:
            return .automationDenied
        case wouldRequireConsent:
            return .automationNotRequested
        case applicationNotRunning:
            return .notRunning
        case timedOut:
            return .failed(String(localized: "The player did not answer in time."))
        default:
            return .failed(String(localized: "Apple Event \(status)"))
        }
    }
}

/// The result of asking macOS whether Audune may send Apple Events to one player.
enum AutomationPermission: Equatable {
    case granted
    case notRequested
    case denied
    case targetNotRunning
    case failed(Int)

    /// Maps the `OSStatus` from `AEDeterminePermissionToAutomateTarget`.
    static func from(status: Int) -> AutomationPermission {
        switch status {
        case 0: return .granted
        case AppleEventFailure.wouldRequireConsent: return .notRequested
        case AppleEventFailure.automationDenied: return .denied
        case AppleEventFailure.applicationNotRunning: return .targetNotRunning
        default: return .failed(status)
        }
    }

    var availability: PlayerAvailability {
        switch self {
        case .granted: return .ready
        case .notRequested: return .automationNotRequested
        case .denied: return .automationDenied
        case .targetNotRunning: return .notRunning
        case .failed(let status): return .failed(String(localized: "Apple Event \(status)"))
        }
    }
}

enum AutomationPermissionCheck {
    /// Public API from `ApplicationServices`. With `askUserIfNeeded` false it never shows a prompt and
    /// does not send an event. Even so, it can wait on the system permission service and hung the main thread
    /// at launch in testing, so every call must run off the main thread. With true it may wait for the user.
    nonisolated static func determine(bundleIdentifier: String, askUserIfNeeded: Bool) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let address = target.aeDesc else { return .failed(-1) }
        let status = AEDeterminePermissionToAutomateTarget(
            address,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
        return AutomationPermission.from(status: Int(status))
    }
}

enum PlayerStateText {
    static func parse(_ text: String) -> PlayerPlaybackState {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "kPSP", "kPSF", "kPSR":
            return .playing
        case "kPSp":
            return .paused
        case "kPSS":
            return .stopped
        default:
            break
        }
        switch trimmed.lowercased() {
        case "playing", "fast forwarding", "rewinding":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        default:
            return .unknown
        }
    }
}

enum PlaybackButton {
    static func isEnabled(selection: String, availability: PlayerAvailability, busy: Bool) -> Bool {
        guard busy == false, selection.isEmpty == false else { return false }
        return availability == .ready
    }

    static func symbol(availability: PlayerAvailability, state: PlayerPlaybackState) -> String {
        switch availability {
        case .ready:
            return state == .playing ? "pause.fill" : "play.fill"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .failed, .automationDenied:
            return "exclamationmark.triangle"
        default:
            return "play.fill"
        }
    }

    static func title(availability: PlayerAvailability, state: PlayerPlaybackState) -> String {
        switch availability {
        case .noSelection:
            return String(localized: "Player")
        case .notInstalled:
            return String(localized: "Missing")
        case .notRunning:
            return String(localized: "Not running")
        case .checking:
            return String(localized: "Checking")
        case .automationNotRequested:
            return String(localized: "Needs access")
        case .automationDenied:
            return String(localized: "Denied")
        case .failed:
            return String(localized: "Failed")
        case .ready:
            switch state {
            case .playing:
                return String(localized: "Pause")
            case .paused, .stopped:
                return String(localized: "Play")
            case .unknown:
                return String(localized: "Play/Pause")
            }
        }
    }
}

@MainActor
protocol PlayerControlling: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var bundleIdentifier: String { get }
    func availability() -> PlayerAvailability
    func playbackState() -> PlayerCommandResult
    func togglePlayPause() -> PlayerCommandResult
}

enum AppleScriptPlayer {
    /// Installed and running only. It never calls the Automation permission API; the caller does that off the main thread.
    static func availability(bundleIdentifier: String) -> PlayerAvailability {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil else {
            return .notInstalled
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false else {
            return .notRunning
        }
        return .ready
    }

    /// Sends one Apple Event on the main actor. Callers must not use this from the audio callback.
    /// Callers only reach this after the permission preflight says `.ready`; the timeout keeps a stuck player from freezing the UI.
    static func run(bundleIdentifier: String, source body: String) -> PlayerCommandResult {
        let source = "with timeout of 2 seconds\ntell application id \"\(bundleIdentifier)\"\n\(body)\nend tell\nend timeout"
        guard let script = NSAppleScript(source: source) else {
            return .failed(String(localized: "The play command could not be prepared."))
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let status = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                ?? (error[NSAppleScript.errorNumber] as? Int)
                ?? 0
            let availability = AppleEventFailure.availability(status: status)
            if case .failed(let message) = availability {
                return .failed(message)
            }
            return .unavailable(availability)
        }
        let text = descriptor.stringValue ?? ""
        guard text.isEmpty == false else {
            return .failed(String(localized: "The player did not return a state."))
        }
        let state = PlayerStateText.parse(text)
        guard state != .unknown else {
            return .failed(String(localized: "The player returned an unrecognized state."))
        }
        return .state(state)
    }
}

@MainActor
final class MusicPlayerController: PlayerControlling {
    let id = "music"
    let displayName = "Music"
    let bundleIdentifier = "com.apple.Music"

    func availability() -> PlayerAvailability {
        AppleScriptPlayer.availability(bundleIdentifier: bundleIdentifier)
    }

    func playbackState() -> PlayerCommandResult {
        let gate = availability()
        guard gate == .ready else { return .unavailable(gate) }
        return AppleScriptPlayer.run(bundleIdentifier: bundleIdentifier, source: "return player state as string")
    }

    func togglePlayPause() -> PlayerCommandResult {
        let gate = availability()
        guard gate == .ready else { return .unavailable(gate) }
        return AppleScriptPlayer.run(
            bundleIdentifier: bundleIdentifier,
            source: "playpause\nreturn player state as string"
        )
    }
}

@MainActor
final class SpotifyPlayerController: PlayerControlling {
    let id = "spotify"
    let displayName = "Spotify"
    let bundleIdentifier = "com.spotify.client"

    func availability() -> PlayerAvailability {
        AppleScriptPlayer.availability(bundleIdentifier: bundleIdentifier)
    }

    func playbackState() -> PlayerCommandResult {
        let gate = availability()
        guard gate == .ready else { return .unavailable(gate) }
        return AppleScriptPlayer.run(bundleIdentifier: bundleIdentifier, source: "return player state as string")
    }

    func togglePlayPause() -> PlayerCommandResult {
        let gate = availability()
        guard gate == .ready else { return .unavailable(gate) }
        return AppleScriptPlayer.run(
            bundleIdentifier: bundleIdentifier,
            source: "playpause\nreturn player state as string"
        )
    }
}
#endif
