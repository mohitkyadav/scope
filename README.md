<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/readme/banner-dark.png">
    <img src="Design/readme/banner-light.png" width="840" alt="Scope: screen recordings that edit themselves">
  </picture>
</p>

<p align="center">A native macOS screen recorder that zooms in on every click, smooths your cursor and frames it all on a beautiful background, automatically.</p>

<p align="center">
  <a href="https://only4.dev/scope/"><img src="https://img.shields.io/badge/website-only4.dev%2Fscope-e8473e" alt="Website"></a>
  <a href="https://github.com/mohitkyadav/scope/releases/latest"><img src="https://img.shields.io/github/v/release/mohitkyadav/scope?label=version&color=e8473e" alt="Latest version"></a>
  <a href="https://github.com/mohitkyadav/scope/releases"><img src="https://img.shields.io/github/downloads/mohitkyadav/scope/total?color=e8473e" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-e8473e" alt="macOS 15 or later">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/mohitkyadav/scope?color=e8473e" alt="MIT license"></a>
</p>

```sh
brew install mohitkyadav/tap/scope
```

<p align="center">
  <img src="Design/readme/demo.gif" width="840" alt="A recording made with Scope: it zooms in on each click and follows the cursor">
  <br>
  <sub>Made with Scope. Every zoom here was added automatically.</sub>
</p>

## Features

| | |
|---|---|
| **Record** | Display, window or an area of the screen · mic, system audio, camera · countdown · ⌘⇧2 to stop · 30/60 fps |
| **Zoom** | Auto zoom on clicks and typing · pick the area · per-zoom level, transition and animation · spotlight · motion blur |
| **Cursor** | Smoothed path · real cursor shapes · click ripples · hides when still · glides across cuts |
| **Style** | Gradient or image backgrounds · padding, corners, shadow · frame formats · webcam bubble |
| **Edit** | Split, delete, 0.25–4× speed · notes · per-track volume · music and voice-over · undo |
| **Export** | MP4 at any size and quality · seamless looping GIFs |

Every recording is a project you can reopen and keep editing, saved to Downloads or a folder you choose.

## How it works

Record, and the zooms are already there. Tweak anything you like on the timeline, then export.

<p align="center">
  <img src="Design/readme/editor.gif" width="840" alt="Editing a recording in Scope: zooms on the timeline, a background and the zoom settings">
</p>

## Private

Scope never connects to the internet: no analytics, no tracking, no update checks. It runs in Apple's App Sandbox without network access, so it couldn't even if it tried. For zooming on typing it notes when keys are pressed, never which. Check for yourself:

```sh
codesign -d --entitlements - /Applications/Scope.app   # no network.client entitlement
```

## Install

```sh
brew install mohitkyadav/tap/scope
```

Needs macOS 15+. Update with `brew upgrade scope`, remove with `brew uninstall --zap scope`. Recordings are never touched.

Downloading the zip from [Releases](https://github.com/mohitkyadav/scope/releases) instead? Scope isn't notarized, so allow it once in System Settings → Privacy & Security → **Open Anyway**.

<details>
<summary><strong>Permissions</strong></summary>
<br>

| Permission | Needed for |
|---|---|
| Screen & System Audio Recording | Recording (required, reopen Scope after allowing) |
| Microphone | Voice-over (optional) |
| Camera | Webcam bubble (optional) |

</details>

<details>
<summary><strong>Build from source</strong></summary>
<br>

Open `Scope.xcodeproj` in Xcode and run, or:

```sh
xcodebuild -project Scope.xcodeproj -scheme Scope -configuration Release build
```

</details>

## License

[MIT](LICENSE)
