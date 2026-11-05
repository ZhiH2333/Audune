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
- [ ] `NOT TESTED` — Clicking a blank area outside the control popover closes it; clicking elsewhere does not stop capture unexpectedly.
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

### External player control (removed)

Music/Spotify Play/Pause, Settings → Playback, Automation / Apple Events prompts, and `NSAppleEventsUsageDescription` were removed from the product. Audune only visualizes system audio. Do not re-test player Automation rows; they no longer apply.

### Studio v1.4 drag and resize

Root cause evidence is from code and a probe, not from a GUI pass: `NSHostingView.isFlipped` is `true` on macOS 27.0.1, while the drag hit map flipped SwiftUI frames a second time. That mirrored the grip and the control regions to the opposite window edge. The fix keeps SwiftUI frames as they are inside a flipped container. `StudioWindowBehaviorTests` routes points in a real `NSHostingView` inside an offscreen window; that is a coordinate check, not a pointer drag. A Debug build logs the grip drag begin and end: `log stream --predicate 'subsystem == "Audune" AND category == "StudioDrag"'`. These rows stay `NOT TESTED` until a real macOS GUI session.

- [ ] `NOT TESTED` — Dragging the grip moves Studio, and the console does not log `Window move completed without beginning`. The Debug log shows `drag begin` and `drag end` with different origins.
- [ ] `NOT TESTED` — Dragging the blank canvas, a button, a slider, or a picker does not move the window.
- [ ] `NOT TESTED` — Resizing from the four edges and four corners works, keeps the visual border transparent, and stops at the minimum size.
- [ ] `NOT TESTED` — Position and size restore after relaunch and stay on a visible screen.

### Studio v1.4 Settings window

`SettingsWindowTests` checks the window style mask, level, collection behavior, and sizes only. They do not show the window on a desktop. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — The Studio bar shows only the grip, Spectrum, Waveform, Orbit, and Settings. The window around the graphic stays fully transparent.
- [ ] `NOT TESTED` — The Settings button and the menu-bar `Settings…` item open one Settings window of about 760x600 that can be resized and keeps its frame after relaunch.
- [ ] `NOT TESTED` — Settings stays an ordinary window under On Desktop, On Top, and As Window. Record whether an On Top Studio covers it.
- [ ] `NOT TESTED` — Hiding Studio from Settings or the menu bar leaves Settings open. Show Studio brings Studio back.
- [ ] `NOT TESTED` — The sidebar lists Startup, Appearance, Visualization, Studio, and Notch Island; Visualization switches Spectrum / Waveform / Orbit in-page; Studio holds layout preview plus window controls; every non-Startup control changes Studio immediately and survives relaunch.

### Studio v1.4 Appearance and Spectrum

`StudioPreferencesTests`, `SpectrumBandsTests`, `SpectrumDynamicsTests`, and `SpectrumBarsTests` use synthetic bins and values. They check migration, ranges, that adjacent bars do not repeat a value, motion math, and peak-cap geometry. They do not judge appearance or real playback. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — Appearance presets, the two color pickers, opacity, and stroke width change Studio immediately and survive relaunch. The window around the graphic stays transparent.
- [ ] `NOT TESTED` — Spectrum bar counts 8 to 64 follow real playback; Logarithmic and Linear look different; low and high frequency limits move which bars react; Solid / Frequency / Amplitude color mapping are visibly different and Peak Hold caps stay readable.
- [ ] `NOT TESTED` — Sensitivity, amplitude, smoothing, attack, release, and peak hold change the motion. Silence settles to the baseline. The menu bar stays at 16 bars.
- [ ] `NOT TESTED` — Peak hold Fall speed changes how quickly caps drop after Hold time. Turning peak hold off removes caps without changing bar heights.
- [ ] `NOT TESTED` — Silence gate Noise floor (RMS) with hysteresis: weak noise settles; normal quiet music still moves. Entering silence releases through Attack/Release (no snap). Disabling the gate keeps weak signal motion. Studio and Notch Island match.
- [ ] `NOT TESTED` — Reset Appearance and Reset Spectrum restore their defaults only. Changing these settings does not start a second Process Tap.

### Studio v1.4 Waveform

