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

### Studio v1.2 window checks

`StudioWindowBehaviorTests` checks collection-behavior flags, drag-route geometry, and screen-coordinate origin math. Calling `performDrag(with:)` previously logged `Window move completed without beginning` and is not treated as a successful drag. These rows stay `NOT TESTED` until a real macOS GUI session sees the window move. Do not mark them `PASS` from a unit test, a synthetic mouse event, or a successful build.

- [ ] `SUPERSEDED` — Dragging the canvas blank area moves the Studio window. Blank clicks do not drag. Use the grip check in Studio Transparent Canvas, which stays `NOT TESTED`.
- [ ] `NOT TESTED` — Start, Stop, mode, color, opacity, Always on Top, Reset, and Close do not move the window.
- [ ] `NOT TESTED` — Resizing from the window edges does not clip the graphic.
- [ ] `NOT TESTED` — Position and size restore after relaunch.
- [ ] `NOT TESTED` — With Studio open, switching to another desktop Space still shows Studio without reopening it.
- [ ] `NOT TESTED` — A full-screen app shows Studio on that Space while Always on Top is on.
- [ ] `NOT TESTED` — With Always on Top off, a full-screen app can cover Studio.
- [ ] `NOT TESTED` — Leaving full screen leaves Studio visible on the normal desktop.
- [ ] `NOT TESTED` — Dragging Studio to another display, then disconnecting that display, returns it to a visible screen.

### Studio v1.2 Clean Canvas

Superseded by Studio Transparent Canvas. Do not mark these rows `PASS`. The full-window plate, border, shadow, and Clean Canvas toggle were removed. `StudioChromeTests` still checks the hide delay, held controls, and Reduce Motion durations. `StudioPreferencesTests` checks that saving clears the old `studio.cleanCanvas` key. Neither test moves a window.

- [ ] `SUPERSEDED` — Clean Canvas off keeps the full Studio interface visible with no auto-hide.
- [ ] `SUPERSEDED` — Clean Canvas on and Waveform: after the pointer leaves, only the real waveform remains. The background, border, shadow, and controls are gone, and the wave does not jump.
- [ ] `SUPERSEDED` — Moving the pointer back fades the same controls in. Opening settings or dragging a slider keeps them visible.
- [ ] `SUPERSEDED` — The menu-bar Clean Canvas switch restores the full interface.
- [ ] `NOT TESTED` — Hiding or showing the chrome does not stop menu-bar capture.
- [ ] `NOT TESTED` — Spectrum and Orbit bar counts update immediately across 8, 12, 16, 24, 32, 48, and 64, persist after relaunch, and do not change the menu bar from 16 bars.
- [ ] `SUPERSEDED` — Studio v1.2 visual review. One shared canvas, graphite and warm white, controls appear on demand, and Spectrum, Waveform, and Orbit use that same chrome.

### Studio Transparent Canvas

`StudioWindowBehaviorTests` checks that the panel is non-opaque, has no shadow, does not ignore mouse events, and that only the grip rectangle routes to drag. That is not a visual or window-movement pass. These rows stay `NOT TESTED` until a real macOS GUI session. Do not mark them `PASS` from a unit test, a synthetic mouse event, or a successful build.

- [ ] `NOT TESTED` — Studio has no full-window plate, mask, card, border, or window shadow. Desktop content is visible around Spectrum, Waveform, and Orbit, including after the controls fade out.
- [ ] `NOT TESTED` — Spectrum, Waveform, and Orbit follow the shared audio snapshot. Opacity changes the graphic only. The menu bar stays at 16 bars.
- [ ] `NOT TESTED` — Mode, Settings, Pin / On Top, and Hide work. Clicking them does not move the window. Start, Stop, color, opacity, bar count, and Reset inside Settings do not move the window.
- [ ] `NOT TESTED` — Dragging the grip moves the Studio window. Dragging the blank area does not.
- [ ] `NOT TESTED` — Resizing from the window edges does not clip the graphic.
- [ ] `NOT TESTED` — Position, size, mode, opacity, color, bar count, and Always on Top restore after relaunch.
- [ ] `NOT TESTED` — With Studio open, switching to another desktop Space still shows Studio without reopening it.
- [ ] `NOT TESTED` — A full-screen app shows Studio on that Space while Always on Top is on.
- [ ] `NOT TESTED` — With Always on Top off, a full-screen app can cover Studio.
- [ ] `NOT TESTED` — Leaving full screen leaves Studio visible on the normal desktop.
- [ ] `NOT TESTED` — Dragging Studio to another display, then disconnecting that display, returns it to a visible screen.
- [ ] `NOT TESTED` — After the pointer leaves, the controls fade and no full background appears. Moving the pointer back shows the same controls.
- [ ] `NOT TESTED` — Clicking the transparent area around the visualization. Record whether the app underneath receives the click. The panel does not set `ignoresMouseEvents`; this row is not click-through success.
- [ ] `NOT TESTED` — Showing or hiding Studio, or changing bar count, does not restart menu-bar capture.

