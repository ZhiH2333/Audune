import CoreAudio
import Foundation
import Observation

private let silenceRMSThreshold: Float = 0.0001
private let alivePollInterval: Duration = .milliseconds(50)
private let alivePollLimit: Duration = .seconds(2)

enum SpikePhase: String {
    case idle
    case starting
    case running
    case failed
}

struct SpikeAliveResult: Sendable {
    var ready: Bool
    var cancelled: Bool
    var elapsedMilliseconds: Int
    var detail: String
}

@MainActor
@Observable
final class ProcessTapSpike {
    var phase: SpikePhase = .idle
    var tapAutoStart = true
    var appliedTapAutoStart = false
    var statusText = "noErr (0)"
    var failureText = ""
    var outputUIDAtStart = ""
    var outputUIDAfterStart = ""
    var outputUIDAfterStop = ""
    var aliveText = "not started"
    var formatText = "unknown"
    var cleanupText = ""
    var reading = SpikeLevelSnapshot(frames: 0, rms: nil, finiteSamples: 0, nonFiniteSamples: 0, formatMismatch: false, bufferCount: 0)
    var framesAtRun = UInt64(0)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var meter: SpikeLevelMeter?
    private var active = false
    private var startInFlight = false
    let snapshots = AudioSnapshotBox()
    let silenceGate = SilenceGateBox()
    private var analysisTask: Task<Void, Never>?

    var displayState: String {
        switch phase {
        case .idle:
            return "idle"
        case .starting:
            return "starting"
        case .failed:
            return "failed"
        case .running:
            guard reading.frames > framesAtRun else { return "running" }
            guard let rms = reading.rms else { return "running" }
            return rms < silenceRMSThreshold ? "silent" : "receiving"
        }
    }

    func refreshReading() {
        guard let meter else { return }
        reading = meter.snapshot()
    }

    /// Updates visual silence detection. Does not change Process Tap mute behavior.
    func applySilenceSettings(_ settings: SilenceGateSettings) {
        silenceGate.store(settings)
    }

