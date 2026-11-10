# Third-party notices

## mediaremote-adapter (Experimental Island Now Playing)

- Package: [ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) (Swift Package Manager fork)
- Upstream technique: [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
- Pinned revision: `5b6afde3f501a3da567e23bf7f23d562938a1809`
- Purpose: optional system Now Playing metadata and transport via Apple’s private `MediaRemote.framework`, bridged through `/usr/bin/perl` on macOS 15.4+
- Scope in Audune: Settings → Notch Island → Show Now Playing when expanded (default off). Not part of Core MVP. Not App Store–ready. May break after OS updates.
- Audune does not claim ownership of MediaRemote; the helper is used only when the user enables the Experimental switch.

## Multi-Source Lyrics providers (Island Fullscreen Lyrics)

Audune's Island Fullscreen Lyrics can query multiple audited online providers through a local router. The live audit matrix is `docs/LYRICS_PROVIDER_AUDIT.md`. Online lyric text remains session-only by default: never written to disk, uploaded, bundled, or redistributed. Audune never sends audio, artwork, account identifiers, playback history, or diagnostics. Open-source aggregator/server licenses do **not** grant redistribution rights for lyric content.

### LRCLIB

- Service/API: [lrclib.net](https://lrclib.net), documentation at [lrclib.net/docs](https://lrclib.net/docs). No API key required for the public endpoints Audune uses.
- Scope: first-class direct provider in the default Auto pool. Calls `/api/get` (404 → `/api/search`) with title/artist and optional album/duration.
- Client identity: `User-Agent: Audune/1.0 (macOS lyrics client)` (or the app version string). Ephemeral `URLSession`, timeouts, request spacing, cancellation, 429/`Retry-After`, bounded 503 retry.
- Licensing: MIT covers server software, not necessarily lyric records. Residual copyright/terms risk remains.

### LiriQo (aggregator)

- Public API: `https://api.liriqo-alfarrizi.my.id/v1` ([GitHub](https://github.com/AlFarrizi-Studio/LiriQo)).
- Scope: default Auto aggregator. Upstream providers in the response are attribution only, not selectable Audune nodes.
- Residual risk: upstream lyric rights and public API stability are outside Audune's control.

### LRC Mux (aggregator)

- Public API: `https://api.lrcmux.dev` ([docs](https://lrcmux.dev/docs), [GitHub](https://github.com/f1nniboy/lrcmux)).
- Scope: default Auto aggregator. `meta.source` is attribution only.
- Residual risk: aggregated lyric content rights are not verified beyond session-only display.

### Better Lyrics

- API docs: [lyrics-api-docs.boidu.dev](https://lyrics-api-docs.boidu.dev/). Base URL `https://api.betterlyrics.org`.
- Scope: experimental/manual. Cache hits may work without a key; uncached requests can require an API key that Audune never hard-codes.
- Attribution appreciated by the project; residual lyric-rights risk remains.

### lrc.red

- Site/API: [lrc.red](https://lrc.red). Live paths used by Audune: `/search.json`, `/s/{isrc}.ttml`, `/s/{isrc}.lrc`.
- Scope: default Auto direct provider. Attribution/link required when displaying results.
- Residual risk: lyric content rights are not fully verified.

### Lyrics.ovh

- API: `https://api.lyrics.ovh/v1/{artist}/{title}`.
- Scope: experimental unsynced fallback only. Never treated as synchronized lyrics.

### Meting / NetEase / QQ Music

- Meting public mirror audited: `https://api.i-meto.com/meting/api` ([metowolf/Meting](https://github.com/metowolf/Meting)).
- Scope: Meting is in the default Auto pool as a China-oriented mirror aggregator with replaceable nodes. NetEase/QQ Music wrappers are experimental and route through Meting. Direct undocumented platform endpoints are not enabled.
- Residual risk: public mirrors may change or go offline; lyric rights remain with upstream platforms/authors.

### Disabled / candidate

- LrcShare: API key required; blocked without credentials.
- LrcAPI (`api.lrc.cx`): pending license review (docs site CC BY-NC-SA does not clear lyric content rights).
- VVHAN: unavailable during audit (DNS failure).
- KuGou direct: candidate only until a verified public path exists.
