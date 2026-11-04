# Audune — GitHub Issue Backlog

> Copy these issues into GitHub. Implement them sequentially by dependency, one issue per coding session unless the user explicitly groups work. Current branch must remain `dev`. Automatically commit each completed TODO after its relevant checks/tests pass; never auto-push.

## Suggested labels

`P0`, `P1`, `audio`, `dsp`, `visualization`, `ui`, `menu-bar`, `island`, `lyrics`, `desktop-magnet`, `settings`, `performance`, `test`, `docs`, `release`, `spike`.

## Suggested milestones

1. `Phase 0 — Audio Spike`
2. `Phase 1 — Foundation`
3. `Phase 2 — Core Surfaces`
4. `Phase 3 — Island`
5. `Phase 4 — Desktop Magnet`
6. `Phase 5 — Release Readiness`
7. `Experimental — Island Now Playing`
8. `Future — Music Providers`

---

## AUD-01 — [SPIKE] Verify Core Audio Process Tap on supported macOS

**Labels:** `P0`, `audio`, `spike`
**Milestone:** Phase 0 — Audio Spike

### Goal
Prove that Audune can receive real system output audio and reliably release all Core Audio resources before investing in UI work.

### Tasks
- [ ] Build a minimal test target or spike using current public Core Audio Process Tap APIs.
- [ ] Configure `NSAudioCaptureUsageDescription`.
- [ ] Create the tap and aggregate device with a non-muting configuration.
- [ ] Read PCM data and calculate a simple RMS/sample counter.
- [ ] Test permission granted, permission denied, start failure, stop, restart, and process exit.
- [ ] Test browser audio and a local audio player.
- [ ] Verify normal output audio continues unchanged.
- [ ] Record exact macOS version, hardware, steps, API behavior, and limitations.

### Acceptance criteria
- [ ] Real PCM data is received after authorization on the tested supported system.
- [ ] Capture does not mute, redirect, or interrupt normal system playback.
- [ ] Stop and restart repeatedly without accumulating taps/devices/callbacks.
- [ ] Denial/failure is distinguishable from silence.
- [ ] Spike conclusion and manual test result are documented.

### Dependencies
None. This is the release-blocking technical spike.

---

## AUD-02 — Create native project and repository foundation

**Labels:** `P0`, `setup`, `docs`
**Milestone:** Phase 1 — Foundation

### Tasks
- [ ] Inspect and preserve any existing repo structure.
- [ ] Create/configure a native macOS Xcode project using SwiftUI + AppKit.
- [ ] Set minimum deployment target to macOS 14.2, subject to AUD-01 verification.
- [ ] Configure the app as a menu-bar utility (no default Dock icon).
- [ ] Add `.gitignore`, `LICENSE` (proposed MIT), concise README, and project build instructions.
- [ ] Add CI for build and hardware-independent tests after the scheme is known.
- [ ] Ensure no secrets, signing certificates, DerivedData, or user-specific files are committed.

### Acceptance criteria
- [ ] Clean checkout can be opened/built with documented steps.
- [ ] The app can launch and quit from its menu bar entry.
- [ ] CI build configuration reflects the actual Xcode project and scheme.

### Dependencies
AUD-01 conclusion.

---

## AUD-03 — Implement audio capture lifecycle and permission state

**Labels:** `P0`, `audio`
**Milestone:** Phase 1 — Foundation

### Tasks
- [ ] Turn the verified spike into a single `AudioCaptureService` / `ProcessTapCapture` implementation.
- [ ] Implement idempotent start, stop, restart, and cleanup.
- [ ] Model permission, starting, running, silent, interrupted, unsupported, and failed states separately.
- [ ] Handle failure at every partial creation step and roll back prior resources.
- [ ] Handle output device changes, sleep/wake, and permission changes.
- [ ] Keep raw audio in memory only; never write it to disk or network.
- [ ] Do not use microphone input as a fallback.

### Acceptance criteria
- [ ] Repeated start/stop cycles do not leak capture resources.
- [ ] UI can observe a readable capture state without being updated directly from the realtime callback.
- [ ] Errors preserve actionable internal codes but expose clear user-facing messages.
- [ ] Application exit stops and destroys all capture resources.

