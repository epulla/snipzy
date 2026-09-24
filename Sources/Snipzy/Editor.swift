import AppKit

enum AnnotationTool: String, CaseIterable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case text
    case pixelate
    case ocr

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlight"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .pixelate: return "Pixelate"
        case .ocr: return "Read Text"
        }
    }

    var shortcut: String {
        switch self {
        case .pen: return "p"
        case .highlighter: return "h"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .text: return "t"
        case .pixelate: return "b"
        case .ocr: return "o"
        }
    }

    var symbolName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .pixelate: return "squareshape.split.3x3"
        case .ocr: return "eye"
        }
    }

    var helpText: String {
        switch self {
        case .pen: return "Draw freehand."
        case .highlighter: return "Translucent marker for emphasis."
        case .arrow: return "Drag to point at something."
        case .rectangle: return "Drag a box. Hold Shift for a square."
        case .ellipse: return "Drag an oval. Hold Shift for a circle."
        case .text: return "Click to type. Drag existing text to move it."
        case .pixelate: return "Drag to hide sensitive areas."
        case .ocr: return "Drag to copy text out of the image."
        }
    }
}

struct Annotation {
    let id = UUID()
    let tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    let points: [CGPoint]
    let text: String
    let color: NSColor
    let lineWidth: CGFloat
}

@MainActor
final class EditorCanvas: NSView {
    private(set) var annotations: [Annotation] = []
    private let image: NSImage
    private let bitmap: NSBitmapImageRep?
    private(set) var tool: AnnotationTool = .pen
    private var strokeColor: NSColor = .systemRed
    private var strokeWidth: CGFloat = 3
    private var undoAnnotations: [[Annotation]] = []
    private var redoAnnotations: [[Annotation]] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var dragPoints: [CGPoint] = []
    private var constrainDrag = false
    private var movingText: (index: Int, last: CGPoint, moved: Bool)?
    private var cursors: [AnnotationTool: NSCursor] = [:]
    var textHandler: ((CGPoint) -> Void)?
    var commandHandler: ((EditorCommand) -> Void)?
    var ocrHandler: ((CGRect) -> Void)?
    private(set) var ocrSelection: CGRect?

