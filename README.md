<p align="center"><img src="docs/assets/logo-with-label.png" width="280" alt="Snipzy logo"></p>

# Snipzy

macOS menu bar screenshot tool. Capture a region, annotate it, then copy or
save the result.

[Watch the demo](docs/assets/demo_0-1-1.mp4)

## Requirements

- macOS 14 or newer
- Swift 6 toolchain for local builds
- Screen Recording permission

## Install

Download the latest ZIP from [Releases](https://github.com/epulla/snipzy/releases),
unzip it, and move `Snipzy.app` to `/Applications`.

Release builds are ad-hoc signed and not notarized. On first launch, Control-click
`Snipzy.app`, choose **Open**, and confirm. macOS may instead show **Open Anyway**
under **System Settings > Privacy & Security**.

## Setup

Grant Screen Recording permission in `System Settings > Privacy & Security >
Screen Recording`. For `make run`, grant permission to the terminal or IDE running
Snipzy, then restart it after changing permission.

Snipzy uses `Cmd-Shift-4`. Disable macOS's default shortcut in `System Settings >
Keyboard > Keyboard Shortcuts > Screenshots` so Snipzy can receive it.

## Use

1. Press `Cmd-Shift-4` and select an area.
2. Edit the capture with the annotation tools.
3. Copy the image or save it as PNG.

For OCR, press `O` or click the eye button, then select text. OCR runs on-device;
edit or copy its result from the popover.

## Build

```sh
make build
make test
make bundle
open dist/Snipzy.app
```

`make bundle` creates `dist/Snipzy.app`. Use `make run` to launch the development
build directly.

## More

- [Roadmap](docs/ROADMAP.md)
- [Cross-platform plan](docs/CROSS_PLATFORM_PLAN.md)
