# Audune

**Sound, in motion.**

A native macOS music visualizer. Audune turns your system audio into live Spectrum, Waveform, and Orbit graphics — in the menu bar, a Studio window, and a Notch Island. Free, open source, and local-first. No account, ads, or analytics. Audio is never recorded, saved, or uploaded.

## Features

- **Menu Bar** — a living spectrum icon with Start/Stop, Studio, Island, and Settings
- **Studio** — a floating canvas with Spectrum, Waveform, and Orbit; On Desktop, On Top, or As Window
- **Notch Island** — a compact indicator around the camera housing (when available)
- **Lyrics** *(experimental)* — fullscreen lyrics for the current track, with local LRC and online search
- **English & 简体中文** — follows system language

## Requirements

macOS 14.2 or later · Xcode with a current macOS SDK

## Get started

```bash
xcodebuild -project Audune.xcodeproj -scheme Audune -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/Audune-*/Build/Products/Debug/Audune.app
```

On first Start, macOS may ask for **Screen & System Audio Recording**. Audune captures system output only — never the microphone.

## Privacy

Everything runs on your Mac. Capture is real-time analysis only. Online lyrics (when enabled) send title, artist, album, and duration to reviewed providers, stay in memory, and are never saved or uploaded. Details: [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md).

## Contributing

Work on `dev`. See [`CONTRIBUTING.md`](CONTRIBUTING.md), [`AGENTS.md`](AGENTS.md), and [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md).

## License

Open source — license file pending before first public release (MIT intended).
