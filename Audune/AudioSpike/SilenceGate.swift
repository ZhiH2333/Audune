import Foundation

/// Visual silence detection from PCM RMS. Does not mute system audio capture.
nonisolated struct SilenceGateSettings: Equatable, Sendable {
    var enabled: Bool
    /// Enter silence when RMS stays at or below this value.
    var enterRMS: Float
    /// Leave silence when RMS rises above this value (hysteresis).
    var exitRMS: Float
    /// Consecutive quiet analysis frames required before entering silence.
    var enterFrames: Int

    /// Matches the previous hard-coded analyzer thresholds.
    static let standard = SilenceGateSettings(
        enabled: true,
        enterRMS: 0.0008,
        exitRMS: 0.0015,
        enterFrames: 8
    )

    /// Builds enter/exit from a user threshold. Exit stays ~1.875× enter for hysteresis.
    static func from(enabled: Bool, threshold: Double) -> SilenceGateSettings {
        let enter = Float(threshold.isFinite ? max(threshold, 0) : Double(standard.enterRMS))
        let exit = enter * (standard.exitRMS / standard.enterRMS)
        return SilenceGateSettings(
            enabled: enabled,
            enterRMS: enter,
            exitRMS: exit.isFinite ? max(exit, enter) : standard.exitRMS,
            enterFrames: standard.enterFrames
        )
    }
}

/// Latest silence settings shared by the main thread and the analysis task.
nonisolated final class SilenceGateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var settings = SilenceGateSettings.standard

    func store(_ settings: SilenceGateSettings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
    }

    func load() -> SilenceGateSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }
}
