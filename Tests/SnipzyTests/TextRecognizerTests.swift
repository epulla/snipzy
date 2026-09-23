import AppKit
import Testing
@testable import Snipzy

@Suite
struct TextRecognizerTests {
    @Test
    func orderedTextSortsTopToBottomThenLeftToRight() {
        let lines: [(box: CGRect, text: String)] = [
            (CGRect(x: 0.5, y: 0.8, width: 0.3, height: 0.1), "world"),
            (CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.1), "second"),
            (CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1), "hello"),
            (CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1), "   ")
        ]

        #expect(VisionTextRecognizer.orderedText(lines) == "hello world\nsecond")
    }

    @Test
    func visionRecognizesRenderedText() async throws {
        let image = renderImage(width: 600, height: 200, texts: [("SNIPZY", CGPoint(x: 40, y: 45))])
        let result = try await VisionTextRecognizer().recognizeText(
            in: image,
            region: CGRect(x: 0, y: 0, width: 1, height: 1)
        )

        #expect(result.uppercased().contains("SNIPZY"))
    }

    @Test
    func visionRespectsRegionOfInterest() async throws {
        let image = renderImage(
            width: 1000,
            height: 200,
            texts: [("LEFT", CGPoint(x: 40, y: 45)), ("RIGHT", CGPoint(x: 600, y: 45))]
        )
        let result = try await VisionTextRecognizer().recognizeText(
            in: image,
            region: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        )
        let uppercased = result.uppercased()

        #expect(uppercased.contains("LEFT"))
        #expect(!uppercased.contains("RIGHT"))
    }
}

private func renderImage(width: Int, height: Int, texts: [(String, CGPoint)]) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    for (text, point) in texts {
        NSString(string: text).draw(
            at: point,
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 96),
                .foregroundColor: NSColor.black
            ]
        )
    }
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}
