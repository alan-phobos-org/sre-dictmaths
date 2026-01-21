# Investigation Plan: Pointer Leaks Through Pointer-Keyed Dictionaries

## Overview

This document outlines a focused approach to understanding the core mechanics of the pointer leak vulnerability disclosed by Project Zero. Rather than simulating a full attack scenario, we'll build a self-contained proof-of-concept that demonstrates ASLR slide extraction from within a single process.

## Background

The vulnerability exploits pointer-based hashing in `NSDictionary` to leak memory addresses. By crafting dictionaries with specific key patterns and observing serialization order, the `NSNull` singleton address can be extracted using the Chinese Remainder Theorem.

Apple patched this in their March 31, 2025 security releases.

## Design Philosophy

**Keep it simple.** Focus on the mathematical and implementation fundamentals:
- Hash function behavior (`_CFHashInt`)
- Dictionary bucket allocation and collision resolution
- Key construction to control bucket occupancy
- Chinese Remainder Theorem application

**No victim needed.** The PoC operates entirely within its own process space, making it easier to understand, debug, and verify patch effectiveness.

## Core PoC: Self-Contained ASLR Slide Leak

### Single Binary Design

Build one Objective-C program (`leak-slide.m`) that:
1. Constructs `NSDictionary` instances with calculated `NSNumber` keys
2. Serializes the dictionaries containing `NSNull` singleton
3. Observes `NSNull` position in serialized output
4. Applies Chinese Remainder Theorem to extract the address
5. Compares extracted address against actual `NSNull` location
6. Calculates and displays the ASLR slide

### Key Components

#### Hash Function Understanding

The `_CFHashInt` function for `NSNumber`:
```c
hash = value * 0x9e3779b9
```

Given a target hash and table size (prime number), we can calculate which `NSNumber` values will occupy specific buckets:
```c
bucket_index = (value * 0x9e3779b9) % table_size
```

#### Dictionary Construction Strategy

For each prime table size (23, 41, 71, 127, 191, 251, 383, 631, 1087):

1. Create two dictionaries:
   - **Even pattern**: Keys hash to even bucket indices (0, 2, 4, ...)
   - **Odd pattern**: Keys hash to odd bucket indices (1, 3, 5, ...)

2. Insert `NSNull` as a key in both dictionaries

3. Serialize each dictionary using `NSKeyedArchiver`

4. Parse serialized output to find `NSNull` position relative to `NSNumber` keys

5. From the position, deduce `NSNull_hash % table_size`

#### Chinese Remainder Theorem Application

With remainders for 9 different primes, we have:
```
NSNull_address ≡ r₁ (mod 23)
NSNull_address ≡ r₂ (mod 41)
...
NSNull_address ≡ r₉ (mod 1087)
```

The product `23 × 41 × 71 × 127 × 191 × 251 × 383 × 631 × 1087` exceeds 2^64, so the CRT solution is unique and gives us the full 64-bit address.

### Implementation Focus Areas

#### 1. Key Generator

Function to compute `NSNumber` values that hash to desired buckets:
```objective-c
NSArray* keysForBuckets(NSArray *targetBuckets, NSUInteger tableSize)
```

Must solve: `(value * 0x9e3779b9) % tableSize = targetBucket`

This requires computing the modular multiplicative inverse of `0x9e3779b9` modulo each prime.

#### 2. Dictionary Builder

Create dictionaries with precise bucket occupation patterns:
```objective-c
NSDictionary* buildDictWithPattern(PatternType pattern, NSUInteger tableSize)
```

Patterns:
- `EVEN`: Occupy indices 0, 2, 4, ... leaving 1, 3, 5, ... empty
- `ODD`: Occupy indices 1, 3, 5, ... leaving 0, 2, 4, ... empty

#### 3. Serialization Observer

Serialize dictionary and extract key ordering:
```objective-c
NSArray* extractKeyOrder(NSDictionary *dict)
```

Parse the `NSKeyedArchiver` output to determine which position `NSNull` occupies.

#### 4. CRT Solver

Given remainders and moduli, compute the unique solution:
```objective-c
uint64_t chineseRemainderTheorem(NSArray *remainders, NSArray *moduli)
```

Implement extended Euclidean algorithm for modular inverse computation.

#### 5. Slide Calculator

Compare leaked address to known shared cache location:
```objective-c
void calculateSlide(uint64_t leakedAddress)
```

The slide is the difference between actual and expected base addresses.

## Testing Approach

### Success Criteria

On **unpatched** systems:
- Extract exact `NSNull` singleton address
- Calculate correct ASLR slide
- Verify against `dladdr()` or similar

On **patched** systems:
- Extraction fails or returns incorrect address
- Document specific mitigation (keyed hash, randomized serialization, etc.)

### Validation Steps

1. Run PoC and capture leaked address
2. Use debugger to confirm actual `NSNull` address: `p (void*)[NSNull null]`
3. Compare values
4. Calculate slide and verify against system info

### Debug Output

The PoC should print:
```
[+] Testing with table size 23 (even pattern)
    NSNull position: 3
    NSNull mod 23 = 14

[+] Testing with table size 23 (odd pattern)
    NSNull position: 7
    NSNull mod 23 = 14 (confirmed)

[...repeat for all primes...]

[+] Applying Chinese Remainder Theorem
    Leaked address: 0x1eb91ab60
    Actual address: 0x1eb91ab60 [MATCH]
    ASLR slide: 0x1eb900000
```

## Platform Coverage

### macOS

Primary development target. Test on:
- Latest macOS (patched)
- Older macOS versions (if available for comparison)
- Both Apple Silicon and Intel

### iOS

Port the same single-binary approach:
- Compile for arm64
- Run on jailbroken device or simulator
- Observe any iOS-specific differences in behavior

## Code Structure

```
src/
  leak-slide.m          # Main PoC implementation
  hash-utils.h/m        # Hash function and modular arithmetic
  dict-builder.h/m      # Dictionary construction logic
  crt-solver.h/m        # Chinese Remainder Theorem implementation

tests/
  test-hash-function.m  # Verify _CFHashInt replication
  test-modular-inverse.m # Verify inverse computation
  test-crt.m            # Verify CRT solver with known values

Makefile                # Build for macOS and iOS
README.md               # Build and run instructions
```

## Key Insights to Document

1. **Hash function accuracy**: How closely does our `_CFHashInt` replica match actual behavior?
2. **Bucket collision resolution**: Does linear probing work exactly as expected?
3. **Serialization determinism**: Is key ordering in `NSKeyedArchiver` output stable?
4. **CRT precision**: Does the mathematical reconstruction produce exact addresses?
5. **Patch mechanism**: How did Apple mitigate this? Keyed hashing? Randomization?

## References

- Project Zero Blog: https://projectzero.google/2025/09/pointer-leaks-through-pointer-keyed.html
- Apple Security Updates: March 31, 2025
- reference.md in this repository
