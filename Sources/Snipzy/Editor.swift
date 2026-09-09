import AppKit

enum AnnotationTool: String, CaseIterable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case text
    case pixelate

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlight"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .pixelate: return "Pixelate"
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
        }
    }
}

struct Annotation {
    let id = UUID()
    let tool: AnnotationTool
    let start: CGPoint
    let end: CGPoint
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
    var textHandler: ((CGPoint) -> Void)?
    var commandHandler: ((EditorCommand) -> Void)?

    init(image: NSImage) {
        self.image = image
        bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

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
        if let selectedTool = AnnotationTool.allCases.first(where: { $0.shortcut == key }) {
            setTool(selectedTool)
            return
        }
        super.keyDown(with: event)
    }

    func setTool(_ tool: AnnotationTool) {
        self.tool = tool
        window?.makeFirstResponder(self)
    }

    func setColor(_ color: NSColor) {
        strokeColor = color
    }

    var currentColor: NSColor { strokeColor }

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
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = normalizedPoint(event.locationInWindow)
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return }
        if tool == .text {
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
        guard dragStart != nil else { return }
        let point = normalizedPoint(event.locationInWindow)
        let adjustedPoint = adjusted(clamped(point))
        dragCurrent = adjustedPoint
        if tool == .pen || tool == .highlighter { dragPoints.append(adjustedPoint) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart, let current = dragCurrent else { return }
        defer {
            dragStart = nil
            dragCurrent = nil
            dragPoints = []
            constrainDrag = false
            needsDisplay = true
        }
        recordState()
        let points = (tool == .pen || tool == .highlighter) ? dragPoints : []
        guard tool != .text else { return }
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

    private func recordState() {
        undoAnnotations.append(annotations)
        redoAnnotations.removeAll()
    }

    private func drawInProgress(in rect: CGRect) {
        guard let start = dragStart, let current = dragCurrent else { return }
        let color = tool == .highlighter ? strokeColor.withAlphaComponent(0.35) : strokeColor
        let width = tool == .highlighter ? max(12, strokeWidth * 4) : strokeWidth
        let annotation = Annotation(tool: tool, start: start, end: current, points: dragPoints, text: "", color: color, lineWidth: width)
        draw(annotation, in: rect)
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
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: max(1, 22 * renderScale), weight: .bold), .foregroundColor: annotation.color]
            NSString(string: annotation.text).draw(at: start, withAttributes: attributes)
        case .pixelate:
            drawPixelation(in: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)), imageRect: rect)
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
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: EditorCanvas
    private let pasteboard: any ImagePasting
    private var inlineTextField: InlineTextField?
    var onClose: ((EditorWindowController) -> Void)?

    init(image: NSImage, pasteboard: any ImagePasting = SystemPasteboard()) {
        canvas = EditorCanvas(image: image)
        self.pasteboard = pasteboard
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Snipzy Editor"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildView()
        canvas.textHandler = { [weak self] point in self?.requestText(at: point) }
        canvas.commandHandler = { [weak self] command in
            switch command {
            case .undo: self?.undo()
            case .redo: self?.redo()
            case .copy: self?.copyImage()
            case .save: self?.saveImage()
            case .close: self?.close()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
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
            toolbar.addArrangedSubview(button)
        }
        let colorWell = NSColorWell()
        colorWell.color = canvas.currentColor
        colorWell.target = self
        colorWell.action = #selector(changeColor(_:))
        colorWell.toolTip = "Annotation color"
        toolbar.addArrangedSubview(colorWell)
        let widthSlider = NSSlider(value: 3, minValue: 1, maxValue: 12, target: self, action: #selector(changeWidth(_:)))
        widthSlider.controlSize = .small
        widthSlider.toolTip = "Line width"
        widthSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        toolbar.addArrangedSubview(widthSlider)
        let spacer = NSView()
        toolbar.addArrangedSubview(spacer)
        let undo = NSButton(title: "Undo", target: self, action: #selector(undo))
        let redo = NSButton(title: "Redo", target: self, action: #selector(redo))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyImage))
        let save = NSButton(title: "Save", target: self, action: #selector(saveImage))
        [undo, redo, copy, save].forEach { toolbar.addArrangedSubview($0) }
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

    @objc private func copyImage() {
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
        guard inlineTextField == nil else { return }
        let field = InlineTextField(frame: NSRect(origin: canvas.viewPoint(for: point), size: CGSize(width: 240, height: 30)))
        field.font = .systemFont(ofSize: 22, weight: .bold)
        field.textColor = canvas.currentColor
        field.backgroundColor = NSColor.white.withAlphaComponent(0.9)
        field.isBezeled = true
        field.isEditable = true
        field.onCommit = { [weak self, weak field] in
            guard let self, let field else { return }
            self.finishText(field, at: point, commit: true)
        }
        field.onCancel = { [weak self, weak field] in
            guard let self, let field else { return }
            self.finishText(field, at: point, commit: false)
        }
        inlineTextField = field
        canvas.addSubview(field)
        window?.makeFirstResponder(field)
    }

    private func finishText(_ field: InlineTextField, at point: CGPoint, commit: Bool) {
        if commit { canvas.addText(field.stringValue, at: point) }
        field.removeFromSuperview()
        inlineTextField = nil
        window?.makeFirstResponder(canvas)
    }
}

enum EditorCommand {
    case undo, redo, copy, save, close
}

@MainActor
private final class InlineTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommit?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}
