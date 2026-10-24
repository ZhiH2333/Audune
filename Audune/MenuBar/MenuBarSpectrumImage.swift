#if os(macOS)
import AppKit

enum MenuBarVisualState: Equatable {
    case idle
    case starting
    case silent
    case receiving
    case failed
}

/// Reused template image for the single status item. Drawing never allocates a new bitmap.
final class MenuBarSpectrumImage {
    static let pointSize = NSSize(width: 56, height: 18)

    private let rep: NSBitmapImageRep

    init() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelsWide = Int(Self.pointSize.width * scale)
        let pixelsHigh = Int(Self.pointSize.height * scale)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        if let bitmap {
            bitmap.size = Self.pointSize
            rep = bitmap
        } else {
            rep = NSBitmapImageRep()
        }
    }

    func render(state: MenuBarVisualState, spectrum: [Float]) -> NSImage {
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let bounds = NSRect(origin: .zero, size: Self.pointSize)
            NSColor.clear.setFill()
            bounds.fill(using: .copy)
            NSColor.black.withAlphaComponent(0.92).setFill()
            switch state {
            case .failed:
                NSBezierPath(roundedRect: NSRect(x: 22, y: 8, width: 12, height: 2), xRadius: 1, yRadius: 1).fill()
            case .receiving:
                drawBars(spectrum, in: bounds)
            case .idle, .starting, .silent:
                NSBezierPath(rect: NSRect(x: 1, y: 1, width: bounds.width - 2, height: 1)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size: Self.pointSize)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private func drawBars(_ spectrum: [Float], in bounds: NSRect) {
        let count = AudioSnapshot.bandCount
        let gap: CGFloat = 1
        let barWidth = (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count)
        guard barWidth > 0 else { return }
        for index in 0..<count {
            let raw = index < spectrum.count ? spectrum[index] : 0
            let level = raw.isFinite ? min(max(raw, 0), 1) : 0
            let height = max(1, CGFloat(level) * (bounds.height - 2))
            let rect = NSRect(x: CGFloat(index) * (barWidth + gap), y: 1, width: barWidth, height: height)
            NSBezierPath(rect: rect).fill()
        }
    }
}
#endif
