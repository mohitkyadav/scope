# Scope

Native macOS screen recorder for making polished product demos and tutorials. 

## Stack

- Swift + SwiftUI, single app target `Scope` in `Scope.xcodeproj`
- Minimum macOS 15.0 (needed for `SCRecordingOutput` in ScreenCaptureKit)
- App Sandbox and Hardened Runtime enabled
- Swift 5 language mode with approachable concurrency; default actor isolation is `MainActor`

## Layout

- `Scope/` is a file-system-synchronized group: any file added here is part of the target automatically. Do not hand-edit `project.pbxproj` to add sources.
- `Scope/Assets.xcassets` holds the accent color.
- The app icon is `Scope/AppIcon.icon`, an Icon Composer document with flat layers so macOS adds the Liquid Glass effect (Xcode also generates the macOS 15 fallback from it). It's generated from `Design/Scope Icon - Frame.svg` by `python3 Design/make_icon.py`; edit the script rather than the `.icon`, and don't bake shadows, glows or highlights into the layers. Check the result with Icon Composer or `ictool` (in `Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/`).
- Recordings are always saved straight into `~/Downloads` as `.scope` project packages (`Scope <timestamp>.scope/`, sandbox: Downloads read-write). A package holds `screen.mp4`, `cursor.json`, the optional `webcam.mov` with `webcam.json` (its start offset), and `project.json` with the editor's settings; imported audio comes later. Files with a `version` field decode missing keys as defaults so older projects keep opening. Exports go next to it as plain files. The type is declared in `Scope/Info.plist`.

## Editor

- Every frame is drawn by `FrameRenderer` through `SceneCompositor` (a custom `AVVideoCompositing`) at a steady 60 fps; preview and export share it.
- The timeline (`TimelineEdits` in `project.json`) is a list of clips (ranges of the recording with a speed). `ProjectComposition` builds playback from it, and `TimeMap` converts between final-video time and recording time.
- Clips, zooms, notes and the webcam offset are in recording time, so they stay with their content when clips are trimmed. Imported audio offsets are in final-video time.
- Timeline changes go through `EditorModel.perform` or a gesture (`update` … `endGesture`) so they can be undone.

## Build

```sh
xcodebuild -project Scope.xcodeproj -scheme Scope -configuration Debug build
```

## Release

- Pushing a `v*` tag runs `.github/workflows/release.yml`: it signs with the self-signed "Scope Release" certificate (from repository secrets), publishes a GitHub release with `Scope-<version>.zip`, and updates `Casks/scope.rb` in `mohitkyadav/homebrew-tap`.
- `scripts/build-release.sh <version>` builds and signs locally (`SIGNING_IDENTITY`, `SIGNING_KEYCHAIN` override the defaults). It signs ad hoc first so Xcode adds the entitlements, then re-signs with the certificate and strips `get-task-allow`.
- `scripts/cask.sh <version> <sha256>` prints the cask. Releases aren't notarized, so the cask clears the quarantine flag after install.

## Local overrides

Personal, machine-specific notes live in CLAUDE.local.md (gitignored):

@CLAUDE.local.md
