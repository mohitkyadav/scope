# Scope

Native macOS screen recorder for making polished product demos and tutorials. 

## Stack

- Swift + SwiftUI, single app target `Scope` in `Scope.xcodeproj`
- Minimum macOS 15.0 (needed for `SCRecordingOutput` in ScreenCaptureKit)
- App Sandbox and Hardened Runtime enabled
- Swift 5 language mode with approachable concurrency; default actor isolation is `MainActor`

## Layout

- `Scope/` is a file-system-synchronized group: any file added here is part of the target automatically. Do not hand-edit `project.pbxproj` to add sources.
- `Scope/Assets.xcassets` holds the app icon and accent color.

## Build

```sh
xcodebuild -project Scope.xcodeproj -scheme Scope -configuration Debug build
```

## Local overrides

Personal, machine-specific notes live in CLAUDE.local.md (gitignored):

@CLAUDE.local.md
