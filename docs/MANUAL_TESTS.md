# Audune — Manual Test Checklist

> Run this checklist on a real macOS user session. Mark each case `PASS`, `FAIL`, or `NOT TESTED`; include macOS version, Mac model, and notes. Do not mark real system-audio capture as passed based only on synthetic DSP tests or CI.

## Test environment

- macOS version/build:
- Mac model / CPU:
- Display setup (built-in / external / scaled resolutions):
- Audune version / commit:
- Tester / date:

## A. First launch and permissions

- [ ] `PASS / FAIL / NOT TESTED` — First launch shows the expected app entry point and no unexpected Dock icon.
- [ ] `PASS / FAIL / NOT TESTED` — Starting system audio capture presents the expected macOS permission prompt.
- [ ] `PASS / FAIL / NOT TESTED` — Granting permission leads to a running capture state.
- [ ] `PASS / FAIL / NOT TESTED` — Denying permission produces clear instructions and does not falsely show live audio.
- [ ] `PASS / FAIL / NOT TESTED` — Changing permission in System Settings and retrying/relaunching behaves predictably.
- [ ] `PASS / FAIL / NOT TESTED` — Audune does not request microphone permission.

## B. Real system audio capture

- [ ] `PASS / FAIL / NOT TESTED` — Browser video/audio drives the visualizer.
- [ ] `PASS / FAIL / NOT TESTED` — A local audio player drives the visualizer.
- [ ] `PASS / FAIL / NOT TESTED` — Pausing playback returns the display to a stable silence/baseline state.
- [ ] `PASS / FAIL / NOT TESTED` — Resuming playback resumes visual response without restarting the app.
- [ ] `PASS / FAIL / NOT TESTED` — Output volume/device remains unchanged; capture does not mute or interrupt playback.
- [ ] `PASS / FAIL / NOT TESTED` — Built-in speakers and available headphones work.
- [ ] `PASS / FAIL / NOT TESTED` — Available Bluetooth output device can be selected/connected without leaving the app stuck.
- [ ] `PASS / FAIL / NOT TESTED` — System sleep/wake restores capture or presents an actionable error.
- [ ] `PASS / FAIL / NOT TESTED` — Stop/start capture 20 times without crash or resource accumulation.

## C. Menu bar

- [ ] `PASS / FAIL / NOT TESTED` — Menu-bar visual responds to real audio and settles during silence.
- [ ] `PASS / FAIL / NOT TESTED` — Icon remains legible in the current menu-bar appearance.
- [ ] `PASS / FAIL / NOT TESTED` — Clicking the icon opens the control popover.
- [ ] `PASS / FAIL / NOT TESTED` — Mode switching does not interrupt capture.
- [ ] `PASS / FAIL / NOT TESTED` — Studio, Settings, retry, and Quit actions work.
- [ ] `PASS / FAIL / NOT TESTED` — On macOS versions with a system menu-bar visibility control, Audune remains visible when permitted by system settings.

## D. Studio

- [ ] `PASS / FAIL / NOT TESTED` — Studio opens and closes independently of the audio engine.
- [ ] `PASS / FAIL / NOT TESTED` — Studio can be moved and resized without graphic clipping.
- [ ] `PASS / FAIL / NOT TESTED` — Always-on-Top on/off changes window layering as expected.
- [ ] `PASS / FAIL / NOT TESTED` — Window geometry and chosen mode restore after app restart.
- [ ] `PASS / FAIL / NOT TESTED` — Moving to an external display then disconnecting it restores Studio to a visible screen.

## E. Visualizers

- [ ] `PASS / FAIL / NOT TESTED` — Spectrum responds to changes in audio frequency and energy.
- [ ] `PASS / FAIL / NOT TESTED` — Waveform represents incoming samples and does not use random motion.
- [ ] `PASS / FAIL / NOT TESTED` — Orbit responds to real frequency-band data.
- [ ] `PASS / FAIL / NOT TESTED` — All modes handle silence with a stable baseline.
- [ ] `PASS / FAIL / NOT TESTED` — Switching modes repeatedly creates no duplicate capture tasks.
- [ ] `PASS / FAIL / NOT TESTED` — Very small and large window sizes do not crash or draw invalid geometry.

## F. Island (only after the Island milestone)

- [ ] `PASS / FAIL / NOT TESTED` — Notch location uses actual display geometry on a supported MacBook.
- [ ] `PASS / FAIL / NOT TESTED` — Collapsed state is compact and does not block normal menu-bar controls.
- [ ] `PASS / FAIL / NOT TESTED` — Hover expansion, click-to-pin, delayed collapse, and Escape behave correctly.
- [ ] `PASS / FAIL / NOT TESTED` — Opening/closing Island does not restart capture.
- [ ] `PASS / FAIL / NOT TESTED` — Built-in and external display switching recalculates location correctly.
- [ ] `PASS / FAIL / NOT TESTED` — On a no-notch display, Island is disabled or degrades as documented without covering unrelated system UI.
- [ ] `PASS / FAIL / NOT TESTED` — Full-screen applications do not cause stuck, invisible, or click-blocking windows.

## G. Desktop Magnet (only after the Magnet milestone)

- [ ] `PASS / FAIL / NOT TESTED` — Magnet can be dragged and resized.
- [ ] `PASS / FAIL / NOT TESTED` — A normal application window can cover Magnet.
- [ ] `PASS / FAIL / NOT TESTED` — Magnet does not force itself to front when switching apps.
- [ ] `PASS / FAIL / NOT TESTED` — Position, size, and mode restore on next launch.
- [ ] `PASS / FAIL / NOT TESTED` — Display disconnect moves it back into a visible area.
- [ ] `PASS / FAIL / NOT TESTED` — Closing/hiding Magnet does not stop the shared audio engine.

## H. Performance, lifecycle, privacy

- [ ] `PASS / FAIL / NOT TESTED` — Run for at least 30 minutes without crash or obvious memory growth.
- [ ] `PASS / FAIL / NOT TESTED` — Hidden surfaces no longer perform high-frequency drawing.
- [ ] `PASS / FAIL / NOT TESTED` — When audio analysis is explicitly stopped, capture resources are released.
- [ ] `PASS / FAIL / NOT TESTED` — No raw audio file is created.
- [ ] `PASS / FAIL / NOT TESTED` — No audio data, telemetry, or analytics is sent over the network.
- [ ] `PASS / FAIL / NOT TESTED` — Permission and capture errors remain distinguishable from silence.
- [ ] `PASS / FAIL / NOT TESTED` — Current Git branch is `dev`; no commit/push occurred unless explicitly requested.

## Results

- Passed:
- Failed:
- Not tested:
- Issues filed:
- Logs/screen recordings (avoid capturing private audio content):
