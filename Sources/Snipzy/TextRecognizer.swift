import CoreGraphics
import Vision

protocol TextRecognizing: Sendable {
    func recognizeText(in image: CGImage, region: CGRect) async throws -> String
}

struct VisionTextRecognizer: TextRecognizing {
    func recognizeText(in image: CGImage, region: CGRect) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.revision = VNRecognizeTextRequestRevision3
            let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            let roi = region.intersection(unitRect)
            request.regionOfInterest = roi.isNull || roi.isEmpty ? unitRect : roi
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let lines = (request.results ?? []).map {
                (box: $0.boundingBox, text: $0.topCandidates(1).first?.string ?? "")
            }
            return Self.orderedText(lines)
        }.value
    }

    static func orderedText(_ lines: [(box: CGRect, text: String)]) -> String {
        let sorted = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.box.maxY > $1.box.maxY }
        var rows: [[(box: CGRect, text: String)]] = []

        for line in sorted {
            if let index = rows.firstIndex(where: {
                abs(line.box.midY - $0[0].box.midY) < min(line.box.height, $0[0].box.height) / 2
            }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }

        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }
}