### Studio v1.3 drag

`StudioWindowBehaviorTests` checks that a hidden grip does not route to drag, and that one screen-coordinate delta changes an offscreen panel origin. Neither test is a real pointer drag. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — Dragging the grip moves the Studio window on a real Mac. The console does not log `Window move completed without beginning`.
- [ ] `NOT TESTED` — Dragging the blank canvas, a button, a slider, or a picker does not move the window.
- [ ] `NOT TESTED` — Resizing from the window edges still works after the grip tracking change.

### Studio v1.3 window modes

Level and collection-behavior flags are covered by `StudioWindowBehaviorTests`. Those tests do not show the panel on another Space or over a full-screen app. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — On Desktop sits behind an ordinary app window and stays visible above the wallpaper.
- [ ] `NOT TESTED` — On Top stays above ordinary app windows.
- [ ] `NOT TESTED` — As Window uses normal ordering and can be covered by another ordinary window.
- [ ] `NOT TESTED` — Switching among the three modes does not hide Studio or change its position.
- [ ] `NOT TESTED` — On Top remains visible after switching to another desktop Space, remains visible beside a full-screen app, and is still on the normal desktop after leaving full screen.
- [ ] `NOT TESTED` — As Window stays on its own Space and a full-screen app can cover it.
- [ ] `NOT TESTED` — On Desktop's actual multi-Space behavior is recorded here after a real session. Do not mark this `PASS` from `canJoinAllSpaces` alone.
- [ ] `NOT TESTED` — The selected window mode and frame restore after relaunch.

### Studio v1.3 hover controls

`StudioChromeTests` checks the 200ms / 400ms / 250ms timings, Reduce Motion, and an 8pt edge slop. It does not move a pointer over the window. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — With the pointer away, only the visualization is visible. No full-window background, bar, or border appears.
- [ ] `NOT TESTED` — Moving into the window fades in mode, settings, window mode, and the grip. Moving toward those controls does not hide them.
- [ ] `NOT TESTED` — After the pointer leaves, the controls wait briefly and then fade out.
- [ ] `NOT TESTED` — Settings, window mode, and the grip can be used. Hide is inside Settings. None of these clicks move the window.
- [ ] `NOT TESTED` — Reduce Motion shows and hides the controls without a fade. The leave delay remains.

### Studio v1.3 visuals

Geometry tests cover bar gap, waveform display gain, orbit inner ring, and display smoothing. They do not judge appearance on a real desktop. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — Spectrum, Waveform, and Orbit look deliberate at their defaults, before any slider is moved. Waveform and Orbit are not a recolor of the previous drawing.
- [ ] `NOT TESTED` — Line width, color, opacity, amplitude, and smoothing change the graphic immediately and restore after relaunch. Reset returns the defaults.
- [ ] `NOT TESTED` — Spectrum bar counts 8, 12, 16, 24, 32, 48, and 64 follow real frequency energy. The menu bar stays at 16 bars. Gap, corner radius, and optional bar stroke work.
- [ ] `NOT TESTED` — Waveform follows real playback, including quiet passages. Orbit follows frequency energy and rests on its ring during silence.
- [ ] `NOT TESTED` — Changing these settings does not create a second Process Tap.

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
