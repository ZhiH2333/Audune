#if os(macOS)
import AppKit
import SwiftUI

extension StudioColor {
    var swiftUI: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        self.init(red: Double(converted.redComponent), green: Double(converted.greenComponent), blue: Double(converted.blueComponent))
    }
}
#endif