### Dependencies
AUD-01, AUD-02.

---

## AUD-04 — Implement bounded audio buffering for real-time capture

**Labels:** `P0`, `audio`, `performance`
**Milestone:** Phase 1 — Foundation

### Tasks
- [ ] Use a preallocated bounded buffer/ring buffer between the Core Audio callback and DSP worker.
- [ ] Avoid blocking locks, UI work, file/network IO, synchronous logging, or unbounded allocation in the callback.
- [ ] Define behavior for overflow/underrun: drop stale visual samples, recover without unbounded latency.
- [ ] Document producer/consumer ownership and thread-safety assumptions.

### Acceptance criteria
- [ ] Capture callback remains bounded and does not wait on DSP/UI.
- [ ] Buffer capacity is finite; overflow does not grow memory or delay the UI indefinitely.
- [ ] Stress testing does not crash or deadlock.

### Dependencies
AUD-03.

---

## AUD-05 — Implement AudioSnapshot and AudioAnalyzer DSP

**Labels:** `P0`, `dsp`, `test`
**Milestone:** Phase 1 — Foundation

### Tasks
- [ ] Define immutable latest `AudioSnapshot` including sequence number, timestamp, spectrum, waveform, RMS, peak, and silence state.
- [ ] Use Accelerate/vDSP for FFT and frequency-band aggregation.
- [ ] Generate fixed-size waveform samples.
- [ ] Add smoothing, clamping, and silence hysteresis.
- [ ] Sanitize NaN/Infinity and empty/invalid buffers.
- [ ] Keep the analyzer independent of UI and Core Audio object lifetime.

### Acceptance criteria
- [ ] Synthetic silence yields near-zero levels and stable silence state.
- [ ] Synthetic sine waves produce expected frequency-band response.
- [ ] Increasing amplitude increases energy metrics within normalized bounds.
- [ ] No NaN/Infinity escapes to rendering data.
- [ ] Output array lengths are stable during steady-state operation.

### Dependencies
AUD-04.

---

## AUD-06 — Add core audio analyzer and settings tests

**Labels:** `P0`, `test`
**Milestone:** Phase 1 — Foundation

### Tasks
- [ ] Add XCTest for silence, sine waves, different frequencies, amplitude changes, invalid input, and silence hysteresis.
- [ ] Add tests for default preferences, persistence, normalization, and reset-to-default.
- [ ] Ensure tests do not require audio permissions or real hardware.

### Acceptance criteria
- [ ] Test suite runs in local Xcode/CI.
- [ ] Tests check outputs and tolerances, not implementation-only details.

### Dependencies
AUD-05, AUD-02.

---

## AUD-07 — Implement dynamic menu bar item

**Labels:** `P0`, `menu-bar`, `ui`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Add one AppKit `NSStatusItem` with a custom-rendered compact visualizer.
- [ ] Support compact Spectrum and Waveform; support compact Orbit if it remains legible at status-item size.
- [ ] Cap update rate around 20–30 visual updates per second and adapt downward when appropriate.
- [ ] Ensure dark/light menu bar legibility.
- [ ] Do not allocate one menu bar item per spectrum bar.
- [ ] Document current macOS menu-bar visibility controls in troubleshooting when relevant.

### Acceptance criteria
- [ ] Actual audio changes drive the icon.
- [ ] Static/silent input settles into a stable baseline.
- [ ] No visible flicker or high CPU use during ordinary playback.
- [ ] The status item remains functional when popover/Studio is closed.

### Dependencies
AUD-05.

---

## AUD-08 — Implement menu bar popover and app controls

**Labels:** `P0`, `menu-bar`, `ui`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Create a compact popover with capture state and safe start/stop/retry actions.
- [ ] Add open/hide Studio, choose visualization, open Settings, and Quit actions.
- [ ] Add clear permission-required, silent, running, and failed states.
- [ ] Support keyboard navigation and Escape-to-close.

### Acceptance criteria
- [ ] All MVP actions can be reached without a Dock icon.
- [ ] Closing the popover does not stop capture unexpectedly.
- [ ] Quit fully stops capture and exits cleanly.

### Dependencies
AUD-03, AUD-07.

---

## AUD-09 — Implement Studio floating panel

