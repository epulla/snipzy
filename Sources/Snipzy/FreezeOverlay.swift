import AppKit

@MainActor
enum DisplayUnderMouse {
    static var frame: CGRect? {
        (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.frame
    }

    static var primaryMaxY: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    /// AppKit frames use a bottom-left origin; screencapture expects top-left.
    nonisolated static func captureRect(for frame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }
}

/// Covers a display with a still snapshot so `screencapture -i` selects from a frozen screen.
@MainActor
final class FreezeOverlay {
    private let window: NSPanel

    init(image: NSImage, frame: CGRect) {
        window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        window.contentView = imageView
        window.setFrame(frame, display: false)
    }

    func show() {
        window.orderFrontRegardless()
        window.display()
    }

    func close() {
        window.orderOut(nil)
    }
}
