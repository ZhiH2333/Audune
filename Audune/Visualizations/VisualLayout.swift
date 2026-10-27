import CoreGraphics

/// Where the visualization is drawn inside a container (the Studio window).
/// Pure geometry: the window's own size limits are handled elsewhere.
nonisolated enum VisualLayout {
    /// Visualization rectangle in the container's top-left coordinate space.
    /// Fixed mode keeps a size set by scale and aspect; it only shrinks (keeping aspect) when the container is smaller.
    static func frame(in container: CGSize, layout: VisualLayoutPreferences) -> CGRect {
        guard container.width.isFinite, container.height.isFinite, container.width > 0, container.height > 0 else {
            return .zero
        }
        let whole = CGRect(origin: .zero, size: container)
        guard layout.mode == .fixed else { return whole }

        let scale = layout.scale.isFinite
            ? min(max(layout.scale, VisualLayoutPreferences.scaleRange.lowerBound), VisualLayoutPreferences.scaleRange.upperBound)
            : 1
        let ratio = layout.aspect.ratio
        var width = VisualLayoutPreferences.referenceWidth * scale
        var height = width / ratio
        let fit = min(container.width / width, container.height / height, 1)
        width *= fit
        height *= fit
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }
}
