import Foundation

nonisolated enum IslandPreferenceKey {
    static let isEnabled = "island.isEnabled"
    static let targetScreenID = "island.targetScreenID"
    static let mode = "island.mode"
    static let hoverToExpand = "island.hoverToExpand"
    static let collapseDelaySeconds = "island.collapseDelaySeconds"
    static let expandDelaySeconds = "island.expandDelaySeconds"
    static let hapticStrength = "island.hapticStrength"
    static let animationSpeed = "island.animationSpeed"
    static let compactBarCountPerSide = "island.compactBarCountPerSide"
    static let showsInFullScreen = "island.showsInFullScreen"
    static let followsReduceMotion = "island.followsReduceMotion"
    static let nowPlayingEnabled = "island.nowPlayingEnabled"
    static let lyricsEnabled = "island.lyricsEnabled"
    static let automaticOnlineLyrics = "island.automaticOnlineLyrics"
    static let lyricsBlurEnabled = "island.lyricsBlurEnabled"
    static let lyricsOffsetSeconds = "island.lyricsOffsetSeconds"
    static let lyricsRoutingMode = "island.lyricsRoutingMode"
    static let lyricsManualProviderID = "island.lyricsManualProviderID"
    static let lyricsManualNodeID = "island.lyricsManualNodeID"
    static let showsLyricsTranslation = "island.showsLyricsTranslation"
    static let showsLyricsPronunciation = "island.showsLyricsPronunciation"
    static let showArtwork = "island.nowPlayingLayout.showArtwork"
    static let showTitleArtist = "island.nowPlayingLayout.showTitleArtist"
    static let showProgress = "island.nowPlayingLayout.showProgress"
    static let showTransport = "island.nowPlayingLayout.showTransport"
    static let showVisualization = "island.nowPlayingLayout.showVisualization"
}

/// Expanded Now Playing chrome visibility. Does not change Compact wings.
nonisolated struct IslandNowPlayingLayout: Equatable, Sendable {
    var showArtwork: Bool
    var showTitleArtist: Bool
    var showProgress: Bool
    var showTransport: Bool
    var showVisualization: Bool

    static let standard = IslandNowPlayingLayout(
        showArtwork: true,
        showTitleArtist: true,
        showProgress: true,
        showTransport: true,
        showVisualization: true
    )

    /// True when at least one player-chrome element is visible.
    var showsAnyChrome: Bool {
        showArtwork || showTitleArtist || showProgress || showTransport
    }

    var showsFullScreenMetadata: Bool {
        showArtwork || showTitleArtist
    }
}