**Labels:** `P0`, `ui`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Create an AppKit `NSPanel` or equivalent public-API window with no title bar.
- [ ] Support dragging, resizing, hide/show, and safe minimum size.
- [ ] Add an explicit Always-on-Top toggle with visible state.
- [ ] Persist size, position, and topmost preference.
- [ ] Clamp stale/off-screen coordinates back onto a visible screen.
- [ ] Keep the global audio service running when Studio closes.

### Acceptance criteria
- [ ] Window can be moved, resized, hidden, and reopened.
- [ ] Always-on-Top immediately changes its level as expected.
- [ ] Restart restores the window geometry safely.
- [ ] No additional capture loop starts when the window opens.

### Dependencies
AUD-02, AUD-08.

---

## AUD-10 — Implement Spectrum renderer

**Labels:** `P0`, `visualization`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Draw frequency bars from `AudioSnapshot.spectrum`.
- [ ] Use sensible band distribution and stable scaling.
- [ ] Add sensitivity/smoothing support and a compact mode for small surfaces.
- [ ] Sanitize geometry for very small/large canvas sizes.

### Acceptance criteria
- [ ] Different test frequencies produce visibly different bands.
- [ ] Silence settles toward baseline within the configured decay window.
- [ ] No negative dimensions, invalid drawing coordinates, or NaN geometry.

### Dependencies
AUD-05, AUD-09.

---

## AUD-11 — Implement Waveform renderer

**Labels:** `P0`, `visualization`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Draw a line from actual `AudioSnapshot.waveform` samples.
- [ ] Define a stable baseline and amplitude scaling.
- [ ] Handle empty or stale samples without random animation.

### Acceptance criteria
- [ ] Shape changes with input waveform.
- [ ] Silence yields a stable baseline.
- [ ] Switching modes repeatedly does not allocate extra capture services.

### Dependencies
AUD-05, AUD-09.

---

## AUD-12 — Implement Orbit renderer

**Labels:** `P0`, `visualization`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Map spectrum bands to radial elements around a stable center.
- [ ] Adapt element count and radius to canvas size.
- [ ] Reuse theme, sensitivity, smoothing, and silence behavior.

### Acceptance criteria
- [ ] Orbit responds to real frequency changes.
- [ ] Layout stays within bounds when resized.
- [ ] Silence yields a stable, low-motion state.

### Dependencies
AUD-05, AUD-09.

---

## AUD-13 — Implement SettingsStore and settings UI

**Labels:** `P0`, `settings`, `ui`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Add mode, accent color, sensitivity, smoothing, Studio opacity, and topmost settings.
- [ ] Persist values using UserDefaults/SettingsStore.
- [ ] Validate all values and normalize invalid saved settings.
- [ ] Add Reset to Defaults.
- [ ] Separate global visual settings from per-surface geometry/behavior preferences.

### Acceptance criteria
- [ ] Settings update views immediately.
- [ ] Preferences survive app restart.
- [ ] Reset reliably restores documented defaults.
- [ ] Invalid stored values never crash the app.

### Dependencies
AUD-07 through AUD-12 as needed.

---

## AUD-14 — Permission/error UX and privacy documentation

**Labels:** `P0`, `audio`, `docs`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Distinguish unsupported system, permission required/denied, silent input, interrupted capture, and failed capture.
- [ ] Add retry flow and safe guidance for changing macOS permissions.
- [ ] Document that Audune does not use the microphone, store raw audio, upload sound, or collect telemetry.
- [ ] Inspect project/dependencies for unrequested network access.

### Acceptance criteria
- [ ] Known failures provide a clear next step.
- [ ] Permission changes can be retried without reinstalling the app, subject to macOS behavior.
- [ ] README/privacy docs match actual implementation.

### Dependencies
AUD-03, AUD-08.

---

## AUD-15 — Performance, lifecycle, and device-change hardening

**Labels:** `P0`, `performance`, `test`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Stop or reduce drawing when surfaces are hidden/covered.
- [ ] Reduce unnecessary DSP updates during sustained silence while preserving responsive wake-up.
- [ ] Handle output-device changes, sleep/wake, and permission revocation.
- [ ] Use Instruments/Activity Monitor to record a baseline on real Apple Silicon hardware.
- [ ] Verify all capture and timer resources are cleaned up.

