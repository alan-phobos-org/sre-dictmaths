#import "hash-utils.h"
#include <stdio.h>
#include <stdlib.h>

uint64_t cf_hash_int(uint64_t value) {
    return value * CF_HASH_MULTIPLIER;
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
    // We need to solve: (value * 0x9e3779b9) % table_size = target_bucket
    // This means: value = target_bucket * inverse(0x9e3779b9, table_size) % table_size

    uint64_t inv;
    if (!mod_inverse(CF_HASH_MULTIPLIER, table_size, &inv)) {
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