`WaveformSamplerTests` uses synthetic sample arrays. It checks that density only picks real samples (no upsampling), edge fade, flat silence, and curve geometry inside the canvas. It does not judge appearance or real playback. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — The default Waveform is a smooth centered curve with a faint baseline and ends that rest on the baseline; it is not the old polyline in a new color.
- [ ] `NOT TESTED` — Real playback changes the shape, quiet passages still move off the baseline, and silence settles to a flat line.
- [ ] `NOT TESTED` — Fine Line, Soft Fill, and Mirror styles, density 32/64/128, custom line color, stroke width, maximum display height, visual amplitude, fill strength, and motion smoothing apply immediately, survive relaunch, and Reset Waveform restores them. Default visual amplitude stays calmer than the old ×3 boost. At maximum display height 100% and max stroke width, peaks reach the stroke-safe canvas edge without a mid-canvas hard clip; strokes stay inside the visualization frame after resizing.
- [ ] `NOT TESTED` — With Layout → Fill window, Waveform uses the full Studio content area (minus stroke inset). With Fixed size, enlarging the window leaves empty margin around a fixed viz — that is Layout, not Waveform clipping.
- [ ] `NOT TESTED` — Notch Island Expanded Waveform stays inside the island content area with the same range/amplitude prefs; Island window geometry is unchanged.

### Studio v1.4 Orbit

`OrbitLayoutTests` uses synthetic spectra. It checks that bars and their rounded caps stay inside the canvas, silence is an even ring, mirroring is symmetric and reads half the bands, and gap and radius settings move the geometry. It does not judge appearance or real playback. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — The default Orbit looks deliberate: a centered ring of rounded bars, low frequencies at the top, left and right mirrored, not the old thin spokes.
- [ ] `NOT TESTED` — Real playback moves the bars; silence settles to a ring of dots and does not rotate; resizing keeps the ring centered and inside the window.
- [ ] `NOT TESTED` — Bars 8 to 64, mirror, inner and outer radius, angular gap, Single/Dual Band layers, pulse strength, stroke, custom color, amplitude, and motion smoothing apply immediately, survive relaunch, and Reset Orbit restores them.

### Visual presets v1

`VisualPresetStoreTests`, `VisualPresetApplyTests`, `VisualPresetSelectorTests`, `VisualPresetCustomTests`, `VisualPresetIslandTests`, `VisualPresetExchangeCodecTests`, `VisualPresetExchangeExportTests`, and `VisualPresetExchangeImportTests` check encoding, corrupt data, mode isolation, built-in values, custom save/rename/delete, portable exchange round-trips, import validation/conflicts, and that Studio and Notch Island hold the same mode structs. They do not judge how the presets look or how the settings window sits on a desktop. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — Spectrum, Waveform, and Orbit each show a Visual preset control at the top. Choosing Clean, Dense, Dynamic, Fine Line, Soft Fill, Mirror, Compact, Halo, or Dense Ring changes that mode immediately in an open Studio. The other mode, Appearance colors, and the window mode stay as they were.
- [ ] `NOT TESTED` — Saving the current settings asks for a name, then shows that custom preset. Duplicate, Rename, and Delete work on custom presets. Built-in presets cannot be renamed or deleted. Delete asks first and leaves the current sliders where they are.
- [ ] `NOT TESTED` — After a preset is applied, status shows only the preset name; moving one of that mode's sliders changes it to “name (Modified)”. Changing only Appearance does not. Quit and relaunch keeps the applied preset (including when Startup previously pointed at a different Visual preset).
- [ ] `NOT TESTED` — With Notch Island expanded on the same mode, the graphic follows the preset. Compact wings keep their own bar count. Studio and Island can show different modes at the same time. Applying a preset does not start a second Process Tap.
- [ ] `NOT TESTED` — Export… opens a multi-select sheet for the current mode (built-in and custom). Exporting one or many presets writes a `.json` file via the save panel. The file opens as readable JSON with `format` `audune.visualPresetExchange` and does not change Appearance, Window, or other modes.
- [ ] `NOT TESTED` — Import… opens a file picker, shows a preview with names, modes, and name conflicts, and offers Import as copies / Skip conflicts / Cancel. Confirming adds only new custom presets (new ids). Cancel leaves the library unchanged. Importing a built-in snapshot creates a custom copy and does not alter the built-in definition. A file with an unsupported schema version is rejected with an error and does not write.

### Studio v1.4 Window settings

`StudioChromeTests`, `StudioPreferencesTests`, and `StudioWindowBehaviorTests` check hide-delay math, Reduce Motion rules, ranges, style-mask and drag flags, and the centered default frame. None of them moves a window, shows a Space, or touches a real pointer. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — Turning off "Allow dragging by the grip" stops the grip from moving the window; turning it on restores dragging.
- [ ] `NOT TESTED` — Turning off "Allow resizing from the edges" stops edge resizing; turning it on restores it.
- [ ] `NOT TESTED` — "Restore position and size at launch" off opens Studio centered at the default size; on restores the last frame. Reset Position and Size recenters at the default size on a visible screen.
- [ ] `NOT TESTED` — Window → Size Width/Height (pt) resize Studio immediately; dragging edges updates the sliders; relaunch restores size when Restore is on; Reset Position and Size returns to 640×400. Notch Island size is unchanged. Old min/max size limit controls are gone from the UI.
- [ ] `NOT TESTED` — Fade on/off and Follow system Reduce Motion change the control fade as described. There is no hide-delay slider; buttons hide 3 seconds after the pointer leaves. Studio never gets a window background.
- [ ] `NOT TESTED` — The three window modes change the level and Spaces behavior described in the Window pane. Record the real multi-desktop result for On Desktop here; do not infer it from `canJoinAllSpaces`.

