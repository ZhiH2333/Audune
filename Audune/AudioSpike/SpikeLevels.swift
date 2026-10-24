import CoreAudio
import Synchronization

/// Stream layout copied on the main thread before IO starts.
/// The realtime callback only reads this value.
nonisolated struct SpikeStreamFormat: Sendable {
    var sampleRate: Double
    var channelsPerFrame: UInt32
    var bytesPerFrame: UInt32
    var bitsPerChannel: UInt32
    var formatID: AudioFormatID
    var formatFlags: AudioFormatFlags
    var isFloat32: Bool
    var isNonInterleaved: Bool

    init(_ asbd: AudioStreamBasicDescription) {
        sampleRate = asbd.mSampleRate
        channelsPerFrame = asbd.mChannelsPerFrame
        bytesPerFrame = asbd.mBytesPerFrame
        bitsPerChannel = asbd.mBitsPerChannel
        formatID = asbd.mFormatID
        formatFlags = asbd.mFormatFlags
        isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let isLinearFloat = asbd.mFormatID == kAudioFormatLinearPCM
            && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            && (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) == 0
            && asbd.mBitsPerChannel == 32
            && asbd.mChannelsPerFrame > 0
        if isNonInterleaved {
            isFloat32 = isLinearFloat && asbd.mBytesPerFrame == 4
        } else {
            isFloat32 = isLinearFloat && asbd.mBytesPerFrame == asbd.mChannelsPerFrame * 4
        }
    }

    var formatIDText: String {
        Self.fourCharacter(formatID)
    }

    private static func fourCharacter(_ value: UInt32) -> String {
        let bytes = [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ]
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else {
            return String(value)
        }
        return String(bytes: bytes, encoding: .ascii) ?? String(value)
    }
}

nonisolated struct SpikeLevelSnapshot: Sendable {
    var frames: UInt64
    var rms: Float?
    var finiteSamples: UInt64
    var nonFiniteSamples: UInt64
    var formatMismatch: Bool
    var bufferCount: UInt32
}

