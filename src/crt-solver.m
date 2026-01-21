#import "crt-solver.h"
#import "hash-utils.h"
#include <stdio.h>
#include <stdlib.h>

bool mul_u64_checked(uint64_t a, uint64_t b, uint64_t *result) {
    if (a == 0 || b == 0) {
        *result = 0;
        return true;
    }

    if (a > UINT64_MAX / b) {
        return false; // Overflow would occur
    }

    *result = a * b;
    return true;
}

uint64_t mod_mul(uint64_t a, uint64_t b, uint64_t m) {
    // Compute (a * b) % m avoiding overflow using the identity:
    // (a * b) % m = ((a % m) * (b % m)) % m
    // For large values, use __uint128_t if available

#ifdef __SIZEOF_INT128__
    __uint128_t result = ((__uint128_t)a * (__uint128_t)b) % m;
    return (uint64_t)result;
#else
    // Fallback for systems without 128-bit integers
    // Use repeated addition: a * b = a + a + ... (b times)
    uint64_t result = 0;
    a %= m;

    while (b > 0) {
        if (b & 1) {
            result = (result + a) % m;
        }
        a = (a * 2) % m;
        b >>= 1;
    }

    return result;
#endif
}

bool chinese_remainder_theorem(const uint64_t *remainders, const uint64_t *moduli,
                                size_t count, uint64_t *result) {
    if (count == 0) {
        return false;
    }

    // Start with first congruence
    uint64_t x = remainders[0];
    uint64_t M = moduli[0];

    // Iteratively combine congruences
    for (size_t i = 1; i < count; i++) {
        uint64_t r = remainders[i];
        uint64_t m = moduli[i];

        // We have: x ≡ r₁ (mod M) and need to satisfy x ≡ r₂ (mod m)
        // Find solution: x = x₁ + k*M where (x₁ + k*M) ≡ r₂ (mod m)
        // This gives: k*M ≡ (r₂ - x₁) (mod m)
        // So: k ≡ (r₂ - x₁) * M⁻¹ (mod m)

        int64_t diff = (int64_t)r - (int64_t)(x % m);
        if (diff < 0) {
            diff += m;
        }

        uint64_t M_inv;
        if (!mod_inverse(M % m, m, &M_inv)) {
            fprintf(stderr, "Error: moduli are not coprime\n");
            return false;
        }

        uint64_t k = mod_mul((uint64_t)diff, M_inv, m);

        // Update x = x + k * M
        // Since we're working with 64-bit addresses, use 128-bit arithmetic
#ifdef __SIZEOF_INT128__
        __uint128_t new_x = (__uint128_t)x + (__uint128_t)k * (__uint128_t)M;
        __uint128_t new_M = (__uint128_t)M * (__uint128_t)m;

        x = (uint64_t)(new_x % new_M);
        M = (uint64_t)new_M;
#else
        // For systems without 128-bit support, compute carefully
        uint64_t k_times_M = mod_mul(k, M, UINT64_MAX);
        x = (x + k_times_M);

        uint64_t new_M;
        if (!mul_u64_checked(M, m, &new_M)) {
            // Product exceeds 64 bits, which is actually what we want
            // The final result should be < 2^64, so just keep the lower bits
            M = M * m; // Let it wrap
        } else {
            M = new_M;
        }
#endif
    }

    *result = x;
    return true;
}