### Studio signed-build check (permissions)

Static build facts recorded on 2026-10-25 (macOS 27.0.1, Apple Silicon MacBook Pro), Debug build signed by `xcodebuild test` without `CODE_SIGNING_ALLOWED=NO`:

- `codesign -dvv`: signed by `Apple Development`, team `334R786Y6V`, identifier `devplaceholder.UFJKN3LA.Audune` (a placeholder bundle identifier), no hardened runtime flag.
- `codesign --verify --strict`: `valid on disk`, `satisfies its Designated Requirement`.
- `Info.plist` has non-empty `NSAudioCaptureUsageDescription` only among usage descriptions; no `NSAppleEventsUsageDescription`, no microphone key. `ReleaseConfigurationTests` asserts this on the built app bundle.

- [ ] `NOT TESTED` — First launch does not prompt for Automation / Apple Events. Only system audio recording permission appears when capture starts.
- [ ] `NOT TESTED` — Studio chrome has no Play/Pause control; Settings has no Playback sidebar category.

### Studio mouse passthrough and auto-hide

`StudioPassthroughTests` checks separate-panel frames, that the visual panel ignores mouse events in On Top, On Desktop, and As Window, and that a canvas point is absent from that panel's window-server hit list. `StudioChromeTests` checks hide timing, cancellation, and summon-region geometry. `StudioPreferencesTests` checks defaults and clamping. None of these is a click in another app. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — In On Top, On Desktop, and As Window, a click on the blank visualization reaches the app underneath. The three visual modes, Settings, the grip, and the resize edges still receive their own clicks.
- [ ] `NOT TESTED` — Hiding Studio, or switching away, leaves no invisible control or resize overlay. A saved "passthrough off" value does not bring the full-window hit target back.
- [ ] `NOT TESTED` — Auto-hide on: the canvas stays the full window. After the pointer leaves the controls, they fade out 3 seconds later. Returning before those 3 seconds cancels the hide. Holding the mouse button keeps the controls up.
- [ ] `NOT TESTED` — The drag handle stays visible and can move the window while the other buttons are hidden. Moving the pointer near that handle shows the icon-and-text buttons. Moving away hides those buttons again. Hidden buttons do not receive clicks.
- [ ] `NOT TESTED` — Auto-hide off keeps the controls visible. Reduce Motion removes the fade and does not remove the hide delay. A missing preference key does not reset the other window settings.

## E. Visualizers

- [ ] `PASS` — Spectrum responds to changes in audio frequency and energy. This was the menu bar only: left bars tracked 80 Hz and a separated bar tracked 4 kHz. Studio draws those same 16 bands, but that window was not part of this recorded session and stays `NOT TESTED`.
- [ ] `NOT TESTED` — Waveform represents incoming samples and does not use random motion. `WaveformSamplerTests` uses synthetic windows only.
- [ ] `NOT TESTED` — Orbit responds to real frequency-band data. `OrbitLayoutTests` checks geometry only.
- [ ] `NOT TESTED` — All modes handle silence with a stable baseline.
- [ ] `NOT TESTED` — Switching modes repeatedly creates no duplicate capture tasks.
- [ ] `NOT TESTED` — Very small and large window sizes do not crash or draw invalid geometry.

## F. Island (Notch Island v1)

`IslandGeometryTests`, `IslandPreferencesTests`, `IslandStateMachineTests`, and `IslandWindowControllerTests` cover pure screen-geometry validation, multi-display fallback, symmetric compact bar rects, preferences persistence/clamping, state transitions (Disabled / Compact / Expanded / Pinned), delayed collapse cancellation, and offscreen panel flags. They do not verify physical notch alignment, real pointer hover, menu-bar click pass-through outside the compact frame, Spaces, or full-screen behavior on a real desktop. All rows below stay `NOT TESTED` until run in a real macOS GUI session.

