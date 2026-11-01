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

/// Frozen Island preview samples (spectrum + optional Now Playing) while energy-saving.
struct IslandLayoutPreviewSnapshot: Equatable {
    var spectrum: [Float]
    var peaks: [Float]
    var waveform: [Float]
    var drawsBars: Bool
    var nowPlaying: NowPlayingSnapshot

    @MainActor
    static func live(from island: IslandModel, studio: StudioModel) -> IslandLayoutPreviewSnapshot {
        let np: NowPlayingSnapshot
        if island.prefs.nowPlayingEnabled,
           island.nowPlaying.availability == .listening,
           island.nowPlaying.hasTrack
        {
            np = island.nowPlaying
        } else {
            np = .previewDemo
        }
        return IslandLayoutPreviewSnapshot(
            spectrum: island.expandedSpectrum.isEmpty ? studio.studioSpectrum : island.expandedSpectrum,
            peaks: island.expandedPeaks.isEmpty ? studio.spectrumPeaks : island.expandedPeaks,
            waveform: island.expandedWaveform.isEmpty ? studio.displayWaveform : island.expandedWaveform,
            drawsBars: island.snapshot.isSilent == false || studio.snapshot.isSilent == false,
            nowPlaying: np
        )
    }
}

struct IslandLayoutPreviewEnergyState: Equatable {
    var isEnergySaving = false
    var snapshot: IslandLayoutPreviewSnapshot?

    mutating func enterEnergySaving(capturing live: IslandLayoutPreviewSnapshot) {
        isEnergySaving = true
        snapshot = live
    }

    mutating func resume() {
        isEnergySaving = false
        snapshot = nil
    }
}
#endif
