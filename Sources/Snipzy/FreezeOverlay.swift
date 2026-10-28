import AppKit
import ScreenCaptureKit

@MainActor
enum DisplayUnderMouse {
    /// Snapshot of the display under the mouse, or nil without Screen Recording permission.
    /// Uses ScreenCaptureKit because a second `screencapture` run right before `screencapture -i`
    /// fails with "cannot run two interactive screen captures at a time".
    static func snapshot() async -> (image: NSImage, frame: CGRect)? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        let frame = screen.frame
        let pixelSize = CGSize(width: frame.width * screen.backingScaleFactor, height: frame.height * screen.backingScaleFactor)
        guard let image = try? await capture(displayID: displayID, pixelSize: pixelSize) else { return nil }
        return (NSImage(cgImage: image, size: frame.size), frame)
    }

    private nonisolated static func capture(displayID: CGDirectDisplayID, pixelSize: CGSize) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration)
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