- [ ] `NOT TESTED` — Notch location uses actual display geometry (`safeAreaInsets.top` + `auxiliaryTopLeftArea` + `auxiliaryTopRightArea`) on a supported MacBook and blends cleanly with the camera housing.
- [ ] `NOT TESTED` — Collapsed (Compact) state shows a symmetric live spectrum on both sides of the notch during playback, settles to a minimal static baseline during silence, keeps a fixed window width, and does not block normal menu-bar items or status-bar icons outside the compact wings.
- [ ] `NOT TESTED` — Moving the pointer into the compact island smoothly expands the panel without jitter; moving out waits for the configured collapse delay and collapses; re-entering before the delay elapses cancels the collapse.
- [ ] `NOT TESTED` — Clicking Pin in the expanded island keeps it open when the pointer leaves; clicking Unpin restores delayed collapse; pressing `Escape` or Collapse returns to Compact immediately.
- [ ] `NOT TESTED` — Expanded state switches cleanly among Spectrum, Waveform, and Orbit, follows Appearance colors, and can open Studio or Settings (`Notch Island` pane) without stealing focus or showing a Dock icon.
- [ ] `NOT TESTED` — The Expanded full-screen button fills the selected notched display with the live visualization; mode switching remains available, the exit button and first Escape return to Expanded/Pinned, and a second Escape collapses to Compact without restarting capture.
- [ ] `NOT TESTED` — Enabling, disabling, expanding, collapsing, or changing Notch Island settings never starts, stops, or restarts `ProcessTapSpike` capture.
- [ ] `NOT TESTED` — Built-in and external display switching, resolution/scaling changes, and wake from sleep recalculate the island location or hide it cleanly when no notched display remains.
- [ ] `NOT TESTED` — On a non-notched display (or clamshell mode with an external monitor only), Notch Island is disabled, hides its window, stops its display timer, and explains the requirement in the menu bar popover and Settings > Notch Island without covering the menu bar.
- [ ] `NOT TESTED` — Switching desktop Spaces and entering/leaving full-screen applications (with "Show in full-screen apps" both off and on) do not leave stuck, invisible, or click-blocking windows.
- [ ] `NOT TESTED` — Reduce Motion removes the expand/collapse frame animation when "Follow system Reduce Motion" is enabled while preserving the collapse delay.

### Notch Island interaction v1.1

`IslandStateMachineTests`, `IslandPreferencesTests`, and `IslandWindowControllerTests` cover the expand delay, prefeedback scale, haptic trigger rules, animation-speed math, and Reduce Motion priority. They do not move a physical pointer or vibrate a trackpad. These rows stay `NOT TESTED`.

- [ ] `NOT TESTED` — Hovering the compact island shows a small content change immediately and does not move the window frame. The island expands only after the expand delay (default 0.35 seconds) if the pointer is still inside. Leaving before that cancels the expand; entering again starts the delay over. The collapse delay stays independent.
- [ ] `NOT TESTED` — Pin, Escape, disabling Island, or changing screens does not leave a late expand or collapse. Pinning from the compact island does not play a haptic.
- [ ] `NOT TESTED` — Haptic feedback off does nothing. Light, Medium, and Strong each fire once when a hover expand finishes, and not again on a cancelled hover, a repeated enter, or an island that is already expanded. A Mac without Force Touch does not vibrate. The three settings are system patterns, not an amplitude slider.
- [ ] `NOT TESTED` — Animation speed changes both expand and collapse. Expand eases out without passing the target frame; collapse eases in. Reduce Motion still removes the frame animation when its follow setting is on, at every speed, including 2.0×.

### Experimental Island Now Playing (AUD-NP-01)

Requires a real macOS GUI session, preferably **15.4+**. `IslandPreferencesTests`, `IslandGeometryTests.testExpandedPlayerFrameIsLargeRegardlessOfNowPlayingSwitch`, and `NowPlayingServiceTests` cover preference defaults (including layout toggles), unified Expanded size, start/stop, empty/unavailable mapping, and seek-unsupported fallback with a fake controller. They do **not** prove MediaRemote or the Perl adapter on a live desktop. Mark rows `PASS` / `FAIL` / `NOT TESTED` honestly. CI must not claim these passed.

- [ ] `NOT TESTED` — With Now Playing default off, Expanded Island uses the same large frame as when Now Playing is on; no mediaremote-adapter process is running; chrome is hidden and visualization fills the body (if Visualization is on).
- [ ] `NOT TESTED` — Settings → Notch Island → Show Now Playing when expanded shows an Experimental note; enabling it does not start or stop Process Tap and does not change Expanded window size.
- [ ] `NOT TESTED` — Settings → Notch Island Preview mirrors Artwork / Title & Artist / Progress / Controls / Visualization toggles (demo track when nothing is listening); Pause freezes the preview and Resume restores live updates; leaving the category pauses like Studio Layout preview.
- [ ] `NOT TESTED` — With Now Playing on and Music / Spotify / Safari (or another Now Playing client) active, Expanded shows only the chrome pieces enabled in layout toggles; Compact wings still show spectrum only (no title text).
- [ ] `NOT TESTED` — With Now Playing on, the full-screen Visualizer scene shows compact artwork and title/artist below the visualization in the lower-left according to their layout toggles, plus a background-free play/pause icon at the lower-right that controls the active player; the icon is disabled with an explanatory tooltip when Now Playing is off or no track is available, and it is not shown in the Lyrics scene (that scene has its own transport row).
- [ ] `NOT TESTED` — Transport controls affect the system Now Playing client; scrubber seek works where MediaRemote supports it, and becomes display-only for sources that silently ignore seek without blocking transport.
- [ ] `NOT TESTED` — Turning the preference off, disabling Island, losing notch geometry, or quitting Audune stops the adapter listener; Expanded keeps the same frame and drops the player chrome when the preference is off.
- [ ] `NOT TESTED` — Empty (nothing reporting Now Playing) and unavailable (adapter failure) states show clear copy and do not crash or misplace the island.
- [ ] `NOT TESTED` — Sleep/wake and display reconfiguration leave Now Playing usable again or show unavailable cleanly without a second Process Tap.

