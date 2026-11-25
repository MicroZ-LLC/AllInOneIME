#if canImport(Vision) && canImport(ImageIO)
import Foundation
import ImageIO

extension VisionTextRecognizer {
    /// `image` with its long side at most `longSide` pixels (never made bigger), as JPEG: ImageIO's thumbnail of it,
    /// rotated as the image says. Nil when ImageIO can't read it.
    public func downscaled(_ image: Data, longSide: Int) -> PromptImage? {
        Self.jpeg(image, longSide: longSide)
    }

    static func jpeg(_ image: Data, longSide: Int, quality: Double = 0.85) -> PromptImage? {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return PromptImage(data: output as Data, mediaType: "image/jpeg")
    }
}
#endif
