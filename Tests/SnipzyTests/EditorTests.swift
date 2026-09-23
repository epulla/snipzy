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
        let canvas = try canvas(of: controller)

        canvas.commandHandler?(.copy)

        #expect(pasteboard.writeCount == 1)
        #expect(!pasteboard.pngData.isEmpty)
        #expect(!pasteboard.tiffData.isEmpty)
    }

    @Test
    func ocrDragReportsRegionWithoutAnnotationOrHistory() throws {
        let controller = EditorWindowController(image: testImage())
        let canvas = try canvas(of: controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        canvas.addText("keep", at: CGPoint(x: 0.2, y: 0.2))
        let before = try #require(canvas.renderedPNGData())
        canvas.setTool(.ocr)
        var reported: CGRect?
        canvas.ocrHandler = { reported = $0 }
        let window = try #require(controller.window)
        let start = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.1, y: 0.1)), to: nil)
        let end = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.6, y: 0.7)), to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: end, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: end, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: down)
        canvas.mouseDragged(with: drag)
        canvas.mouseUp(with: up)

        let region = try #require(reported)
        #expect(abs(region.origin.x - 0.1) < 0.02)
        #expect(abs(region.origin.y - 0.1) < 0.02)
        #expect(abs(region.width - 0.5) < 0.02)
        #expect(abs(region.height - 0.6) < 0.02)
        #expect(canvas.annotations.count == 1)
        #expect(canvas.ocrSelection != nil)
        #expect(canvas.renderedPNGData() == before)
        canvas.undo()
        #expect(canvas.annotations.isEmpty)
    }

    @Test
    func ocrRegionTreatsClickAsWholeImageAndStandardizesDrag() {
        let whole = EditorCanvas.ocrRegion(from: CGPoint(x: 0.4, y: 0.4), to: CGPoint(x: 0.4, y: 0.4))
        #expect(whole == CGRect(x: 0, y: 0, width: 1, height: 1))
        let thin = EditorCanvas.ocrRegion(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0.5, y: 0.005))
        #expect(thin == CGRect(x: 0, y: 0, width: 1, height: 1))
        let region = EditorCanvas.ocrRegion(from: CGPoint(x: 0.6, y: 0.7), to: CGPoint(x: 0.1, y: 0.2))
        #expect(abs(region.origin.x - 0.1) < 0.0001)
        #expect(abs(region.origin.y - 0.2) < 0.0001)
        #expect(abs(region.width - 0.5) < 0.0001)
        #expect(abs(region.height - 0.5) < 0.0001)
    }

    @Test
    func ocrResultCopiesOnlyOnCopyButton() async throws {
        let (controller, pasteboard) = try await runOCR(result: .success("hello"))
        #expect(pasteboard.strings.isEmpty)
        #expect(pasteboard.writeCount == 0)
        #expect(controller.ocrResult?.text == "hello")
        #expect(controller.ocrResult?.canCopy == true)
        let result = try #require(controller.ocrResult)
        result.view.layoutSubtreeIfNeeded()
        let scroll = try #require(result.view.subviews.compactMap { $0 as? NSScrollView }.first)
        let textView = try #require(scroll.documentView as? NSTextView)
        #expect(textView.frame.width > 0)
        controller.ocrResult?.copyText()
        #expect(pasteboard.strings == ["hello"])
    }

    @Test
    func ocrEmptyResultShowsNoTextAndDisablesCopy() async throws {
        let (controller, pasteboard) = try await runOCR(result: .success("   "))
        #expect(controller.ocrResult?.text == "No text found")
        #expect(controller.ocrResult?.canCopy == false)
        controller.ocrResult?.copyText()
        #expect(pasteboard.strings.isEmpty)
    }

    @Test
    func ocrFailureShowsErrorWithoutCopy() async throws {
        let (controller, pasteboard) = try await runOCR(result: .failure(StubError()))
        #expect(controller.ocrResult?.text == "stub failure")
        #expect(controller.ocrResult?.canCopy == false)
        #expect(pasteboard.strings.isEmpty)
    }

    private func canvas(of controller: EditorWindowController) throws -> EditorCanvas {
        try #require(controller.window?.contentView?.subviews.compactMap { $0 as? EditorCanvas }.first)
    }

    private func runOCR(result: Result<String, StubError>) async throws -> (EditorWindowController, RecordingPasteboard) {
        let pasteboard = RecordingPasteboard()
        let controller = EditorWindowController(image: testImage(), pasteboard: pasteboard, recognizer: StubRecognizer(result: result))
        let canvas = try canvas(of: controller)
        canvas.ocrHandler?(CGRect(x: 0, y: 0, width: 1, height: 1))
        await controller.ocrTask?.value
        return (controller, pasteboard)
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

private struct StubRecognizer: TextRecognizing {
    let result: Result<String, StubError>

    func recognizeText(in image: CGImage, region: CGRect) async throws -> String {
        try result.get()
    }
}

private struct StubError: LocalizedError, Sendable {
    var errorDescription: String? { "stub failure" }
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