### Island Fullscreen Lyrics (AUD-27; shipped on `dev`)

Automated parser, clock, provider, manager, controller, localization, and presentation-timing tests do not verify real MediaRemote clients, macOS file dialogs, VoiceOver, typography, or full-screen motion. The only live external verification performed below is the LRCLIB HTTP request and the live Spotify session recorded below. Rows not marked `PASS` remain `PARTIAL` or `NOT TESTED` until checked in a real macOS session.

Live GUI acceptance (2026-11-05, 1800×1169 notched Mac, Spotify): entering Audune Fullscreen Lyrics with a real track showed the current cover, title, artist, duration, elapsed/remaining time, and three transport controls; the window stayed exactly 1800×1169 at (0,0) and exited back to the compact 288×38 notch panel. Automatic LRCLIB lookup produced line-synced lyrics for 乾杯, 洋蔥, and 私奔到月球, and plain lyrics for 任性. The focused line advanced with playback, context lines blurred by distance, and the blurred album-art backdrop changed with the track. A temporary local imported-lyrics store fixture using real 乾杯 line text and synthetic equal word durations proved local-first priority, per-character fill, and translation under the active line; the fixture was removed afterward. Setting `island.automaticOnlineLyrics` to false showed the localized online-off state and disabled retry; the preference was restored to true. The progress knob appeared on hover; clicking the bar sought, pause froze the displayed time, resume advanced it, and the next control changed tracks. Release CPU spot-check while the line-synced scene was playing was about 9.4% (down from about 12.2% before the redraw optimization) versus about 1.0% paused; this is an observation, not a profiler trace. These checks do not cover the file picker, VoiceOver, Reduce Motion, offline/error branches, ambiguity, or a live display matrix.

Visual redesign pass (2026-11-05, offscreen only): the real view file was rendered with synthetic artwork and sample Japanese/English lines through a temporary `ImageRenderer` harness at 1296×841 and 900×600 (split) and 900×520, 700×520, 600×900 (compact); the renderer confirmed the upper-third active line, translation tier, distance blur/dim, word fill, interlude dots, player column, and no transport/source clipping. A separate `NSHostingView` snapshot exercised the real blurred-artwork backdrop with `reduceMotion` on. The harness was removed after inspection and did not touch live Now Playing, MediaRemote, or VoiceOver. `ImageRenderer` could not capture the unsynced `ScrollView` content, so that state remains unverified visually.
Typography and offset pass (2026-11-05, offscreen only): the real view was rendered again after switching every lyric row to one uniform font size and absolute row positioning. A long line wrapped identically when focused and when one line away from focus, confirming that focus no longer re-wraps or changes row height. The +0.3 s offset pill appeared beside the source menu, and a second render with `lyricsBlurEnabled` off kept inactive lines sharp but still dimmed. Split 1296×841 and compact 900×520 still fit. `ImageRenderer` cannot show the spring animation or the popover contents; the offset popover, Settings toggle/slider, persistence across relaunch, and live scroll smoothness were **not** exercised in a live GUI.
Elastic motion pass (2026-11-05, offscreen only): the active row uses a 1.06 leading-anchored visual scale against 0.96 for inactive rows (both disabled under Reduce Motion), with a 93% lyric measure so the scaled glyphs cannot clip; upcoming lines use a lighter fade/blur than past lines. Split 1296×841 and compact 900×520 renders confirmed the larger active line, the stable wrap, and the reserved right edge. Interlude dots rendered as three phase-offset dots in the paused state. `ImageRenderer` captures a single frame, so overshoot, the 1.2 s dot hop, and live scroll feel remain **not tested** in a real session; Reduce Motion, pause/resume, and the blur toggle still need live confirmation.

