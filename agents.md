# Investigation Plan: Pointer Leaks Through Pointer-Keyed Dictionaries

## Overview

This document outlines our approach to validate Apple's patch for CVE-2025-XXXXX (Pointer leaks through pointer-keyed data structures). We will build proof-of-concept binaries for both macOS and iOS to demonstrate that the vulnerability has been properly mitigated.

## Background

The vulnerability, disclosed by Jann Horn of Project Zero on September 26, 2025, allows remote extraction of pointer values without memory safety violations or timing attacks. The attack exploits pointer-based hashing in `NSDictionary` combined with `NSKeyedArchiver` serialization to leak the address of the `NSNull` singleton using the Chinese Remainder Theorem.

Apple patched this vulnerability in their March 31, 2025 security releases.

## Investigation Goals

1. Build a macOS proof-of-concept to verify the patch is effective
2. Build an iOS proof-of-concept to verify the patch extends to iOS devices
3. Document the differences in behavior pre/post-patch

## Phase 1: macOS PoC Binary

### Objectives

- Implement the three-stage attack described in the Project Zero research
- Verify that on patched macOS systems, the attack fails or returns incorrect addresses
- Document the specific behavior changes introduced by the patch

### Components to Build

#### 1.1 Input Generator (`attacker-input-generator.c`)

Creates serialized plist data containing:
- Multiple `NSDictionary` instances with calculated `NSNumber` keys
- Two dictionaries per prime (23, 41, 71, 127, 191, 251, 383, 631, 1087)
- Even-index and odd-index patterns to leak bucket positions
- An `NSNull` singleton reference

**Key implementation details:**
- Generate keys whose hashes modulo table_size create specific patterns
- Use `_CFHashInt` logic: `hash = value * 0x9e3779b9`
- Create both even and odd bucket occupation patterns

#### 1.2 Victim Program (`round-trip-victim.m`)

Objective-C program that:
- Accepts input plist file
- Deserializes using `NSKeyedUnarchiver.unarchivedObjectOfClasses`
- Whitelists: `NSDictionary`, `NSNumber`, `NSArray`, `NSString`, `NSNull`
- Re-serializes using `NSKeyedArchiver.archivedDataWithRootObject`
- Outputs the modified plist

#### 1.3 Pointer Extractor (`extract-pointer.c`)

Analyzes the re-serialized plist:
- Determines `NSNull` position in each dictionary
- Calculates `hash_code % prime` for each table size
- Applies Chinese Remainder Theorem to reconstruct full address
- Compares extracted address against expected `NSNull` singleton location

### Testing Methodology

1. Compile all components on latest macOS
2. Run the three-stage attack
3. Compare extracted address against actual `NSNull` address in memory
4. Document whether:
   - Address extraction fails completely
   - Extracted address is incorrect (hashing changed)
   - Additional randomization was introduced
   - Dictionary serialization order changed

### Success Criteria

- On patched systems, the attack should fail to extract the correct `NSNull` address
- We should identify the specific mitigation technique used (e.g., keyed hash function, randomized serialization order)

## Phase 2: iOS PoC Binary

### Objectives

- Port the macOS PoC to iOS
- Run on jailbroken iPhone to bypass code signing restrictions
- Verify patch effectiveness on iOS

### Prerequisites

- Jailbroken iPhone running iOS 18.3 or later (March 31, 2025 patch included)
- SSH access to device
- Ability to compile and sign binaries for iOS

### Components to Port

Same three-stage implementation as macOS:
- `attacker-input-generator` (compile for arm64)
- `round-trip-victim` (Objective-C, iOS SDK)
- `extract-pointer` (compile for arm64)

### iOS-Specific Considerations

#### 2.1 Build Configuration

- Use iOS SDK instead of macOS SDK
- Target arm64 architecture
- Sign with development certificate or fakesign on jailbroken device
- Bundle as standalone binaries or simple app bundle

#### 2.2 Deployment

- Transfer binaries via SSH/scp
- Execute from command line (via SSH) or mobile terminal
- May need to adjust file paths for iOS filesystem structure

#### 2.3 Testing Approach

1. Generate attack input on development machine or device
2. Run victim program on iOS device
3. Extract pointer and compare results
4. Document any iOS-specific behavioral differences

### iOS vs macOS Comparison

Document differences:
- Address space layout differences
- Shared cache location variations
- Any iOS-specific mitigations
- Performance characteristics

### Success Criteria

- Confirm the patch is present and effective on iOS
- Identify any platform-specific mitigation differences
- Document shared cache behavior on iOS

## Phase 3: Documentation and Analysis

### Deliverables

1. **Technical Report**
   - Detailed findings for both platforms
   - Specific mitigation techniques identified
   - Behavioral differences pre/post-patch

2. **Source Code**
   - All PoC components with clear documentation
   - Build instructions for both platforms
   - Sample inputs and expected outputs

3. **Comparison Matrix**
   - macOS vs iOS behavior
   - Patched vs unpatched systems (if historical data available)
   - Performance impact of mitigations

## Risk Considerations

### Ethical Constraints

- Only test on controlled, authorized devices
- Do not weaponize or distribute attack tools publicly
- Coordinate with responsible disclosure timelines

### Technical Risks

- Jailbreak may interfere with testing
- iOS sandbox restrictions may limit execution
- Differences in Apple Silicon vs Intel may affect results

## Timeline

1. **Week 1-2:** macOS PoC implementation and testing
2. **Week 3:** iOS porting and jailbreak environment setup
3. **Week 4:** iOS testing and cross-platform analysis
4. **Week 5:** Documentation and final report

## References

- Project Zero Blog: https://projectzero.google/2025/09/pointer-leaks-through-pointer-keyed.html
- Apple Security Updates: March 31, 2025
- reference.md in this repository
