# Audune — AI Coding Agent Instructions

Read `docs/PRODUCT_SPEC.md` and `docs/GITHUB_ISSUES.md` before changing code. These instructions apply to every coding session and override generic assumptions about how to finish a task.

## Mandatory Git rules

- Work only on the `dev` branch. Before editing, run `git status --short` and `git branch --show-current`.
- If not on `dev` and the worktree is clean, switch to an existing `dev` branch. If switching could affect uncommitted work, stop and report; never stash/reset/discard user changes. If `dev` does not exist, create it from the current clean baseline. Never create another development branch.
- Never switch to `main` or continue work on another branch. Never merge, rebase, hard-reset, force-push, delete branches, or overwrite existing user changes.
- **Automatically create one commit after each completed TODO.** A TODO means a checkbox/task item in the approved plan or GitHub Issue. Commit it only after its implementation is complete and its relevant checks/tests pass. Do not wait for the user to ask for each commit.
- Keep commits small and traceable: normally one commit per completed TODO. If multiple checklist items genuinely cannot be built or validated independently, define the smallest independently verifiable unit in the plan and commit that unit; do not batch unrelated completed TODOs just to reduce the commit count, and do not split work into meaningless micro-commits.
- Before each commit, inspect `git status --short` and the full staged diff. Stage only files belonging to that TODO. Never include pre-existing user changes, unrelated files, secrets, local settings, build outputs, or generated artifacts. If ownership of a changed file is ambiguous, stop and ask rather than commit it.
- If relevant checks fail, the TODO is incomplete: do not mark it complete or commit it. Fix the issue or report the blocker. For documentation-only TODOs, run an appropriate consistency/link/format check when available. Never bypass failing hooks or tests just to commit.
- Use exactly `:gitmoji: short-git-message` for every commit, one line, for example `:sparkles: add system audio capture`. Use one gitmoji shortcode, one space, and a short English description. Do not add `feat:`, issue numbers, or other prefixes. Do not automatically push.
- Re-check the active branch at task completion. It must still be `dev`.

## Coding workflow

1. Inspect the repository, current diff, Xcode project/schemes, and existing conventions before editing.
2. Implement only the requested Issue and its necessary dependencies. Do not generate the whole app in one pass.
3. Keep every stage buildable. Run the relevant build/tests and report exactly what ran and what did not.
4. Never claim that a test passed unless it actually ran successfully. System audio permission and notch/window behaviors may require a real macOS user session and must be listed as manual tests if CI cannot verify them.
5. Do not replace real system capture with random/demo data. Any demo mode must be explicitly labelled, off by default, and must not be confused with actual capture.
6. Use public Apple APIs. No private APIs, code injection, undocumented WindowServer manipulation, microphone fallback, or system-file modification — **except** the scoped Experimental Island Now Playing path documented in `docs/PRODUCT_SPEC.md` (MediaRemote via `mediaremote-adapter`, user-gated, default off). That exception does **not** authorize SkyLight, CGSSpace, WindowServer injection, Accessibility masquerading, microphone use, or telemetry.
7. Avoid adding dependencies or frameworks without a clear need and license review. Prefer Swift, SwiftUI, AppKit, Core Audio, Accelerate/vDSP, XCTest, and UserDefaults. The Experimental Now Playing feature may depend on `ejbills/mediaremote-adapter` only as specified.
8. Preserve existing user work. Do not use destructive commands or broad formatting/refactoring unrelated to the issue.

## Product invariants

- Audune is native macOS, free, fully open source, local-first, and has no account, ads, telemetry, or analytics SDK.
- Do not request microphone permission. Use Core Audio Process Tap for system output audio, explain permission using `NSAudioCaptureUsageDescription`, and never persist or upload raw PCM.
- Audio tap callbacks must not update UI, write files, access network, block, synchronously log, or perform unbounded allocation. Use preallocated bounded buffers and move DSP off the real-time callback.
- One capture pipeline and one latest `AudioSnapshot` feed all visible surfaces. Each surface must not create its own tap or FFT loop.
- Core visualizations are Spectrum, Waveform, and Orbit. They must respond to real analyzed audio, not random movement.
- Menu Bar and Studio belong to Core MVP. Island and Desktop Magnet are later staged features defined by the product spec; do not silently scope-creep.
- Island must use public screen geometry and degrade safely where notch positioning cannot be supported.
- Experimental Island Now Playing (Expanded/Pinned only, default off) may use MediaRemote through `mediaremote-adapter`. It must never start/stop Process Tap, must not appear in Compact wings, and must degrade to a clear unavailable/empty state without crashing Island.
- Island Fullscreen Lyrics is a separate approved scope (AUD-27), not a general Now Playing promotion. It must consume NowPlayingService as the authoritative playback state through a temporary runtime demand, without mutating the persistent Expanded-display preference. Keep Playback Identity distinct from a cross-player Lyrics Track Key. Persist only user-imported, locally parsed lyrics; use security-scoped access for the selected file.
- Online lyrics use the audited Multi-Source Lyrics Registry in `Audune/Island/LyricsProviders/` (see `docs/LYRICS_PROVIDER_AUDIT.md`). Only providers marked enabled for default Auto may be queried automatically. LRCLIB remains a first-class direct provider via its documented public API in `Audune/Island/LRCLIBLyricsProvider.swift`. Do not invent Provider/Node aliases for an aggregator's upstream sources unless that API exposes real selection. Requests may send only the minimum fields allowed by each provider capability (typically title, artist, album, duration, and ISRC when available); never send audio, artwork, account identifiers, playback history, or diagnostics. Keep documented User-Agent, timeout, cancellation, 429/`Retry-After`, and bounded retry handling; keep online results session-only by default (never persisted, bundled, uploaded, or shared) unless a provider's reviewed terms explicitly allow a bounded cache TTL. Label the actual source (and aggregator upstream when provided) in the UI. Do not add another provider or scrape undocumented endpoints without a new API/terms/privacy/licensing review recorded in the audit table and `docs/THIRD_PARTY_NOTICES.md`.
- Desktop Magnet uses normal window level and can be covered by regular app windows; it must not be implemented as an always-on-top overlay or a private desktop-layer hack.
- Maintain truthful product docs and manual acceptance records.

## Completion report

At the end of each task, report:
- Files changed and the behavior implemented.
- Build/test commands actually run and results.
- Manual tests still required.
- Known limitations or blockers.
- Confirmation the current branch remains `dev`.
- After each completed and validated TODO, create the required commit automatically; report the commit hash and message in the completion report. Never push automatically.
