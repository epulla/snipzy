# Snipzy Agent Rules

- AppKit only. No SwiftUI.
- Swift Package Manager project.
- Run `make build` and `make test` before commit.
- Use Conventional Commits.
- Editor lives in `Sources/Snipzy/Editor.swift`.
- Toolbar and help popover order follow `AnnotationTool.allCases` order.
- Annotation coordinates normalized 0...1 over image.
- Store line widths and font sizes in image points; multiply by render scale when drawing.
- On-screen editing previews must use same scale as final rendering.
- Every drag-to-draw tool, including freehand, pen-like, highlighter, line, arrow, shapes, pixelate, and OCR, uses cursor hotspot exactly at stroke start.
- Default drag-to-draw cursor is `NSCursor.crosshair`.
- Custom glyph cursor requires measured hotspot on glyph tip and hotspot test `penCursorHotspotIsOnGlyphTip` in `Tests/SnipzyTests/EditorTests.swift`.
- Highlighter uses crosshair; glyph cursor made stroke origin ambiguous.
- Clickable buttons show pointing-hand cursor.
