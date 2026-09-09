import AppKit
import XCTest
@testable import Snipzy

final class CaptureServiceTests: XCTestCase {
    func testCaptureUsesInteractiveSelectionArgumentsAndValidatesOutput() throws {
        let runner = RecordingRunner()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CaptureService(runner: runner, temporaryDirectory: directory)
        let result = try service.capture()

        XCTAssertEqual(runner.executable, "/usr/sbin/screencapture")
        XCTAssertEqual(Array(runner.arguments.prefix(4)), ["-i", "-s", "-x", "-d"])
        XCTAssertTrue(runner.arguments.last?.hasSuffix(".png") == true)
        XCTAssertFalse(result.pngData.isEmpty)
        XCTAssertFalse(result.tiffData.isEmpty)
        XCTAssertGreaterThan(result.image.size.width, 0)
        XCTAssertNotNil(runner.outputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runner.outputURL!.path))
    }

    func testNonZeroCaptureStatusThrows() {
        let runner = RecordingRunner(status: 1, error: Data("device unavailable".utf8), writesOutput: true)
        XCTAssertThrowsError(try CaptureService(runner: runner).capture()) { error in
            guard case let CaptureError.processFailed(status, message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 1)
            XCTAssertEqual(message, "device unavailable")
        }
    }

    func testInteractiveCancellationWithoutOutputThrowsCancelled() {
        let runner = RecordingRunner(status: 1, error: Data("cancelled".utf8), outputData: nil)

        XCTAssertThrowsError(try CaptureService(runner: runner).capture()) { error in
            guard case CaptureError.cancelled = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSuccessfulProcessWithoutOutputIsCancelled() throws {
        let runner = RecordingRunner(outputData: nil)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CaptureService(runner: runner, temporaryDirectory: directory)

        XCTAssertThrowsError(try service.capture()) { error in
            guard case CaptureError.cancelled = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertNotNil(runner.outputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runner.outputURL!.path))
    }

    func testNonEmptyInvalidOutputThrowsInvalidImageAndCleansUp() throws {
        let runner = RecordingRunner(outputData: Data("not an image".utf8))
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CaptureService(runner: runner, temporaryDirectory: directory)

        XCTAssertThrowsError(try service.capture()) { error in
            guard case CaptureError.invalidImage = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertNotNil(runner.outputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runner.outputURL!.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("snipzy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

private final class RecordingRunner: ProcessRunning {
    var executable = ""
    var arguments: [String] = []
    var outputURL: URL?
    let status: Int32
    let error: Data
    let outputData: Data?

    init(
        status: Int32 = 0,
        error: Data = Data(),
        outputData: Data? = Self.validPNGData,
        writesOutput: Bool = false
    ) {
        self.status = status
        self.error = error
        self.outputData = writesOutput ? Self.validPNGData : outputData
    }

    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        self.executable = executable
        self.arguments = arguments
        outputURL = URL(fileURLWithPath: arguments.last!)
        if let outputData {
            try outputData.write(to: outputURL!)
        }
        return ProcessResult(status: status, standardOutput: Data(), standardError: error)
    }

    private static let validPNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
}
