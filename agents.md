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
1. **Runs diagnostic tests** to characterize hash behavior
2. Constructs `NSDictionary` instances with calculated `NSNumber` keys
3. Serializes the dictionaries containing `NSNull` singleton
4. Observes `NSNull` position in serialized output
5. Applies Chinese Remainder Theorem to extract the address
6. Compares extracted address against actual `NSNull` location
7. Calculates and displays the ASLR slide

### Phase 0: Hash Behavior Diagnostics

Before attempting the full attack, run diagnostic tests to understand the current hash implementation and identify which mitigation (if any) Apple deployed.

#### Test 1: NSNull Hash Stability

```objective-c
void testNSNullHashStability() {
    NSNull *null1 = [NSNull null];
    NSNull *null2 = [NSNull null];

    uintptr_t addr = (uintptr_t)null1;
    NSUInteger hash = [null1 hash];

    printf("[Diagnostic] NSNull singleton address: 0x%lx\n", addr);
    printf("[Diagnostic] NSNull hash value:         0x%lx\n", hash);
    printf("[Diagnostic] Hash == Address:           %s\n",
           (hash == addr) ? "YES (vulnerable)" : "NO (possibly patched)");
    printf("[Diagnostic] Singleton identity:        %s\n",
           (null1 == null2) ? "YES" : "NO");
}
```

**What this reveals:**
- If `hash == address`: Pointer-based hashing is still used (unpatched or insufficient mitigation)
- If `hash != address`: Apple changed the hash function (keyed hash or object ID approach)

#### Test 2: Hash Determinism Across Runs

```objective-c
void testHashDeterminism() {
    NSNull *null = [NSNull null];
    NSUInteger hash1 = [null hash];

    // Force re-computation if possible
    sleep(1);
    NSUInteger hash2 = [null hash];

    printf("[Diagnostic] First hash:  0x%lx\n", hash1);
    printf("[Diagnostic] Second hash: 0x%lx\n", hash2);
    printf("[Diagnostic] Deterministic: %s\n",
           (hash1 == hash2) ? "YES" : "NO (randomized per-run)");
}
```

**What this reveals:**
- If hash changes between runs: Keyed hash with per-process or per-boot randomization
- If hash is stable: Either unpatched or deterministic object ID approach

#### Test 3: Dictionary Serialization Order

```objective-c
void testSerializationOrder() {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // Insert in controlled order
    dict[@1] = @"first";
    dict[@2] = @"second";
    dict[[NSNull null]] = @"null";
    dict[@3] = @"third";

    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dict
                                         requiringSecureCoding:NO
                                                         error:&error];

    NSDictionary *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class]
                                                               fromData:data
                                                                  error:&error];

    printf("[Diagnostic] Serialization test:\n");
    NSUInteger idx = 0;
    for (id key in decoded) {
        const char *keyType = [key isKindOfClass:[NSNull class]] ? "NSNull" : "NSNumber";
        printf("  Position %lu: %s\n", idx++, keyType);
    }
}
```

**What this reveals:**
- If order is deterministic: Serialization order is based on hash values (leak possible)
- If order is randomized: Apple added serialization randomization

#### Test 4: NSNumber Hash Behavior

```objective-c
void testNSNumberHashBehavior() {
    printf("[Diagnostic] NSNumber hash tests:\n");

    for (int i = 0; i < 10; i++) {
        NSNumber *num = @(i);
        NSUInteger hash = [num hash];
        uint64_t expected = (uint64_t)i * 0x9e3779b9;

        printf("  @%d: hash=0x%lx, expected=0x%llx, %s\n",
               i, hash, expected,
               (hash == expected) ? "MATCH" : "DIFFERENT");
    }
}
```

**What this reveals:**
- If hashes match `value * 0x9e3779b9`: NSNumber behavior unchanged
- If hashes differ: Apple also changed NSNumber hashing (unlikely but possible)

#### Test 5: Bucket Position Prediction

```objective-c
void testBucketPrediction() {
    // Create a small dictionary and verify we can predict positions
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    uint64_t prime = 23;
    // Calculate keys that should occupy even buckets
    for (uint64_t bucket = 0; bucket < prime; bucket += 2) {
        uint64_t key = findKeyForBucket(bucket, prime);
        dict[@(key)] = @(bucket);
    }

    dict[[NSNull null]] = @"marker";

    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dict
                                         requiringSecureCoding:NO
                                                         error:&error];

    NSDictionary *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class]
                                                               fromData:data
                                                                  error:&error];

    printf("[Diagnostic] Bucket prediction test (table size %llu):\n", prime);
    NSUInteger position = 0;
    for (id key in decoded) {
        if ([key isKindOfClass:[NSNull class]]) {
            printf("  NSNull found at position %lu\n", position);

            // Try to deduce hash mod 23
            // This should give us NSNull_hash % 23
            printf("  This suggests NSNull hash %% 23 is in range [...]\n");
            break;
        }
        position++;
    }
}
```

**What this reveals:**
- If NSNull position matches prediction: Attack vector still viable
- If position is unpredictable: Mitigation is effective

### Diagnostic Output Format

The PoC should start with:
```
========================================
Hash Behavior Diagnostics
========================================

[Diagnostic] NSNull singleton address: 0x1eb91ab60
[Diagnostic] NSNull hash value:         0x1eb91ab60
[Diagnostic] Hash == Address:           YES (vulnerable)
[Diagnostic] Singleton identity:        YES

[Diagnostic] First hash:  0x1eb91ab60
[Diagnostic] Second hash: 0x1eb91ab60
[Diagnostic] Deterministic: YES

[Diagnostic] Serialization test:
  Position 0: NSNumber
  Position 1: NSNull
  Position 2: NSNumber
  Position 3: NSNumber

[Diagnostic] NSNumber hash tests:
  @0: hash=0x0, expected=0x0, MATCH
  @1: hash=0x9e3779b9, expected=0x9e3779b9, MATCH
  ...

[Diagnostic] Bucket prediction test (table size 23):
  NSNull found at position 7
  This suggests NSNull hash % 23 is in range [...]

========================================
Assessment: System appears VULNERABLE
Proceeding with full attack...
========================================
```