    func start() async {
        guard phase == .idle || phase == .failed else { return }
        active = true
        phase = .starting
        failureText = ""
        cleanupText = ""
        appliedTapAutoStart = tapAutoStart
        reading = SpikeLevelSnapshot(frames: 0, rms: nil, finiteSamples: 0, nonFiniteSamples: 0, formatMismatch: false, bufferCount: 0)

        guard let outputDevice = copyDefaultOutputDevice() else {
            fail("The default output device is unavailable.", status: kAudioHardwareBadDeviceError)
            return
        }
        guard let outputUID = copyDeviceUID(outputDevice) else {
            fail("The default output device has no UID.", status: kAudioHardwareBadDeviceError)
            return
        }
        outputUIDAtStart = outputUID
        outputUIDAfterStart = ""
        outputUIDAfterStop = ""

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Audune Spike Tap"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.isExclusive = true

        var createdTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &createdTap)
        statusText = describe(tapStatus)
        guard tapStatus == noErr, createdTap != kAudioObjectUnknown else {
            fail("AudioHardwareCreateProcessTap failed.", status: tapStatus)
            return
        }
        tapID = createdTap
        guard stillActive else { return }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Audune Spike Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: NSNumber(value: 1),
            kAudioAggregateDeviceIsStackedKey: NSNumber(value: 0),
            kAudioAggregateDeviceTapAutoStartKey: NSNumber(value: tapAutoStart ? 1 : 0),
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: NSNumber(value: 1)
                ]
            ]
        ]
        var createdAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &createdAggregate)
        statusText = describe(aggregateStatus)
        guard aggregateStatus == noErr, createdAggregate != kAudioObjectUnknown else {
            fail("AudioHardwareCreateAggregateDevice failed.", status: aggregateStatus)
            return
        }
        aggregateID = createdAggregate
        guard stillActive else { return }

        let alive = await waitUntilAlive(createdAggregate)
        aliveText = alive.detail
        guard stillActive else { return }
        guard alive.ready else {
            fail("Aggregate device was not alive within 2 seconds. \(alive.detail)", status: kAudioHardwareBadDeviceError)
            return
        }

        guard let asbd = copyInputStreamFormat(createdAggregate) else {
            fail("The aggregate input stream format is unavailable.", status: kAudioHardwareBadStreamError)
            return
        }
        let format = SpikeStreamFormat(asbd)
        formatText = formatDescription(format)
        guard format.isFloat32 else {
            fail("Input format is not 32-bit float linear PCM. \(formatText)", status: kAudioHardwareUnsupportedOperationError)
            return
        }

        let levelMeter = SpikeLevelMeter(format: format)
        meter = levelMeter
        var createdProc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcID(createdAggregate, auduneSpikeIOProc, Unmanaged.passUnretained(levelMeter).toOpaque(), &createdProc)
        statusText = describe(procStatus)
        guard procStatus == noErr, let createdProc else {
            fail("AudioDeviceCreateIOProcID failed.", status: procStatus)
            return
        }
        ioProcID = createdProc
        guard stillActive else { return }

        startInFlight = true
        let deviceID = createdAggregate
        let procID = createdProc
        let startStatus = await Task.detached(priority: .userInitiated) {
            AudioDeviceStart(deviceID, procID)
        }.value
        startInFlight = false
        statusText = describe(startStatus)
        guard active else {
            releaseResources()
            phase = .idle
            return
        }
        guard startStatus == noErr else {
            fail("AudioDeviceStart failed.", status: startStatus)
            return
        }

        outputUIDAfterStart = copyDefaultOutputDevice().flatMap(copyDeviceUID) ?? ""
        framesAtRun = levelMeter.snapshot().frames
        phase = .running
        startAnalysis(meter: levelMeter)
        if outputUIDAfterStart != outputUIDAtStart {
            failureText = "Default output UID changed while starting. Capture was not switched onto another device by Audune."
        }
    }

    func stop() {
        guard active || tapID != kAudioObjectUnknown || aggregateID != kAudioObjectUnknown || ioProcID != nil else {
            return
        }
        active = false
        if startInFlight {
            failureText = "Stop requested while AudioDeviceStart is still returning."
            return
        }
        releaseResources()
        if phase != .failed {
            phase = .idle
        }
    }

    private var stillActive: Bool {
        active && !startInFlight
    }

    private func fail(_ message: String, status: OSStatus) {
        statusText = describe(status)
        failureText = message
        phase = .failed
        active = false
        releaseResources()
    }

    private func startAnalysis(meter: SpikeLevelMeter) {
        analysisTask?.cancel()
        analysisTask = nil
        let generation = snapshots.reset()
        let snapshots = self.snapshots
        let sampleRate = meter.format.sampleRate
        let silenceGate = self.silenceGate
        analysisTask = Task.detached(priority: .userInitiated) {
            let analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
            while Task.isCancelled == false {
                analyzer.applySilenceSettings(silenceGate.load())
                if let window = meter.copyLatestWindow() {
                    var snapshot = analyzer.process(window)
                    snapshot.waveform = WaveformSampler.downsample(window)
                    snapshots.store(snapshot, generation: generation)
                }
                try? await Task.sleep(for: .milliseconds(32))
            }
        }
    }

    private func stopAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        _ = snapshots.reset()
    }

    private func releaseResources() {
        stopAnalysis()
        let deviceID = aggregateID
        let procID = ioProcID
        let createdTap = tapID
        ioProcID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown

        var notes: [String] = []
        if let procID, deviceID != kAudioObjectUnknown {
            let stopStatus = AudioDeviceStop(deviceID, procID)
            let destroyProcStatus = AudioDeviceDestroyIOProcID(deviceID, procID)
            notes.append("AudioDeviceStop \(describe(stopStatus))")
            notes.append("AudioDeviceDestroyIOProcID \(describe(destroyProcStatus))")
        }
        if deviceID != kAudioObjectUnknown {
            let destroyAggregateStatus = AudioHardwareDestroyAggregateDevice(deviceID)
            notes.append("AudioHardwareDestroyAggregateDevice \(describe(destroyAggregateStatus))")
        }
        if createdTap != kAudioObjectUnknown {
            let destroyTapStatus = AudioHardwareDestroyProcessTap(createdTap)
            let remaining = copyTapIDs()
            let stillPresent = remaining.contains(createdTap)
            notes.append("AudioHardwareDestroyProcessTap \(describe(destroyTapStatus))")
            if stillPresent {
                notes.append("tap \(createdTap) is still in the system tap list (\(remaining.count))")
            } else if remaining.isEmpty && destroyTapStatus == noErr {
                notes.append("tap \(createdTap) is absent; destroy returned noErr; tap list count \(remaining.count)")
            } else {
                notes.append("tap \(createdTap) is absent; destroy returned \(describe(destroyTapStatus)); tap list count \(remaining.count)")
            }
        }
        meter = nil
        outputUIDAfterStop = copyDefaultOutputDevice().flatMap(copyDeviceUID) ?? ""
        cleanupText = notes.joined(separator: "; ")
    }

    private func waitUntilAlive(_ deviceID: AudioObjectID) async -> SpikeAliveResult {
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started + alivePollLimit
        var lastValue = "unread"
        while true {
            if !active {
                return SpikeAliveResult(ready: false, cancelled: true, elapsedMilliseconds: elapsedMilliseconds(from: started, to: clock.now), detail: "stopped during DeviceIsAlive wait")
            }
            let alive = copyDeviceIsAlive(deviceID)
            if alive.status != noErr {
                return SpikeAliveResult(
                    ready: false,
                    cancelled: false,
                    elapsedMilliseconds: elapsedMilliseconds(from: started, to: clock.now),
                    detail: "DeviceIsAlive read failed \(describe(alive.status))"
                )
            }
            lastValue = String(alive.value)
            if alive.value == 1 {
                let elapsed = elapsedMilliseconds(from: started, to: clock.now)
                return SpikeAliveResult(ready: true, cancelled: false, elapsedMilliseconds: elapsed, detail: "alive after \(elapsed) ms, value \(alive.value)")
            }
            if clock.now >= deadline {
                let elapsed = elapsedMilliseconds(from: started, to: clock.now)
                return SpikeAliveResult(ready: false, cancelled: false, elapsedMilliseconds: elapsed, detail: "not alive after \(elapsed) ms, last value \(lastValue)")
            }
            try? await Task.sleep(for: alivePollInterval)
        }
    }
}

