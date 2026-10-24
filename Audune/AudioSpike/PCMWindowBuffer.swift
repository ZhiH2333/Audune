import Foundation
import Synchronization

/// Fixed 4096-float mono window.
/// The realtime callback only writes. Analysis copies the newest full 1024-sample frame.
nonisolated final class PCMWindowBuffer: @unchecked Sendable {
    static let windowLength = 1024
    static let slotCount = 3
    /// One accumulator plus three published frames.
    static let capacity = windowLength * (slotCount + 1)

    private let storage: UnsafeMutablePointer<Float>
    /// Audio thread only.
    private var fillCount = 0
    private let publishedSequence = Atomic<UInt64>(0)

    init() {
        storage = .allocate(capacity: Self.capacity)
        storage.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        storage.deinitialize(count: Self.capacity)
        storage.deallocate()
    }

    var allocatedSampleCount: Int { Self.capacity }

    func write(_ source: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var offset = 0
        while offset < count {
            let space = Self.windowLength - fillCount
            let chunk = min(space, count - offset)
            guard chunk > 0 else { return }
            storage.advanced(by: fillCount).update(from: source.advanced(by: offset), count: chunk)
            fillCount += chunk
            offset += chunk
            if fillCount == Self.windowLength {
                publishAccumulator()
            }
        }
    }

    func copyLatestWindow() -> [Float]? {
        let sequence = publishedSequence.load(ordering: .acquiring)
        guard sequence > 0 else { return nil }
        let slot = Int((sequence - 1) % UInt64(Self.slotCount))
        let start = storage.advanced(by: Self.windowLength * (slot + 1))
        return Array(UnsafeBufferPointer(start: start, count: Self.windowLength))
    }

    private func publishAccumulator() {
        let next = publishedSequence.load(ordering: .relaxed) &+ 1
        let slot = Int((next - 1) % UInt64(Self.slotCount))
        let destination = storage.advanced(by: Self.windowLength * (slot + 1))
        destination.update(from: storage, count: Self.windowLength)
        fillCount = 0
        publishedSequence.store(next, ordering: .releasing)
    }
}
