import Foundation

/// Fixed-length time-domain samples from one PCM window.
/// Call it off the realtime callback. Empty and non-finite input become zeros.
nonisolated enum WaveformSampler {
    static func downsample(_ samples: [Float], count: Int = AudioSnapshot.waveformCount) -> [Float] {
        guard count > 0 else { return [] }
        var output = [Float](repeating: 0, count: count)
        guard samples.isEmpty == false else { return output }
        for index in 0..<count {
            let start = index * samples.count / count
            let end = min(samples.count, max((index + 1) * samples.count / count, start + 1))
            var peak: Float = 0
            var seen = false
            for sample in samples[start..<end] where sample.isFinite {
                if seen == false || abs(sample) > abs(peak) {
                    peak = sample
                    seen = true
                }
            }
            output[index] = seen ? min(max(peak, -1), 1) : 0
        }
        return output
    }
}