Manual browse pass (2026-11-05, implementation only): wheel and trackpad scroll events enter a native vertical scroll view; rows use scale 1 and blur 0, non-focused original and translated lyrics use 0.30 opacity, and the playing row remains highlighted. The layout anchor stays frozen while playback highlighting continues. Clicking a timestamped line seeks to its playback time with the lyrics offset applied; untimed lines and lines from players without seek support are disabled. The 3.5 s idle timer and the “Back to current lyric” button return to the playing line before restoring the normal focus hierarchy. No live window was available for this pass, so wheel direction, momentum scrolling, pointer containment, row seeking, idle resume, and button hit-testing remain **NOT TESTED** in a real session.
Real provider check (2026-11-04, outside the app): `curl` to `https://lrclib.net/api/get?track_name=Still%20Alive&artist_name=Portal&duration=185` with `User-Agent: Audune/1.0 (macOS lyrics client)` returned HTTP 200, `content-type: application/json`, Cloudflare, record `13709040`, duration `185.0`, `instrumental: false`, `hasWordSync: false`. `syncedLyrics` begins `[00:11.37] This was a triumph!` / `[00:14.95] I'm making a note here`. Automated provider tests parse this response shape and cover 404 search fallback, 429/503/500, timeout, offline, cancellation, HTML/JSON errors, wrong-duration rejection, instrumental, plain-only, and word-sync preference with mocks. The live request was **not** made through the app UI.

- [x] `PASS` — Live LRCLIB API reachable with documented query parameters and returns parseable synchronized lyrics; HTTP status and sanitized result recorded above.
- [x] `PASS` — Spotify populated Now Playing metadata for multiple real tracks; title, artist, album, duration, artwork, and progress were correct.
- [x] `PASS` — Entering Lyrics started an LRCLIB lookup without Import; changing tracks started a new lookup and replaced the previous document.
- [x] `PASS` — Line-synced LRCLIB lyrics followed playback; line-only sources showed no fabricated word fill. A temporary word-timed local fixture showed continuous per-character fill.
- [ ] `PARTIAL` — The online-off state was verified live; no-match, offline, provider-unavailable, rate-limit, network, and parse-error states are covered by automated tests but were not exercised live.
- [ ] `PARTIAL` — Song identity and progress stayed usable when online lyrics were disabled; a real network disconnect/reconnect was not exercised.
- [ ] `NOT TESTED` — The macOS file picker was not exercised. A local store fixture confirmed the local document path, but not security-scoped file access or the listed file encodings.
- [ ] `PARTIAL` — A local store fixture won over the online result and showed the local source label; deletion through the menu was not exercised.
- [ ] `NOT TESTED` — The Settings pane itself was not opened; the preference was toggled through defaults to verify the online-off scene.
- [ ] `PARTIAL` — Progress advanced during online lyrics, froze on pause, resumed, and reset on track change. Local-lyrics, searching, no-lyrics, and invalid-duration variants were not all exercised in one live pass.
- [ ] `PARTIAL` — Pause froze the displayed time and scene; resume advanced from the same position. Word fill was not observed across a pause boundary.
- [ ] `PARTIAL` — Click-to-seek relocated the line immediately and a seek into a word-timed line showed partial fill; gap and past-final-line seeks were not exercised live.
- [x] `PASS` — Live track changes never showed the prior document overwriting the new song; cancellation and generation checks are also covered by `LyricsManagerTests`.
- [ ] `PARTIAL` — Ambiguity and competing-import choice remain automated-test only; no live ambiguous track was selected.
- [ ] `PARTIAL` — The post-redesign split/compact spacing was inspected only through offscreen renders at 1296×841, 900×600, 900×520, 700×520, and 600×900; no live display matrix, resize drag, or real-album-art visual pass was run.
- [ ] `PARTIAL` — Offscreen renders confirmed uniform lyric typography, identical wrapping with and without focus, the +0.3 s offset pill, and the blur-off state; live spring scrolling and live blur toggling were not observed.
- [ ] `NOT TESTED` — The in-lyrics offset popover, the Settings “Blur inactive lyrics” toggle and “Lyrics offset (s)” slider, and persistence across relaunch were not opened in a live GUI. Offset clamping/NaN handling and preference round-trips have unit tests.
- [ ] `NOT TESTED` — Live word fill and interlude-dot motion were not observed; the interlude clock has unit coverage and the dots were inspected as a still render only.
- [ ] `PARTIAL` — Elastic row scaling, direction-aware fading, and the 93% measure guard were inspected offscreen; spring overshoot, live scroll feel, and the 1.2 s dot hop were not observed in a real session.
- [ ] `NOT TESTED` — Manual lyric browsing (native wheel/trackpad scrolling, 0.30 opacity for non-focused lyrics, frozen layout anchor, playing-line highlight, and clicking a timestamped row to seek with lyrics offset) was not exercised in a live window. Also verify untimed/unsupported rows are disabled, the 3.5 s idle auto-resume, and the “Back to current lyric” button with real trackpad, mouse-wheel, and pointer-leave checks.
- [ ] `NOT TESTED` — The final 1:1 visual comparison against AMLL and refined-now-playing-netease on real artwork, display scale, and window sizes was not performed live.
- [ ] `PARTIAL` — On the notched 1800×1169 display the panel stayed 1800×1169 and exited to the compact notch frame; non-notched and display-reconfiguration cases were not run.
- [x] `PASS` — The live player column placed the cover, title/artist, progress, times, and three centered controls as designed; the glyph reflected real Spotify play/pause and no floating play button appeared.
- [x] `PASS` — Play-pause, previous, and next controlled Spotify live; previous restarted the current track as Spotify does. No shuffle or repeat buttons are present by design.
- [ ] `PARTIAL` — The hover knob and click-to-seek worked; VoiceOver's ±5 s action was not tested.
- [ ] `NOT TESTED` — VoiceOver was not exercised.
- [ ] `NOT TESTED` — Reduce Motion was not exercised.
- [ ] `PARTIAL` — Expanded Island, the fullscreen visualizer scene picker, and exit to compact were seen; Compact wings, Studio, Menu Bar, and a full visualizer regression pass were not run.
- [ ] `NOT TESTED` — Process Tap and duplicate-listener behavior were not observed live.

