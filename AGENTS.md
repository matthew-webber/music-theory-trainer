# Repository Guidelines

## Project Structure & Architecture

- `music-theory-trainer/MyApp.swift` is the SwiftUI app entry point.
- `music-theory-trainer/ContentView.swift` contains the current prototype: interval and root-note models, the interval wheel and practice UI, feeling-tag settings, and synthesized audio.
- `music-theory-trainer/Assets.xcassets/` holds app assets.
- `music-theory-trainer.xcodeproj/` contains the Xcode project and scheme. There is no separate package or test directory yet.

Keep the prototype straightforward and shared across macOS and iOS. When a feature makes `ContentView.swift` difficult to navigate, split it into focused Swift files while preserving portable SwiftUI behavior and isolating audio-specific code as needed.

## Build, Test & Run

Build the macOS app:

```sh
xcodebuild -project music-theory-trainer.xcodeproj -scheme music-theory-trainer -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Check iOS portability:

```sh
xcodebuild -project music-theory-trainer.xcodeproj -scheme music-theory-trainer -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

To run interactively, open `music-theory-trainer.xcodeproj` in Xcode, select the `music-theory-trainer` scheme and a macOS or iOS simulator destination, then use **Run**. The project currently has no test target or test sources; treat successful builds as compile checks, not behavioral test coverage.

## Coding Style

Use four spaces for Swift indentation. Name types and SwiftUI views in `UpperCamelCase`; use `lowerCamelCase` for properties, functions, and state. Prefer small, private view helpers and descriptive names. Follow the existing SwiftUI style and keep interactions accessible with labels and hints. No formatter or linter is configured, so keep diffs focused and consistent with nearby code.

## Commits & Pull Requests

The short Git history uses plain descriptive subjects and has no formal prefix convention. Use concise summaries that describe the change. For pull requests, explain the user-visible behavior, list macOS/iOS builds run, link related issues when applicable, and include screenshots for UI changes.
