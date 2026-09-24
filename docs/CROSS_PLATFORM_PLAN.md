# Cross-Platform Plan (Proposal)

Status: **proposal, not decided**. This documents how Snipzy could be ported to
macOS, Windows, and Linux (X11 + Wayland) as a new repo, `snipzy.app`, using
Tauri v2 + React. The current Swift/AppKit app stays as-is until a decision is
made.

## Goal

Feature parity with the current macOS app:

- Global hotkey -> region select -> annotation editor.
- Tools: pen, highlighter, arrow, rectangle, ellipse, text, pixelate.
- Undo/redo, copy to clipboard, save PNG.
- OCR region tool.

## Why Tauri (and not Go/Wails, Electron, or Flutter)

| Concern | Wails v2 (Go) | Wails v3 (Go, alpha) | Tauri v2 (Rust) | Electron |
|---|---|---|---|---|
| Maturity | Stable | Alpha, API churn | Stable | Stable |
| Multi-window / transparent overlay | Single window only | Yes | Yes | Yes |
| Systray | 3rd-party, cgo | Built-in | Built-in | Built-in |
| Global hotkey | `golang.design/x/hotkey` (cgo) | Built-in | `tauri-plugin-global-shortcut` | Built-in |
| Clipboard image on Wayland | No (X11 only) | No | Yes (`arboard`) | Yes |
| OCR without C deps | No (Tesseract via cgo) | No | Yes (`ocrs`, pure Rust) | No (tesseract.js is slow) |
| Binary size | ~10 MB | ~10 MB | ~5-10 MB | ~150 MB |
| Build toolchain | Go + cgo (MinGW on Windows) | Same | Rust + cargo | Node |

Wails v2 is blocked by single-window (the region selector needs a fullscreen
overlay per monitor separate from the editor). Wails v3 fixes that but is
alpha and still needs a cgo pile for hotkey, clipboard, and OCR. Electron
works but is heavy. Flutter has weak tray/hotkey plugins.

Tauri covers every box today. The Rust surface is small (~300-500 LOC:
capture, crop, clipboard, OCR, hotkey). React does the heavy lifting.

## Stack

- Tauri v2, thin Rust backend, React 18 + TypeScript + Vite, pnpm.
- Rust crates: `xcap` (capture on macOS/Windows/X11), `ashpd` (Wayland
  portal), `image` (crop/PNG), `ocrs` (OCR).
- Tauri plugins: `global-shortcut`, `clipboard-manager`, `dialog`, `fs`,
  `single-instance`, `store`.
- Raw `<canvas>` 2D for the editor. No canvas library.
- Tests: `vitest` for TS geometry/state, `cargo test` for capture/crop math.

## Repo layout

```
snipzy.app/
  src/                      # React
    main.tsx                # route by window label: overlay | editor
    windows/overlay/        # region selector (one window per monitor)
    windows/editor/         # annotation editor
    editor/
      model.ts              # AnnotationTool, Annotation (normalized 0-1 coords), EditorState
      state.ts              # reducer: undo/redo stacks, tool/color/width
      geometry.ts           # clamp, shift-constrain, ocrRegion, imageRect fit
      render.ts             # drawAnnotation(ctx, ann, rect, bitmap) - port of Editor.swift draw code
      export.ts             # render to PNG on OffscreenCanvas at bitmap pixel size
    lib/ipc.ts              # typed invoke wrappers
  src-tauri/
    src/main.rs             # tray, menu, shortcut, activation policy
    src/capture/mod.rs      # trait CaptureProvider { fn capture_all_monitors() }
    src/capture/xcap.rs     # macOS / Windows / X11
    src/capture/portal.rs   # Wayland via ashpd
    src/ocr.rs              # ocrs wrapper, models lazy-loaded
    src/commands.rs         # #[tauri::command] functions
    src/clipboard.rs        # image write via plugin
    tauri.conf.json
    capabilities/           # per-window permissions
  models/                   # ocrs detection + recognition .rten (bundled resource)
```

## Swift -> new mapping

| Swift (current) | New | Port type |
|---|---|---|
| `AnnotationTool` enum (`Editor.swift:3-51`) | `editor/model.ts` | Verbatim (titles, shortcuts `p/h/a/r/e/t/b/o`) |
| `Annotation` struct (`Editor.swift:53-62`) | `model.ts` | Verbatim, color as CSS string |
| undo/redo/`recordState` (`Editor.swift:143-155, 337-340`) | `state.ts` reducer | Verbatim semantics (snapshot arrays) |
| `imageRect`, `normalizedPoint`, `clamped`, `adjusted` (`Editor.swift:284-310`) | `geometry.ts` | Verbatim math; flip Y (AppKit bottom-left -> canvas top-left) |
| `draw(annotation)`, `drawArrow`, `drawPixelation` (`Editor.swift:368-440`) | `render.ts` | Verbatim; pixelate samples via `getImageData` |
| Highlighter alpha 0.35, width `max(12, w*4)`; arrow head `max(12, w*4)`; text 22pt bold * scale | `render.ts` constants | Verbatim |
| Text move drag (`movingText`, `Editor.swift:211-247`) | pointer handlers | Verbatim |
| `renderedPNGData` (`Editor.swift:164-192`) | `export.ts` OffscreenCanvas -> `toBlob` | Rewrite |
| `EditorWindowController` toolbar/popover (`Editor.swift:444+`) | React components | Rewrite |
| `CaptureService` (`screencapture` subprocess) | Rust `capture/` + overlay window | Rewrite |
| `HotKeyMonitor` (Carbon) | `tauri-plugin-global-shortcut` + `--capture` CLI flag | Rewrite |
| `TextRecognizer` (Vision) | Rust `ocr.rs` (`ocrs`) | Rewrite |
| `AppDelegate` tray/menu/activation policy | `main.rs` | Rewrite |
| `UserDefaults` hint flag | `tauri-plugin-store` | Trivial |