### Acceptance criteria
- [ ] 30-minute run has no crash or obvious runaway memory growth.
- [ ] 20 capture start/stop cycles do not accumulate resources.
- [ ] Hiding Studio stops high-frequency drawing for that surface.
- [ ] Device changes never leave the UI permanently stuck in `running`.

### Dependencies
AUD-03 through AUD-13.

---

## AUD-16 — [SPIKE] Prototype safe notch positioning for Island

**Labels:** `P1`, `island`, `spike`
**Milestone:** Phase 3 — Island

### Tasks
- [ ] On a notched MacBook, inspect public `NSScreen` safe area and auxiliary top areas.
- [ ] Prototype a small custom window around the notch using public AppKit APIs only.
- [ ] Test menu-bar click targets and window hit-testing.
- [ ] Test external displays, display scaling, screen changes, and full-screen app behavior.
- [ ] Define graceful fallback for non-notched displays.

### Acceptance criteria
- [ ] Notch positioning is based on screen geometry, not hard-coded universal coordinates.
- [ ] The window does not persistently block system menu-bar interactions.
- [ ] Unsupported layouts cleanly disable Island without affecting other surfaces.
- [ ] Spike has real-device evidence and documented API constraints.

### Dependencies
AUD-09, AUD-13.

---

## AUD-17 — Implement Island collapsed/expanded states

**Labels:** `P1`, `island`, `ui`
**Milestone:** Phase 3 — Island

### Tasks
- [ ] Build collapsed compact visual state and expanded panel.
- [ ] Implement hover-to-expand, click-to-pin, delayed collapse, and Escape behavior.
- [ ] Support mode selection and shortcut to Studio.
- [ ] Add Reduce Motion behavior.
- [ ] Ensure opening/closing never restarts audio capture.

### Acceptance criteria
- [ ] Stable position on supported notched display.
- [ ] Expanded UI does not clip critical content or block unrelated menu-bar areas.
- [ ] Hover transitions are smooth and don't collapse before users can reach controls.
- [ ] Non-notched screens show a clear disabled/fallback state.

### Dependencies
AUD-16.

---

## AUD-18 — Implement Desktop Magnet as normal-level window

**Labels:** `P1`, `desktop-magnet`, `ui`
**Milestone:** Phase 4 — Desktop Magnet

### Tasks
- [ ] Add a small, border-light window using normal window level.
- [ ] Ensure the window can be covered by ordinary app windows; do not use floating/status-bar levels.
- [ ] Support move, resize, opacity and visualization mode.
- [ ] Persist window geometry and restore to a visible screen after display changes.
- [ ] Default to one instance and current Space; don't use private APIs to place it behind desktop icons.

### Acceptance criteria
- [ ] An ordinary app window can cover Magnet.
- [ ] Magnet does not repeatedly force itself to the front when switching applications.
- [ ] Position/mode/size survive app restart.
- [ ] Missing-display recovery works safely.

### Dependencies
AUD-09, AUD-13, AUD-15.

---

## AUD-18B — Startup Behavior v1 (superseded on `dev` by AUD-18C)

**Labels:** `P1`, `settings`, `ui`
**Milestone:** Phase 2 — Core Surfaces

### Goal
Original mutually exclusive destination picker plus mode/preset. Replaced by AUD-18C independent surface checkboxes.

### Dependencies
AUD-09, AUD-13, AUD-17 (Island enable APIs).

---

## AUD-18C — Startup Behavior & Launch at Login v1 (shipped on `dev`)

**Labels:** `P1`, `settings`, `ui`
**Milestone:** Phase 2 — Core Surfaces

### Goal
Let users choose independent launch surfaces (Studio / Notch Island / Settings), visualization mode, optional Visual Preset, optional auto-capture, and Launch at Login via `SMAppService.mainApp`.

