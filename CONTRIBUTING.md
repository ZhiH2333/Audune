# Contributing to Audune

Thanks for contributing. Audune is a native, local-first macOS audio visualizer. Please read `AGENTS.md`, `docs/PRODUCT_SPEC.md`, and `docs/GITHUB_ISSUES.md` before changing code.

## Branch policy

- Development stays on `dev`.
- Do not create extra working branches, merge, rebase, reset hard, force-push, or discard user changes.
- Do not create commits automatically. Commit only when the maintainer explicitly asks.
- If asked to commit, use the exact one-line format `:gitmoji: short-git-message`, e.g. `:sparkles: add spectrum renderer`.
- Do not push unless explicitly asked.

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

## Tests

- Use XCTest for audio analysis math, settings, and geometry logic that can run without hardware.
- Run real system-audio permission/capture and notch/window tests on supported Macs and record outcomes in `docs/MANUAL_TESTS.md`.
- Never report a test as passed if it did not run.
