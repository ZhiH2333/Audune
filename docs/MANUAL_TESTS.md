# Audune — Manual Test Checklist

> Run this checklist on a real macOS user session. Mark each case `PASS`, `FAIL`, or `NOT TESTED`; include macOS version, Mac model, and notes. Do not mark real system-audio capture as passed based only on synthetic DSP tests or CI.

## Test environment

- macOS version/build: macOS 27.0.1 (26A434)
- Mac model / CPU: MacBook Pro (Mac15,6), Apple M3 Pro
- Display setup (built-in / external / scaled resolutions): built-in Liquid Retina XDR, 3024 x 1964, one display
- Audune version / commit: Debug build at `400e264` (`:sparkles: add menu bar spectrum`)
- Tester / date: local session, 2026-10-24

## A. First launch and permissions

- [ ] `NOT TESTED` — First launch shows the expected app entry point and no unexpected Dock icon.
- [ ] `NOT TESTED` — Starting system audio capture presents the expected macOS permission prompt.
- [ ] `NOT TESTED` — Granting permission leads to a running capture state.
- [ ] `NOT TESTED` — Denying permission produces clear instructions and does not falsely show live audio.
- [ ] `NOT TESTED` — Changing permission in System Settings and retrying/relaunching behaves predictably.
- [ ] `NOT TESTED` — Audune does not request microphone permission.

## B. Real system audio capture

- [ ] `NOT TESTED` — Browser video/audio drives the visualizer.
- [ ] `PASS` — A local audio player drives the visualizer. `afplay` of an 80 Hz + 4 kHz tone moved the menu bar; the debug window went from `Frames 0` / `State running` to `State receiving` (39424, then 1264128, then 1315328 frames).
- [ ] `PASS` — Pausing playback returns the display to a stable silence/baseline state. After stopping `afplay`, the panel read `No audio` and the status item was one baseline.
- [ ] `PASS` — Resuming playback resumes visual response without restarting the app. Playing again returned `Listening` and the same 16-bar shape.
- [ ] `NOT TESTED` — Output volume/device remains unchanged; capture does not mute or interrupt playback.
- [ ] `NOT TESTED` — Built-in speakers and available headphones work.
- [ ] `NOT TESTED` — Available Bluetooth output device can be selected/connected without leaving the app stuck.
- [ ] `NOT TESTED` — System sleep/wake restores capture or presents an actionable error.
- [ ] `NOT TESTED` — Stop/start capture 20 times without crash or resource accumulation.

## C. Menu bar

- [ ] `PASS` — Menu-bar visual responds to real audio and settles during silence. Idle and silence are one baseline. The two-tone showed 16 bars, tall on the left and one shorter bar to the right. Stop while audio continued returned the baseline and it stayed there on a second capture. `Not listening` before Start; `No audio` while running and silent; `Listening` while audio played. `Starting` and `Capture failed` were not seen.
- [ ] `PASS` — Icon remains legible in the current menu-bar appearance. Dark appearance: light baseline and light bars on the dark menu bar. System appearance was then set to light: the popover used dark text on a light panel, and the menu bar item stayed light on the dark menu-bar material, still readable. Appearance was restored to Dark.
- [ ] `PASS` — Clicking the icon opens the control popover. The panel showed `Not listening`, an enabled Start, a dimmed Stop, `Open Debug Window`, and `Quit Audune`.
- [ ] `NOT TESTED` — Mode switching does not interrupt capture.
- [ ] `NOT TESTED` — Studio, Settings, retry, and Quit actions work.
- [ ] `NOT TESTED` — On macOS versions with a system menu-bar visibility control, Audune remains visible when permitted by system settings.

## D. Studio

- [ ] `NOT TESTED` — Studio opens and closes independently of the audio engine.
- [ ] `FAIL` — Studio can be dragged. On the real Mac session below, the borderless panel did not move.
- [ ] `NOT TESTED` — Studio can be resized without graphic clipping.
- [ ] `NOT TESTED` — Always-on-Top on/off changes window layering as expected.
- [ ] `NOT TESTED` — Window geometry and chosen mode restore after app restart.
- [ ] `NOT TESTED` — Moving to an external display then disconnecting it restores Studio to a visible screen.
- [ ] `FAIL` — Studio is visible on every macOS desktop Space. It appeared on only one Space.
- [ ] `NEEDS REDESIGN` — Studio visual review. The current chrome is not acceptable and needs a systematic redesign.

Studio v1 observation, 2026-10-24, same MacBook Pro (Mac15,6) and macOS 27.0.1 listed above. Debug build at `69a3f68` (`:sparkles: add studio visual settings`). Confirmed on that build: multi-desktop `FAIL`, dragging `FAIL`, visual review `NEEDS REDESIGN`. These three are not `PASS`. Rows that were not run in that session stay `NOT TESTED`.

The floating panel can be opened from the menu bar. `StudioFrameTests` only checks off-screen frame clamping. Color, opacity, mode, and always-on-top persistence are covered by `StudioPreferencesTests`; seeing them in the window stays `NOT TESTED`.

### Studio v1.1 window checks

`StudioWindowBehaviorTests` checks collection-behavior flags and drag-route geometry only. These rows stay `NOT TESTED` until a real macOS GUI session runs them. Do not mark them `PASS` from that automated test.