### Notes
- Defaults preserve prior launch behavior (Studio/Settings off, Island follows `island.isEnabled`, `keepCurrent`, no preset, auto-capture off).
- Legacy `startup.destination` migrates once into surface booleans.
- Island launch checkbox uses a session presentation gate; it does not silently rewrite `island.isEnabled`.
- Launch at Login reads real `SMAppService` status; no UserDefaults mirror; no helper/LaunchAgents.
- Auto-capture starts only when already authorized (`CGPreflightScreenCaptureAccess`); never prompted at login for permission.
- Applied once per process by `StartupApplicator`; not on activation or window reopen.
- “Restore last session” remains out of scope (AUD-19).

### Dependencies
AUD-09, AUD-13, AUD-17, AUD-18B.

---

## AUD-19 — Implement SurfaceManager and per-surface preferences

**Labels:** `P1`, `settings`, `ui`
**Milestone:** Phase 4 — Desktop Magnet

### Tasks
- [ ] Add explicit enable/disable controls for Menu Bar, Studio, Island, Magnet.
- [ ] Keep one central audio capture service regardless of enabled surface count.
- [ ] Store each surface's mode, size, opacity, location and window behavior separately.
- [ ] Share global sensitivity/smoothing/accent color unless a clear user need justifies per-surface override.
- [ ] Restore only surfaces the user had enabled (broader than Startup Behavior launch checkboxes).

### Acceptance criteria
- [ ] Enabling/disabling surfaces does not create duplicate capture services.
- [ ] Studio sizing/level changes don't unintentionally change Magnet geometry/level.
- [ ] Configurations restore after restart and invalid state falls back safely.

### Dependencies
AUD-17, AUD-18.

---

## AUD-20 — Accessibility, Reduce Motion, and visual polish

**Labels:** `P1`, `ui`
**Milestone:** Phase 4 — Desktop Magnet

### Tasks
- [ ] Add VoiceOver labels and keyboard-accessible controls.
- [ ] Respect Reduce Motion for Island and surface transitions.
- [ ] Verify dark/light menu-bar visibility and contrast.
- [ ] Ensure capture state is not conveyed by color alone.
- [ ] Review minimum window sizes and small-surface rendering.

### Acceptance criteria
- [ ] Core actions usable by keyboard and discoverable through VoiceOver.
- [ ] Reduced-motion setting measurably reduces nonessential transitions.
- [ ] UI remains legible in supported system appearances.

### Dependencies
AUD-08 through AUD-19.

---

## AUD-21 — Add manual test matrix and CI hardening

**Labels:** `P0`, `test`, `release`
**Milestone:** Phase 5 — Release Readiness

### Tasks
- [ ] Add a manual test checklist covering audio capture, permissions, device switching, surfaces, display changes, and extended run.
- [ ] Ensure CI builds and runs all hardware-independent tests.
- [ ] Document CI limitations for TCC/system-audio permission tests.
- [ ] Add build/test status instructions to README.

### Acceptance criteria
- [ ] Manual tests have explicit Pass/Fail/Not Tested fields.
- [ ] CI failures cannot be suppressed by deleting or broadly skipping tests.
- [ ] System-audio behavior is marked Not Tested until run on real macOS hardware.

### Dependencies
AUD-06, AUD-14, AUD-15, AUD-20.

---

## AUD-22 — README, CONTRIBUTING, license, and first test build

**Labels:** `P0`, `docs`, `release`
**Milestone:** Phase 5 — Release Readiness

### Tasks
- [ ] Document features, macOS requirements, permission flow, privacy, build steps, known limitations and manual tests.
- [ ] Add `CONTRIBUTING.md` and root `AGENTS.md` instructions.
- [ ] Add final selected open-source license and dependency notices.
- [ ] Provide a reproducible test build (ZIP first; DMG later if useful).
- [ ] Explain signing/notarization status and macOS Gatekeeper prompts honestly.

### Acceptance criteria
- [ ] A new contributor can build from a clean checkout using the documented steps.
- [ ] Release artifact corresponds to the documented source revision.
- [ ] No unsupported promises about signing, notarization or permissions.

### Dependencies
AUD-02, AUD-14, AUD-21.

---

## AUD-NP-01 — [EXPERIMENTAL] Island Now Playing (optional full player)

**Labels:** `P2`, `island`, `experimental`
**Milestone:** Experimental — Island Now Playing

