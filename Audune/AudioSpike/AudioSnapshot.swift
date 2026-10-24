import Foundation

nonisolated struct AudioSnapshot: Sendable, Equatable {
    var sequence: UInt64
    var timestampNanoseconds: UInt64
    var spectrum: [Float]
    var waveform: [Float]
    var rms: Float
    var peak: Float
    var isSilent: Bool

    static let bandCount = 16
    static let waveformCount = 128

    static let zero = AudioSnapshot(
        sequence: 0,
        timestampNanoseconds: 0,
        spectrum: Array(repeating: 0, count: bandCount),
        waveform: Array(repeating: 0, count: waveformCount),
        rms: 0,
        peak: 0,
        isSilent: true
    )
}

/// Latest spectrum shared by the analysis task and the main thread.
/// The realtime callback never locks or writes this box.
nonisolated final class AudioSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var snapshot = AudioSnapshot.zero

    func reset() -> UInt64 {
        lock.lock()
        generation &+= 1
        snapshot = .zero
        let token = generation
        lock.unlock()
        return token
    }

    func store(_ snapshot: AudioSnapshot, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation else { return }
        self.snapshot = snapshot
    }

    func load() -> AudioSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}
