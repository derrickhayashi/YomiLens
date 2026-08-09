import ImageIO
import UIKit
import Vision

struct OCRResult {
    let text: String
    let regions: [OCRRegion]
}

struct OCRRegion: Identifiable {
    let id: UUID
    let order: Int
    let text: String
    let normalizedRect: CGRect
}

enum OCRService {
    @MainActor
    static func recognizeJapanese(in image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.imageConversionFailed
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "ja")]
        request.usesLanguageCorrection = true

        let observations = try await request.perform(
            on: cgImage,
            orientation: image.imageOrientation.cgImagePropertyOrientation
        )

        var regions: [OCRRegion] = []

        for (index, observation) in observations.enumerated() {
            guard let text = observation.topCandidates(1).first?.string else {
                continue
            }

            regions.append(OCRRegion(
                id: observation.uuid,
                order: index + 1,
                text: text,
                normalizedRect: observation.boundingBox.verticallyFlipped().cgRect
            ))
        }

        return OCRResult(
            text: regions.map { $0.text }.joined(separator: "\n"),
            regions: regions
        )
    }
}

private enum OCRError: LocalizedError {
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            "The captured photo could not be prepared for text recognition."
        }
    }
}

private extension UIImage.Orientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up:
            .up
        case .upMirrored:
            .upMirrored
        case .down:
            .down
        case .downMirrored:
            .downMirrored
        case .left:
            .left
        case .leftMirrored:
            .leftMirrored
        case .right:
            .right
        case .rightMirrored:
            .rightMirrored
        @unknown default:
            .up
        }
    }
}
