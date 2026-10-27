import Foundation

nonisolated struct SpectrumDynamicsSettings: Equatable {
    var attackSeconds: Double
    var releaseSeconds: Double
    /// 0 keeps each bar independent. 1 averages each bar with both neighbors.
    var neighborSmoothing: Float
    /// `nil` turns peak caps off.
    var peakHoldSeconds: Double?
    /// How far peak caps fall per second after the hold time. Ignored when hold is off.
    var peakFallPerSecond: Float

    static let defaultPeakFallPerSecond: Float = 0.9
}

nonisolated struct SpectrumDynamicsState: Equatable {
    var levels: [Float] = []
    var peaks: [Float] = []
    var peakAge: [Double] = []
}

/// Time-based bar motion for Studio Spectrum. Pure and independent of the frame rate.
nonisolated enum SpectrumDynamics {
    static let maximumStep = 0.25
    static let settleEpsilon: Float = 0.01

    static func step(
        state: SpectrumDynamicsState,
        target: [Float],
        dt requestedDt: Double,
        settings: SpectrumDynamicsSettings
    ) -> SpectrumDynamicsState {
        let count = target.count
        guard count > 0 else { return SpectrumDynamicsState() }
        let dt = requestedDt.isFinite ? min(max(requestedDt, 0), maximumStep) : 0
        let goal = spread(sanitized(target), amount: settings.neighborSmoothing)
        let attack = coefficient(dt: dt, seconds: settings.attackSeconds)
        let release = coefficient(dt: dt, seconds: settings.releaseSeconds)
        let fall = settings.peakFallPerSecond.isFinite
            ? max(settings.peakFallPerSecond, 0)
            : SpectrumDynamicsSettings.defaultPeakFallPerSecond

        var next = SpectrumDynamicsState()
        next.levels.reserveCapacity(count)
        next.peaks.reserveCapacity(count)
        next.peakAge.reserveCapacity(count)
        for index in 0..<count {
            let now = index < state.levels.count && state.levels[index].isFinite ? state.levels[index] : 0
            let weight = goal[index] > now ? attack : release
            let level = min(max(now + (goal[index] - now) * weight, 0), 1)
            next.levels.append(level)

            guard let hold = settings.peakHoldSeconds, hold.isFinite else {
                next.peaks.append(level)
                next.peakAge.append(0)
                continue
            }
            let oldPeak = index < state.peaks.count && state.peaks[index].isFinite ? state.peaks[index] : 0
            let oldAge = index < state.peakAge.count && state.peakAge[index].isFinite ? state.peakAge[index] : 0
            if level >= oldPeak {
                next.peaks.append(level)
                next.peakAge.append(0)
            } else {
                let age = oldAge + dt
                var peak = oldPeak
                if age > hold {
                    peak = max(level, oldPeak - fall * Float(dt))
                }
                next.peaks.append(min(max(peak, level), 1))
                next.peakAge.append(age)
            }
        }
        return next
    }

    /// True when bars (and optional peak caps) have settled near zero.
    static func isSettled(
        levels: [Float],
        peaks: [Float] = [],
        epsilon: Float = settleEpsilon
    ) -> Bool {
        let limit = epsilon.isFinite ? max(epsilon, 0) : settleEpsilon
        let levelQuiet = levels.allSatisfy { value in
            let safe = value.isFinite ? value : 0
            return abs(safe) <= limit
        }
        guard levelQuiet else { return false }
        return peaks.allSatisfy { value in
            let safe = value.isFinite ? value : 0
            return abs(safe) <= limit
        }
    }

    private static func coefficient(dt: Double, seconds: Double) -> Float {
        guard dt > 0 else { return 0 }
        let tau = seconds.isFinite ? max(seconds, 0.001) : 0.1
        return Float(1 - exp(-dt / tau))
    }

    private static func sanitized(_ values: [Float]) -> [Float] {
        values.map { $0.isFinite ? min(max($0, 0), 1) : 0 }
    }

    private static func spread(_ values: [Float], amount: Float) -> [Float] {
        let weight = amount.isFinite ? min(max(amount, 0), 1) : 0
        guard weight > 0, values.count >= 3 else { return values }
        return values.indices.map { index in
            let left = values[max(index - 1, 0)]
            let right = values[min(index + 1, values.count - 1)]
            return values[index] * (1 - weight) + (left + values[index] + right) / 3 * weight
        }
    }
}
