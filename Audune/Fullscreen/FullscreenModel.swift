import AppKit
import Foundation

@MainActor
@Observable
final class FullscreenModel {
    var prefs = FullscreenPreferences.standard
    var isPresented = false
    var nowPlaying = NowPlayingSnapshot.idle
    var snapshot = AudioSnapshot.zero
    var appearance = AppearancePreferences.standard
    var spectrum = SpectrumPreferences.standard
    var waveform = WaveformPreferences.standard
    var orbit = OrbitPreferences.standard
    var mode: StudioVisualMode = .orbit
    var lyricsStatus: LyricsLoadStatus = .idle
    var lyricsLines: [LyricLine] = []
    var lyricsSourceLabel: String = ""
}
