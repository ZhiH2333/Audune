#if os(macOS)
import AppKit
import CoreImage
import SwiftUI

/// Full-window ambient fluid backdrop for Lyrics. The album artwork is downsampled to a compact
/// colour field, saturation-boosted and blurred off the main actor, cached by track identity,
/// and composited as slowly counter-rotating fluid layers that mirror Apple Music.
struct LyricsArtworkBackdrop: View {
    var artwork: NSImage?
    var trackIdentity: String
    var isPlaying: Bool = true
    var reduceMotion: Bool

    @State private var current: BackdropLayer?
    @State private var previous: BackdropLayer?
    @State private var phaseAnchor = Date()

    var body: some View {
        GeometryReader { proxy in
            let animateFluid = isPlaying && reduceMotion == false && current != nil
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.11, blue: 0.15),
                        Color(red: 0.07, green: 0.06, blue: 0.09),
                        Color(red: 0.035, green: 0.032, blue: 0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: animateFluid == false)) { timeline in
                    let elapsed = animateFluid ? timeline.date.timeIntervalSince(phaseAnchor) : 0
                    ZStack {
                        if let previous, previous.id != current?.id {
                            fluidMesh(previous, size: proxy.size, elapsed: elapsed)
                        }

                        if let current {
                            fluidMesh(current, size: proxy.size, elapsed: elapsed)
                                .id(current.id)
                                .transition(.opacity)
                        }
                    }
                }

                // Subtle luminance and edge control so white lyrics stay effortless to read
                // without crushing the artwork palette into muddy gray.
                Color.black.opacity(0.24)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.18), location: 0),
                        .init(color: .black.opacity(0.05), location: 0.38),
                        .init(color: .black.opacity(0.12), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.10), location: 0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.26), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.28,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.85
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : .easeInOut(duration: 0.78),
            value: current?.id
        )
        .onAppear {
            phaseAnchor = Date()
            scheduleLoad()
        }
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

    private func fluidMesh(_ layer: BackdropLayer, size: CGSize, elapsed: TimeInterval) -> some View {
        let primaryAngle = (elapsed / 68.0).truncatingRemainder(dividingBy: 1.0) * 360.0
        let secondaryAngle = -(elapsed / 86.0).truncatingRemainder(dividingBy: 1.0) * 360.0
        let driftX = CGFloat(sin(elapsed / 9.5)) * size.width * 0.045
        let driftY = CGFloat(cos(elapsed / 11.5)) * size.height * 0.045

        return ZStack {
            // Base saturated field covering the entire viewport.
            Image(nsImage: layer.image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(1.28)

            // Primary slow-orbiting colour lobe.
            Image(nsImage: layer.image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(1.68)
                .rotationEffect(.degrees(primaryAngle))
                .offset(x: driftX, y: driftY)
                .opacity(0.64)

            // Counter-rotating soft bloom lobe that produces Apple Music's organic mesh shifts.
            Image(nsImage: layer.image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(1.86)
                .rotationEffect(.degrees(secondaryAngle + 32))
                .offset(x: -driftY * 0.85, y: driftX * 0.85)
                .opacity(0.26)
                .blendMode(.plusLighter)
        }
        .frame(width: size.width, height: size.height)
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

        // A 256px base reduces Core Image convolution work by >90% compared to 900px
        // while producing an even smoother, banding-free colour mesh for full-screen scaling.
        let scale = min(1, 256 / max(extent.width, extent.height))
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let enriched = scaled.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 1.36,
                kCIInputBrightnessKey: -0.03,
                kCIInputContrastKey: 1.05
            ]
        )
        let blurred = enriched
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 18)
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