Or on a patched system:
```
========================================
Hash Behavior Diagnostics
========================================

[Diagnostic] NSNull singleton address: 0x1eb91ab60
[Diagnostic] NSNull hash value:         0x7f3a9b2c1d8e
[Diagnostic] Hash == Address:           NO (possibly patched)
[Diagnostic] Hash appears randomized

========================================
Assessment: Mitigation detected
Attack unlikely to succeed, but attempting anyway for research...
========================================
```

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
  leak-slide.m          # Main PoC implementation with diagnostics
  diagnostics.h/m       # Phase 0 hash behavior tests
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

### Execution Flow

```
1. Run Phase 0 diagnostics
   ├─ Test NSNull hash stability
   ├─ Test hash determinism
   ├─ Test serialization order
   ├─ Test NSNumber hashing
   └─ Test bucket prediction

2. Analyze diagnostic results
   └─ Determine if system is vulnerable/patched

3. Proceed with full attack (if viable)
   ├─ Generate keys for each prime
   ├─ Build dictionaries with even/odd patterns
   ├─ Serialize and extract positions
   ├─ Apply Chinese Remainder Theorem
   └─ Compare leaked vs actual address

4. Report results
   ├─ Display ASLR slide (if successful)
   ├─ Document mitigation mechanism (if patched)
   └─ Write findings to stdout
```

## Key Insights to Document

1. **Hash function accuracy**: How closely does our `_CFHashInt` replica match actual behavior?
2. **Bucket collision resolution**: Does linear probing work exactly as expected?
3. **Serialization determinism**: Is key ordering in `NSKeyedArchiver` output stable?
4. **CRT precision**: Does the mathematical reconstruction produce exact addresses?
5. **Patch mechanism**: How did Apple mitigate this? Keyed hashing? Randomization?

## Prior Research and Public Disclosure

### Original Disclosure

Jann Horn of Google Project Zero published this vulnerability research on September 26, 2025. The technique was disclosed responsibly to Apple, and Apple addressed it in their March 31, 2025 security releases across macOS and iOS.

### Public Coverage

Multiple security outlets covered this disclosure:
- [The Cyber Express](https://thecyberexpress.com/project-zero-exposes-aslr-bypass/) - Project Zero Exposes ASLR Bypass in Apple Serialization Flaw
- [Cryptika](https://www.cryptika.com/google-project-zero-details-aslr-bypass-on-apple-devices-using-nsdictionary-serialization/) - ASLR Bypass on Apple Devices Using NSDictionary Serialization
- [Cybersecurity News](https://cybersecuritynews.com/aslr-bypass-on-apple-devices/) - Google Project Zero Details ASLR Bypass on Apple Devices
- [CertCube Blog](https://blog.certcube.com/apple-fixes-aslr-bypass-vulnerability-discovered-by-google-project-zero-researcher/) - Apple Fixes ASLR Bypass Vulnerability

### Known Technical Details

**Vulnerability Scope:**
- Affects both macOS and iOS
- No specific CVE was assigned (likely due to limited real-world attack surface)
- Jann Horn noted this was reported without filing in the Project Zero bugtracker due to lack of demonstrated real-world impact

**Attack Characteristics:**
- Requires ~50KB of crafted serialized data
- Uses NSDictionary with mixed NSNumber and NSNull keys
- Exploits deterministic serialization ordering in NSKeyedArchiver
- Leverages pointer-based hashing in CoreFoundation's CFHash function

**Apple's Mitigation Approach:**

From the Project Zero blog (Conclusion section), Jann Horn states:
> "The most robust mitigation against this is to avoid using object addresses as lookup keys, or alternatively hash them with a keyed hash function (which should reduce the potential address leak to a pointer equality oracle)."

Horn also notes the performance tradeoff:
> "using an ID stored inside an object instead of the object's address could add a memory load to the critical path of lookups."

It's unclear from public sources whether Apple implemented:
1. **Keyed hash function** - Adding secret randomization to hash computation
2. **Object ID instead of address** - Storing identifiers inside objects for hashing
3. **Serialization randomization** - Randomizing output order during serialization
4. **Alternative singleton handling** - Changing how NSNull singleton is hashed
5. **Combination approach** - Multiple mitigations layered together

### Gap in Public Knowledge

**Unknown specifics:**
- Exact implementation details of Apple's patch
- Whether mitigation is in CoreFoundation, Foundation, or both layers
- Performance impact of the mitigation
- Whether older iOS/macOS versions received backports

**Our PoC Goal:**
By building a focused proof-of-concept that tests the core mechanics, we can:
1. Verify patch effectiveness on current systems
2. Identify which mitigation strategy Apple employed
3. Document behavioral changes in hash computation or serialization
4. Test cross-platform consistency (macOS vs iOS)

## References

- Project Zero Blog: https://projectzero.google/2025/09/pointer-leaks-through-pointer-keyed.html
- [Apple Security Updates](https://support.apple.com/en-us/100100) - March 31, 2025
- [CFHash Documentation](https://developer.apple.com/documentation/corefoundation/cfhash(_:)) - Apple Developer
- reference.md in this repository
