import XCTest
import AppKit
import SwiftUI
@testable import Audune

final class FullscreenPaletteTests: XCTestCase {
    @MainActor
    func testNilImageReturnsDefaultPalette() {
        let palette = FullscreenPalette.extract(from: nil)
        XCTAssertEqual(palette, FullscreenPalette.defaultAppleMusic)
        XCTAssertEqual(palette.allColors.count, 4)
    }

    @MainActor
    func testExtractFromGeneratedImage() {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let palette = FullscreenPalette.extract(from: image)
        XCTAssertEqual(palette.allColors.count, 4)
    }
}