- [ ] `NOT TESTED` — With Studio open, switching to another desktop Space still shows Studio without reopening it.
- [ ] `NOT TESTED` — A full-screen app shows Studio on that Space while Always on Top is on.
- [ ] `NOT TESTED` — With Always on Top off, a full-screen app can cover Studio.
- [ ] `NOT TESTED` — Leaving full screen leaves Studio visible on the normal desktop.
- [ ] `NOT TESTED` — Dragging the canvas moves Studio. Start, Stop, mode, Always on Top, color, opacity, Reset, and Close do not start a drag.
- [ ] `NOT TESTED` — Resizing from the window edges does not clip the graphic.
- [ ] `NOT TESTED` — Dragging Studio to another display, then disconnecting that display, returns it to a visible screen.
- [ ] `NOT TESTED` — Studio v1.1 visual review. Graphite and warm white, the canvas is the main surface, the bar stays compact, appearance settings stay collapsed until requested, and Spectrum, Waveform, and Orbit share that chrome.

The v1 `NEEDS REDESIGN` row above stays as the record of the old chrome. The v1.1 visual review stays `NOT TESTED` until someone looks at it on a real Mac.

## E. Visualizers

- [ ] `PASS` — Spectrum responds to changes in audio frequency and energy. This was the menu bar only: left bars tracked 80 Hz and a separated bar tracked 4 kHz. Studio draws those same 16 bands, but that window was not part of this recorded session and stays `NOT TESTED`.
- [ ] `NOT TESTED` — Waveform represents incoming samples and does not use random motion. `WaveformSamplerTests` uses synthetic windows only.
- [ ] `NOT TESTED` — Orbit responds to real frequency-band data. `OrbitLayoutTests` checks geometry only.
- [ ] `NOT TESTED` — All modes handle silence with a stable baseline.
- [ ] `NOT TESTED` — Switching modes repeatedly creates no duplicate capture tasks.
- [ ] `NOT TESTED` — Very small and large window sizes do not crash or draw invalid geometry.

## F. Island (only after the Island milestone)

- [ ] `NOT TESTED` — Notch location uses actual display geometry on a supported MacBook.
- [ ] `NOT TESTED` — Collapsed state is compact and does not block normal menu-bar controls.
- [ ] `NOT TESTED` — Hover expansion, click-to-pin, delayed collapse, and Escape behave correctly.
- [ ] `NOT TESTED` — Opening/closing Island does not restart capture.
- [ ] `NOT TESTED` — Built-in and external display switching recalculates location correctly.
- [ ] `NOT TESTED` — On a no-notch display, Island is disabled or degrades as documented without covering unrelated system UI.
- [ ] `NOT TESTED` — Full-screen applications do not cause stuck, invisible, or click-blocking windows.

## G. Desktop Magnet (only after the Magnet milestone)

- [ ] `NOT TESTED` — Magnet can be dragged and resized.
- [ ] `NOT TESTED` — A normal application window can cover Magnet.
- [ ] `NOT TESTED` — Magnet does not force itself to front when switching apps.
- [ ] `NOT TESTED` — Position, size, and mode restore on next launch.
- [ ] `NOT TESTED` — Display disconnect moves it back into a visible area.
- [ ] `NOT TESTED` — Closing/hiding Magnet does not stop the shared audio engine.

## H. Performance, lifecycle, privacy

- [ ] `NOT TESTED` — Run for at least 30 minutes without crash or obvious memory growth.
- [ ] `NOT TESTED` — Hidden surfaces no longer perform high-frequency drawing.
- [ ] `NOT TESTED` — When audio analysis is explicitly stopped, capture resources are released.
- [ ] `NOT TESTED` — No raw audio file is created.
- [ ] `NOT TESTED` — No audio data, telemetry, or analytics is sent over the network.
- [ ] `NOT TESTED` — Permission and capture errors remain distinguishable from silence.
- [ ] `PASS` — Current Git branch is `dev`.
- [ ] `PASS` — Every completed and validated TODO has its own commit using `:gitmoji: short-git-message`. Spectrum path is `75cef7e`; menu bar is `400e264`.
- [ ] `PASS` — No automatic push occurred and no pre-existing user changes were included in commits. `dev` has no upstream.

## Results

- Passed: local playback, pause, resume, menu-bar response, silence baseline, popover, shared debug-window counters, Quit, and both appearance checks recorded on 2026-10-24. `Open Debug Window` brought the existing counter window forward. Frames stayed at 1326080 across two reads after Stop. Quit left output unmuted on `MacBook Pro扬声器`.
- Failed: Studio v1 at `69a3f68` on 2026-10-24 — multi-desktop `FAIL`, dragging `FAIL`, visual review `NEEDS REDESIGN`. The earlier menu-bar cases in this file had no failures.
- Not tested: permission prompt (Start did not show one and capture still ran), denying or changing permission, microphone prompt, browser audio, headphones, Bluetooth, sleep, 20 start/stop cycles, 30-minute run, mode switching, Studio open/close, resize, Always-on-Top, geometry restore, external-display disconnect, Settings, retry, Island, Magnet, waveform, orbit, and `Capture failed`. `Starting` passed too quickly to read. Output volume was 44 unmuted near the start of the session and 38 unmuted immediately before and after Quit; the device did not change and Quit did not mute playback, but the earlier volume change was not bracketed, so that checklist row stays `NOT TESTED`.
- Issues filed: none.
- Logs/screen recordings (avoid capturing private audio content): none saved in the repository.
