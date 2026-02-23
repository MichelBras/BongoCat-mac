# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BongoCat-mac is a native macOS overlay app (macOS 13.0+) that displays an animated cat reacting to keyboard and mouse input. It is an Xcode project written in Swift, using a SwiftUI + AppKit hybrid architecture.

The Xcode project is located in `app/` — not the repository root.

## Build & Development Commands

```bash
# Build (debug by default)
./Scripts/build.sh
./Scripts/build.sh --debug --test   # Build and run tests
./Scripts/build.sh --release --run  # Release build and launch app

# Run tests
./Scripts/test.sh
./Scripts/test.sh --filter StrokeCounter  # Run tests matching a pattern
./Scripts/test.sh --verbose               # Verbose output

# Interactive menu (all workflows)
./run.sh

# Version management
./Scripts/bump_version.sh 1.9.0          # Update version across all files
./Scripts/check_version.sh              # Verify version consistency

# Release packaging
./Scripts/package.sh --dmg             # Create DMG
./Scripts/package.sh --app-store       # Package for App Store
./Scripts/sign.sh --app --notarize     # Sign and notarize
./Scripts/push.sh --github             # Publish GitHub release
```

Before release builds, create a `.env` file from `.env.template` with Apple credentials and PostHog API keys.

## Code Architecture

The app uses a **SwiftUI + AppKit hybrid** with **MVVM** pattern. All Swift source lives in `app/BongoCat/`.

### Key Components

| File | Role |
| --- | --- |
| `App/BongoCatApp.swift` | `AppDelegate` — central coordinator. Owns all major objects, manages all UserDefaults state (scale, position, flip, paw behavior, etc.), and drives the menu bar |
| `App/main.swift` | Entry point |
| `Managers/OverlayWindow.swift` | Manages the borderless, always-on-top transparent NSWindow; contains `TouchDetectionView` for trackpad events |
| `Managers/InputMonitor.swift` | Uses `NSEvent.addGlobalMonitorForEvents` to capture keyboard and mouse events system-wide; requires Accessibility permission |
| `Views/CatView.swift` | SwiftUI view rendering the cat sprite; contains `StrokeCounter` and `CatAnimationController`; handles paw animations and `PawBehaviorMode` (keyboard layout, random, alternating) |
| `Views/PreferencesWindow.swift` | Settings UI (scale, rotation, flip, per-app positioning, paw behavior, etc.) |
| `Views/WelcomeScreen.swift` | First-launch onboarding UI |
| `Analytics/PostHogAnalyticsManager.swift` | PostHog analytics integration |
| `Analytics/UpdateChecker.swift` | Auto-update checking |
| `Analytics/MilestoneNotificationManager.swift` | Keystroke milestone notifications |
| `Services/FirstLaunchGuide.swift` | Guides user through Accessibility permission setup |

### Data Flow

1. `InputMonitor` detects global keyboard/mouse events → calls a callback with `InputType`
2. `AppDelegate` wires this callback to `CatAnimationController` (inside `CatView`)
3. `CatAnimationController` maps inputs to left/right paw animations based on `PawBehaviorMode`
4. `StrokeCounter` tracks cumulative keystrokes and mouse clicks (persisted in UserDefaults)

### State Persistence

All settings are stored in `UserDefaults` using `BongoCat`-prefixed keys. Per-app positioning stores an `[String: NSPoint]` dictionary keyed by app bundle identifier.

### Build Configuration

- `app/Common.xcconfig` — shared settings (deployment target: macOS 13.5, bundle ID: `com.leaptech.bongocat`)
- `app/Debug.xcconfig` / `app/Release.xcconfig` — configuration-specific overrides
- Version is tracked in `app/BongoCat/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`)

## Swift Code Conventions

- 4-space indentation (never tabs)
- `@StateObject` for owned objects, `@ObservedObject` for passed objects
- Settings persistence uses UserDefaults with `BongoCat`-prefixed keys
- Input monitoring logic stays in `InputMonitor.swift`; animation logic stays in `CatView.swift`; window management stays in `OverlayWindow.swift`
- Minimize view updates with proper state management; debounce rapid input events; keep the main thread free for UI
- All UI elements need accessibility labels; respect the `reduceMotion` system preference; support VoiceOver navigation

## Testing

Tests live in `app/BongoCatTests/`. Run with `./Scripts/test.sh` (supports `--filter <pattern>`, `--verbose`, `--coverage`).

- Test naming: `test_featureName_whenCondition_shouldExpectedResult()`
- Use Arrange-Act-Assert structure
- Mock system dependencies: `CGEvent` and `NSEvent` for input monitoring, `UserDefaults` for settings, `NSWindow`/`NSScreen` for positioning
- Use dependency injection to make components testable

## Version Management

Version follows Semantic Versioning. Three files must stay in sync:
- `app/BongoCat/Info.plist` — `CFBundleShortVersionString` (e.g. `1.9.0`) and `CFBundleVersion` (build number, format `YYYY.MM`)
- `Package.swift` — if version is specified there
- `CHANGELOG.md` — version entry with release date

Use the scripts to manage versions safely:
```bash
./Scripts/bump_version.sh 1.9.0           # Update all version references
./Scripts/bump_version.sh 1.9.0 --commit --push  # Also commit and tag
./Scripts/check_version.sh               # Verify consistency across files
```

Release process: complete feature → run tests → update changelog → bump version → verify → build release → package → commit + tag.

## Changelog

Always update `CHANGELOG.md` after implementing features or fixing bugs. Use [Keep a Changelog](https://keepachangelog.com/) format with an `[unreleased]` section at the top.

Required sections: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

Entries should use emojis matching the existing style (e.g., `🎯`, `🐛`, `⚡`) and start with action verbs. Example:

```markdown
### Fixed
- **🐛 Window Positioning** - Fixed cat position not saving correctly across restarts
```
