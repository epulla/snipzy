# Roadmap

## Current Baseline

- Menu bar app with `Cmd-Shift-4` global hotkey.
- Interactive area capture through `/usr/sbin/screencapture -i -s -x -d`.
- Annotation tools: pen, highlighter, arrow, rectangle, ellipse, text, and pixelate.
- Undo, redo, clipboard copy, and PNG save.
- On-device OCR region tool.
- Swift package build and minimal `.app` bundling through `make bundle`.

## Next

- Add signed and notarized release artifacts.
- Improve capture and editor error states, including permission guidance.
- Add user-configurable hotkey and annotation color/width settings.
- Add persistent capture history and recent save locations.
- Expand automated coverage around editor rendering and bundle validation.
- Add per-tool render tests for pen, highlighter, arrow, shapes, and pixelate.
- Add Shift-constrain and clamp tests.
- Separate testable save writer from `NSSavePanel`.
- Add OCR extras: translate, copy as table, and live text overlay.

## Plan B: ScreenCaptureKit

Keep the current `screencapture` path as default until a concrete limitation
requires replacement. If command-line capture becomes unreliable or Snipzy
needs display/window selection, implement a native ScreenCaptureKit provider.

The future provider should:

- Request and explain Screen Recording permission through normal macOS flow.
- Use `SCShareableContent` to enumerate displays and windows.
- Use ScreenCaptureKit content filters and `SCScreenshotManager` for capture.
- Return image data through the same capture boundary used by the editor.
- Avoid the subprocess and temporary PNG handoff used by the current path.

ScreenCaptureKit remains future work, not part of current build or runtime
behavior. It will require async capture handling, availability checks for the
supported macOS baseline, and new manual tests for display/window selection,
permission denial, and multi-display scaling.
