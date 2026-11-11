import Foundation

/// Lock-free integer atomics for the realtime audio path on macOS 14.2+.
/// Wraps C11 `_Atomic` so we do not depend on `Synchronization.Atomic` (macOS 15+).
nonisolated enum RTAtomicOrdering {
    case relaxed
    case acquiring
    case releasing

    var rawValue: Int32 {
        switch self {
        case .relaxed: return Int32(RTAtomicOrderRelaxed)
        case .acquiring: return Int32(RTAtomicOrderAcquire)
        case .releasing: return Int32(RTAtomicOrderRelease)
        }
    }
}

nonisolated final class RTAtomicUInt64: @unchecked Sendable {
    private var storage: UInt64

    init(_ value: UInt64 = 0) {
        storage = value
    }

    func load(ordering: RTAtomicOrdering) -> UInt64 {
        RTAtomicU64Load(&storage, ordering.rawValue)
    }

    func store(_ value: UInt64, ordering: RTAtomicOrdering) {
        RTAtomicU64Store(&storage, value, ordering.rawValue)
    }

    func wrappingAdd(_ delta: UInt64, ordering: RTAtomicOrdering) {
        _ = RTAtomicU64FetchAdd(&storage, delta, ordering.rawValue)
    }
}

nonisolated final class RTAtomicUInt32: @unchecked Sendable {
    private var storage: UInt32

    init(_ value: UInt32 = 0) {
        storage = value
    }

    func load(ordering: RTAtomicOrdering) -> UInt32 {
        RTAtomicU32Load(&storage, ordering.rawValue)
    }

    func store(_ value: UInt32, ordering: RTAtomicOrdering) {
        RTAtomicU32Store(&storage, value, ordering.rawValue)
    }
}

nonisolated final class RTAtomicUInt8: @unchecked Sendable {
    private var storage: UInt8

    init(_ value: UInt8 = 0) {
        storage = value
    }

    func load(ordering: RTAtomicOrdering) -> UInt8 {
        RTAtomicU8Load(&storage, ordering.rawValue)
    }

    func store(_ value: UInt8, ordering: RTAtomicOrdering) {
        RTAtomicU8Store(&storage, value, ordering.rawValue)
    }
}
