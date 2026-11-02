import Foundation

nonisolated enum FullscreenPreferenceKey {
    static let isEnabled = "fullscreen.isEnabled"
    static let lyricsNetworkEnabled = "fullscreen.lyricsNetworkEnabled"
    static let lyricsSource = "fullscreen.lyricsSource"
}

/// Experimental Fullscreen Player preferences. Missing keys preserve defaults (feature off, no network lyrics).
nonisolated struct FullscreenPreferences: Equatable, Sendable {
    /// Master switch: allow opening the Fullscreen Player surface.
    var isEnabled: Bool
    /// When true, LyricsService may HTTPS-query LRCLIB with title/artist metadata only.
    var lyricsNetworkEnabled: Bool
    /// Automatic races enabled providers; an explicit choice queries only that source.
    var lyricsSource: LyricsSourceSelection

    init(
        isEnabled: Bool,
        lyricsNetworkEnabled: Bool,
        lyricsSource: LyricsSourceSelection = .automatic
    ) {
        self.isEnabled = isEnabled
        self.lyricsNetworkEnabled = lyricsNetworkEnabled
        self.lyricsSource = lyricsSource
    }

    static let standard = FullscreenPreferences(
        isEnabled: false,
        lyricsNetworkEnabled: false,
        lyricsSource: .automatic
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
        let source = defaults.string(forKey: FullscreenPreferenceKey.lyricsSource)
            .flatMap(LyricsSourceSelection.init(rawValue:))
            ?? standard.lyricsSource
        return FullscreenPreferences(
            isEnabled: enabled,
            lyricsNetworkEnabled: lyrics,
            lyricsSource: source
        ).normalized()
    }

    func normalized() -> FullscreenPreferences {
        self
    }

    func save(to defaults: UserDefaults = .standard) {
        let normalized = normalized()
        defaults.set(normalized.isEnabled, forKey: FullscreenPreferenceKey.isEnabled)
        defaults.set(normalized.lyricsNetworkEnabled, forKey: FullscreenPreferenceKey.lyricsNetworkEnabled)
        defaults.set(normalized.lyricsSource.rawValue, forKey: FullscreenPreferenceKey.lyricsSource)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        standard.save(to: defaults)
    }
}
