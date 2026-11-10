# Lyrics Provider Audit

Audit date: **2026-11-10**  
Client User-Agent: `Audune/1.0 (macOS lyrics client; https://github.com/Audune)`  
Method: live HTTPS requests from the Audune development machine. Values are real measurements; empty or blocked rows are not fabricated.

Sample tracks:

- EN: *Blinding Lights* — The Weeknd — After Hours — duration 200s
- CN: *晴天* — 周杰伦
- Negative: nonexistent title/artist against LRCLIB `/api/get` → HTTP 404

## Results

| Provider | Actual Endpoint | HTTP | Parse / content | Sync | Latency | Status |
|---|---|---:|---|---|---:|---|
| LRCLIB | `GET https://lrclib.net/api/get` | 200 | synced + plain + lyricsfile | word (hasWordSync) | ~970 ms | **ENABLED** |
| LRCLIB | `GET https://lrclib.net/api/search` (晴天) | 200 | multiple CN candidates with LRC | line | ~718 ms | **ENABLED** |
| LRCLIB | negative `/api/get` | 404 | TrackNotFound JSON | — | ~642 ms | OK error mapping |
| LiriQo | `GET https://api.liriqo-alfarrizi.my.id/v1/lyrics` EN `fast=1` | 200 | primary + tracks; upstream Apple Music | syllable | ~6533 ms | **ENABLED** (aggregator) |
| LiriQo | same CN `fast=1` | 200 | CN timed lyrics; multiple tracks | syllable | ~2988 ms | **ENABLED** |
| LRC Mux | `GET https://api.lrcmux.dev/get?format=json` EN | 200 | JSON lines; `meta.source=deezer` | word | ~1774 ms | **ENABLED** (aggregator) |
| LRC Mux | same CN | 404 | `no lyrics found` | — | ~1743 ms | ENABLED (may miss CN) |
| Better Lyrics | `GET https://api.betterlyrics.org/getLyrics` EN | 200 | TTML body (cache hit, no key) | syllable/word TTML | ~1179 ms | **EXPERIMENTAL** (key may be required on cache miss) |
| lrc.red | `GET https://lrc.red/search.json` | 200 | hits with ISRC | — | ~448 ms | **ENABLED** |
| lrc.red | `GET https://lrc.red/s/{isrc}.lrc` / `.ttml` | 200 | enhanced LRC + TTML | word | ~416–712 ms | **ENABLED** |
| lrc.red | documented `/api/search.json` | 404 HTML SPA | — | — | — | path corrected to `/search.json` |
| Lyrics.ovh | `GET https://api.lyrics.ovh/v1/{artist}/{title}` | 200 | plain text only | unsynced | ~1332 ms | **EXPERIMENTAL** fallback |
| Meting | `GET https://api.i-meto.com/meting/api` tencent search+lrc | 200 | LRC for 晴天/周杰伦 | line | ~838–983 ms | **ENABLED** (multi-node ready) |
| Meting | netease search | 200 | noisy cover rankings | — | ~972–1648 ms | usable with strict artist match |
| NetEase direct | — | — | no first-party public API verified | — | — | **EXPERIMENTAL** via Meting |
| QQ Music direct | via Meting `server=tencent` | 200 | LRC confirmed; QRC not confirmed | line | ~838 ms | **EXPERIMENTAL** via Meting |
| KuGou | — | — | not directly verified | — | — | **CANDIDATE** |
| LrcShare | `https://api.lrcshare.com/v1/` | 403 | Cloudflare / auth wall | — | ~490 ms | **DISABLED** — BLOCKED: API key required |
| LrcAPI | `GET https://api.lrc.cx/lyrics` | 200 | LRC for 晴天 | line | ~952 ms | **DISABLED** — PENDING LICENSE REVIEW |
| VVHAN | `https://api.vvhan.com/api/lyric` | DNS fail | — | — | — | **CANDIDATE** — UNAVAILABLE |

## Default Auto pool (post-audit)

1. LiriQo (aggregator)
2. LRC Mux (aggregator)
3. LRCLIB (direct)
4. lrc.red (direct)
5. Meting (China-oriented mirror aggregator)

## Explicitly out of default Auto

- Better Lyrics — experimental; API key policy for cache misses
- Lyrics.ovh — unsynced-only fallback
- NetEase / QQ Music as standalone selectable experimental routes (via Meting)
- KuGou, VVHAN — candidate
- LrcShare — blocked without key
- LrcAPI — pending license review

## Licensing posture

Open-source aggregator servers do **not** grant redistribution rights for lyric text. Audune keeps online lyrics **session-only**, labels attribution in UI, and records residual risk in `docs/THIRD_PARTY_NOTICES.md`.
