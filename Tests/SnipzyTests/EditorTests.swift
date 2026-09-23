import AppKit
import Testing
@testable import Snipzy

@MainActor
@Suite
struct EditorTests {
    @Test
    func annotationHistorySupportsUndoAndRedo() {
        let canvas = EditorCanvas(image: testImage())
        canvas.addText("hello", at: CGPoint(x: 0.25, y: 0.25))

        #expect(canvas.annotations.count == 1)
        #expect(canvas.annotations[0].tool.rawValue == AnnotationTool.text.rawValue)
        #expect(canvas.annotations[0].text == "hello")

        canvas.undo()
        #expect(canvas.annotations.isEmpty)

        canvas.redo()
        #expect(canvas.annotations.count == 1)
        #expect(canvas.annotations[0].text == "hello")
    }

    @Test
    func emptyTextDoesNotCreateAnnotationOrHistoryEntry() {
        let canvas = EditorCanvas(image: testImage())
        canvas.addText("", at: CGPoint(x: 0.5, y: 0.5))

        #expect(canvas.annotations.isEmpty)
        canvas.undo()
        #expect(canvas.annotations.isEmpty)
    }

    @Test
    func rendererProducesPNGBeforeAndAfterAnnotation() throws {
        let canvas = EditorCanvas(image: testImage())
        let original = try #require(canvas.renderedPNGData())

        canvas.addText("rendered", at: CGPoint(x: 0.2, y: 0.2))
        let annotated = try #require(canvas.renderedPNGData())

        #expect(!original.isEmpty)
        #expect(!annotated.isEmpty)
        #expect(original != annotated)
        #expect(NSImage(data: annotated) != nil)
    }

    @Test
    func copyCommandUsesInjectedClipboardWriter() throws {
        let pasteboard = RecordingPasteboard()
        let controller = EditorWindowController(image: testImage(), pasteboard: pasteboard)
        let canvas = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? EditorCanvas }.first)

        canvas.commandHandler?(.copy)

        #expect(pasteboard.writeCount == 1)
        #expect(!pasteboard.pngData.isEmpty)
        #expect(!pasteboard.tiffData.isEmpty)
    }

    private func testImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100, height: 100)).fill()
        image.unlockFocus()
        return image
    }
}

private final class RecordingPasteboard: ImagePasting {
    var writeCount = 0
    var strings: [String] = []
    var pngData = Data()
    var tiffData = Data()

    @discardableResult
    func write(string: String) -> Bool {
        strings.append(string)
        return true
    }

    @discardableResult
    func write(pngData: Data, tiffData: Data) -> Bool {
        writeCount += 1
        self.pngData = pngData
        self.tiffData = tiffData
        return true
    }
}