nonisolated struct IslandPreferences: Equatable, Sendable {
    var isEnabled: Bool
    var targetScreenID: String
    var mode: StudioVisualMode
    var hoverToExpand: Bool
    var collapseDelaySeconds: Double
    var expandDelaySeconds: Double
    var hapticStrength: IslandHapticStrength
    var animationSpeed: Double
    var compactBarCountPerSide: Int
    var showsInFullScreen: Bool
    var followsReduceMotion: Bool
    /// Experimental system Now Playing in Expanded/Pinned. Default off. Does not change Expanded frame size.
    var nowPlayingEnabled: Bool
    /// Fullscreen Lyrics scene. Experimental and opt-in.
    var lyricsEnabled: Bool
    /// Lyrics Scene may query the reviewed online provider automatically for the current song.
    var automaticOnlineLyricsEnabled: Bool
    /// Blur non-focus lyric lines. The active line stays sharp when this is off.
    var lyricsBlurEnabled: Bool
    /// Shifts the lyric timeline relative to playback. Positive values show lyrics later.
    var lyricsOffsetSeconds: Double
    /// Multi-source lyrics routing mode (Auto Fastest / Auto Best Match / Manual).
    var lyricsRoutingMode: LyricsRoutingMode
    /// Manual provider id when `lyricsRoutingMode == .manual`.
    var lyricsManualProviderID: String
    /// Manual node id for providers that expose multiple nodes.
    var lyricsManualNodeID: String
    /// Whether translated lyric lines are shown beneath the main text when available.
    var showsLyricsTranslation: Bool = true
    /// Whether romanized / phonetic pronunciation lines are shown when available.
    var showsLyricsPronunciation: Bool = true
    /// Which Expanded Now Playing chrome pieces are shown when listening.
    var nowPlayingLayout: IslandNowPlayingLayout

    var lyricsRoutingSelection: LyricsRoutingSelection {
        LyricsRoutingSelection(
            mode: lyricsRoutingMode,
            providerID: lyricsManualProviderID.isEmpty ? nil : lyricsManualProviderID,
            nodeID: lyricsManualNodeID.isEmpty ? nil : lyricsManualNodeID
        )
    }

    static let collapseDelayRange: ClosedRange<Double> = 0.15...1.5
    static let expandDelayRange: ClosedRange<Double> = 0.1...1.0
    static let animationSpeedRange: ClosedRange<Double> = 0.5...2.0
    static let lyricsOffsetRange: ClosedRange<Double> = -5.0...5.0
    static let compactBarCounts = IslandGeometry.compactBarCounts

    static let standard = IslandPreferences(
        isEnabled: true,
        targetScreenID: "",
        mode: .spectrum,
        hoverToExpand: true,
        collapseDelaySeconds: 0.35,
        expandDelaySeconds: 0.35,
        hapticStrength: .off,
        animationSpeed: 1,
        compactBarCountPerSide: 5,
        showsInFullScreen: false,
        followsReduceMotion: true,
        nowPlayingEnabled: false,
        lyricsEnabled: false,
        automaticOnlineLyricsEnabled: true,
        lyricsBlurEnabled: true,
        lyricsOffsetSeconds: 0,
        lyricsRoutingMode: .autoBestMatch,
        lyricsManualProviderID: "",
        lyricsManualNodeID: "",
        nowPlayingLayout: .standard
    )

    var targetScreenMode: IslandTargetScreenMode {
        IslandTargetScreenMode(storedID: targetScreenID)
    }

    static func load(from defaults: UserDefaults = .standard) -> IslandPreferences {
        let standard = Self.standard
        let isEnabled = defaults.object(forKey: IslandPreferenceKey.isEnabled) == nil
            ? standard.isEnabled
            : defaults.bool(forKey: IslandPreferenceKey.isEnabled)
        let targetScreenID = defaults.string(forKey: IslandPreferenceKey.targetScreenID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? standard.targetScreenID
        let mode = defaults.string(forKey: IslandPreferenceKey.mode)
            .flatMap(StudioVisualMode.init(rawValue:)) ?? standard.mode
        let hoverToExpand = defaults.object(forKey: IslandPreferenceKey.hoverToExpand) == nil
            ? standard.hoverToExpand
            : defaults.bool(forKey: IslandPreferenceKey.hoverToExpand)
        let collapseDelay: Double
        if defaults.object(forKey: IslandPreferenceKey.collapseDelaySeconds) != nil {
            collapseDelay = StudioPreferences.clamped(
                defaults.double(forKey: IslandPreferenceKey.collapseDelaySeconds),
                to: collapseDelayRange,
                fallback: standard.collapseDelaySeconds
            )
        } else {
            collapseDelay = standard.collapseDelaySeconds
        }
        let expandDelay: Double
        if defaults.object(forKey: IslandPreferenceKey.expandDelaySeconds) != nil {
            expandDelay = StudioPreferences.clamped(
                defaults.double(forKey: IslandPreferenceKey.expandDelaySeconds),
                to: expandDelayRange,
                fallback: standard.expandDelaySeconds
            )
        } else {
            expandDelay = standard.expandDelaySeconds
        }
        let hapticStrength = defaults.string(forKey: IslandPreferenceKey.hapticStrength)
            .flatMap(IslandHapticStrength.init(rawValue:)) ?? standard.hapticStrength
        let animationSpeed: Double
        if defaults.object(forKey: IslandPreferenceKey.animationSpeed) != nil {
            animationSpeed = StudioPreferences.clamped(
                defaults.double(forKey: IslandPreferenceKey.animationSpeed),
                to: animationSpeedRange,
                fallback: standard.animationSpeed
            )
        } else {
            animationSpeed = standard.animationSpeed
        }
        let compactBarCount: Int
        if defaults.object(forKey: IslandPreferenceKey.compactBarCountPerSide) != nil {
            let stored = defaults.integer(forKey: IslandPreferenceKey.compactBarCountPerSide)
            compactBarCount = compactBarCounts.contains(stored) ? stored : standard.compactBarCountPerSide
        } else {
            compactBarCount = standard.compactBarCountPerSide
        }
        let showsInFullScreen = defaults.object(forKey: IslandPreferenceKey.showsInFullScreen) == nil
            ? standard.showsInFullScreen
            : defaults.bool(forKey: IslandPreferenceKey.showsInFullScreen)
        let followsReduceMotion = defaults.object(forKey: IslandPreferenceKey.followsReduceMotion) == nil
            ? standard.followsReduceMotion
            : defaults.bool(forKey: IslandPreferenceKey.followsReduceMotion)
        let nowPlayingEnabled = defaults.object(forKey: IslandPreferenceKey.nowPlayingEnabled) == nil
            ? standard.nowPlayingEnabled
            : defaults.bool(forKey: IslandPreferenceKey.nowPlayingEnabled)
        let lyricsEnabled = defaults.object(forKey: IslandPreferenceKey.lyricsEnabled) == nil
            ? standard.lyricsEnabled
            : defaults.bool(forKey: IslandPreferenceKey.lyricsEnabled)
        let automaticOnlineLyricsEnabled = defaults.object(forKey: IslandPreferenceKey.automaticOnlineLyrics) == nil
            ? standard.automaticOnlineLyricsEnabled
            : defaults.bool(forKey: IslandPreferenceKey.automaticOnlineLyrics)
        let lyricsBlurEnabled = defaults.object(forKey: IslandPreferenceKey.lyricsBlurEnabled) == nil
            ? standard.lyricsBlurEnabled
            : defaults.bool(forKey: IslandPreferenceKey.lyricsBlurEnabled)
        let lyricsOffsetSeconds: Double
        if defaults.object(forKey: IslandPreferenceKey.lyricsOffsetSeconds) != nil {
            lyricsOffsetSeconds = StudioPreferences.clamped(
                defaults.double(forKey: IslandPreferenceKey.lyricsOffsetSeconds),
                to: lyricsOffsetRange,
                fallback: standard.lyricsOffsetSeconds
            )
        } else {
            lyricsOffsetSeconds = standard.lyricsOffsetSeconds
        }
        let lyricsRoutingMode = defaults.string(forKey: IslandPreferenceKey.lyricsRoutingMode)
            .flatMap(LyricsRoutingMode.init(rawValue:)) ?? standard.lyricsRoutingMode
        let lyricsManualProviderID = defaults.string(forKey: IslandPreferenceKey.lyricsManualProviderID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? standard.lyricsManualProviderID
        let lyricsManualNodeID = defaults.string(forKey: IslandPreferenceKey.lyricsManualNodeID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? standard.lyricsManualNodeID
        let showsLyricsTranslation = defaults.object(forKey: IslandPreferenceKey.showsLyricsTranslation) == nil
            ? standard.showsLyricsTranslation
            : defaults.bool(forKey: IslandPreferenceKey.showsLyricsTranslation)
        let showsLyricsPronunciation = defaults.object(forKey: IslandPreferenceKey.showsLyricsPronunciation) == nil
            ? standard.showsLyricsPronunciation
            : defaults.bool(forKey: IslandPreferenceKey.showsLyricsPronunciation)
        let nowPlayingLayout = IslandNowPlayingLayout(
            showArtwork: defaults.object(forKey: IslandPreferenceKey.showArtwork) == nil
                ? standard.nowPlayingLayout.showArtwork
                : defaults.bool(forKey: IslandPreferenceKey.showArtwork),
            showTitleArtist: defaults.object(forKey: IslandPreferenceKey.showTitleArtist) == nil
                ? standard.nowPlayingLayout.showTitleArtist
                : defaults.bool(forKey: IslandPreferenceKey.showTitleArtist),
            showProgress: defaults.object(forKey: IslandPreferenceKey.showProgress) == nil
                ? standard.nowPlayingLayout.showProgress
                : defaults.bool(forKey: IslandPreferenceKey.showProgress),
            showTransport: defaults.object(forKey: IslandPreferenceKey.showTransport) == nil
                ? standard.nowPlayingLayout.showTransport
                : defaults.bool(forKey: IslandPreferenceKey.showTransport),
            showVisualization: defaults.object(forKey: IslandPreferenceKey.showVisualization) == nil
                ? standard.nowPlayingLayout.showVisualization
                : defaults.bool(forKey: IslandPreferenceKey.showVisualization)
        )

        return IslandPreferences(
            isEnabled: isEnabled,
            targetScreenID: targetScreenID,
            mode: mode,
            hoverToExpand: hoverToExpand,
            collapseDelaySeconds: collapseDelay,
            expandDelaySeconds: expandDelay,
            hapticStrength: hapticStrength,
            animationSpeed: animationSpeed,
            compactBarCountPerSide: compactBarCount,
            showsInFullScreen: showsInFullScreen,
            followsReduceMotion: followsReduceMotion,
            nowPlayingEnabled: nowPlayingEnabled,
            lyricsEnabled: lyricsEnabled,
            automaticOnlineLyricsEnabled: automaticOnlineLyricsEnabled,
            lyricsBlurEnabled: lyricsBlurEnabled,
            lyricsOffsetSeconds: lyricsOffsetSeconds,
            lyricsRoutingMode: lyricsRoutingMode,
            lyricsManualProviderID: lyricsManualProviderID,
            lyricsManualNodeID: lyricsManualNodeID,
            showsLyricsTranslation: showsLyricsTranslation,
            showsLyricsPronunciation: showsLyricsPronunciation,
            nowPlayingLayout: nowPlayingLayout
        ).normalized()
    }

    func normalized() -> IslandPreferences {
        var result = self
        let standard = Self.standard
        result.targetScreenID = targetScreenID.trimmingCharacters(in: .whitespacesAndNewlines)
        result.collapseDelaySeconds = StudioPreferences.clamped(
            collapseDelaySeconds,
            to: Self.collapseDelayRange,
            fallback: standard.collapseDelaySeconds
        )
        result.expandDelaySeconds = StudioPreferences.clamped(
            expandDelaySeconds,
            to: Self.expandDelayRange,
            fallback: standard.expandDelaySeconds
        )
        result.animationSpeed = StudioPreferences.clamped(
            animationSpeed,
            to: Self.animationSpeedRange,
            fallback: standard.animationSpeed
        )
        result.compactBarCountPerSide = Self.compactBarCounts.contains(compactBarCountPerSide)
            ? compactBarCountPerSide
            : standard.compactBarCountPerSide
        result.lyricsOffsetSeconds = StudioPreferences.clamped(
            lyricsOffsetSeconds,
            to: Self.lyricsOffsetRange,
            fallback: standard.lyricsOffsetSeconds
        )
        result.lyricsManualProviderID = lyricsManualProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        result.lyricsManualNodeID = lyricsManualNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.lyricsRoutingMode == .manual, result.lyricsManualProviderID.isEmpty {
            result.lyricsRoutingMode = .autoBestMatch
        }
        return result
    }

    func save(to defaults: UserDefaults = .standard) {
        let normalized = self.normalized()
        defaults.set(normalized.isEnabled, forKey: IslandPreferenceKey.isEnabled)
        if normalized.targetScreenID.isEmpty {
            defaults.removeObject(forKey: IslandPreferenceKey.targetScreenID)
        } else {
            defaults.set(normalized.targetScreenID, forKey: IslandPreferenceKey.targetScreenID)
        }
        defaults.set(normalized.mode.rawValue, forKey: IslandPreferenceKey.mode)
        defaults.set(normalized.hoverToExpand, forKey: IslandPreferenceKey.hoverToExpand)
        defaults.set(normalized.collapseDelaySeconds, forKey: IslandPreferenceKey.collapseDelaySeconds)
        defaults.set(normalized.expandDelaySeconds, forKey: IslandPreferenceKey.expandDelaySeconds)
        defaults.set(normalized.hapticStrength.rawValue, forKey: IslandPreferenceKey.hapticStrength)
        defaults.set(normalized.animationSpeed, forKey: IslandPreferenceKey.animationSpeed)
        defaults.set(normalized.compactBarCountPerSide, forKey: IslandPreferenceKey.compactBarCountPerSide)
        defaults.set(normalized.showsInFullScreen, forKey: IslandPreferenceKey.showsInFullScreen)
        defaults.set(normalized.followsReduceMotion, forKey: IslandPreferenceKey.followsReduceMotion)
        defaults.set(normalized.nowPlayingEnabled, forKey: IslandPreferenceKey.nowPlayingEnabled)
        defaults.set(normalized.lyricsEnabled, forKey: IslandPreferenceKey.lyricsEnabled)
        defaults.set(normalized.automaticOnlineLyricsEnabled, forKey: IslandPreferenceKey.automaticOnlineLyrics)
        defaults.set(normalized.lyricsBlurEnabled, forKey: IslandPreferenceKey.lyricsBlurEnabled)
        defaults.set(normalized.lyricsOffsetSeconds, forKey: IslandPreferenceKey.lyricsOffsetSeconds)
        defaults.set(normalized.lyricsRoutingMode.rawValue, forKey: IslandPreferenceKey.lyricsRoutingMode)
        if normalized.lyricsManualProviderID.isEmpty {
            defaults.removeObject(forKey: IslandPreferenceKey.lyricsManualProviderID)
        } else {
            defaults.set(normalized.lyricsManualProviderID, forKey: IslandPreferenceKey.lyricsManualProviderID)
        }
        if normalized.lyricsManualNodeID.isEmpty {
            defaults.removeObject(forKey: IslandPreferenceKey.lyricsManualNodeID)
        } else {
            defaults.set(normalized.lyricsManualNodeID, forKey: IslandPreferenceKey.lyricsManualNodeID)
        }
        defaults.set(normalized.showsLyricsTranslation, forKey: IslandPreferenceKey.showsLyricsTranslation)
        defaults.set(normalized.showsLyricsPronunciation, forKey: IslandPreferenceKey.showsLyricsPronunciation)
        defaults.set(normalized.nowPlayingLayout.showArtwork, forKey: IslandPreferenceKey.showArtwork)
        defaults.set(normalized.nowPlayingLayout.showTitleArtist, forKey: IslandPreferenceKey.showTitleArtist)
        defaults.set(normalized.nowPlayingLayout.showProgress, forKey: IslandPreferenceKey.showProgress)
        defaults.set(normalized.nowPlayingLayout.showTransport, forKey: IslandPreferenceKey.showTransport)
        defaults.set(normalized.nowPlayingLayout.showVisualization, forKey: IslandPreferenceKey.showVisualization)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        standard.save(to: defaults)
    }
}
