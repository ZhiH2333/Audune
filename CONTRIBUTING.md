# Contributing to Audune

Thanks for contributing. Audune is a native, local-first macOS audio visualizer. Please read `AGENTS.md`, `docs/PRODUCT_SPEC.md`, and `docs/GITHUB_ISSUES.md` before changing code.

## Branch policy

- Development stays on `dev`.
- Do not create extra working branches, merge, rebase, reset hard, force-push, or discard user changes.
- Automatically create one commit after each completed, independently verifiable TODO/checklist item once its relevant tests/checks pass. Do not ask for permission for each commit.
- Before each commit, inspect status and staged diff; stage only files related to that TODO and never include pre-existing user changes or unrelated files. If relevant tests fail, do not commit that TODO.
- Use exactly `:gitmoji: short-git-message`, e.g. `:sparkles: add spectrum renderer`. Use one gitmoji shortcode, one space, and a short English description; no `feat:` or issue-number prefix.
- Never push automatically.

## Development workflow

1. Check `git status --short` and `git branch --show-current`.
2. Read the relevant issue, dependencies, and acceptance criteria.
3. Make the smallest implementation that satisfies the issue.
4. Run the relevant build and tests. Report tests that need real macOS permissions/hardware as manual tests.
5. Update documentation and `docs/MANUAL_TESTS.md` when behavior changes.
6. Before finishing, check the diff and verify the branch is still `dev`.

## Product invariants

- Use public macOS APIs. Do not use private APIs or modify system files.
- Never request microphone permission as a fallback for system audio capture.
- Do not persist or upload raw audio, add telemetry, or introduce accounts/ads.
- Keep one shared audio capture and analysis pipeline for all display surfaces.
- Keep changes focused; no unrequested advanced visuals or unrelated refactors.

## Build and test

```bash
xcodebuild -project Audune.xcodeproj -scheme Audune -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Audune.xcodeproj -scheme Audune -configuration Debug -destination 'platform=macOS' test
xcodebuild -project Audune.xcodeproj -scheme Audune -configuration Release -destination 'platform=macOS' build
```

- The shared scheme runs tests in English (`language = "en"` on the test action), so tests that compare English text pass on any Mac. The Simplified Chinese checks read `zh-Hans.lproj` directly.
- If a test run fails at `CodeSign` because of an unsigned `AuduneTests.xctest`, run `xcodebuild ... clean` and test again. This came from stale build products, not from the code.
- A Release build separates code problems from signing problems: add `CODE_SIGNING_ALLOWED=NO` to check that it compiles without a signing identity.

## Debug and Release builds

- Developer-only code lives behind `#if DEBUG`: the capture counter window (`Audune/Debug`), the menu item that opens it, raw status codes next to capture errors, the drag trace log, and the `...ForTests` hooks on window controllers.
- Everything a user needs stays in both configurations: capture, Studio, Notch Island, Settings, Playback, and the permission and error messages. Never put a product feature or user-facing error behind `#if DEBUG`.
- Release types must not reference Debug-only types. Pass an optional closure (as `openDebug` does) instead of a Debug-only type.

## Localization

- User-visible text is localized with String Catalogs: `Audune/Localizable.xcstrings` and `Audune/InfoPlist.xcstrings` (permission descriptions). Languages are English (`en`, the key text) and Simplified Chinese (`zh-Hans`).
- SwiftUI literals (`Text("...")`, `Button("...")`, `Section("...")`) localize automatically. Text held in a `String` needs `String(localized: "...")`; use `LocalizedStringKey` for computed SwiftUI text. Do not pick between literals with an inline `cond ? "A" : "B"` where the result is a `String`.
- Stored values (preference keys, preset ids, mode raw values, preset `name`) must not depend on the language. Built-in preset names are translated only for display through `VisualPreset.displayName`.
- Adding or changing text: add the `zh-Hans` value in the catalog. `LocalizationTests` fails if a key has no translation or the placeholders differ, and `UserFacingCopyTests` rejects developer vocabulary.
- Keep product names such as Studio and Notch Island untranslated in `zh-Hans`.
- Release users should see plain-language errors. Keep raw status codes and counters in Debug.

## Tests

- Use XCTest for audio analysis math, settings, and geometry logic that can run without hardware.
- Run real system-audio permission/capture and notch/window tests on supported Macs and record outcomes in `docs/MANUAL_TESTS.md`.
- Never report a test as passed if it did not run.
