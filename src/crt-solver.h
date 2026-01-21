#ifndef CRT_SOLVER_H
#define CRT_SOLVER_H

#include <stdint.h>
#include <stdbool.h>

// Chinese Remainder Theorem solver
// Given remainders and moduli, compute the unique solution modulo their product
// Returns true on success, false on error
bool chinese_remainder_theorem(const uint64_t *remainders, const uint64_t *moduli,
                                size_t count, uint64_t *result);

// Helper: multiply two uint64_t with overflow detection
bool mul_u64_checked(uint64_t a, uint64_t b, uint64_t *result);

// Helper: modular multiplication (a * b) % m avoiding overflow
uint64_t mod_mul(uint64_t a, uint64_t b, uint64_t m);

#endif // CRT_SOLVER_H
