import SwiftUI
import UIKit

struct OCRDebugImageView: View {
    let image: UIImage
    let regions: [OCRRegion]

    var body: some View {
        GeometryReader { geometry in
            let imageRect = aspectFitRect(
                imageSize: image.size,
                containerSize: geometry.size
            )

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ForEach(regions) { region in
                    let rect = displayRect(
                        for: region.normalizedRect,
                        in: imageRect
                    )

                    Rectangle()
                        .stroke(.red, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Text("\(region.order)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.red, in: Circle())
                        .position(
                            x: max(rect.minX, 12),
                            y: max(rect.minY, 12)
                        )
                }
            }
        }
        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func aspectFitRect(
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func displayRect(
        for normalizedRect: CGRect,
        in imageRect: CGRect
    ) -> CGRect {
        CGRect(
            x: imageRect.minX + normalizedRect.minX * imageRect.width,
            y: imageRect.minY + normalizedRect.minY * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }
}
