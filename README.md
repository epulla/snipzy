# Snipzy

Snipzy is a small macOS menu bar screenshot tool. Press `Cmd-Shift-4`, select
an area, annotate it, then copy or save the result.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Screen Recording permission

Snipzy currently delegates capture to `/usr/sbin/screencapture`. Its capture
command is:

```text
/usr/sbin/screencapture -i -s -x -d /tmp/snipzy-<uuid>.png
```

The `-i -s -x -d` flags mean interactive selection, selection-only mode, no
capture sound, and native graphical error reporting. The output path is a temporary
PNG removed after it is loaded. Escape cancellation produces no editor and keeps
existing clipboard contents unchanged.

Because Snipzy intentionally uses macOS's existing shortcut, disable `Cmd-Shift-4`
in `System Settings > Keyboard > Keyboard Shortcuts > Screenshots` after launch.

## Permissions

Grant `Screen Recording` to Snipzy in `System Settings > Privacy & Security >
Screen Recording`. When running with `make run`, grant that permission to the
terminal or IDE that owns the process. Restart the process after changing the
permission.

Unsigned local builds may need permission re-granted after rebuilding. Bundle
uses stable identifier `com.epulla.snipzy` and ad-hoc signing only.

The current Carbon global hotkey implementation does not require Accessibility
permission. macOS may still show different prompts depending on how the app is
launched or managed.

## Build

```sh
make build
make test
make bundle
open dist/Snipzy.app
```

`make test` uses Swift Testing, which ships with Command Line Tools; the Makefile
adds the Command Line Tools framework search path that SwiftPM omits, so run
`make test` rather than bare `swift test` when Xcode is not installed.

`make bundle` builds a release executable and creates `dist/Snipzy.app` without
changing `Resources/Info.plist`. The bundler resolves paths from its own
location, so it can run from any working directory. Override `APP_PATH` or
`DIST_DIR` when a different output location is needed.

## OCR

Press `O` or click the eye button in the editor. Drag a rectangle to read that
region, or click without dragging to read the whole image. Recognition runs
on-device with Apple Vision (automatic language detection) and needs no extra
permission. Results appear in an editable popover; text reaches the clipboard
only when you click Copy Text. The dashed selection is never included in copied
or saved images. Small or low-resolution text may read poorly.

## Manual Tests

Run these on a real macOS desktop:

1. Launch `dist/Snipzy.app`; confirm scissors icon appears in the menu bar.
2. Press `Cmd-Shift-4`, select an area, and confirm editor opens with captured image.
3. Open menu `Capture Selection` and confirm it starts another selection.
4. Exercise pen, highlighter, arrow, rectangle, ellipse, text, and pixelate tools.
5. Verify `Undo` and `Redo`, then `Copy` into an image-capable app.
6. Use `Save`, choose a PNG path, and verify file opens with annotations.
7. Cancel selection and verify app remains usable; missing permission should show an error.
8. Choose `Quit Snipzy` and confirm menu bar item exits.
9. Inspect bundle metadata with `plutil -p dist/Snipzy.app/Contents/Info.plist`.
10. Capture text, press `O`, drag over a paragraph, and confirm the popover shows text.
11. Confirm clipboard still holds the image until `Copy Text`, then paste into TextEdit.
12. Click without dragging and confirm the whole image is read.
13. Close the popover and confirm the dashed rectangle is cleared.
14. Undo after OCR and confirm only real annotations are removed.
15. Copy or save a PNG and confirm it has no dashed rectangle.
16. With the editor open, switch to another app and confirm Snipzy appears in the Dock and Cmd-Tab; close the last editor and confirm the Dock icon disappears.
17. Pick Text, type, press Return, and confirm the text has no background; drag the text with the Text tool and confirm it moves (Undo restores it).
18. Pick Text, type without pressing Return, click `Copy`, and confirm the pasted image includes the text.

## Current Limits

- Capture depends on the macOS `screencapture` command and its permission behavior.
- Capture is selection-based; window and display-specific UI are not exposed by Snipzy.
- App distribution, signing, notarization, and update delivery are not set up.

See [ROADMAP.md](ROADMAP.md) for planned work and the ScreenCaptureKit fallback.
