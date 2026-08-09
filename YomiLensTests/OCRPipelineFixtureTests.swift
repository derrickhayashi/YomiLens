import XCTest
@testable import YomiLens

private struct OCRPipelineFixture: Decodable {
    let id: String
    let image: String
    let knownOCRIssue: String?
    let expectedOCRText: String
    let expectedText: String
    let requiredDictionaryForms: [String]
    let requiredExpressions: [String]
}

@MainActor
final class OCRPipelineFixtureTests: XCTestCase {
    func testOriginalFixturesThroughCompletePipeline() async throws {
        let fixtureURLs = try XCTUnwrap(
            Bundle(for: Self.self).urls(
                forResourcesWithExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(fixtureURLs.isEmpty, "No OCR pipeline fixtures found")

        for fixtureURL in fixtureURLs {
            let fixture = try JSONDecoder().decode(
                OCRPipelineFixture.self,
                from: Data(contentsOf: fixtureURL)
            )
            // Analyze corrected text independently so an OCR regression does
            // not disguise a tokenizer or dictionary-matching regression.
            let correctedAnalysis = await JapaneseAnalysisService.shared.analyze(
                fixture.expectedText
            )

            let analyzedForms = Set(
                correctedAnalysis.tokens.map {
                    $0.dictionaryForm ?? $0.surface
                }
            )
            let missingForms = fixture.requiredDictionaryForms.filter {
                !analyzedForms.contains($0)
            }
            XCTAssertTrue(
                missingForms.isEmpty,
                """
                \(fixture.id): missing dictionary forms: \(missingForms.joined(separator: ", "))
                Actual forms: \(analyzedForms.sorted())
                """
            )

            let expressionSurfaces = Set(
                correctedAnalysis.expressions.map(\.surface)
            )
            let missingExpressions = fixture.requiredExpressions.filter {
                !expressionSurfaces.contains($0)
            }
            XCTAssertTrue(
                missingExpressions.isEmpty,
                """
                \(fixture.id): missing expressions: \(missingExpressions.joined(separator: ", "))
                Actual expressions: \(expressionSurfaces.sorted())
                """
            )

            // Render our original text so OCR coverage needs no game screenshots.
            let image = renderedImage(for: fixture.expectedText)

            let ocrStart = ContinuousClock.now
            let ocrResult = try await OCRService.recognizeJapanese(in: image)
            let ocrDuration = ocrStart.duration(to: .now)

            let analysisStart = ContinuousClock.now
            let analysis = await JapaneseAnalysisService.shared.analyze(
                ocrResult.text
            )
            let analysisDuration = analysisStart.duration(to: .now)

            XCTAssertEqual(
                normalized(ocrResult.text),
                normalized(fixture.expectedOCRText),
                """
                \(fixture.id): Vision output changed. Review whether this is an improvement or regression, then update expectedOCRText.

                Actual OCR:
                \(ocrResult.text)
                """
            )

            let recognizedExpectedText = normalized(ocrResult.text).contains(
                normalized(fixture.expectedText)
            )
            let ocrFailureMessage = """
            \(fixture.id): OCR did not contain the corrected fixture text.

            Expected body:
            \(fixture.expectedText)

            Actual OCR:
            \(ocrResult.text)
            """

            if let knownOCRIssue = fixture.knownOCRIssue {
                XCTExpectFailure(knownOCRIssue) {
                    XCTAssertTrue(
                        recognizedExpectedText,
                        ocrFailureMessage
                    )
                }
            } else {
                XCTAssertTrue(recognizedExpectedText, ocrFailureMessage)
            }

            print(
                "[\(fixture.id)] OCR \(ocrDuration), "
                    + "analysis \(analysisDuration), "
                    + "\(analysis.tokens.count) tokens, "
                    + "expressions "
                    + "\(analysis.expressions.map(\.surface))"
            )
        }
    }

    private func renderedImage(for text: String) -> UIImage {
        let lines = text.components(separatedBy: "\n")
        let font = UIFont.systemFont(ofSize: 32)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let width = lines.map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 1
        let lineHeight: CGFloat = 56
        let size = CGSize(width: ceil(width) + 80, height: CGFloat(lines.count) * lineHeight + 80)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: 40, y: 40 + CGFloat(index) * lineHeight),
                    withAttributes: attributes
                )
            }
        }
    }

    private func normalized(_ text: String) -> String {
        String(
            text.precomposedStringWithCanonicalMapping.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }
        )
    }
}