    init(image: NSImage) {
        self.image = image
        bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    func cursor(at viewPoint: CGPoint) -> NSCursor {
        guard imageRect.contains(viewPoint) else { return .arrow }
        switch tool {
        case .text:
            return textIndex(at: viewPoint) != nil ? .openHand : .iBeam
        case .pen, .highlighter:
            if let cursor = cursors[tool] { return cursor }
            let cursor = makeCursor(tool)
            cursors[tool] = cursor
            return cursor
        case .arrow, .rectangle, .ellipse, .pixelate, .ocr:
            return .crosshair
        }
    }

    private func updateCursor() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point) else { return }
        cursor(at: point).set()
    }

    private func makeCursor(_ tool: AnnotationTool) -> NSCursor {
        let sizeConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)?.withSymbolConfiguration(sizeConfiguration) else { return .crosshair }
        guard let white = symbol.withSymbolConfiguration(sizeConfiguration.applying(.init(paletteColors: [.white]))), let black = symbol.withSymbolConfiguration(sizeConfiguration.applying(.init(paletteColors: [.black]))) else { return .crosshair }
        guard let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0) else { return .crosshair }
        representation.size = CGSize(width: 24, height: 24)
        let context = NSGraphicsContext(bitmapImageRep: representation)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let symbolSize = symbol.size
        let scale = min(16 / symbolSize.width, 16 / symbolSize.height)
        let glyphSize = CGSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let glyphRect = CGRect(origin: CGPoint(x: 12 - glyphSize.width / 2, y: 12 - glyphSize.height / 2), size: glyphSize)
        for offset in [CGPoint(x: -1, y: -1), CGPoint(x: 0, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
            white.draw(in: glyphRect.offsetBy(dx: offset.x, dy: offset.y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        black.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: CGSize(width: 24, height: 24))
        image.addRepresentation(representation)
        // Tips measured from 16pt semibold SF Symbol art; test guards drift.
        let hotSpot = tool == .pen ? NSPoint(x: 11.5, y: 5.5) : NSPoint(x: 6, y: 16.5)
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            switch key {
            case "z": commandHandler?(event.modifierFlags.contains(.shift) ? .redo : .undo)
            case "c": commandHandler?(.copy)
            case "s": commandHandler?(.save)
            case "w": commandHandler?(.close)
            default: super.keyDown(with: event)
            }
            return
        }
        if event.characters == "?" {
            commandHandler?(.help)
            return
        }
        if let selectedTool = AnnotationTool.allCases.first(where: { $0.shortcut == key }) {
            setTool(selectedTool)
            return
        }
        super.keyDown(with: event)
    }

    func setTool(_ tool: AnnotationTool) {
        self.tool = tool
        window?.makeFirstResponder(self)
        updateCursor()
    }

    func setColor(_ color: NSColor) {
        strokeColor = color
    }

    var currentColor: NSColor { strokeColor }

    var cgImage: CGImage? { bitmap?.cgImage }

    func clearOCRSelection() {
        ocrSelection = nil
        needsDisplay = true
    }

    nonisolated static func ocrRegion(from start: CGPoint, to end: CGPoint) -> CGRect {
        let region = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard region.width >= 0.01, region.height >= 0.01 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return region
    }

    func setLineWidth(_ width: CGFloat) {
        strokeWidth = max(1, width)
    }

    func undo() {
        guard let previous = undoAnnotations.popLast() else { return }
        redoAnnotations.append(annotations)
        annotations = previous
        needsDisplay = true
    }

    func redo() {
        guard let next = redoAnnotations.popLast() else { return }
        undoAnnotations.append(annotations)
        annotations = next
        needsDisplay = true
    }

    func addText(_ text: String, at point: CGPoint) {
        guard !text.isEmpty else { return }
        recordState()
        annotations.append(Annotation(tool: .text, start: point, end: point, points: [], text: text, color: strokeColor, lineWidth: strokeWidth))
        needsDisplay = true
    }

    func renderedPNGData() -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let pixelSize = bitmap.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? size
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let representation else { return nil }
        let context = NSGraphicsContext(bitmapImageRep: representation)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let renderRect = CGRect(origin: .zero, size: pixelSize)
        NSBezierPath(rect: renderRect).addClip()
        image.draw(in: renderRect, from: .zero, operation: .sourceOver, fraction: 1)
        drawAnnotations(in: renderRect)
        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation.representation(using: .png, properties: [:])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        drawAnnotations(in: rect)
        drawInProgress(in: rect)
        if let ocrSelection { strokeOCRRect(ocrSelection, in: rect) }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = normalizedPoint(event.locationInWindow)
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return }
        if tool == .text {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let index = textIndex(at: viewPoint) {
                movingText = (index, point, false)
                NSCursor.closedHand.set()
                return
            }
            textHandler?(point)
            return
        }
        let clampedPoint = clamped(point)
        dragStart = clampedPoint
        dragCurrent = clampedPoint
        dragPoints = [clampedPoint]
        constrainDrag = event.modifierFlags.contains(.shift)
    }

    override func mouseDragged(with event: NSEvent) {
        if var movingText {
            guard annotations.indices.contains(movingText.index), annotations[movingText.index].tool == .text else {
                self.movingText = nil
                return
            }
            let current = normalizedPoint(event.locationInWindow)
            let delta = CGPoint(x: current.x - movingText.last.x, y: current.y - movingText.last.y)
            let annotation = annotations[movingText.index]
            let nextStart = clamped(CGPoint(x: annotation.start.x + delta.x, y: annotation.start.y + delta.y))
            let effectiveDelta = CGPoint(x: nextStart.x - annotation.start.x, y: nextStart.y - annotation.start.y)
            if effectiveDelta.x != 0 || effectiveDelta.y != 0 {
                if !movingText.moved {
                    recordState()
                    movingText.moved = true
                }
                annotations[movingText.index].start = nextStart
                annotations[movingText.index].end = CGPoint(x: annotation.end.x + effectiveDelta.x, y: annotation.end.y + effectiveDelta.y)
                needsDisplay = true
            }
            movingText.last = current
            self.movingText = movingText
            return
        }
        guard dragStart != nil else { return }
        let point = normalizedPoint(event.locationInWindow)
        let adjustedPoint = adjusted(clamped(point))
        dragCurrent = adjustedPoint
        if tool == .pen || tool == .highlighter { dragPoints.append(adjustedPoint) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movingText != nil {
            movingText = nil
            updateCursor()
            return
        }
        guard let start = dragStart, let current = dragCurrent else { return }
        defer {
            dragStart = nil
            dragCurrent = nil
            dragPoints = []
            constrainDrag = false
            needsDisplay = true
        }
        if tool == .ocr {
            let region = Self.ocrRegion(from: start, to: current)
            ocrSelection = region
            ocrHandler?(region)
            return
        }
        guard tool != .text else { return }
        recordState()
        let points = (tool == .pen || tool == .highlighter) ? dragPoints : []
        let color = tool == .highlighter ? strokeColor.withAlphaComponent(0.35) : strokeColor
        let width = tool == .highlighter ? max(12, strokeWidth * 4) : strokeWidth
        annotations.append(Annotation(tool: tool, start: start, end: current, points: points, text: "", color: color, lineWidth: width))
    }

    private var imageRect: CGRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    private func normalizedPoint(_ windowPoint: CGPoint) -> CGPoint {
        let local = convert(windowPoint, from: nil)
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: (local.x - rect.minX) / rect.width, y: (local.y - rect.minY) / rect.height)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    }

    private func adjusted(_ point: CGPoint) -> CGPoint {
        guard constrainDrag, let start = dragStart else { return point }
        guard tool == .rectangle || tool == .ellipse else { return point }
        let dx = point.x - start.x
        let dy = point.y - start.y
        let side = max(abs(dx), abs(dy))
        return clamped(CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side)))
    }

    func viewPoint(for normalized: CGPoint) -> CGPoint {
        point(clamped(normalized), in: imageRect)
    }

    private func point(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + normalized.x * rect.width, y: rect.minY + normalized.y * rect.height)
    }

    private func textAttributes(_ annotation: Annotation, scale: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: max(1, 22 * scale), weight: .bold), .foregroundColor: annotation.color]
    }

    private func textIndex(at viewPoint: CGPoint) -> Int? {
        let rect = imageRect
        let scale = rect.width / max(1, image.size.width)
        for index in annotations.indices.reversed() {
            let annotation = annotations[index]
            guard annotation.tool == .text else { continue }
            let origin = point(annotation.start, in: rect)
            let size = NSString(string: annotation.text).size(withAttributes: textAttributes(annotation, scale: scale))
            if CGRect(origin: origin, size: size).contains(viewPoint) { return index }
        }
        return nil
    }

    private func recordState() {
        undoAnnotations.append(annotations)
        redoAnnotations.removeAll()
    }

    private func drawInProgress(in rect: CGRect) {
        guard let start = dragStart, let current = dragCurrent else { return }
        if tool == .ocr {
            strokeOCRRect(Self.ocrRegion(from: start, to: current), in: rect)
            return
        }
        let color = tool == .highlighter ? strokeColor.withAlphaComponent(0.35) : strokeColor
        let width = tool == .highlighter ? max(12, strokeWidth * 4) : strokeWidth
        let annotation = Annotation(tool: tool, start: start, end: current, points: dragPoints, text: "", color: color, lineWidth: width)
        draw(annotation, in: rect)
    }

    private func strokeOCRRect(_ normalized: CGRect, in rect: CGRect) {
        NSColor.controlAccentColor.setStroke()
        let start = point(normalized.origin, in: rect)
        let end = point(CGPoint(x: normalized.maxX, y: normalized.maxY), in: rect)
        let path = NSBezierPath(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }

    private func drawAnnotations(in rect: CGRect) {
        for annotation in annotations { draw(annotation, in: rect) }
    }

    private func draw(_ annotation: Annotation, in rect: CGRect) {
        let start = point(annotation.start, in: rect)
        let end = point(annotation.end, in: rect)
        let renderScale = rect.width / max(1, image.size.width)
        let lineWidth = annotation.lineWidth * renderScale
        switch annotation.tool {
        case .pen, .highlighter:
            guard let first = annotation.points.first else { return }
            let path = NSBezierPath()
            path.move(to: point(first, in: rect))
            for item in annotation.points.dropFirst() { path.line(to: point(item, in: rect)) }
            annotation.color.setStroke()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.stroke()
        case .arrow:
            drawArrow(from: start, to: end, color: annotation.color, width: lineWidth)
        case .rectangle:
            annotation.color.setStroke()
            let path = NSBezierPath(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
            path.lineWidth = lineWidth
            path.stroke()
        case .ellipse:
            annotation.color.setStroke()
            let path = NSBezierPath(ovalIn: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
            path.lineWidth = lineWidth
            path.stroke()
        case .text:
            NSString(string: annotation.text).draw(at: start, withAttributes: textAttributes(annotation, scale: renderScale))
        case .pixelate:
            drawPixelation(in: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)), imageRect: rect)
        case .ocr:
            break
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, width * 4)
        let left = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
        let head = NSBezierPath()
        head.move(to: left)
        head.line(to: end)
        head.line(to: right)
        head.lineWidth = width
        head.stroke()
    }

    private func drawPixelation(in rect: CGRect, imageRect: CGRect) {
        guard let bitmap, imageRect.width > 0, imageRect.height > 0, rect.width > 0, rect.height > 0 else { return }
        let columns = max(1, Int(rect.width / 10))
        let rows = max(1, Int(rect.height / 10))
        let blockWidth = rect.width / CGFloat(columns)
        let blockHeight = rect.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = rect.minX + CGFloat(column) * blockWidth + blockWidth / 2
                let y = rect.minY + CGFloat(row) * blockHeight + blockHeight / 2
                let imageX = min(bitmap.pixelsWide - 1, max(0, Int(((x - imageRect.minX) / imageRect.width) * CGFloat(bitmap.pixelsWide))))
                let imageY = min(bitmap.pixelsHigh - 1, max(0, Int(((y - imageRect.minY) / imageRect.height) * CGFloat(bitmap.pixelsHigh))))
                (bitmap.colorAt(x: imageX, y: imageY) ?? .systemGray).setFill()
                NSBezierPath(rect: CGRect(x: rect.minX + CGFloat(column) * blockWidth, y: rect.minY + CGFloat(row) * blockHeight, width: blockWidth + 1, height: blockHeight + 1)).fill()
            }
        }
    }
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSPopoverDelegate, NSTextFieldDelegate {
    private let canvas: EditorCanvas
    private let pasteboard: any ImagePasting
    private let recognizer: any TextRecognizing
    private var pendingText: (field: NSTextField, point: CGPoint)?
    private(set) var ocrTask: Task<Void, Never>?
    private(set) var ocrResult: OCRResultViewController?
    private(set) var helpPopover: NSPopover?
    private var helpButton: NSButton!
    private var popover: NSPopover?
    private var tooltipTargets: [ObjectIdentifier: (view: NSView, title: String, shortcut: String?)] = [:]
    private var tooltipTask: Task<Void, Never>?
    private(set) var tooltip: NSView?
    var onClose: ((EditorWindowController) -> Void)?

    init(image: NSImage, pasteboard: any ImagePasting = SystemPasteboard(), recognizer: any TextRecognizing = VisionTextRecognizer()) {
        canvas = EditorCanvas(image: image)
        self.pasteboard = pasteboard
        self.recognizer = recognizer
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Snipzy Editor"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildView()
        canvas.textHandler = { [weak self] point in self?.requestText(at: point) }
        canvas.ocrHandler = { [weak self] region in self?.recognizeText(in: region) }
        canvas.commandHandler = { [weak self] command in
            switch command {
            case .undo: self?.undo()
            case .redo: self?.redo()
            case .copy: self?.copyImage()
            case .save: self?.saveImage()
            case .close: self?.close()
            case .help: self?.toggleHelp()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        ocrTask?.cancel()
        let old = popover
        popover = nil
        old?.close()
        let oldHelp = helpPopover
        helpPopover = nil
        oldHelp?.close()
        onClose?(self)
    }

    func recognizeText(in region: CGRect) {
        ocrTask?.cancel()
        let old = popover
        popover = nil
        old?.close()
        guard let image = canvas.cgImage else {
            canvas.clearOCRSelection()
            return
        }
        let result = OCRResultViewController(pasteboard: pasteboard)
        result.loadViewIfNeeded()
        ocrResult = result
        let newPopover = NSPopover()
        newPopover.contentViewController = result
        newPopover.behavior = .transient
        newPopover.delegate = self
        result.popover = newPopover
        popover = newPopover
        if window?.isVisible == true {
            let start = canvas.viewPoint(for: region.origin)
            let end = canvas.viewPoint(for: CGPoint(x: region.maxX, y: region.maxY))
            let anchor = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            newPopover.show(relativeTo: anchor, of: canvas, preferredEdge: .maxY)
        }
        let recognizer = self.recognizer
        ocrTask = Task { [weak result] in
            do {
                let text = try await recognizer.recognizeText(in: image, region: region)
                guard !Task.isCancelled else { return }
                result?.show(text: text)
            } catch {
                guard !Task.isCancelled else { return }
                result?.show(error: error)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let helpPopover, (notification.object as? NSPopover) === helpPopover {
            self.helpPopover = nil
            return
        }
        guard (notification.object as? NSPopover) === popover else { return }
        ocrTask?.cancel()
        ocrResult = nil
        popover = nil
        canvas.clearOCRSelection()
    }

    private func buildView() {
        guard let window, let contentView = window.contentView else { return }
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        toolbar.distribution = .fill
        for tool in AnnotationTool.allCases {
            let button = NSButton(title: tool.title, target: self, action: #selector(selectTool(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.bezelStyle = .texturedRounded
            if let image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title) {
                button.image = image
                button.imagePosition = .imageOnly
            }
            addTooltip(to: button, title: tool.title, shortcut: tool.shortcut.uppercased())
            toolbar.addArrangedSubview(button)
        }
        let colorWell = NSColorWell()
        colorWell.color = canvas.currentColor
        colorWell.target = self
        colorWell.action = #selector(changeColor(_:))
        addTooltip(to: colorWell, title: "Annotation color")
        toolbar.addArrangedSubview(colorWell)
        let widthSlider = NSSlider(value: 3, minValue: 1, maxValue: 12, target: self, action: #selector(changeWidth(_:)))
        widthSlider.controlSize = .small
        addTooltip(to: widthSlider, title: "Line width")
        widthSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        toolbar.addArrangedSubview(widthSlider)
        let spacer = NSView()
        toolbar.addArrangedSubview(spacer)
        let undo = NSButton(title: "Undo", target: self, action: #selector(undo))
        let redo = NSButton(title: "Redo", target: self, action: #selector(redo))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyImage))
        let save = NSButton(title: "Save", target: self, action: #selector(saveImage))
        addTooltip(to: undo, title: "Undo", shortcut: "⌘Z")
        addTooltip(to: redo, title: "Redo", shortcut: "⇧⌘Z")
        addTooltip(to: copy, title: "Copy image", shortcut: "⌘C")
        addTooltip(to: save, title: "Save PNG", shortcut: "⌘S")
        helpButton = NSButton(title: "", target: self, action: #selector(toggleHelp))
        helpButton.bezelStyle = .helpButton
        helpButton.setAccessibilityLabel("Help")
        addTooltip(to: helpButton, title: "Help", shortcut: "?")
        [undo, redo, copy, save, helpButton].forEach { toolbar.addArrangedSubview($0) }
        contentView.addSubview(toolbar)
        contentView.addSubview(canvas)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 48),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    // Custom tooltips: native ones wait ~1.5s and need an active app; activeAlways does not.
    private func addTooltip(to view: NSView, title: String, shortcut: String? = nil) {
        view.setAccessibilityHelp(shortcut.map { "\(title) (\($0))" } ?? title)
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        view.addTrackingArea(area)
        tooltipTargets[ObjectIdentifier(area)] = (view, title, shortcut)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let area = event.trackingArea, let target = tooltipTargets[ObjectIdentifier(area)] else { return super.mouseEntered(with: event) }
        tooltipTask?.cancel()
        tooltipTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.showTooltip(target.title, shortcut: target.shortcut, for: target.view)
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard let area = event.trackingArea, tooltipTargets[ObjectIdentifier(area)] != nil else { return super.mouseExited(with: event) }
        tooltipTask?.cancel()
        tooltip?.removeFromSuperview()
        tooltip = nil
    }

    func showTooltip(_ title: String, shortcut: String?, for view: NSView) {
        tooltip?.removeFromSuperview()
        guard let contentView = window?.contentView else { return }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        let content = NSStackView(views: [label] + (shortcut.map { [keycap($0)] } ?? []))
        content.spacing = 6
        content.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: shortcut == nil ? 8 : 4)
        content.translatesAutoresizingMaskIntoConstraints = false
        let bubble = NSBox()
        bubble.boxType = .custom
        bubble.titlePosition = .noTitle
        bubble.cornerRadius = 6
        bubble.borderWidth = 1
        bubble.borderColor = .separatorColor
        bubble.fillColor = .windowBackgroundColor
        bubble.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = .black.withAlphaComponent(0.25)
        bubble.shadow = shadow
        bubble.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            content.topAnchor.constraint(equalTo: bubble.topAnchor),
            content.bottomAnchor.constraint(equalTo: bubble.bottomAnchor)
        ])
        let size = content.fittingSize
        let anchor = view.convert(view.bounds, to: contentView)
        let x = min(max(anchor.midX - size.width / 2, 6), contentView.bounds.width - size.width - 6)
        bubble.frame = CGRect(x: x, y: anchor.minY - size.height - 4, width: size.width, height: size.height)
        contentView.addSubview(bubble)
        tooltip = bubble
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let tool = AnnotationTool(rawValue: rawValue) else { return }
        canvas.setTool(tool)
    }

    @objc private func changeColor(_ sender: NSColorWell) {
        canvas.setColor(sender.color)
    }

    @objc private func changeWidth(_ sender: NSSlider) {
        canvas.setLineWidth(CGFloat(sender.doubleValue))
    }

    @objc private func undo() { canvas.undo() }
    @objc private func redo() { canvas.redo() }

    @objc func toggleHelp() {
        if let helpPopover {
            helpPopover.close()
            self.helpPopover = nil
            return
        }
        let newPopover = NSPopover()
        newPopover.contentViewController = HelpViewController()
        newPopover.behavior = .transient
        newPopover.delegate = self
        helpPopover = newPopover
        if window?.isVisible == true {
            newPopover.show(relativeTo: helpButton.bounds, of: helpButton, preferredEdge: .minY)
        }
    }

    @objc private func copyImage() {
        finishText(commit: true)
        guard let png = canvas.renderedPNGData(), let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation else {
            showError(AppError.imageEncodingFailed)
            return
        }
        guard pasteboard.write(pngData: png, tiffData: tiff) else {
            showError(AppError.clipboardWriteFailed)
            return
        }
    }

    @objc private func saveImage() {
        finishText(commit: true)
        guard let png = canvas.renderedPNGData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Snipzy.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func requestText(at point: CGPoint) {
        guard pendingText == nil else { return }
        let field = NSTextField(frame: NSRect(origin: canvas.viewPoint(for: point), size: CGSize(width: 240, height: 30)))
        field.font = .systemFont(ofSize: 22, weight: .bold)
        field.textColor = canvas.currentColor
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.delegate = self
        pendingText = (field, point)
        canvas.addSubview(field)
        window?.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finishText(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finishText(commit: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishText(commit: true)
    }

    private func finishText(commit: Bool) {
        guard let pending = pendingText else { return }
        pendingText = nil
        if commit { canvas.addText(pending.field.stringValue, at: pending.point) }
        pending.field.removeFromSuperview()
        window?.makeFirstResponder(canvas)
    }
}

@MainActor
final class OCRResultViewController: NSViewController {
    private let pasteboard: any ImagePasting
    private let progressIndicator = NSProgressIndicator()
    private let scrollView = NSTextView.scrollableTextView()
    private let copyButton: NSButton
    private let closeButton: NSButton
    weak var popover: NSPopover?

    private var textView: NSTextView { scrollView.documentView as! NSTextView }

    init(pasteboard: any ImagePasting) {
        self.pasteboard = pasteboard
        copyButton = NSButton(title: "Copy Text", target: nil, action: nil)
        closeButton = NSButton(title: "Close", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        copyButton.target = self
        copyButton.action = #selector(copyText)
        copyButton.isEnabled = false
        closeButton.target = self
        closeButton.action = #selector(closePopover)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.startAnimation(nil)
        stack.addArrangedSubview(progressIndicator)

        textView.isRichText = false
        textView.isEditable = true
        scrollView.hasVerticalScroller = true
        scrollView.widthAnchor.constraint(equalToConstant: 360).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        stack.addArrangedSubview(scrollView)

        let buttons = NSStackView(views: [copyButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)
        view = stack
    }

    func show(text: String) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.string = "No text found"
            copyButton.isEnabled = false
        } else {
            textView.string = text
            copyButton.isEnabled = true
        }
    }

    func show(error: Error) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        textView.string = error.localizedDescription
        copyButton.isEnabled = false
    }

    var text: String { textView.string }
    var canCopy: Bool { copyButton.isEnabled }

    @objc func copyText() {
        guard canCopy else { return }
        pasteboard.write(string: textView.string)
    }

    @objc private func closePopover() {
        popover?.close()
    }
}

@MainActor
final class HelpViewController: NSViewController {
    private static let shortcuts = [
        ("⌘Z", "Undo"), ("⇧⌘Z", "Redo"), ("⌘C", "Copy image"), ("⌘S", "Save PNG"),
        ("⌘W", "Close editor"), ("?", "Toggle help"), ("⇧", "Square / circle"), ("⇧⌘4", "New capture")
    ]
    private let width: CGFloat = 320

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)

        stack.addArrangedSubview(sectionTitle("Tools"))
        for tool in AnnotationTool.allCases {
            let row = toolRow(tool)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        let separator = NSBox()
        separator.boxType = .separator
        stack.setCustomSpacing(14, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 1])
        stack.addArrangedSubview(separator)
        stack.setCustomSpacing(14, after: separator)
        separator.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(sectionTitle("Shortcuts"))

        let pairs = Self.shortcuts.map { [keycap($0.0), NSTextField(labelWithString: $0.1)] }
        let grid = NSGridView(views: stride(from: 0, to: pairs.count, by: 2).map { pairs[$0] + pairs[$0 + 1] })
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 2).xPlacement = .trailing
        grid.column(at: 2).leadingPadding = 12
        stack.addArrangedSubview(grid)
        view = stack
        // Popover otherwise sizes to the rows' width and squeezes out the edge insets.
        preferredContentSize = stack.fittingSize
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func toolRow(_ tool: AnnotationTool) -> NSStackView {
        let icon = NSImageView(image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let title = NSTextField(labelWithString: tool.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: tool.helpText)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = width - 64
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [icon, text, keycap(tool.shortcut.uppercased())])
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10
        return row
    }
}

@MainActor
private func keycap(_ key: String) -> NSView {
    let label = NSTextField(labelWithString: key)
    label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    let box = NSBox()
    box.boxType = .custom
    box.titlePosition = .noTitle
    box.cornerRadius = 4
    box.borderWidth = 1
    box.borderColor = .separatorColor
    box.fillColor = .quaternaryLabelColor
    box.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(label)
    NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 5),
        label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -5),
        label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        box.heightAnchor.constraint(equalToConstant: 20),
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 22)
    ])
    return box
}

enum EditorCommand {
    case undo, redo, copy, save, close, help
}
