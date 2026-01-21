# Pointer leaks through pointer-keyed data structures

**Date:** September 26, 2025
**Author:** Jann Horn
**Source:** Project Zero

---

## Introduction

During 2024 discussions within Project Zero, researchers explored potential remote ASLR leak techniques relevant to Apple device exploitation. This investigation uncovered a novel method for extracting pointer values remotely—without memory safety violations or timing attacks—in specific scenarios where systems deserialize attacker-controlled data, then re-serialize and return the results.

The technique was tested artificially using `NSKeyedArchiver` serialization on macOS rather than against real attack surfaces. Apple addressed this in their March 31, 2025 security releases. The post explores the technique's conceptual foundations, as the underlying principles may apply to other contexts.

---

## Background - the tech tree

### hashDoS

The narrative begins with 2011's hashDoS attack presented at 28C3. This denial-of-service technique exploited hash table implementations by demonstrating that while typical operations achieve O(1) complexity, carefully crafted collisions create O(n) worst-case scenarios. An attacker knowing the hash function could construct requests where all parameter keys map to identical buckets, forcing O(n²) processing times.

Historical precedent appears in 1998 Phrack issue 53, where Solar Designer noted that application designers typically optimize typical cases rather than worst cases—yet attackers control input. This observation applies particularly to systems processing untrusted data like intrusion detection systems or kernels using hash tables for connection lookups.

### hashDoS as a timing attack

Beyond denial-of-service, hashDoS reveals a critical principle: attackers controlling numerous chosen keys while knowing their hash bucket mappings can slow subsequent access to targeted buckets. This becomes particularly powerful when mixed-type hash tables exist.

In 2016, Firefox's `Map` implementation used different hashing strategies for integers versus interned strings. By measuring insertion timing after filling buckets with attacker-chosen elements, researchers could determine whether secret-hash strings matched target buckets. Combined with patterns in interned single-character string addresses, this leaked lower 32-bits of heap addresses through "timing measurements."

**Key insight:** Pointer-based hashing in keyed data structures risks leaking addresses through side-channel effects.

### Linux: object ordering leak through in-order listing of a pointer-keyed tree

On Linux systems, unprivileged users can discover `struct file` ordering in kernel memory by reading `/proc/self/fdinfo/<epoll fd>`. This file lists watched files by iterating a red-black tree sorted by referenced object addresses, exposing ordering information to userspace.

This approach becomes particularly interesting for defeating probabilistic memory safety mitigations relying on secret pointer tag bits. If attackers determine address ordering (including tag bits), they can infer whether object tags changed after reallocation.

**Key insight:** Iterating keyed data structures generates output whose ordering reveals hash code information.

### Serialization attacks

Serialization approaches occupy a spectrum. Schema-based serialization (ideal) explicitly declares types and member relationships. Conversely, classic Java serialization allows nearly any `Serializable` class to deserialize flexibly, enabling "gadget chain" attacks achieving remote code execution.

Apple's `NSKeyedUnarchiver.unarchivedObjectOfClasses` occupies the middle ground—fundamentally unsafe deserialization with allowlist filtering. This approach restricts object types while maintaining dangerous structural flexibility.

---

## An artificial test case

The demonstration uses `NSKeyedUnarchiver.unarchivedObjectOfClasses` deserializing an attacker-supplied object graph containing `NSDictionary`, `NSNumber`, `NSArray`, and `NSNull` types. The process deserializes input, re-serializes results, and outputs the modified data.

```objective-c
@import Foundation;
int main() {
  @autoreleasepool {
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    if (args.count != 3) {
      NSLog(@"bad invocation");
      return 1;
    }
    NSString *in_path = args[1];
    NSString *out_path = args[2];

    NSError *error = NULL;
    NSData *input_binary = [NSData dataWithContentsOfFile:in_path];

    /* decode */
    NSArray<Class> *allowed_classes = @[ [NSDictionary class],
        [NSNumber class], [NSArray class], [NSString class], [NSNull class] ];
    NSObject *decoded_data = [NSKeyedUnarchiver
        unarchivedObjectOfClasses:[NSSet setWithArray:allowed_classes]
        fromData:input_binary error:&error];
    if (error) {
      NSLog(@"Error %@ decoding", error);
      return 1;
    }
    NSLog(@"decoded");

    NSData *encoded_binary = [NSKeyedArchiver
        archivedDataWithRootObject:decoded_data
        requiringSecureCoding:true error:&error];
    if (error) {
      NSLog(@"Error %@ encoding", error);
      return 1;
    }
    NSLog(@"reencoded");

    [encoded_binary writeToFile:out_path atomically:NO];
  }
  return 0;
}
```

---

## Building blocks

### The `NSNull` / `CFNull` singleton

`CFNull` is unique: only one singleton instance (`kCFNull`) exists, stored in the shared cache. Deserialization doesn't create new instances—it returns the singleton. When `CFNull` instances lack custom hash handlers, the `CFHash` function uses the object's address as the hash code.