### Goal
Optional system Now Playing on Notch Island Expanded/Pinned: artwork, title, artist, scrubber, previous / play-pause / next. Default off. Compact wings unchanged. Does not count toward Core MVP.

### Tasks
- [x] Document the scoped private-API exception (MediaRemote via mediaremote-adapter only) in PRODUCT_SPEC / AGENTS / MANUAL_TESTS.
- [x] Add `ejbills/mediaremote-adapter` SPM; implement `NowPlayingService` lifecycle gated by `island.nowPlayingEnabled`.
- [x] Expanded/Pinned UI + geometry height bump; Compact zero change; never start/stop Process Tap.
- [x] Seek-unsupported per-bundle fallback to display-only scrubber; empty/unavailable states; unit tests + manual matrix.
- [x] Compact full-screen metadata sits below the visualization and follows the existing Now Playing and artwork/title visibility preferences; an icon-only, background-free play/pause button controls the active player from the lower-right.

### Acceptance criteria
- [x] Default off: Expanded Island matches prior layout (preference + UI gated).
- [ ] When enabled on a notched display: metadata and transport work for system Now Playing clients; Compact shows spectrum only. *(manual — see MANUAL_TESTS)*
- [ ] In full-screen mode, enabled Now Playing displays artwork/title/artist in the lower-left and shows a clear empty/unavailable state when appropriate; the lower-right play/pause icon controls the active player without a background. *(manual — see MANUAL_TESTS)*
- [x] Toggle off / disable Island / no-notch / shutdown stops the adapter listener. *(unit-covered for service stop; Island wiring in controller)*
- [x] Capture pipeline is unaffected by Now Playing toggles. *(NowPlayingService never touches ProcessTapSpike)*
- [ ] Unavailable/empty states are explicit; no App Store claim; 15.4+ manual tests recorded honestly. *(empty/unavailable unit-covered; GUI rows remain NOT TESTED)*

### Dependencies
AUD-17 (Island collapsed/expanded).

### Out of scope
Compact mini Now Playing, art color themes, AppleScript Automation, Accessibility, media-key hijack, Studio/Menu Bar Now Playing, SkyLight/CGS.

---

---

## AUD-23 — [CANCELLED] Apple Music metadata and controls (Apple Events)

**Labels:** `P2`, `audio`
**Status:** Cancelled — per-app Apple Events Play/Pause removed. System-wide Experimental Now Playing is AUD-NP-01 (mediaremote-adapter), not Music Automation.

---

## AUD-24 — [CANCELLED] Spotify metadata and controls (Apple Events)

**Labels:** `P2`, `audio`
**Status:** Cancelled — same as AUD-23. Spotify Automation is not used; AUD-NP-01 covers system Now Playing when enabled.

---

## AUD-25 — [FUTURE] Advanced visual modes (preset file exchange delivered)

**Labels:** `P2`, `visualization`, `settings`
**Milestone:** Future

### Tasks
- [x] Portable preset file import/export (`audune.visualPresetExchange` schema 1) with Settings Export… / Import…, preview, conflict handling, and strict validation.
- [ ] Evaluate Ribbon, Particles and Spectrogram only after profiling basic views.
- [ ] Keep import path free of code execution or arbitrary shader loading when adding advanced visuals.

### Acceptance criteria
- [x] No preset exchange file can execute code or load arbitrary binary payloads.
- [x] Invalid/unknown preset exchange versions fail gracefully.
- [ ] Advanced visuals do not regress the core app's idle power use.

### Dependencies
Core MVP released and profiled. Preset import/export lives in Settings Visual preset controls; remaining work is advanced modes only.

---

## AUD-26 — Studio v1.4: Settings Window & Interaction Polish

**Labels:** `P1`, `ui`, `settings`
**Milestone:** Phase 2 — Core Surfaces

### Tasks
- [ ] Fix Studio grip drag hit coordinates (`NSHostingView` is flipped) and record the resize path; keep drag/resize rows `NOT TESTED` until a real Mac session.
- [ ] Add a separate normal-level, resizable Settings window (about 760x600) with a native sidebar; reduce Studio to three modes, Settings, and a grip.
- [ ] Preferences v2, Appearance, and Spectrum settings; bars come from real FFT bins; one Process Tap.
- [ ] Redraw Waveform from real PCM with style and density settings.
- [ ] Redraw Orbit with radial settings.
- [ ] Window settings: mode, drag/resize, position restore, hover delay, animation, Reduce Motion.
- [x] External player Playback / Apple Events removed from the product (no Music/Spotify control UI or `NSAppleEventsUsageDescription`).
- [ ] (Conditional) Edge resize handles only if the real-Mac check shows `.resizable` fails.

