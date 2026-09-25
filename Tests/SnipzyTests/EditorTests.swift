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
    func copyWhileTypingIncludesPendingText() throws {
        let pasteboard = RecordingPasteboard()
        let controller = EditorWindowController(image: testImage(), pasteboard: pasteboard)
        let canvas = try canvas(of: controller)
        let baseline = try #require(canvas.renderedPNGData())
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        canvas.setTool(.text)
        let window = try #require(controller.window)
        let location = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.2, y: 0.2)), to: nil)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: event)
        let field = try #require(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "hi"

        canvas.commandHandler?(.copy)

        #expect(canvas.annotations.count == 1)
        #expect(canvas.annotations[0].text == "hi")
        #expect(canvas.subviews.compactMap { $0 as? NSTextField }.isEmpty)
        #expect(pasteboard.pngData != baseline)
    }

    @Test
    func returnCommitsTextAndEscapeDiscards() throws {
        let controller = EditorWindowController(image: testImage())
        let canvas = try canvas(of: controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        canvas.setTool(.text)
        let window = try #require(controller.window)
        let firstLocation = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.2, y: 0.2)), to: nil)
        let firstEvent = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: firstLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: firstEvent)
        let firstField = try #require(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        firstField.stringValue = "a"
        _ = firstField.delegate?.control?(firstField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(canvas.annotations.count == 1)
        #expect(canvas.subviews.compactMap { $0 as? NSTextField }.isEmpty)

        let secondLocation = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.7, y: 0.7)), to: nil)
        let secondEvent = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: secondLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: secondEvent)
        let secondField = try #require(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        secondField.stringValue = "b"
        _ = secondField.delegate?.control?(secondField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        #expect(canvas.annotations.count == 1)
        #expect(canvas.subviews.compactMap { $0 as? NSTextField }.isEmpty)
    }

    @Test
    func textToolDragMovesExistingText() throws {
        let controller = EditorWindowController(image: testImage())
        let canvas = try canvas(of: controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        canvas.addText("move", at: CGPoint(x: 0.2, y: 0.2))
        canvas.setTool(.text)
        let window = try #require(controller.window)
        let start = canvas.viewPoint(for: CGPoint(x: 0.2, y: 0.2))
        let downLocation = canvas.convert(CGPoint(x: start.x + 3, y: start.y + 3), to: nil)
        let endLocation = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.5, y: 0.5)), to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: downLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: endLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: endLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: down)
        canvas.mouseDragged(with: drag)
        canvas.mouseUp(with: up)

        #expect(abs(canvas.annotations[0].start.x - 0.5) < 0.02)
        #expect(abs(canvas.annotations[0].start.y - 0.5) < 0.02)
        #expect(canvas.annotations.count == 1)
        #expect(canvas.subviews.compactMap { $0 as? NSTextField }.isEmpty)
        canvas.undo()
        #expect(abs(canvas.annotations[0].start.x - 0.2) < 0.02)
        #expect(abs(canvas.annotations[0].start.y - 0.2) < 0.02)
    }

    @Test(arguments: [AnnotationTool.rectangle, .arrow, .pen, .text])
    func moveToolDragsAnyAnnotation(tool: AnnotationTool) throws {
        let controller = EditorWindowController(image: testImage())
        let canvas = try canvas(of: controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let window = try #require(controller.window)
        let start = CGPoint(x: 0.2, y: 0.2)
        let end = CGPoint(x: 0.4, y: 0.4)
        if tool == .text {
            canvas.addText("move", at: start)
        } else {
            canvas.setTool(tool)
            let downLocation = canvas.convert(canvas.viewPoint(for: start), to: nil)
            let endLocation = canvas.convert(canvas.viewPoint(for: end), to: nil)
            let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: downLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: endLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: endLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            canvas.mouseDown(with: down)
            canvas.mouseDragged(with: drag)
            canvas.mouseUp(with: up)
        }
        let original = canvas.annotations[0]
        let hit = tool == .text ? CGPoint(x: start.x + 0.01, y: start.y + 0.01) : CGPoint(x: 0.3, y: 0.3)
        let destination = CGPoint(x: hit.x + 0.1, y: hit.y + 0.1)
        canvas.setTool(.move)
        let downLocation = canvas.convert(canvas.viewPoint(for: hit), to: nil)
        let endLocation = canvas.convert(canvas.viewPoint(for: destination), to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: downLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: endLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: endLocation, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: down)
        canvas.mouseDragged(with: drag)
        canvas.mouseUp(with: up)

        let moved = canvas.annotations[0]
        #expect(abs(moved.start.x - original.start.x - 0.1) < 0.02)
        #expect(abs(moved.start.y - original.start.y - 0.1) < 0.02)
        #expect(abs(moved.end.x - original.end.x - 0.1) < 0.02)
        #expect(abs(moved.end.y - original.end.y - 0.1) < 0.02)
        if tool == .pen {
            #expect(moved.points.count == original.points.count)
            for (point, oldPoint) in zip(moved.points, original.points) {
                #expect(abs(point.x - oldPoint.x - 0.1) < 0.02)
                #expect(abs(point.y - oldPoint.y - 0.1) < 0.02)
            }
        }
        canvas.undo()
        #expect(canvas.annotations[0].start == original.start)
        #expect(canvas.annotations[0].end == original.end)
        #expect(canvas.annotations[0].points == original.points)
    }

    @Test
    func moveToolDragOnEmptyAreaDoesNotCreateAnnotation() throws {
        let controller = EditorWindowController(image: testImage())
        let canvas = try canvas(of: controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let window = try #require(controller.window)
        canvas.setTool(.move)
        let start = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.1, y: 0.1)), to: nil)
        let end = canvas.convert(canvas.viewPoint(for: CGPoint(x: 0.3, y: 0.3)), to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: end, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: end, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: down)
        canvas.mouseDragged(with: drag)
        canvas.mouseUp(with: up)

        #expect(canvas.annotations.isEmpty)
        #expect(!canvas.annotations.contains { $0.tool == .move })
    }

    @Test
    func cursorFollowsToolAndPosition() throws {
        let controller = EditorWindowController(image: testImage())
        let canvas = try canvas(of: controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let inside = canvas.viewPoint(for: CGPoint(x: 0.5, y: 0.5))
        canvas.setTool(.pen)
        let pen = canvas.cursor(at: inside)
        canvas.setTool(.highlighter)
        let highlighter = canvas.cursor(at: inside)
        #expect(pen !== NSCursor.arrow)
        #expect(pen !== NSCursor.iBeam)
        #expect(pen !== NSCursor.crosshair)
        #expect(highlighter !== NSCursor.arrow)
        #expect(highlighter !== NSCursor.iBeam)
        #expect(highlighter !== NSCursor.crosshair)
        #expect(pen !== highlighter)
        for tool in [AnnotationTool.arrow, .rectangle, .ellipse, .pixelate, .ocr] {
            canvas.setTool(tool)
            #expect(canvas.cursor(at: inside) === NSCursor.crosshair)
        }

        canvas.setTool(.text)
        #expect(canvas.cursor(at: inside) === NSCursor.iBeam)
        canvas.addText("x", at: CGPoint(x: 0.2, y: 0.2))
        let point = canvas.viewPoint(for: CGPoint(x: 0.2, y: 0.2))
        #expect(canvas.cursor(at: CGPoint(x: point.x + 3, y: point.y + 3)) === NSCursor.openHand)
        canvas.setTool(.move)
        #expect(canvas.cursor(at: inside) === NSCursor.openHand)
        #expect(canvas.cursor(at: CGPoint(x: 10, y: 300)) === NSCursor.arrow)
    }

    @Test
    func penCursorHotspotIsOnGlyphTip() throws {
        let controller = EditorWindowController(image: testImage())
        let canvas = try canvas(of: controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let point = canvas.viewPoint(for: CGPoint(x: 0.5, y: 0.5))

        for tool in [AnnotationTool.pen, .highlighter] {
            canvas.setTool(tool)
            let cursor = canvas.cursor(at: point)
            #expect(cursor.image.size == CGSize(width: 24, height: 24))
            if tool == .pen {
                #expect(cursor.hotSpot.y < 12)
            } else {
                #expect(cursor.hotSpot.x < 12)
                #expect(cursor.hotSpot.y > 12)
            }
            let representation = try #require(cursor.image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
            let pixelX = Int(cursor.hotSpot.x * 2)
            let pixelY = Int(cursor.hotSpot.y * 2)
            #expect((representation.colorAt(x: pixelX, y: pixelY)?.alphaComponent ?? 0) > 0.5)
        }
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

    @Test
    func helpTogglesPopoverAndQuestionMarkOpensIt() throws {
        let controller = EditorWindowController(image: testImage())
        controller.toggleHelp()
        let help = try #require(controller.helpPopover?.contentViewController as? HelpViewController)
        let fitting = help.view.fittingSize
        #expect(help.preferredContentSize == fitting)
        controller.toggleHelp()
        #expect(controller.helpPopover == nil)

        let canvas = try canvas(of: controller)
        let window = try #require(controller.window)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "?", charactersIgnoringModifiers: "?", isARepeat: false, keyCode: 44))
        canvas.keyDown(with: event)
        #expect(controller.helpPopover != nil)

        let toolbar = try #require(window.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
        #expect(toolbar.arrangedSubviews.compactMap { $0 as? NSButton }.contains { $0.bezelStyle == .helpButton })
    }

    @Test
    func helpPopoverExposesAccessibleDedicationLink() throws {
        let help = HelpViewController()
        help.loadViewIfNeeded()

        let link = try #require(help.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Doménica Soria" })
        #expect(link.isEnabled)
        #expect(link.accessibilityLabel() == "Doménica Soria")
        #expect(link.accessibilityRole() == .link)
        #expect(HelpViewController.dedicationURL.absoluteString == "https://www.linkedin.com/in/dom%C3%A9nica-soria-40bb12184/")
    }

    @Test
    func toolbarTooltipsTrackHoverAndStayInsideWindow() throws {
        let controller = EditorWindowController(image: testImage())
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        let content = try #require(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let toolbar = try #require(content.subviews.compactMap { $0 as? NSStackView }.first)
        let controls = toolbar.arrangedSubviews.compactMap { $0 as? NSControl }
        #expect(controls.count == 16)
        #expect(controls.allSatisfy { control in control.trackingAreas.contains { $0.owner === controller && $0.options.contains(.activeAlways) } })

        let help = try #require(controls.last)
        controller.showTooltip("Help", shortcut: "?", for: help)
        let tooltip = try #require(controller.tooltip)
        #expect(content.bounds.contains(tooltip.frame))
        #expect(tooltip.frame.maxY <= help.convert(help.bounds, to: content).minY)
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
