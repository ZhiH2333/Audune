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
    static let applicationNotRunning = -600

    static func availability(status: Int) -> PlayerAvailability {
        switch status {
        case automationDenied:
            return .automationDenied
        case applicationNotRunning:
            return .notRunning
        default:
            return .failed("Apple Event \(status)")
        }
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

    static func title(availability: PlayerAvailability, state: PlayerPlaybackState) -> String {
        switch availability {
        case .noSelection:
            return "Player"
        case .notInstalled:
            return "Missing"
        case .notRunning:
            return "Not running"
        case .automationDenied:
            return "Denied"
        case .failed:
            return "Failed"
        case .ready:
            switch state {
            case .playing:
                return "Pause"
            case .paused, .stopped:
                return "Play"
            case .unknown:
                return "Play/Pause"
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
    static func run(application name: String, source body: String) -> PlayerCommandResult {
        let source = "tell application \"\(name)\"\n\(body)\nend tell"
        guard let script = NSAppleScript(source: source) else {
            return .failed("The play command could not be prepared.")
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
            return .failed("The player did not return a state.")
        }
        let state = PlayerStateText.parse(text)
        guard state != .unknown else {
            return .failed("The player returned an unrecognized state.")
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
        return AppleScriptPlayer.run(application: "Music", source: "return player state as string")
    }

    func togglePlayPause() -> PlayerCommandResult {
        let gate = availability()
        guard gate == .ready else { return .unavailable(gate) }
        return AppleScriptPlayer.run(
            application: "Music",
            source: "playpause\nreturn player state as string"
        )
    }
}
#endif