Pointer-based hashing extends beyond `NSNull`, but few types deserialize to shared cache singletons. Conversely, many types hash to heap addresses.

### `NSNumber`

The `NSNumber` type encapsulates numeric values. Its hash handler (`__CFNumberHash`) hashes 32-bit integers using `_CFHashInt`—essentially multiplying by a large prime.

### `NSDictionary`

`NSDictionary` instances are immutable hash tables accepting arbitrarily-typed keys. Key hashes map to buckets via "hash_code % num_buckets". Hash table sizes are always prime numbers from a predefined list, with tables normally maintaining 38%-62% occupancy. Collisions resolve through linear probing—scanning forward until finding available buckets.

Serialization iterates hash buckets sequentially.

---

## The attack

### The basic idea: Infoleak through key ordering in serialized `NSDictionary`

If a target process deserializes an `NSDictionary` with attacker-chosen `NSNumber` keys, attackers control bucket occupancy by selecting numbers producing desired `(hash % table_size)` values. Inserting an `NSNull` key during deserialization then serializing the result reveals information about `NSNull`'s hash.

Consider this pattern using `NSNumber` keys (where `#` indicates occupied buckets, `_` indicates empty buckets) in a size-7 table:

```
bucket index:    0123456
bucket contents: #_#_#_#
```

The `NSNull` could insert at:
- **Index 1** if `hash_code % 7` equals 6, 0, or 1 (resulting in `NSNull` second in serialized data)
- **Index 3** if `hash_code % 7` equals 2 or 3 (resulting in `NSNull` third)
- **Index 5** if `hash_code % 7` equals 4 or 5 (resulting in `NSNull` fourth)

By receiving re-serialized data, attackers distinguish these states and narrow the range of `hash_code % table_size`.

### Extending it: Leaking the entire bucket index

Repeating with the opposite pattern (occupying odd indices, leaving even empty):

```
0123456
_#_#_#_
```

The `NSNull` could insert at:
- Index 0 if `hash_code % 7` equals 0
- Index 2 if `hash_code % 7` equals 1 or 2
- Index 4 if `hash_code % 7` equals 3 or 4
- Index 6 if `hash_code % 7` equals 5 or 6

Combining both patterns determines the exact value of `hash_code % table_size`. An attacker sends an `NSArray` containing two `NSDictionary` instances using these patterns, receives the re-serialized copy, and calculates the precise remainder.

### Some math: Leaking the entire `hash_code`

Repeating with different prime table sizes (23, 41, 71, 127, 191, 251, 383, 631, 1087) yields multiple remainders. The Chinese Remainder Theorem reconstructs `hash_code` modulo their product: `23×41×71×127×191×251×383×631×1087 = 0x5ce23017b3bd51495`.

Since this product exceeds the maximum 64-bit value, the calculated remainder equals the actual `hash_code`—the `NSNull` singleton's address.

### Putting it together

Attackers transmit ~50 KiB of serialized data containing one large container with two `NSDictionary` instances per prime number (using even-indices and odd-indices patterns). The target deserializes, re-serializes, and returns the modified data.

The attacker then:
1. Determines bucket positions for `NSNull` in each `NSDictionary`
2. Calculates `hash_code % table_size` for each prime
3. Applies the extended Euclidean algorithm to obtain the full address

### The reproducer

A complete implementation demonstrates the attack in three stages:

**Stage 1 (Attacker):** Generate serialized input
```bash
clang -o attacker-input-generator attacker-input-generator.c
./attacker-input-generator > attacker-input.plist
plutil -convert binary1 attacker-input.plist
```

**Stage 2 (Target):** Deserialize and re-serialize
```bash
clang round-trip-victim.m -fobjc-arc -fmodules -o round-trip-victim
./round-trip-victim attacker-input.plist reencoded.plist
```

**Stage 3 (Attacker):** Extract the pointer
```bash
plutil -convert xml1 reencoded.plist
clang -o extract-pointer extract-pointer.c
./extract-pointer < reencoded.plist
```

The output shows `NSNull` position in each dictionary, modulo values for each prime, and finally reconstructs the complete address:

```
NSNull mod 23 = 14
NSNull mod 41 = 13
...
NSNull = 0x1eb91ab60
```

---

## Conclusion

This technique demonstrates that pointer-based hashing in keyed data structures permits address extraction even without timing attacks, under aligned circumstances. The victim's re-serialization requirement makes real-world exploitation challenging, though timing-based variants might succeed with additional requests and precision measurements.

`NSDictionary` enables information leakage about pointer ordering and number hashes through mixed-type keys. Similar information extraction might occur from pointer-only structures, especially when attackers can estimate allocation distances or reference objects across containers.

Robust mitigation requires either eliminating object addresses as lookup keys or hashing them with keyed functions (reducing leaks to pointer equality oracles). However, performance tradeoffs exist—for instance, storing object IDs rather than addresses could burden lookup critical paths.