Regression evidence from `dev`: full `xcodebuild test -project Audune.xcodeproj -scheme Audune -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` executes 381 tests with 1 failure, the pre-existing window-server test `StudioPassthroughTests.testCanvasPointResolvesToTheWindowUnderTheVisualPanel` (`AuduneTests/StudioPassthroughTests.swift:213`), which fails identically when run alone and is unrelated to Lyrics. Excluding that suite, `-skip-testing:AuduneTests/StudioPassthroughTests` executes 374 tests with 0 failures. All Lyrics, Now Playing, controller, localization, and presentation-timing suites pass. Debug and Release builds succeed. Re-run on 2026-11-05 after the Lyrics player-column rework (Apple Music–style control stack): the same `-skip-testing:AuduneTests/StudioPassthroughTests` invocation executed 374 tests with 0 failures, including the localization catalog checks after adding the `Playback controls` key. Layout was also checked with an offscreen `ImageRenderer` harness at 1296×841 (split) and 900×520 (compact) using the real view file; that harness only inspects spacing and does not touch live Now Playing, MediaRemote, or VoiceOver. Re-ran again on 2026-11-05 after the full Lyrics scene rebuild and its redraw optimization: 374 tests with 0 failures, and Debug and Release builds succeeded. Re-ran after the visual redesign and compact layout: `-skip-testing:AuduneTests/StudioPassthroughTests` executed 375 tests with 0 failures; Debug and Release builds succeeded. That pass included the temporary offscreen render harness at the five sizes above and an `NSHostingView` backdrop snapshot; the harness was removed before final verification. Re-ran on 2026-11-05 after making lyric typography stable, adding the blur preference, and adding the persisted lyric offset: the same invocation executed 376 tests with 0 failures, and Debug and Release builds succeeded. A temporary offscreen pass rendered the real view at 1296×841 and 900×520, confirmed a long line wraps identically with and without focus, inspected the +0.3 s offset pill and a blur-disabled scene, then removed the harness. These automated results do not upgrade runtime rows that remain partial or not tested.

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

## H2. Startup Behavior & Launch at Login v1

`StartupPreferencesTests`, `StartupApplicatorTests`, and `LaunchAtLoginServiceTests` cover surface defaults/migration, independent checkbox combinations, Island session gate, mode/preset resolution, missing presets, one-shot apply, Launch at Login status mapping, and auto-capture authorization gating. They do not replace a real cold launch or signed Login Items session. All rows below stay `NOT TESTED` until a real macOS GUI session.

