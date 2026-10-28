import AppKit
import ScreenCaptureKit

@MainActor
enum DisplayUnderMouse {
    /// Snapshot of the display under the mouse, or nil without Screen Recording permission.
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
