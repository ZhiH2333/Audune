# Audune

Audune is a native, local-first macOS music visualizer. It draws the system audio output as a Spectrum, Waveform, or Orbit in the menu bar, in a Studio window, and in a Notch Island. It is free and open source, has no account, ads, or analytics, and never records, saves, or uploads audio.

> Status: pre-release. The project builds and is tested in Debug; the items under [Before the first public release](#before-the-first-public-release) are still open.

## What works

- Menu bar item with a live spectrum icon and a popover for Start/Stop, Studio, Notch Island, Settings, About, and Quit.
- Studio window with Spectrum, Waveform, and Orbit; On Desktop, On Top, and As Window modes; drag and resize; Visual Presets.
- Notch Island on displays that have a camera housing. On other displays it is unavailable and says so; the menu bar and Studio still work.
- Play/Pause for Apple Music or Spotify through Automation (one player at a time).
- English and Simplified Chinese. The language follows the system language order; there is no in-app switcher.

Not included: Desktop Magnet, other players, volume or mute control, microphone input, and any non-macOS platform.

## Requirements

- macOS 27.0 or later (the current deployment target; `docs/PRODUCT_SPEC.md` still lists 14.2 as the goal pending verification).
- Xcode with the macOS 27 SDK to build.

## Permissions and first run

- **System audio capture.** Press Start in the menu bar popover. Audune uses a Core Audio process tap on the output device (public API) and never asks for the microphone. If capture fails, the popover and Studio explain what to check, usually System Settings > Privacy & Security > Screen & System Audio Recording.
- **Automation (optional).** Only needed for Play/Pause. Choose Music or Spotify in Settings > Playback, open that app, then choose Request Access. If it was denied, use Open Automation Settings.
- **Menu bar visibility.** If the Audune icon is missing, check that macOS allows Audune in System Settings > Menu Bar.

## Build and test

```bash
xcodebuild -project Audune.xcodeproj -scheme Audune -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Audune.xcodeproj -scheme Audune -configuration Debug -destination 'platform=macOS' test
xcodebuild -project Audune.xcodeproj -scheme Audune -configuration Release -destination 'platform=macOS' build
```

The shared scheme runs tests in English. Real system-audio capture, permission prompts, notch behavior, and window levels need a real macOS session; see `docs/MANUAL_TESTS.md`.

## Debug and Release

| | Debug | Release |
| --- | --- | --- |
| Developer capture window and its menu item | Yes | No |
| Raw status codes next to capture errors | Yes | No, plain-language messages only |
| Drag log and test hooks on window controllers | Yes | No |
| Capture, Studio, Notch Island, Settings, Playback, error and permission messages | Yes | Yes |
| App Sandbox | Off (local development) | On |

## License

There is no `LICENSE` file yet. The project intends to be fully open source, and `docs/PRODUCT_SPEC.md` proposes the MIT License. The owner must confirm the license and copyright holder and add `LICENSE` before the first public release.

## Before the first public release

These need the owner's identity, credentials, or decisions and are intentionally not changed in the repository:

- Real bundle identifier. The project still uses the placeholder `devplaceholder.UFJKN3LA.Audune`.
- Signing identity, Hardened Runtime, notarization, and a distribution build. The Release build made from this project is signed with an Apple Development identity and carries `get-task-allow`, so it is not distributable.
- Release App Sandbox entitlements. Release is sandboxed with only the default entitlements. Whether system audio capture and Apple Music/Spotify Automation work under that sandbox has not been verified and probably needs entitlements or a different distribution choice (see the Automation note in `docs/PRODUCT_SPEC.md`).
- App icon. No app icon is configured.
- `LICENSE`, and copyright text for the About panel.
- Minimum macOS version decision (27.0 now, 14.2 in the spec).
- A manual pass of `docs/MANUAL_TESTS.md` on a Release build, including the Simplified Chinese interface.

See `CONTRIBUTING.md` for the branch and commit rules.