private func elapsedMilliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
    let milliseconds = (end - start) / Duration.milliseconds(1)
    return Int(milliseconds.rounded())
}

nonisolated private func auduneSpikeIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    _ = inDevice
    _ = inNow
    _ = inInputTime
    _ = outOutputData
    _ = inOutputTime
    guard let inClientData else { return noErr }
    let meter = Unmanaged<SpikeLevelMeter>.fromOpaque(inClientData).takeUnretainedValue()
    meter.consume(inInputData)
    return noErr
}

nonisolated private func copyDefaultOutputDevice() -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
}

nonisolated private func copyDeviceUID(_ deviceID: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let storage = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UnsafeRawPointer?>.stride, alignment: MemoryLayout<UnsafeRawPointer?>.alignment)
    defer { storage.deallocate() }
    storage.storeBytes(of: nil as UnsafeRawPointer?, as: UnsafeRawPointer?.self)
    var size = UInt32(MemoryLayout<UnsafeRawPointer?>.stride)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage)
    guard status == noErr, let opaque = storage.load(as: UnsafeRawPointer?.self) else { return nil }
    return Unmanaged<CFString>.fromOpaque(opaque).takeRetainedValue() as String
}

nonisolated private struct AliveRead: Sendable {
    var status: OSStatus
    var value: UInt32
}

nonisolated private func copyDeviceIsAlive(_ deviceID: AudioObjectID) -> AliveRead {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var alive: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive)
    return AliveRead(status: status, value: alive)
}

nonisolated private func copyInputStreamFormat(_ deviceID: AudioObjectID) -> AudioStreamBasicDescription? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamFormat,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format)
    guard status == noErr else { return nil }
    return format
}

nonisolated private func copyTapIDs() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTapList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let objectID = AudioObjectID(kAudioObjectSystemObject)
    let sizeStatus = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
    guard sizeStatus == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    guard count > 0 else { return [] }
    var identifiers = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &identifiers)
    guard status == noErr else { return [] }
    return identifiers
}

private func formatDescription(_ format: SpikeStreamFormat) -> String {
    let layout = format.isNonInterleaved ? "non-interleaved" : "interleaved"
    return "\(format.formatIDText) flags=0x\(String(format.formatFlags, radix: 16)) \(format.channelsPerFrame) ch \(format.bitsPerChannel)-bit \(layout) \(format.sampleRate) Hz bytesPerFrame=\(format.bytesPerFrame) float32=\(format.isFloat32)"
}

private func describe(_ status: OSStatus) -> String {
    if status == noErr { return "noErr (0)" }
    let value = UInt32(bitPattern: status)
    let bytes = [
        UInt8(truncatingIfNeeded: value >> 24),
        UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value)
    ]
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }), let text = String(bytes: bytes, encoding: .ascii) {
        return "'\(text)' (\(status))"
    }
    return "\(status)"
}
