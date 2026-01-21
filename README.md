# sre-dictmaths: NSDictionary Pointer Leak PoC

Proof-of-concept demonstrating ASLR slide extraction through `NSDictionary` serialization on macOS, based on the vulnerability disclosed by Google Project Zero (September 2025).

## Overview

This PoC demonstrates how pointer-based hashing in `NSDictionary` can leak memory addresses through serialization order. By constructing dictionaries with carefully chosen `NSNumber` keys and observing where `NSNull` appears in serialized output, the Chinese Remainder Theorem can reconstruct the complete 64-bit address of the `NSNull` singleton.

## Vulnerability Details

- **Disclosed**: September 26, 2025 by Jann Horn (Project Zero)
- **Patched**: March 31, 2025 (Apple Security Updates)
- **Affected Systems**: macOS and iOS (unpatched versions)
- **Attack Vector**: Deterministic serialization of pointer-keyed data structures

## Build Requirements

- macOS 10.13 or later
- Xcode Command Line Tools
- clang compiler with Objective-C support

### Installing Xcode Command Line Tools

```bash
xcode-select --install
```

## Building

```bash
make
```

This produces a universal binary (`leak-slide`) compatible with both Apple Silicon (arm64) and Intel (x86_64) Macs.

### Build Options

- `make` - Build the binary
- `make run` - Build and run the PoC
- `make clean` - Remove build artifacts
- `make check` - Verify build environment
- `make help` - Show help message

## Running

```bash
./leak-slide
```

The program runs in two phases:

### Phase 0: Diagnostics

Tests the system's hash behavior to determine if mitigations are present:

1. **NSNull Hash Stability** - Checks if hash equals pointer address
2. **Hash Determinism** - Verifies hash consistency across calls
3. **Serialization Order** - Tests if dictionary ordering is deterministic
4. **NSNumber Hash Behavior** - Validates expected hash function
5. **Bucket Prediction** - Tests if bucket placement is predictable

### Phase 1: Address Extraction

Attempts to extract the `NSNull` address using the Chinese Remainder Theorem:

1. Constructs dictionaries with even/odd bucket patterns for 9 prime table sizes
2. Serializes each dictionary and observes `NSNull` position
3. Calculates `NSNull_hash % prime` for each prime
4. Applies CRT to reconstruct the full 64-bit address
5. Compares leaked address with actual address

## Expected Output

### On Unpatched Systems

```
========================================
Hash Behavior Diagnostics
========================================

[Diagnostic] NSNull singleton address: 0x1eb91ab60
[Diagnostic] NSNull hash value:         0x1eb91ab60
[Diagnostic] Hash == Address:           YES (vulnerable)

...

========================================
Assessment: System appears VULNERABLE
Proceeding with full attack...
========================================

[+] Applying Chinese Remainder Theorem
    Leaked address: 0x1eb91ab60
    Actual address: 0x1eb91ab60
    Result: MATCH ✓
```

### On Patched Systems

```
========================================
Hash Behavior Diagnostics
========================================

[Diagnostic] NSNull singleton address: 0x1eb91ab60
[Diagnostic] NSNull hash value:         0x7f3a9b2c1d8e
[Diagnostic] Hash == Address:           NO (possibly patched)

========================================
Assessment: Mitigation detected
Attack unlikely to succeed, but attempting anyway for research...
========================================
```

## Code Structure

```
src/
  leak-slide.m        - Main program with Phase 0 and Phase 1
  diagnostics.h/m     - Hash behavior diagnostic tests
  hash-utils.h/m      - Hash function and modular arithmetic utilities
  dict-builder.h/m    - Dictionary construction with bucket patterns
  crt-solver.h/m      - Chinese Remainder Theorem implementation

Makefile              - Build system for macOS
README.md             - This file
agents.md             - Detailed technical design document
reference.md          - Original Project Zero disclosure
```

## Technical Details

### Hash Function

The PoC replicates CoreFoundation's `_CFHashInt` function used for `NSNumber`:

```c
hash = value * 0x9e3779b9
```

### Dictionary Bucket Calculation

```c
bucket_index = (hash_code % table_size)
```

Table sizes are always prime: 23, 41, 71, 127, 191, 251, 383, 631, 1087

### Chinese Remainder Theorem

Given remainders for 9 primes, the product `23×41×71×...×1087` exceeds 2^64, making the solution unique and recovering the full address.

## Limitations

- Self-contained PoC (leaks addresses within its own process)
- Requires serialization/deserialization capability
- No actual exploitation (demonstrates leak only)
- May not work on patched systems (as intended)

## Research Purpose

This PoC is for security research and educational purposes:

- Understanding pointer-based hashing vulnerabilities
- Analyzing Apple's mitigation strategies
- Demonstrating practical application of Chinese Remainder Theorem
- Testing patch effectiveness across macOS versions

## References

- [Project Zero Blog Post](https://projectzero.google/2025/09/pointer-leaks-through-pointer-keyed.html)
- [Apple Security Updates - March 31, 2025](https://support.apple.com/en-us/100100)
- [The Cyber Express Coverage](https://thecyberexpress.com/project-zero-exposes-aslr-bypass/)

## License

Research code provided as-is for educational purposes.
