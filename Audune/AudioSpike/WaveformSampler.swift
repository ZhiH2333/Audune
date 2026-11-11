import Foundation

/// Fixed-length time-domain samples from one PCM window.
/// Call it off the realtime callback. Empty and non-finite input become zeros.
nonisolated enum WaveformSampler {
    static let minimumTriggerWindowCount = 64

    /// Finds a rising zero-crossing (`<= 0` to `> 0`) in the leading search window so periodic waveforms anchor in phase.
    static func risingZeroCrossingOffset(in samples: [Float], maxSearch: Int) -> Int? {
        let limit = min(maxSearch, samples.count - 1)
        guard limit >= 1 else { return nil }
        var bestIndex: Int?
        var bestSlope: Float = 0
        for index in 0..<limit {
            let current = samples[index]
            let next = samples[index + 1]
            guard current.isFinite, next.isFinite, current <= 0, next > 0 else { continue }
            let slope = next - current
            if bestIndex == nil || slope > bestSlope * 1.15 {
                bestIndex = index
                bestSlope = slope
            }
        }
        return bestIndex
    }

    static func downsample(_ samples: [Float], count: Int = AudioSnapshot.waveformCount) -> [Float] {
        guard count > 0 else { return [] }
        var output = [Float](repeating: 0, count: count)
        guard samples.isEmpty == false else { return output }

        let window: ArraySlice<Float>
        let minTriggerCount = max(count * 2, minimumTriggerWindowCount)
        if samples.count >= minTriggerCount {
            let span = max(samples.count * 3 / 4, count)
            let maxSearch = max(samples.count - span, 0)
            if let trigger = risingZeroCrossingOffset(in: samples, maxSearch: maxSearch) {
                window = samples[trigger ..< min(trigger + span, samples.count)]
            } else {
                window = samples[...]
            }
        } else {
            window = samples[...]
        }

        let sliceCount = window.count
        let baseIndex = window.startIndex
        for index in 0..<count {
            let start = baseIndex + index * sliceCount / count
            let end = min(baseIndex + sliceCount, max(baseIndex + (index + 1) * sliceCount / count, start + 1))
            var peak: Float = 0
            var seen = false
            for sample in window[start..<end] where sample.isFinite {
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
