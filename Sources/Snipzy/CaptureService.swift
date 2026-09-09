import AppKit
import CoreGraphics
import ImageIO

struct ProcessResult {
    let status: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol ProcessRunning {
    func run(executable: String, arguments: [String]) throws -> ProcessResult
}

struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            standardOutput: output.fileHandleForReading.readDataToEndOfFile(),
            standardError: error.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

struct CapturedImage {
    let image: NSImage
    let pngData: Data
    let tiffData: Data
}

enum CaptureError: LocalizedError {
    case cancelled
    case processFailed(Int32, String)
    case invalidImage
    case unableToCreateTIFF

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case let .processFailed(status, message):
            let detail = message.isEmpty ? "" : ": \(message)"
            return "Screenshot process failed (status \(status))\(detail)"
        case .invalidImage:
            return "Screenshot file is not a valid image"
        case .unableToCreateTIFF:
            return "Could not create TIFF representation"
        }
    }
}

struct CaptureService: @unchecked Sendable {
    let runner: any ProcessRunning
    let fileManager: FileManager
    let temporaryDirectory: URL

    init(
        runner: any ProcessRunning = SystemProcessRunner(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    func capture() throws -> CapturedImage {
        let url = temporaryDirectory.appendingPathComponent("snipzy-\(UUID().uuidString).png")
        defer { try? fileManager.removeItem(at: url) }

        let result = try runner.run(
            executable: "/usr/sbin/screencapture",
            arguments: ["-i", "-s", "-x", "-d", url.path]
        )
        guard result.status == 0 else {
            // Escape has no documented exit status. No output plus no stderr is
            // the only safe cancellation signal; -d displays native errors.
            let message = String(data: result.standardError, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard fileManager.fileExists(atPath: url.path) || !message.isEmpty else {
                throw CaptureError.cancelled
            }
            throw CaptureError.processFailed(result.status, message)
        }
        guard fileManager.fileExists(atPath: url.path), (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
            throw CaptureError.cancelled
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw CaptureError.invalidImage
        }
        let pngData = try Data(contentsOf: url)
        guard let bitmap = NSBitmapImageRep(data: pngData),
              let tiffData = bitmap.tiffRepresentation,
              let image = NSImage(data: pngData) else {
            throw CaptureError.unableToCreateTIFF
        }
        return CapturedImage(image: image, pngData: pngData, tiffData: tiffData)
    }
}

protocol ImagePasting {
    @discardableResult
    func write(pngData: Data, tiffData: Data) -> Bool
}

struct SystemPasteboard: ImagePasting {
    @discardableResult
    func write(pngData: Data, tiffData: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setData(pngData, forType: .png), item.setData(tiffData, forType: .tiff) else { return false }
        return pasteboard.writeObjects([item])
    }
}
