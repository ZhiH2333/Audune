#if os(macOS)
import AppKit
import CoreImage
import SwiftUI

/// Full-window ambient backdrop for Lyrics. The album artwork is downsampled once,
/// blurred off the main actor, cached by artwork identity, and crossfaded between tracks.
struct LyricsArtworkBackdrop: View {
    var artwork: NSImage?
    var trackIdentity: String
    var reduceMotion: Bool

    @State private var current: BackdropLayer?
    @State private var previous: BackdropLayer?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.105, green: 0.092, blue: 0.085),
                        Color(red: 0.052, green: 0.047, blue: 0.044),
                        Color(red: 0.025, green: 0.024, blue: 0.023)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let previous, previous.id != current?.id {
                    layer(previous)
                }

                if let current {
                    layer(current)
                        .id(current.id)
                        .transition(.opacity)
                }

                Color.black.opacity(0.24)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.34), location: 0),
                        .init(color: .black.opacity(0.06), location: 0.48),
                        .init(color: .black.opacity(0.18), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.12), location: 0.55),
                        .init(color: .black.opacity(0.46), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    center: .center,
                    startRadius: 180,
                    endRadius: 980
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : .easeInOut(duration: 0.72),
            value: current?.id
        )
        .onAppear(perform: scheduleLoad)
        .onChange(of: loadID) { _, _ in scheduleLoad() }
        .onDisappear {
            guard let shown = current, shown.id == loadID else { return }
            current = nil
            previous = nil
        }
    }

    private var loadID: String {
        // Do not key on `ObjectIdentifier`: MediaRemote can hand back a fresh NSImage
        // object for the same track on every metadata event, which would re-run the
        // Gaussian blur while the song is paused or seeks. Track identity plus artwork
        // availability is stable for the lifetime of a track.
        let artID = artwork == nil ? "none" : "art"
        let size = artwork.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "0x0"
        return "\(trackIdentity)|\(artID)|\(size)"
    }

    private func scheduleLoad() {
        let id = loadID
        guard let artwork else {
            current = nil
            previous = nil
            return
        }
        guard current?.id != id else { return }

        Task { @MainActor in
            guard let cgImage = artwork.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ) else { return }
            guard let rendered = await LyricsBackdropRenderer.shared.render(cgImage, key: id) else { return }
            guard Task.isCancelled == false, loadID == id else { return }

            let image = NSImage(
                cgImage: rendered.image,
                size: NSSize(width: rendered.pixelWidth, height: rendered.pixelHeight)
            )
            if let current {
                previous = current
            }
            current = BackdropLayer(id: id, image: image)
        }
    }

    private func layer(_ layer: BackdropLayer) -> some View {
        Image(nsImage: layer.image)
            .resizable()
            .scaledToFill()
            .saturation(0.92)
            .contrast(1.02)
            .clipped()
    }
}

private struct BackdropLayer: Identifiable {
    var id: String
    var image: NSImage
}

private struct RenderedBackdrop: @unchecked Sendable {
    var image: CGImage
    var pixelWidth: CGFloat
    var pixelHeight: CGFloat
}

private actor LyricsBackdropRenderer {
    static let shared = LyricsBackdropRenderer()

    private let context = CIContext(options: [.cacheIntermediates: false])
    private var cache: [String: RenderedBackdrop] = [:]
    private var order: [String] = []
    private let cacheLimit = 6

    func render(_ cgImage: CGImage, key: String) -> RenderedBackdrop? {
        if let cached = cache[key] {
            return cached
        }

        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        // A ~900px base is plenty for a heavily blurred full-window backdrop and keeps
        // Core Image work bounded when tracks change quickly.
        let scale = min(1, 900 / max(extent.width, extent.height))
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = scaled
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 46)
            .cropped(to: scaled.extent)
        guard let output = context.createCGImage(blurred, from: scaled.extent) else { return nil }

        let rendered = RenderedBackdrop(
            image: output,
            pixelWidth: scaled.extent.width,
            pixelHeight: scaled.extent.height
        )
        cache[key] = rendered
        order.append(key)
        while order.count > cacheLimit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return rendered
    }
}
#endif