- [ ] `NOT TESTED` — With default Startup settings (missing keys), a Release cold launch matches prior behavior: menu bar present, Studio/Settings hidden, Island only if `island.isEnabled` and the display supports a notch. No Dock icon. Capture stays idle.
- [ ] `NOT TESTED` — All Show-at-launch checkboxes unchecked: quiet menu-bar-only launch; Island stays hidden for the session without permanently clearing `island.isEnabled`; menu bar Show Notch Island restores presentation.
- [ ] `NOT TESTED` — Studio / Notch Island / Settings checkboxes can be combined; each selected surface appears once; no duplicate windows; Debug window never appears in Release.
- [ ] `NOT TESTED` — Show Notch Island checked while Island is disabled: Island does not appear; Settings shows the dependency hint and Enable entry; enabling Island presents it without rewriting unrelated prefs.
- [ ] `NOT TESTED` — Show Notch Island on a non-notched layout stays unavailable and the app still launches; no misplaced window.
- [ ] `NOT TESTED` — Startup mode Spectrum / Waveform / Orbit is visible on the first Studio frame and on expanded Island without a visible mode flash; **Keep current selection** leaves prior Studio/Island modes alone even when a startup Visual preset is also set (preset params still apply).
- [ ] `NOT TESTED` — Choosing a built-in or custom startup Visual preset (which sets an explicit mode in the Startup UI) applies that mode’s look at launch (same as Settings apply); Appearance, Window size controls, and Island compact/hover settings stay as they were.
- [ ] `NOT TESTED` — Deleting the custom preset referenced by Startup leaves Settings showing that the preset is unavailable; the next launch still succeeds and does not apply a different preset.
- [ ] `NOT TESTED` — Changing Startup window/mode/preset/auto-capture options in Settings does not alter the current session until the next cold launch.
- [ ] `NOT TESTED` — Switching away from Audune and back, or reopening Studio / expanding Island, does not reapply Startup configuration.
- [ ] `NOT TESTED` — Launch Audune at login: enabling registers via `SMAppService.mainApp`; disabling unregisters; toggle mirrors real system status after System Settings changes; `requiresApproval` shows guidance and Open Login Items.
- [ ] `NOT TESTED` — Login launch with all surfaces unchecked stays quiet (menu bar only); with surfaces checked, the same checkbox rules apply as a manual launch.
- [ ] `NOT TESTED` — Auto-start capture off by default; when on and already authorized, capture starts without a new prompt; when on but unauthorized, no permission dialog appears at launch and Menu Bar Start still works.
- [ ] `NOT TESTED` — Startup Chinese and English copy in Settings → Startup is complete and fits the Settings window.

## I. Production polish (P1)

> Added with P1. These rows were not run by the agent that wrote them; mark them on a real Release build.

- [ ] `NOT TESTED` — Release build with default Startup settings launches without a counter window, Dock icon, or `Open Debug Window` item; Studio stays hidden unless the Show Studio checkbox is on.
- [ ] `NOT TESTED` — Debug build does not show the counter window at launch; `Open Debug Window` in the popover still opens it on demand.
- [ ] `NOT TESTED` — With Restore position enabled, move/resize Studio, quit, and relaunch: Studio returns near the previous frame instead of centering.
- [ ] `NOT TESTED` — Release capture failure shows a plain-language message in the popover and Studio, with no raw status code.
- [ ] `NOT TESTED` — Release (sandboxed) build can start system audio capture and asks for the expected permission.
- [ ] `NOT TESTED` — With the system language set to Simplified Chinese, the popover, Studio controls, Notch Island, every Settings pane, and preset dialogs are Chinese and nothing is clipped at the 640 pt Settings width.
- [ ] `NOT TESTED` — With the system language set to English, the same surfaces are English and nothing is clipped.
- [ ] `NOT TESTED` — The macOS permission prompts show the Chinese and English descriptions for the matching system language.
- [ ] `NOT TESTED` — About Audune opens the standard panel with version, build, and the privacy statement.
- [ ] `NOT TESTED` — The popover idle hint shows before the first Start and is replaced by the error text if capture fails.
- [ ] `NOT TESTED` — Studio chrome mode buttons and Settings remain reachable; there is no play/pause control to dim.
- [ ] `NOT TESTED` — Switching the system language and relaunching keeps saved presets, selected modes, and window settings unchanged.

## Results

- Passed: local playback, pause, resume, menu-bar response, silence baseline, popover, shared debug-window counters, Quit, and both appearance checks recorded on 2026-10-24. `Open Debug Window` brought the existing counter window forward. Frames stayed at 1326080 across two reads after Stop. Quit left output unmuted on `MacBook Pro扬声器`.
- Failed: Studio v1 at `69a3f68` on 2026-10-24 — multi-desktop `FAIL`, dragging `FAIL`, visual review `NEEDS REDESIGN`. The earlier menu-bar cases in this file had no failures.
- Not tested: permission prompt (Start did not show one and capture still ran), denying or changing permission, microphone prompt, browser audio, headphones, Bluetooth, sleep, 20 start/stop cycles, 30-minute run, mode switching, Studio open/close, resize, Always-on-Top, geometry restore, external-display disconnect, Settings, retry, Island, Magnet, waveform, orbit, and `Capture failed`. `Starting` passed too quickly to read. Output volume was 44 unmuted near the start of the session and 38 unmuted immediately before and after Quit; the device did not change and Quit did not mute playback, but the earlier volume change was not bracketed, so that checklist row stays `NOT TESTED`.
- Issues filed: none.
- Logs/screen recordings (avoid capturing private audio content): none saved in the repository.
