#if os(macOS)
import AppKit
import SwiftUI

/// Extracts a vibrant 4-color palette from album artwork for the Apple Music fluid background.
nonisolated struct FullscreenPalette: Equatable, Sendable {
    var primary: Color
    var secondary: Color
    var tertiary: Color
    var accent: Color

    static let defaultAppleMusic = FullscreenPalette(
        primary: Color(red: 0.88, green: 0.42, blue: 0.65),    // Vibrant Rose Pink
        secondary: Color(red: 0.42, green: 0.58, blue: 0.92),  // Sky / Lavender Blue
        tertiary: Color(red: 0.62, green: 0.28, blue: 0.72),   // Deep Violet / Magenta
        accent: Color(red: 0.32, green: 0.22, blue: 0.48)      // Atmospheric Indigo
    )

    var allColors: [Color] {
        [primary, secondary, tertiary, accent]
    }

    @MainActor
    static func extract(from image: NSImage?) -> FullscreenPalette {
        guard let image else { return defaultAppleMusic }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return defaultAppleMusic
        }

        let width = 16
        let height = 16
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return defaultAppleMusic
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func colorAt(x: Int, y: Int) -> Color {
            let offset = (y * width + x) * 4
            let r = Double(rawData[offset]) / 255.0
            let g = Double(rawData[offset + 1]) / 255.0
            let b = Double(rawData[offset + 2]) / 255.0
            return Color(red: r, green: g, blue: b)
        }

        // Sample key areas: top-left, top-right, center, bottom-left, bottom-right
        let c1 = colorAt(x: 3, y: 3)
        let c2 = colorAt(x: 12, y: 3)
        let c3 = colorAt(x: 8, y: 8)
        let c4 = colorAt(x: 4, y: 12)

        return FullscreenPalette(
            primary: c1,
            secondary: c2,
            tertiary: c3,
            accent: c4
        )
    }
}
#endif
