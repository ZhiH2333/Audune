#include "RTAtomic.h"

#include <stdatomic.h>

static memory_order RTAtomicMapOrder(int order) {
    switch (order) {
    case RTAtomicOrderAcquire:
        return memory_order_acquire;
    case RTAtomicOrderRelease:
        return memory_order_release;
    case RTAtomicOrderRelaxed:
    default:
        return memory_order_relaxed;
    }
}

uint64_t RTAtomicU64Load(uint64_t *storage, int order) {
    return atomic_load_explicit((_Atomic(uint64_t) *)storage, RTAtomicMapOrder(order));
}

void RTAtomicU64Store(uint64_t *storage, uint64_t value, int order) {
    atomic_store_explicit((_Atomic(uint64_t) *)storage, value, RTAtomicMapOrder(order));
}

uint64_t RTAtomicU64FetchAdd(uint64_t *storage, uint64_t delta, int order) {
    return atomic_fetch_add_explicit((_Atomic(uint64_t) *)storage, delta, RTAtomicMapOrder(order));
}

uint32_t RTAtomicU32Load(uint32_t *storage, int order) {
    return atomic_load_explicit((_Atomic(uint32_t) *)storage, RTAtomicMapOrder(order));
}

void RTAtomicU32Store(uint32_t *storage, uint32_t value, int order) {
    atomic_store_explicit((_Atomic(uint32_t) *)storage, value, RTAtomicMapOrder(order));
}

uint8_t RTAtomicU8Load(uint8_t *storage, int order) {
    return atomic_load_explicit((_Atomic(uint8_t) *)storage, RTAtomicMapOrder(order));
}

void RTAtomicU8Store(uint8_t *storage, uint8_t value, int order) {
    atomic_store_explicit((_Atomic(uint8_t) *)storage, value, RTAtomicMapOrder(order));
}