## Capture flow

1. Trigger: shortcut, tray menu, or `snipzy --capture` (forwarded via
   `single-instance` to the running process).
2. Rust: `capture_all_monitors()` -> `Vec<{id, x, y, w, h, scale, png_bytes}>`
   in global virtual coordinates.
3. Rust: spawn one frameless, always-on-top, fullscreen overlay window per
   monitor, labelled `overlay-<id>`.
4. Overlay: draw its monitor's screenshot as background, dim, crosshair, drag
   rect. `Esc` cancels; mouse-up confirms.
5. Overlay emits `region-selected {monitor_id, x, y, w, h}` (logical px).
   Rust crops at physical scale, emits `capture-ready {png_base64}`, closes
   all overlays, opens or focuses the editor window.
6. Wayland: skip `xcap`; use `ashpd::desktop::screenshot` (non-interactive)
   which returns one composite PNG. Split by monitor geometry when possible,
   else fall back to a single overlay spanning all monitors.

## Platform matrix

| | macOS | Windows | Linux X11 | Linux Wayland |
|---|---|---|---|---|
| Capture | `xcap` | `xcap` | `xcap` | `ashpd` portal |
| Hotkey | plugin | plugin | plugin | user binds `snipzy --capture` in DE settings (portal GlobalShortcuts later) |
| Clipboard image | plugin | plugin | plugin | plugin (`arboard`) |
| Tray | yes | yes | yes (appindicator) | yes |
| Hide Dock icon | `ActivationPolicy::Accessory` | n/a | n/a | n/a |
| Permission | Screen Recording prompt | none | none | portal dialog |

## Milestones

### M0 - Scaffold

- `pnpm create tauri-app` (React + TS), add plugins, tray with Capture/Quit,
  `Accessory` activation policy on macOS, `single-instance` + `--capture` arg.
- CI: GitHub Actions matrix (macOS / Windows / Ubuntu), `cargo test` + `vitest`.
- Done when: tray icon appears on all three OSes and an empty editor window opens.

### M1 - Editor port (largest, ~40% of effort)

- Port `model/state/geometry/render/export` from `Editor.swift` as pure TS
  with `vitest` tests mirroring `EditorTests.swift` (undo/redo, clamp,
  shift-constrain, `ocrRegion`, text move, PNG export excludes OCR rect).
- Editor window: toolbar (tool buttons with shortcuts, color input, width
  slider, undo/redo/copy/save), canvas, inline text input.
- Load image from `capture-ready` event; dev mode loads a fixture PNG.
- Copy via `clipboard-manager` `writeImage`; save via `dialog.save` + `fs`.
- Done when: README manual tests 4-6 and 17-18 pass on macOS with the fixture.

### M2 - Capture + overlay

- Rust `CaptureProvider` trait, `xcap` implementation, unit tests for crop
  math including HiDPI scale.
- Overlay window(s), region-select UX, `Esc` cancel.
- Wire the full flow: shortcut -> overlay -> editor.
- Done when: README manual tests 2, 3, 7 pass on macOS, Windows, and X11.

### M3 - Wayland

- `ashpd` screenshot provider, runtime detection via `XDG_SESSION_TYPE`.
- Document DE keybind setup; `--capture` through `single-instance`.
- Done when: works on GNOME and KDE Wayland VMs.

### M4 - OCR

- `ocrs` command `recognize(png, rect) -> String`, models bundled in `resources`.
- Editor: `O` tool, dashed rect, popover with editable text and Copy Text.
- Done when: README manual tests 10-15 pass. Accept accuracy below Vision.

### M5 - Packaging

- `tauri build` bundles: `.dmg`, `.msi`/`.exe`, `.deb` + `.AppImage`.
- Icons, macOS `LSUIElement` equivalent, Screen Recording usage string.
- Release workflow on tag.
- README/ROADMAP for the new repo; mark this repo as the macOS-only predecessor.

## Risks and mitigations

- **HiDPI multi-monitor overlay**: test mixed-scale setups early in M2; keep
  all region math in physical pixels on the Rust side.
- **Overlay flash/latency**: capture before showing overlays; if spawn takes
  more than ~200 ms, pre-create overlays hidden.
- **Wayland portal returns one composite PNG**: fall back to a single overlay
  spanning all monitors.
- **`ocrs` model size (~10 MB) and accuracy**: lazy-load on first OCR; note
  the regression vs Apple Vision in the README.
- **WebKitGTK canvas performance** for pen strokes: throttle redraws with
  `requestAnimationFrame`, cache the base image as an `ImageBitmap`.
- **`Cmd-Shift-4` conflict on macOS**: keep the current README instruction;
  make the hotkey configurable as an M5 stretch goal.
- **Loss of native feel on macOS** vs the current AppKit app.

## Out of scope (v1)

Window/display picker, capture history, signing/notarization, configurable
hotkey UI, portal GlobalShortcuts.

## Estimated size

Rust ~500 LOC, TS ~1500 LOC, tests ~600 LOC. Roughly 1.5-2x the current
Swift codebase (~1160 LOC source, ~470 LOC tests).

## Decision needed

- Proceed with the Tauri port in a new `snipzy.app` repo, or
- Keep Snipzy macOS-only and continue the Swift roadmap in `docs/ROADMAP.md`.
