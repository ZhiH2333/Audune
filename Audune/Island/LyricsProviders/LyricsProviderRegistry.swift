import Foundation

/// Canonical IDs for reviewed lyrics providers. Upstream IDs inside an aggregator response
/// are attribution only and must not be treated as selectable Audune nodes.
nonisolated enum LyricsProviderID: String, CaseIterable, Equatable, Sendable {
    case lrclib
    case liriqo
    case lrcmux
    case betterLyrics = "betterlyrics"
    case lrcRed = "lrcred"
    case lyricsOvh = "lyricsovh"
    case meting
    case netease
    case qqMusic = "qqmusic"
    case kugou
    case lrcShare = "lrcshare"
    case lrcAPI = "lrcapi"
    case vvhan
}

/// Static registry built from the audited provider matrix in docs/LYRICS_PROVIDER_AUDIT.md.
nonisolated enum LyricsProviderRegistry {
    static let auditedAt = "2026-11-10"

    static var all: [LyricsProviderCapability] {
        [
            lrclib,
            liriqo,
            lrcmux,
            betterLyrics,
            lrcRed,
            lyricsOvh,
            meting,
            netease,
            qqMusic,
            kugou,
            lrcShare,
            lrcAPI,
            vvhan,
        ]
    }

    static func capability(id: String) -> LyricsProviderCapability? {
        all.first { $0.id == id }
    }

    static func capability(_ id: LyricsProviderID) -> LyricsProviderCapability {
        capability(id: id.rawValue)!
    }

    /// Providers that may appear in Auto routing.
    static var defaultAutoProviders: [LyricsProviderCapability] {
        all.filter { $0.enabledByDefault && $0.enablement == .enabled }
    }

    /// Providers that may appear in the manual selector (enabled + experimental with UI).
    static var selectableProviders: [LyricsProviderCapability] {
        all.filter {
            $0.enablement == .enabled || $0.enablement == .experimental
        }
    }

    // MARK: - Catalog

    static let lrclib = LyricsProviderCapability(
        id: LyricsProviderID.lrclib.rawValue,
        displayName: "LRCLIB",
        providerType: .direct,
        region: .international,
        supportedSyncLevels: [.unsynced, .line, .word],
        supportedFormats: [.plain, .lrc, .lyricsfile],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: true,
        supportsDuration: true,
        supportsTranslations: false,
        supportsMultipleCandidates: true,
        rateLimitSummary: "Space requests; honor 429 Retry-After; bounded 503 retry",
        termsURL: URL(string: "https://lrclib.net"),
        documentationURL: URL(string: "https://lrclib.net/docs"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://lrclib.net"),
        cachePolicy: .sessionOnly,
        enablement: .enabled,
        enabledByDefault: true,
        auditNotes: "Verified 2026-11-10: /api/get and /api/search return synced lyrics for EN/CN samples. Session-only cache.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "lrclib-official",
                providerID: LyricsProviderID.lrclib.rawValue,
                displayName: "lrclib.net",
                baseURL: URL(string: "https://lrclib.net/api")!,
                regionHint: .international,
                attributionURL: URL(string: "https://lrclib.net"),
                termsURL: URL(string: "https://lrclib.net")
            ),
        ]
    )

    static let liriqo = LyricsProviderCapability(
        id: LyricsProviderID.liriqo.rawValue,
        displayName: "LiriQo",
        providerType: .aggregator,
        region: .global,
        supportedSyncLevels: [.unsynced, .line, .word, .syllable],
        supportedFormats: [.plain, .lrc, .ttml, .jsonTimed],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: true,
        supportsSearchByTitle: true,
        supportsAlbum: true,
        supportsDuration: true,
        supportsTranslations: true,
        supportsMultipleCandidates: true,
        rateLimitSummary: "Honor 429 Retry-After; public API may evolve",
        termsURL: URL(string: "https://github.com/AlFarrizi-Studio/LiriQo"),
        documentationURL: URL(string: "https://github.com/AlFarrizi-Studio/LiriQo"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://github.com/AlFarrizi-Studio/LiriQo"),
        cachePolicy: .sessionOnly,
        enablement: .enabled,
        enabledByDefault: true,
        auditNotes: "Verified 2026-11-10: /v1/lyrics returns primary + tracks with upstream provider attribution. Treat as one aggregator, not its upstreams as nodes.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "liriqo-public",
                providerID: LyricsProviderID.liriqo.rawValue,
                displayName: "api.liriqo-alfarrizi.my.id",
                baseURL: URL(string: "https://api.liriqo-alfarrizi.my.id/v1")!,
                regionHint: .global,
                attributionURL: URL(string: "https://github.com/AlFarrizi-Studio/LiriQo")
            ),
        ]
    )

    static let lrcmux = LyricsProviderCapability(
        id: LyricsProviderID.lrcmux.rawValue,
        displayName: "LRC Mux",
        providerType: .aggregator,
        region: .international,
        supportedSyncLevels: [.unsynced, .line, .word],
        supportedFormats: [.plain, .lrc, .lyricsfile, .jsonTimed],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: false,
        supportsDuration: false,
        supportsTranslations: false,
        supportsMultipleCandidates: false,
        rateLimitSummary: "60 req/min, burst 10; cache hits free; honor Retry-After",
        termsURL: URL(string: "https://lrcmux.dev"),
        documentationURL: URL(string: "https://lrcmux.dev/docs"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://lrcmux.dev"),
        cachePolicy: .sessionOnly,
        enablement: .enabled,
        enabledByDefault: true,
        auditNotes: "Verified 2026-11-10: GET https://api.lrcmux.dev/get returns word-level JSON for EN sample; CN sample returned 404. Upstream in meta.source is attribution only.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "lrcmux-public",
                providerID: LyricsProviderID.lrcmux.rawValue,
                displayName: "api.lrcmux.dev",
                baseURL: URL(string: "https://api.lrcmux.dev")!,
                regionHint: .international,
                attributionURL: URL(string: "https://lrcmux.dev"),
                termsURL: URL(string: "https://lrcmux.dev")
            ),
        ]
    )

    static let betterLyrics = LyricsProviderCapability(
        id: LyricsProviderID.betterLyrics.rawValue,
        displayName: "Better Lyrics",
        providerType: .direct,
        region: .international,
        supportedSyncLevels: [.line, .word, .syllable],
        supportedFormats: [.ttml, .qrc, .lrc],
        requiresAPIKey: true,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: true,
        supportsDuration: true,
        supportsTranslations: false,
        supportsMultipleCandidates: false,
        rateLimitSummary: "Cache hits free; uncached may require API key (new keys currently restricted)",
        termsURL: URL(string: "https://lyrics-api-docs.boidu.dev/"),
        documentationURL: URL(string: "https://lyrics-api-docs.boidu.dev/"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://betterlyrics.org"),
        cachePolicy: .sessionOnly,
        enablement: .experimental,
        enabledByDefault: false,
        auditNotes: "Verified 2026-11-10: /getLyrics returned TTML for cached EN sample without key. Uncached responses may 401. Keep out of default Auto until key policy is clear.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "betterlyrics-public",
                providerID: LyricsProviderID.betterLyrics.rawValue,
                displayName: "api.betterlyrics.org",
                baseURL: URL(string: "https://api.betterlyrics.org")!,
                regionHint: .international,
                attributionURL: URL(string: "https://betterlyrics.org")
            ),
        ]
    )

    static let lrcRed = LyricsProviderCapability(
        id: LyricsProviderID.lrcRed.rawValue,
        displayName: "lrc.red",
        providerType: .direct,
        region: .international,
        supportedSyncLevels: [.line, .word],
        supportedFormats: [.lrc, .enhancedLRC, .ttml, .lyricsfileYAML],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: true,
        supportsSearchByTitle: true,
        supportsAlbum: true,
        supportsDuration: true,
        supportsTranslations: false,
        supportsMultipleCandidates: true,
        rateLimitSummary: "Identify with User-Agent; respect published rate limits",
        termsURL: URL(string: "https://lrc.red"),
        documentationURL: URL(string: "https://lrc.red/api"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://lrc.red"),
        cachePolicy: .sessionOnly,
        enablement: .enabled,
        enabledByDefault: true,
        auditNotes: "Verified 2026-11-10: live paths are /search.json and /s/{isrc}.{json,lrc,ttml} (not /api/search.json). Attribution required.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "lrcred-public",
                providerID: LyricsProviderID.lrcRed.rawValue,
                displayName: "lrc.red",
                baseURL: URL(string: "https://lrc.red")!,
                regionHint: .international,
                attributionURL: URL(string: "https://lrc.red"),
                termsURL: URL(string: "https://lrc.red")
            ),
        ]
    )

    static let lyricsOvh = LyricsProviderCapability(
        id: LyricsProviderID.lyricsOvh.rawValue,
        displayName: "Lyrics.ovh",
        providerType: .direct,
        region: .international,
        supportedSyncLevels: [.unsynced],
        supportedFormats: [.plain],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: false,
        supportsDuration: false,
        supportsTranslations: false,
        supportsMultipleCandidates: false,
        rateLimitSummary: "Public undocumented limits; treat as best-effort plain-text fallback",
        termsURL: URL(string: "https://lyrics.ovh"),
        documentationURL: URL(string: "https://lyrics.ovh"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://lyrics.ovh"),
        cachePolicy: .sessionOnly,
        enablement: .experimental,
        enabledByDefault: false,
        auditNotes: "Verified 2026-11-10: plain lyrics only. Must never be marked as synced.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "lyricsovh-public",
                providerID: LyricsProviderID.lyricsOvh.rawValue,
                displayName: "api.lyrics.ovh",
                baseURL: URL(string: "https://api.lyrics.ovh/v1")!,
                regionHint: .international,
                attributionURL: URL(string: "https://lyrics.ovh")
            ),
        ]
    )

    static let meting = LyricsProviderCapability(
        id: LyricsProviderID.meting.rawValue,
        displayName: "Meting",
        providerType: .aggregator,
        region: .china,
        supportedSyncLevels: [.unsynced, .line],
        supportedFormats: [.lrc],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: false,
        supportsDuration: false,
        supportsTranslations: true,
        supportsMultipleCandidates: true,
        rateLimitSummary: "Public mirrors are replaceable; no guaranteed SLA",
        termsURL: URL(string: "https://github.com/metowolf/Meting"),
        documentationURL: URL(string: "https://github.com/metowolf/MetingJS"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://github.com/metowolf/Meting"),
        cachePolicy: .sessionOnly,
        enablement: .enabled,
        enabledByDefault: true,
        auditNotes: "Verified 2026-11-10: i-meto public node search+lrc works for QQ (tencent). NetEase search ranking is noisy; prefer exact artist match. Nodes are mirrors of the same Meting provider.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "meting-i-meto",
                providerID: LyricsProviderID.meting.rawValue,
                displayName: "api.i-meto.com",
                baseURL: URL(string: "https://api.i-meto.com/meting/api")!,
                regionHint: .china,
                attributionURL: URL(string: "https://github.com/metowolf/Meting")
            ),
        ]
    )

    static let netease = LyricsProviderCapability(
        id: LyricsProviderID.netease.rawValue,
        displayName: "NetEase Music",
        providerType: .direct,
        region: .china,
        supportedSyncLevels: [.unsynced, .line, .word],
        supportedFormats: [.lrc, .yrc],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: true,
        supportsDuration: true,
        supportsTranslations: true,
        supportsMultipleCandidates: true,
        rateLimitSummary: "Accessed via verified Meting node unless a dedicated adapter is reviewed",
        termsURL: nil,
        documentationURL: URL(string: "https://github.com/metowolf/Meting"),
        healthEndpoint: nil,
        attributionURL: nil,
        cachePolicy: .sessionOnly,
        enablement: .experimental,
        enabledByDefault: false,
        auditNotes: "No stable first-party public API verified. Routed experimentally through Meting server=netease. Direct undocumented endpoints stay disabled.",
        defaultNodes: []
    )

    static let qqMusic = LyricsProviderCapability(
        id: LyricsProviderID.qqMusic.rawValue,
        displayName: "QQ Music",
        providerType: .direct,
        region: .china,
        supportedSyncLevels: [.unsynced, .line, .word],
        supportedFormats: [.lrc, .qrc],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: true,
        supportsDuration: true,
        supportsTranslations: true,
        supportsMultipleCandidates: true,
        rateLimitSummary: "Accessed via verified Meting node (server=tencent) unless dedicated adapter reviewed",
        termsURL: nil,
        documentationURL: URL(string: "https://github.com/metowolf/Meting"),
        healthEndpoint: nil,
        attributionURL: nil,
        cachePolicy: .sessionOnly,
        enablement: .experimental,
        enabledByDefault: false,
        auditNotes: "Verified via Meting tencent search+lrc on 2026-11-10. QRC not confirmed on the public Meting lrc endpoint.",
        defaultNodes: []
    )

    static let kugou = LyricsProviderCapability(
        id: LyricsProviderID.kugou.rawValue,
        displayName: "KuGou",
        providerType: .direct,
        region: .china,
        supportedSyncLevels: [.unsynced, .line, .word],
        supportedFormats: [.lrc, .krc],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: false,
        supportsDuration: false,
        supportsTranslations: false,
        supportsMultipleCandidates: true,
        rateLimitSummary: "No first-party public API verified in this audit",
        termsURL: nil,
        documentationURL: nil,
        healthEndpoint: nil,
        attributionURL: nil,
        cachePolicy: .sessionOnly,
        enablement: .candidate,
        enabledByDefault: false,
        auditNotes: "Not directly verified. May appear as LiriQo/LRC Mux upstream attribution only.",
        defaultNodes: []
    )

    static let lrcShare = LyricsProviderCapability(
        id: LyricsProviderID.lrcShare.rawValue,
        displayName: "LrcShare",
        providerType: .direct,
        region: .china,
        supportedSyncLevels: [.unsynced, .line, .word],
        supportedFormats: [.lrc, .ttml, .enhancedLRC],
        requiresAPIKey: true,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: true,
        supportsDuration: true,
        supportsTranslations: true,
        supportsMultipleCandidates: true,
        rateLimitSummary: "Requires API key + catalog session per docs",
        termsURL: URL(string: "https://api.lrcshare.com/docs/"),
        documentationURL: URL(string: "https://api.lrcshare.com/docs/"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://lrcshare.com"),
        cachePolicy: .sessionOnly,
        enablement: .disabled,
        enabledByDefault: false,
        auditNotes: "BLOCKED: API key required. /v1/ returned 403 without credentials on 2026-11-10.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "lrcshare-official",
                providerID: LyricsProviderID.lrcShare.rawValue,
                displayName: "api.lrcshare.com",
                baseURL: URL(string: "https://api.lrcshare.com")!,
                regionHint: .china,
                enabled: false
            ),
        ]
    )

    static let lrcAPI = LyricsProviderCapability(
        id: LyricsProviderID.lrcAPI.rawValue,
        displayName: "LrcAPI",
        providerType: .direct,
        region: .china,
        supportedSyncLevels: [.unsynced, .line],
        supportedFormats: [.lrc],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: false,
        supportsDuration: false,
        supportsTranslations: false,
        supportsMultipleCandidates: false,
        rateLimitSummary: "Public API may be slow; docs site uses CC BY-NC-SA 4.0",
        termsURL: URL(string: "https://docs.lrc.cx/docs/QuickStart/"),
        documentationURL: URL(string: "https://docs.lrc.cx/docs/QuickStart/"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://lrc.cx"),
        cachePolicy: .sessionOnly,
        enablement: .disabled,
        enabledByDefault: false,
        auditNotes: "PENDING LICENSE REVIEW. Technically returned LRC for 晴天 on 2026-11-10, but content/redistribution rights are unclear. Keep out of Auto.",
        defaultNodes: [
            LyricsNodeDescriptor(
                id: "lrcapi-public",
                providerID: LyricsProviderID.lrcAPI.rawValue,
                displayName: "api.lrc.cx",
                baseURL: URL(string: "https://api.lrc.cx")!,
                regionHint: .china,
                enabled: false
            ),
        ]
    )

    static let vvhan = LyricsProviderCapability(
        id: LyricsProviderID.vvhan.rawValue,
        displayName: "VVHAN",
        providerType: .direct,
        region: .china,
        supportedSyncLevels: [.unsynced, .line],
        supportedFormats: [.lrc, .plain],
        requiresAPIKey: false,
        requiresAttribution: true,
        supportsISRC: false,
        supportsSearchByTitle: true,
        supportsAlbum: false,
        supportsDuration: false,
        supportsTranslations: false,
        supportsMultipleCandidates: false,
        rateLimitSummary: "Unknown",
        termsURL: URL(string: "https://api.vvhan.com"),
        documentationURL: URL(string: "https://api.vvhan.com"),
        healthEndpoint: nil,
        attributionURL: URL(string: "https://api.vvhan.com"),
        cachePolicy: .sessionOnly,
        enablement: .candidate,
        enabledByDefault: false,
        auditNotes: "UNAVAILABLE: api.vvhan.com DNS resolution failed on 2026-11-10.",
        defaultNodes: []
    )
}
