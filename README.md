<p align="center">
  <img src="Design/readme/icon.png" width="128" height="128" alt="Scope icon">
</p>

<h1 align="center">Scope</h1>

<p align="center">A native macOS screen recorder for polished demos and tutorials.</p>

---

## Features

**Record**
- A whole display or a single window
- Microphone, system audio and camera, each optional
- Countdown before recording, and ⌘⇧2 to stop from any app
- 30 or 60 fps
- Every recording is a project in `~/Downloads` that you can keep editing

**Zoom and cursor**
- Automatic zooms on your clicks that follow the cursor
- Each zoom can have its own level and transition
- A smoothed cursor, adjustable size and click ripples
- Motion blur on zooms, pans and the cursor

**Style**
- Gradient or image backgrounds, with blur for images
- Images you've used are saved for every project
- Padding, rounded corners, a shadow and background parallax
- A webcam bubble: circle or rounded, any size, mirrored, drag to move

**Edit**
- Timeline with split, delete and speed from 0.25× to 4×
- On-screen notes
- Volume and mute for each audio track, plus music or voice-over files
- Bring in another video for the webcam bubble
- Undo and redo, with autosave

**Export**
- MP4 at the original size or smaller, 30 or 60 fps, with a choice of quality
- Looping GIFs, with the cursor eased back to the start so the loop is seamless

## Requirements

macOS 15 or later.

## Build

Open `Scope.xcodeproj` in Xcode and run, or:

```sh
xcodebuild -project Scope.xcodeproj -scheme Scope -configuration Release build
```

## License

[MIT](LICENSE)