/// One-pass RMS and frame counter. The callback only stores atomics.
nonisolated final class SpikeLevelMeter: Sendable {
    let format: SpikeStreamFormat

    private let frames = Atomic<UInt64>(0)
    private let finiteSamples = Atomic<UInt64>(0)
    private let nonFiniteSamples = Atomic<UInt64>(0)
    private let rmsBits = Atomic<UInt32>(0)
    private let hasRMS = Atomic<UInt8>(0)
    private let formatMismatch = Atomic<UInt8>(0)
    private let bufferCount = Atomic<UInt32>(0)

    init(format: SpikeStreamFormat) {
        self.format = format
    }

    func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = Self.buffers(in: input)
        bufferCount.store(UInt32(buffers.count), ordering: .relaxed)
        guard format.isFloat32 else {
            formatMismatch.store(1, ordering: .relaxed)
            return
        }
        if format.isNonInterleaved {
            consumeNonInterleaved(buffers)
        } else {
            consumeInterleaved(buffers)
        }
    }

    func snapshot() -> SpikeLevelSnapshot {
        let rms: Float?
        if hasRMS.load(ordering: .relaxed) == 1 {
            rms = Float(bitPattern: rmsBits.load(ordering: .relaxed))
        } else {
            rms = nil
        }
        return SpikeLevelSnapshot(
            frames: frames.load(ordering: .relaxed),
            rms: rms,
            finiteSamples: finiteSamples.load(ordering: .relaxed),
            nonFiniteSamples: nonFiniteSamples.load(ordering: .relaxed),
            formatMismatch: formatMismatch.load(ordering: .relaxed) == 1,
            bufferCount: bufferCount.load(ordering: .relaxed)
        )
    }

    private func consumeNonInterleaved(_ buffers: UnsafeBufferPointer<AudioBuffer>) {
        if buffers.count != Int(format.channelsPerFrame) {
            formatMismatch.store(1, ordering: .relaxed)
        }
        var safeFrames: UInt32?
        for buffer in buffers {
            guard let count = floatSampleCount(buffer, bytesPerFrame: 4) else { continue }
            safeFrames = min(safeFrames ?? count, count)
        }
        guard let safeFrames, safeFrames > 0 else {
            formatMismatch.store(1, ordering: .relaxed)
            return
        }

        var sumSquares = 0.0
        var finite = 0
        var nonFinite = 0
        for buffer in buffers {
            guard let count = floatSampleCount(buffer, bytesPerFrame: 4), count >= safeFrames,
                  let data = buffer.mData else {
                continue
            }
            let accumulated = accumulate(data, sampleCount: Int(safeFrames))
            sumSquares += accumulated.sumSquares
            finite += accumulated.finite
            nonFinite += accumulated.nonFinite
        }
        commit(frames: safeFrames, sumSquares: sumSquares, finite: finite, nonFinite: nonFinite)
    }

    private func consumeInterleaved(_ buffers: UnsafeBufferPointer<AudioBuffer>) {
        let bytesPerFrame = format.bytesPerFrame
        guard bytesPerFrame > 0 else {
            formatMismatch.store(1, ordering: .relaxed)
            return
        }
        var totalFrames: UInt32 = 0
        var sumSquares = 0.0
        var finite = 0
        var nonFinite = 0
        var sawBuffer = false
        for buffer in buffers {
            guard let frameCount = floatSampleCount(buffer, bytesPerFrame: bytesPerFrame) else { continue }
            guard let data = buffer.mData else { continue }
            sawBuffer = true
            let sampleCount = Int(frameCount) * Int(format.channelsPerFrame)
            let accumulated = accumulate(data, sampleCount: sampleCount)
            sumSquares += accumulated.sumSquares
            finite += accumulated.finite
            nonFinite += accumulated.nonFinite
            totalFrames += frameCount
        }
        guard sawBuffer else {
            formatMismatch.store(1, ordering: .relaxed)
            return
        }
        commit(frames: totalFrames, sumSquares: sumSquares, finite: finite, nonFinite: nonFinite)
    }

    /// `AudioDeviceIOProc` has no frame-count argument. Frames are the samples that fit in `mDataByteSize`.
    private func floatSampleCount(_ buffer: AudioBuffer, bytesPerFrame: UInt32) -> UInt32? {
        guard buffer.mData != nil, buffer.mDataByteSize > 0, bytesPerFrame > 0 else { return nil }
        guard buffer.mDataByteSize.isMultiple(of: bytesPerFrame) else {
            formatMismatch.store(1, ordering: .relaxed)
            return nil
        }
        return buffer.mDataByteSize / bytesPerFrame
    }

    private func accumulate(_ data: UnsafeMutableRawPointer, sampleCount: Int) -> (sumSquares: Double, finite: Int, nonFinite: Int) {
        let samples = data.assumingMemoryBound(to: Float.self)
        var sumSquares = 0.0
        var finite = 0
        var nonFinite = 0
        var index = 0
        while index < sampleCount {
            let sample = samples[index]
            if sample.isFinite {
                sumSquares += Double(sample) * Double(sample)
                finite += 1
            } else {
                nonFinite += 1
            }
            index += 1
        }
        return (sumSquares, finite, nonFinite)
    }

    private func commit(frames addedFrames: UInt32, sumSquares: Double, finite: Int, nonFinite: Int) {
        frames.wrappingAdd(UInt64(addedFrames), ordering: .relaxed)
        if finite > 0 {
            finiteSamples.wrappingAdd(UInt64(finite), ordering: .relaxed)
        }
        if nonFinite > 0 {
            nonFiniteSamples.wrappingAdd(UInt64(nonFinite), ordering: .relaxed)
        }
        guard finite > 0 else { return }
        let rms = Float(sumSquares / Double(finite)).squareRoot()
        guard rms.isFinite else { return }
        rmsBits.store(rms.bitPattern, ordering: .relaxed)
        hasRMS.store(1, ordering: .relaxed)
    }

    private static func buffers(in input: UnsafePointer<AudioBufferList>) -> UnsafeBufferPointer<AudioBuffer> {
        let count = Int(input.pointee.mNumberBuffers)
        guard count > 0, let offset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers) else {
            return UnsafeBufferPointer(start: nil, count: 0)
        }
        let start = UnsafeRawPointer(input).advanced(by: offset).assumingMemoryBound(to: AudioBuffer.self)
        return UnsafeBufferPointer(start: start, count: count)
    }
}
