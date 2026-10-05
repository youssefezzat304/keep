import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// A tiny, pre-blurred texture keeps the backdrop smooth without a window-sized blur layer.
enum ArtworkWash {
    nonisolated static func render(_ image: CGImage) throws -> Data {
        try Task.checkCancellation()
        let size: CGFloat = 64
        let source = CIImage(cgImage: image).transformed(by: CGAffineTransform(
            scaleX: size / CGFloat(image.width), y: size / CGFloat(image.height)))
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let wash = source.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14])
            .cropped(to: bounds)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        guard let output = context.createCGImage(wash, from: bounds) else { throw CocoaError(.fileReadCorruptFile) }
        return try png(output)
    }

    nonisolated static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileReadCorruptFile) }
        return data as Data
    }
}
