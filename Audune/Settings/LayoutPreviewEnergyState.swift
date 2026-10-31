#if os(macOS)
import Foundation

/// Frozen Layout preview samples used while energy-saving is on.
struct LayoutPreviewSnapshot: Equatable {
    var spectrum: [Float]
    var peaks: [Float]
    var waveform: [Float]
    var drawsBars: Bool

    static func live(from model: StudioModel) -> LayoutPreviewSnapshot {
        LayoutPreviewSnapshot(
            spectrum: model.studioSpectrum,
            peaks: model.spectrumPeaks,
            waveform: model.displayWaveform,
            drawsBars: model.snapshot.isSilent == false
        )
    }
}

/// Layout preview pauses when the user leaves the pane; returning keeps energy-saving until Resume.
struct LayoutPreviewEnergyState: Equatable {
    var isEnergySaving = false
    var snapshot: LayoutPreviewSnapshot?

    mutating func enterEnergySaving(capturing live: LayoutPreviewSnapshot) {
        isEnergySaving = true
        snapshot = live
    }

    mutating func resume() {
        isEnergySaving = false
        snapshot = nil
    }
}
#endif
