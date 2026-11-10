import Foundation

/// Highest sync precision a provider can return for some tracks.
/// Actual documents still derive sync level from real timing data.
nonisolated enum LyricsSyncLevelCapability: String, Codable, Equatable, Sendable, CaseIterable {
    case unsynced
    case line
    case word
    case syllable
}

nonisolated enum LyricsProviderFormat: String, Codable, Equatable, Sendable, CaseIterable {
    case plain
    case lrc
    case enhancedLRC
    case lyricsfile
    case ttml
    case qrc
    case yrc
    case krc
    case lyricsfileYAML
    case jsonTimed
}

nonisolated enum LyricsProviderType: String, Codable, Equatable, Sendable {
    case direct
    case aggregator
}

nonisolated enum LyricsCachePolicy: String, Codable, Equatable, Sendable {
    /// Online results stay in memory for the current session only.
    case sessionOnly
    /// Provider terms allow a bounded on-disk TTL (not used unless explicitly wired).
    case persistentTTL
    /// User-imported local lyrics.
    case localPersistent
}

nonisolated enum LyricsProviderEnablement: String, Codable, Equatable, Sendable {
    /// Reviewed, measured, and eligible for Auto routing by default.
    case enabled
    /// Adapter may exist, but Auto must not select it.
    case experimental
    /// Registered for tracking only; not shown as selectable.
    case candidate
    /// Intentionally off (license, outage, missing key, etc.).
    case disabled
}

nonisolated enum LyricsProviderRegionHint: String, Codable, Equatable, Sendable, CaseIterable {
    case international
    case china
    case global
}

/// Static capability card for one lyrics source. Nodes are separate.
nonisolated struct LyricsProviderCapability: Equatable, Sendable, Identifiable {
    var id: String
    var displayName: String
    var providerType: LyricsProviderType
    var region: LyricsProviderRegionHint
    var supportedSyncLevels: [LyricsSyncLevelCapability]
    var supportedFormats: [LyricsProviderFormat]
    var requiresAPIKey: Bool
    var requiresAttribution: Bool
    var supportsISRC: Bool
    var supportsSearchByTitle: Bool
    var supportsAlbum: Bool
    var supportsDuration: Bool
    var supportsTranslations: Bool
    var supportsMultipleCandidates: Bool
    var rateLimitSummary: String
    var termsURL: URL?
    var documentationURL: URL?
    var healthEndpoint: URL?
    var attributionURL: URL?
    var cachePolicy: LyricsCachePolicy
    var enablement: LyricsProviderEnablement
    var enabledByDefault: Bool
    var auditNotes: String
    var defaultNodes: [LyricsNodeDescriptor]

    var highestSyncLevel: LyricsSyncLevelCapability {
        let order: [LyricsSyncLevelCapability] = [.syllable, .word, .line, .unsynced]
        return order.first { supportedSyncLevels.contains($0) } ?? .unsynced
    }
}

/// One network endpoint / mirror for a provider.
nonisolated struct LyricsNodeDescriptor: Equatable, Sendable, Identifiable, Codable {
    var id: String
    var providerID: String
    var displayName: String
    var baseURL: URL
    var regionHint: LyricsProviderRegionHint?
    var attributionURL: URL?
    var termsURL: URL?
    var enabled: Bool
    var isCustom: Bool

    init(
        id: String,
        providerID: String,
        displayName: String,
        baseURL: URL,
        regionHint: LyricsProviderRegionHint? = nil,
        attributionURL: URL? = nil,
        termsURL: URL? = nil,
        enabled: Bool = true,
        isCustom: Bool = false
    ) {
        self.id = id
        self.providerID = providerID
        self.displayName = displayName
        self.baseURL = baseURL
        self.regionHint = regionHint
        self.attributionURL = attributionURL
        self.termsURL = termsURL
        self.enabled = enabled
        self.isCustom = isCustom
    }
}
