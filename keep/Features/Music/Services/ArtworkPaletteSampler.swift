import CoreGraphics
import Foundation

/// A small sRGB thumbnail supplies an average and two prominent, separated hues off the main actor.
enum ArtworkPaletteSampler {
    nonisolated static func sample(_ image: CGImage) throws -> ArtworkPalette? {
        try Task.checkCancellation()
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var average = Bucket()
        var hues = [Bucket](repeating: Bucket(), count: 12)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.1 else { continue }
            let r = min(1, Double(pixels[index]) / 255 / alpha)
            let g = min(1, Double(pixels[index + 1]) / 255 / alpha)
            let b = min(1, Double(pixels[index + 2]) / 255 / alpha)
            average.add(r, g, b, weight: alpha)
            let high = max(r, g, b), low = min(r, g, b), delta = high - low
            guard delta > 0.08, high > 0.12 else { continue }
            var hue: Double
            if high == r { hue = (g - b) / delta }
            else if high == g { hue = 2 + (b - r) / delta }
            else { hue = 4 + (r - g) / delta }
            if hue < 0 { hue += 6 }
            let bin = min(11, Int(hue * 2))
            hues[bin].add(r, g, b, weight: alpha * delta)
        }
        try Task.checkCancellation()
        guard let ambient = average.color else { return nil }
        guard let first = hues.indices.max(by: { hues[$0].weight < hues[$1].weight }),
              let primary = hues[first].color else {
            return ArtworkPalette(ambient: ambient, primary: ambient, secondary: ambient)
        }
        let second = hues.indices.filter { $0 != first }.max { score($0, from: first, hues: hues) < score($1, from: first, hues: hues) }
        return ArtworkPalette(ambient: ambient, primary: primary,
                              secondary: second.flatMap { hues[$0].color } ?? primary)
    }

    nonisolated private static func score(_ index: Int, from first: Int, hues: [Bucket]) -> Double {
        let distance = min(abs(index - first), 12 - abs(index - first))
        // Favor a distinct supporting hue over a neighboring shade of the dominant color.
        return hues[index].weight * Double(distance * distance)
    }

    private struct Bucket: Sendable {
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        nonisolated init() {}
        nonisolated mutating func add(_ r: Double, _ g: Double, _ b: Double, weight value: Double) {
            red += r * value; green += g * value; blue += b * value; weight += value
        }
        nonisolated var color: ArtworkPalette.RGB? {
            guard weight > 0 else { return nil }
            return ArtworkPalette.RGB(red: red / weight, green: green / weight, blue: blue / weight)
        }
    }
}
