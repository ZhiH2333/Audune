# Third-party notices

## mediaremote-adapter (Experimental Island Now Playing)

- Package: [ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) (Swift Package Manager fork)
- Upstream technique: [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
- Pinned revision: `5b6afde3f501a3da567e23bf7f23d562938a1809`
- Purpose: optional system Now Playing metadata and transport via Apple’s private `MediaRemote.framework`, bridged through `/usr/bin/perl` on macOS 15.4+
- Scope in Audune: Settings → Notch Island → Show Now Playing when expanded (default off). Not part of Core MVP. Not App Store–ready. May break after OS updates.
- Audune does not claim ownership of MediaRemote; the helper is used only when the user enables the Experimental switch.

## LRCLIB (Island Fullscreen Lyrics)

- Service/API: [lrclib.net](https://lrclib.net), documentation at [lrclib.net/docs](https://lrclib.net/docs). No API key or account is required for the public endpoints Audune uses.
- Scope in Audune: optional automatic online lyrics lookup for Island Fullscreen Lyrics, enabled by default and controllable under Settings → Notch Island → Lyrics. Audune calls `/api/get` (falling back to `/api/search` on 404) with `track_name`, `artist_name`, and, when available, `album_name` and integer `duration`.
- Client identity: requests send `User-Agent: Audune/1.0 (macOS lyrics client)`. Audune uses a single ephemeral `URLSession`, a 12-second request timeout, sequential request spacing, cancellation when the track changes, a bounded retry for 503 with a short `Retry-After`, and surfaces HTTP 429 rate limits without bypassing them.
- Data handling: Audune never sends audio, artwork, account identifiers, playback history, or diagnostics. Online lyric text is held only in memory for the current session; it is not written to disk, uploaded to a shared database, bundled with the app, or redistributed. User-imported local LRC files are stored separately on the user's Mac.
- Licensing status: LRCLIB's public service source is MIT-licensed, but that license covers the server software, not necessarily the user-contributed lyric records returned by the API. Audune could not verify an explicit license or formal privacy policy covering those records. Audune therefore treats online lyrics as transient display data, labels the source in the UI, and does not persist or redistribute them.
- Residual risk: lyric records may be unavailable, inaccurate, or subject to rights held by third parties; the API or its terms may change without notice. Audune does not claim ownership of lyric content or of LRCLIB. Anyone deploying Audune commercially or at scale should re-review LRCLIB's current terms and obtain appropriate permissions.
