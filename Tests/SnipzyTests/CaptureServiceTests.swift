import AppKit
import Testing
@testable import Snipzy

@Suite
struct CaptureServiceTests {
    @Test
    func captureUsesInteractiveSelectionArgumentsAndValidatesOutput() throws {
        let runner = RecordingRunner()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CaptureService(runner: runner, temporaryDirectory: directory)
        let result = try service.capture()

        #expect(runner.executable == "/usr/sbin/screencapture")
        #expect(Array(runner.arguments.prefix(4)) == ["-i", "-s", "-x", "-d"])
        #expect(runner.arguments.last?.hasSuffix(".png") == true)
        #expect(!result.pngData.isEmpty)
        #expect(!result.tiffData.isEmpty)
        #expect(result.image.size.width > 0)
        #expect(runner.outputURL != nil)
        #expect(!FileManager.default.fileExists(atPath: runner.outputURL!.path))
    }

    @Test
    func nonZeroCaptureStatusThrows() {
        let runner = RecordingRunner(status: 1, error: Data("device unavailable".utf8), writesOutput: true)
        do {
            _ = try CaptureService(runner: runner).capture()
            Issue.record("Expected capture to throw")
        } catch let error as CaptureError {
            guard case let .processFailed(status, message) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(status == 1)
            #expect(message == "device unavailable")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func interactiveCancellationWithoutOutputThrowsCancelled() {
        let runner = RecordingRunner(status: 1, error: Data(), outputData: nil)

        #expect(throws: CaptureError.cancelled) {
            try CaptureService(runner: runner).capture()
        }
    }

    @Test
    func successfulProcessWithoutOutputIsCancelled() throws {
        let runner = RecordingRunner(outputData: nil)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CaptureService(runner: runner, temporaryDirectory: directory)

        #expect(throws: CaptureError.cancelled) {
            try service.capture()
        }
        #expect(runner.outputURL != nil)
        #expect(!FileManager.default.fileExists(atPath: runner.outputURL!.path))
    }

    @Test
    func nonEmptyInvalidOutputThrowsInvalidImageAndCleansUp() throws {
        let runner = RecordingRunner(outputData: Data("not an image".utf8))
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CaptureService(runner: runner, temporaryDirectory: directory)

        #expect(throws: CaptureError.invalidImage) {
            try service.capture()
        }
        #expect(runner.outputURL != nil)
        #expect(!FileManager.default.fileExists(atPath: runner.outputURL!.path))
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
        outputData: Data? = RecordingRunner.validPNGData,
        writesOutput: Bool = false
    ) {
        self.status = status
        self.error = error
        self.outputData = writesOutput ? RecordingRunner.validPNGData : outputData
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