### Acceptance criteria
- [ ] Build and automated tests pass; GUI and Spaces checks are recorded as `PASS`/`FAIL`/`NOT TESTED` in `docs/MANUAL_TESTS.md`.
- [ ] No second capture session; Studio window stays fully transparent; no private APIs.
- [x] Audune does not claim to control browser audio, Music, Spotify, or system output playback.

### Dependencies
AUD-09, AUD-13.

---

## AUD-27 — [FUTURE] Island Fullscreen Lyrics scene

**Labels:** `P2`, `island`, `lyrics`, `ui`, `test`
**Milestone:** Future — Island Fullscreen Lyrics

### Goal
Add Lyrics as a second scene inside the existing Island Fullscreen window. Keep it separate from Compact/Expanded wings, Studio, Menu Bar, and Desktop Magnet. Preserve the existing Now Playing preference and use the existing service only while a runtime Lyrics demand exists.

### Tasks
- [ ] Add independent Visualizer / Lyrics scene selection while preserving Spectrum / Waveform / Orbit selection.
- [x] Add normalized line and optional timed-word data with line-only behavior when no word timestamps exist.
- [x] Implement a read-only continuous lyric time sampler that follows `NowPlayingService`; do not duplicate playback metadata/correction ownership.
- [ ] Implement user-selected local LRC import, security-scoped file access, and persistent cross-player track association.
- [ ] Keep Playback Identity (session change/request validation) separate from Lyrics Track Key (song association); never include player bundle identifier in the lyrics key.
- [ ] Verify title/artist normalization and duration/album disambiguation using actual metadata. Do not invent matching tolerances; offer a compact choice when candidates are ambiguous.
- [ ] Add a focused action to delete the current track's imported lyrics.
- [ ] Acquire/release a temporary Now Playing runtime demand without changing or locking `Show Now Playing when expanded`; restore effective listening to the user's existing preference after leaving Lyrics.
- [ ] Add synchronized scrolling, true timed-word fill where available, translation display, Reduce Motion, accessibility, localization, and empty/error states.
- [ ] Review an online lyrics provider's documented API, terms/license, attribution, maintenance, and privacy before integration. Until reviewed, make no lyric network requests and show online lookup as unavailable. If approved later, query only the minimum required track fields and reject stale responses.

### Acceptance criteria
- [ ] Lyrics is a Fullscreen-only scene; existing visualizer controls, window geometry, Now Playing preference, Compact UI, and Process Tap lifecycle remain independent.
- [ ] Pause freezes, resume continues, seek relocates, and track changes reset lyric presentation using `NowPlayingService` as the sole playback authority.
- [ ] Local LRC is persisted against a cross-player song key, wins over any future online result, can be removed per track, and is read through the selected-file security scope.
- [ ] Ambiguous local versions are never silently selected; match normalization and duration rules are backed by observed metadata.
- [ ] No online lyrics traffic occurs until provider review is complete. Empty, offline, unavailable, and malformed-file states are explicit.
- [ ] Automated tests pass; real Now Playing clients, file access, layout, and accessibility behavior are recorded honestly in `docs/MANUAL_TESTS.md`.

### Dependencies
AUD-17, AUD-NP-01.

---

## Project-wide Definition of Done

- [ ] Current branch is still `dev`.
- [ ] Build passed in the current environment, or the blocker is documented.
- [ ] Relevant automated tests passed; manual tests are honestly marked.
- [ ] No unrelated refactor, private API, new unnecessary dependency, raw audio file, network upload, or telemetry was introduced.
- [ ] User-facing states and docs reflect actual behavior.
- [ ] Each completed and validated TODO has its own commit using `:gitmoji: short-git-message`.
- [ ] No automatic push occurred; commits contain only files belonging to the corresponding TODO, not pre-existing user changes.
