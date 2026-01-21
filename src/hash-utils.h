#ifndef HASH_UTILS_H
#define HASH_UTILS_H

#include <stdint.h>
#include <stdbool.h>

// Golden ratio constant used in _CFHashInt
#define CF_HASH_MULTIPLIER 0x9e3779b9ULL

// Prime numbers used for dictionary table sizes
static const uint64_t TABLE_PRIMES[] = {23, 41, 71, 127, 191, 251, 383, 631, 1087};
#define NUM_PRIMES (sizeof(TABLE_PRIMES) / sizeof(TABLE_PRIMES[0]))

// Compute hash for NSNumber value (mimics _CFHashInt)
uint64_t cf_hash_int(uint64_t value);

// Compute modular multiplicative inverse using extended Euclidean algorithm
bool mod_inverse(uint64_t a, uint64_t m, uint64_t *result);

// Find NSNumber value that will hash to target bucket for given table size
bool find_key_for_bucket(uint64_t target_bucket, uint64_t table_size, uint64_t *result);

// Extended Euclidean algorithm
int64_t extended_gcd(int64_t a, int64_t b, int64_t *x, int64_t *y);

#endif // HASH_UTILS_H
