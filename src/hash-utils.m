#import "hash-utils.h"
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t g_hash_multiplier = DEFAULT_HASH_MULTIPLIER;
static bool g_hash_linear = true;

uint64_t get_hash_multiplier(void) {
    return g_hash_multiplier;
}

bool hash_model_is_linear(void) {
    return g_hash_linear;
}

bool calibrate_nsnumber_hash_multiplier(uint64_t *detected, size_t samples) {
    if (samples == 0) {
        samples = 8;
    }

    uint64_t candidate = (uint64_t)[@1 hash];
    bool linear = true;

    for (size_t i = 0; i < samples; i++) {
        NSNumber *num = @(i);
        uint64_t hash = (uint64_t)[num hash];
        uint64_t expected = (uint64_t)i * candidate;
        if (hash != expected) {
            linear = false;
            break;
        }
    }

    if (linear) {
        g_hash_multiplier = candidate;
    } else {
        g_hash_multiplier = DEFAULT_HASH_MULTIPLIER;
    }

    g_hash_linear = linear;
    if (detected) {
        *detected = g_hash_multiplier;
    }

    return linear;
}

uint64_t cf_hash_int(uint64_t value) {
    return value * g_hash_multiplier;
}

int64_t extended_gcd(int64_t a, int64_t b, int64_t *x, int64_t *y) {
    if (b == 0) {
        *x = 1;
        *y = 0;
        return a;
    }

    int64_t x1, y1;
    int64_t gcd = extended_gcd(b, a % b, &x1, &y1);

    *x = y1;
    *y = x1 - (a / b) * y1;

    return gcd;
}

bool mod_inverse(uint64_t a, uint64_t m, uint64_t *result) {
    int64_t x, y;
    int64_t gcd = extended_gcd((int64_t)a, (int64_t)m, &x, &y);

    if (gcd != 1) {
        return false; // Modular inverse doesn't exist
    }

    // Ensure result is positive
    *result = (uint64_t)((x % (int64_t)m + (int64_t)m) % (int64_t)m);
    return true;
}

bool find_key_for_bucket(uint64_t target_bucket, uint64_t table_size, uint64_t *result) {
    if (!hash_model_is_linear()) {
        uint64_t limit = table_size * 128;
        for (uint64_t candidate = 0; candidate < limit; candidate++) {
            NSNumber *num = @(candidate);
            uint64_t hash = (uint64_t)[num hash];
            if ((hash % table_size) == target_bucket) {
                *result = candidate;
                return true;
            }
        }
        return false;
    }

    // We need to solve: (value * multiplier) % table_size = target_bucket
    // This means: value = target_bucket * inverse(multiplier, table_size) % table_size
    uint64_t multiplier = get_hash_multiplier();
    uint64_t inv;
    if (!mod_inverse(multiplier, table_size, &inv)) {
        return false;
    }

    *result = (target_bucket * inv) % table_size;

    // Verify the result
    uint64_t computed_bucket = (cf_hash_int(*result) % table_size);
    if (computed_bucket != target_bucket) {
        fprintf(stderr, "Warning: bucket mismatch for target=%llu, table_size=%llu: got %llu\n",
                target_bucket, table_size, computed_bucket);
        return false;
    }

    return true;
}
