# Draw mode

## Request

> you can enter in draw mode (shortcut is tbd) so you screen gets freezed and you can use all tools from Snipzy for drawing, make annotations, OCR, etc. If you press Enter, you open a snipzy window with a screenshot with your annotations, if you press Esc, you quit that mode, if you press shift+enter, you save the screenshot+annotations in any folder

> it'd bee nice to freeze display under the mouse as well when cmd+shift+4

> pls save it as this: `snipzy-<datetime>.png`. Also when saving screenshots, save as this `snipzy-<datetime>.png`

Ticket: PROJ-116 (Snipzy: draw mode).

## Decisions

1. Shortcut: ⌘⇧6, plus a "Draw on Screen" menu bar item.
2. Freeze only the display under the mouse.
3. Draw mode uses the editor's full toolbar (all tools incl. OCR, color, width, text size, undo/redo), floating top-center; same key shortcuts.
4. Enter: leave draw mode, open the normal editor with annotations still editable, and copy the annotated image to the clipboard.
5. ⇧Enter: save panel; saving leaves draw mode, cancel returns to drawing.
6. Esc: leave immediately, no confirm; while editing text or with the OCR popover open, Esc closes that first.
7. Delete this plan file in the last task's commit.
8. Default filename `snipzy-yyyy-MM-dd_HH-mm-ss.png` (local time) for draw mode and the editor's ⌘S.
9. ⌘⇧4 freeze: snapshot the display under the mouse, cover it with a still overlay, run the native `screencapture -i` selection on top, remove the overlay afterwards. Other displays stay live.
10. Save panels keep macOS's remembered folder (no forced directory).

## Tasks

- [x] 1. Default save name `snipzy-<datetime>.png` in the editor's save panel.
  *Check:* unit test for the filename format; `make test`.
- [x] 2. Freeze the display under the mouse during ⌘⇧4 (display snapshot + borderless overlay around `screencapture -i`).
  *Check:* `make test`; manual: play a video, ⌘⇧4 → screen is still while selecting, captured image matches, Esc removes the overlay.
- [x] 3. Draw mode overlay: ⌘⇧6 hotkey + menu item open a full-screen canvas over the frozen display with the editor toolbar; Esc leaves.
  *Check:* `make test` (Esc closes draw mode, not the editor); manual: draw with every tool incl. OCR, Esc exits.
- [x] 4. Enter opens the editor with editable annotations and copies the image; ⇧Enter saves via panel (cancel returns to drawing).
  *Check:* unit test that the editor opens with the passed annotations; manual: Enter → editor + clipboard, ⇧Enter → file saved as `snipzy-<datetime>.png`.
- [ ] 5. README + help popover document draw mode and ⌘⇧6; delete this plan file.
  *Check:* `make build && make test`; review README on GitHub.
