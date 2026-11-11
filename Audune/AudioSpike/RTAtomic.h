#pragma once

#include <stdint.h>

enum {
    RTAtomicOrderRelaxed = 0,
    RTAtomicOrderAcquire = 2,
    RTAtomicOrderRelease = 3
};

uint64_t RTAtomicU64Load(uint64_t *storage, int order);
void RTAtomicU64Store(uint64_t *storage, uint64_t value, int order);
uint64_t RTAtomicU64FetchAdd(uint64_t *storage, uint64_t delta, int order);

uint32_t RTAtomicU32Load(uint32_t *storage, int order);
void RTAtomicU32Store(uint32_t *storage, uint32_t value, int order);

uint8_t RTAtomicU8Load(uint8_t *storage, int order);
void RTAtomicU8Store(uint8_t *storage, uint8_t value, int order);
