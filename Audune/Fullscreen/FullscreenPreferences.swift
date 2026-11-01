import Foundation

nonisolated enum FullscreenPreferenceKey {
    static let isEnabled = "fullscreen.isEnabled"
    static let lyricsNetworkEnabled = "fullscreen.lyricsNetworkEnabled"
}

/// Experimental Fullscreen Player preferences. Missing keys preserve defaults (feature off, no network lyrics).
nonisolated struct FullscreenPreferences: Equatable, Sendable {
    /// Master switch: allow opening the Fullscreen Player surface.
    var isEnabled: Bool
    /// When true, LyricsService may HTTPS-query LRCLIB with title/artist metadata only.
    var lyricsNetworkEnabled: Bool

    static let standard = FullscreenPreferences(
        isEnabled: false,
        lyricsNetworkEnabled: false
    )

    static func load(from defaults: UserDefaults = .standard) -> FullscreenPreferences {
        let enabled: Bool
        if defaults.object(forKey: FullscreenPreferenceKey.isEnabled) != nil {
            enabled = defaults.bool(forKey: FullscreenPreferenceKey.isEnabled)
        } else {
            enabled = standard.isEnabled
        }
        let lyrics: Bool
        if defaults.object(forKey: FullscreenPreferenceKey.lyricsNetworkEnabled) != nil {
            lyrics = defaults.bool(forKey: FullscreenPreferenceKey.lyricsNetworkEnabled)
        } else {
            lyrics = standard.lyricsNetworkEnabled
        }
        return FullscreenPreferences(isEnabled: enabled, lyricsNetworkEnabled: lyrics).normalized()
    }

    func normalized() -> FullscreenPreferences {
        self
    }

    func save(to defaults: UserDefaults = .standard) {
        let normalized = normalized()
        defaults.set(normalized.isEnabled, forKey: FullscreenPreferenceKey.isEnabled)
        defaults.set(normalized.lyricsNetworkEnabled, forKey: FullscreenPreferenceKey.lyricsNetworkEnabled)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        standard.save(to: defaults)
    }
}
