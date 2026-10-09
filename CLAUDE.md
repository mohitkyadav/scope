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
- The app icon is `Scope/AppIcon.icon`, an Icon Composer document with flat layers so macOS adds the Liquid Glass effect (Xcode also generates the macOS 15 fallback from it). It's generated from `Design/Scope Icon.svg` by `python3 Design/make_icon.py`; edit the script rather than the `.icon`, and don't bake shadows, glows or highlights into the layers. Check the result with Icon Composer or `ictool` (in `Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/`).
- Recordings are always saved straight into `~/Downloads` as `.scope` project packages (`Scope <timestamp>.scope/`, sandbox: Downloads read-write). A package holds `screen.mp4` and `cursor.json` now, and later the webcam, imported audio and `project.json` edits. Exports go next to it as plain files. The type is declared in `Scope/Info.plist`.

## Build

```sh
xcodebuild -project Scope.xcodeproj -scheme Scope -configuration Debug build
```

## Local overrides

Personal, machine-specific notes live in CLAUDE.local.md (gitignored):

@CLAUDE.local.md
