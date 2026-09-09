import AppKit
import XCTest
@testable import Snipzy

@MainActor
final class EditorTests: XCTestCase {
    func testAnnotationHistorySupportsUndoAndRedo() {
        let canvas = EditorCanvas(image: testImage())
        canvas.addText("hello", at: CGPoint(x: 0.25, y: 0.25))

        XCTAssertEqual(canvas.annotations.count, 1)
        XCTAssertEqual(canvas.annotations[0].tool.rawValue, AnnotationTool.text.rawValue)
        XCTAssertEqual(canvas.annotations[0].text, "hello")

        canvas.undo()
        XCTAssertTrue(canvas.annotations.isEmpty)

        canvas.redo()
        XCTAssertEqual(canvas.annotations.count, 1)
        XCTAssertEqual(canvas.annotations[0].text, "hello")
    }

    func testEmptyTextDoesNotCreateAnnotationOrHistoryEntry() {
        let canvas = EditorCanvas(image: testImage())
        canvas.addText("", at: CGPoint(x: 0.5, y: 0.5))

        XCTAssertTrue(canvas.annotations.isEmpty)
        canvas.undo()
        XCTAssertTrue(canvas.annotations.isEmpty)
    }

    func testRendererProducesPNGBeforeAndAfterAnnotation() throws {
        let canvas = EditorCanvas(image: testImage())
        let original = try XCTUnwrap(canvas.renderedPNGData())

        canvas.addText("rendered", at: CGPoint(x: 0.2, y: 0.2))
        let annotated = try XCTUnwrap(canvas.renderedPNGData())

        XCTAssertFalse(original.isEmpty)
        XCTAssertFalse(annotated.isEmpty)
        XCTAssertNotEqual(original, annotated)
        XCTAssertNotNil(NSImage(data: annotated))
    }

    func testCopyCommandUsesInjectedClipboardWriter() throws {
        let pasteboard = RecordingPasteboard()
        let controller = EditorWindowController(image: testImage(), pasteboard: pasteboard)
        let canvas = try XCTUnwrap(controller.window?.contentView?.subviews.compactMap { $0 as? EditorCanvas }.first)

        canvas.commandHandler?(.copy)

        XCTAssertEqual(pasteboard.writeCount, 1)
        XCTAssertFalse(pasteboard.pngData.isEmpty)
        XCTAssertFalse(pasteboard.tiffData.isEmpty)
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
    var pngData = Data()
    var tiffData = Data()

    @discardableResult
    func write(pngData: Data, tiffData: Data) -> Bool {
        writeCount += 1
        self.pngData = pngData
        self.tiffData = tiffData
        return true
    }
}
