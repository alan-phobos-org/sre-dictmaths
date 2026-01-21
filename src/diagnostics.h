#ifndef DIAGNOSTICS_H
#define DIAGNOSTICS_H

#import <Foundation/Foundation.h>
#include <stdbool.h>

// Phase 0: Run diagnostic tests to characterize hash behavior
// Returns true if system appears vulnerable, false if patched
bool run_diagnostics(void);

// Individual diagnostic tests
void test_nsnull_hash_stability(void);
void test_hash_determinism(void);
void test_serialization_order(void);
void test_nsnumber_hash_behavior(void);
void test_bucket_prediction(void);

#endif // DIAGNOSTICS_H
