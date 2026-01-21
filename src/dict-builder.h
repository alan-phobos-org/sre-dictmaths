#ifndef DICT_BUILDER_H
#define DICT_BUILDER_H

#import <Foundation/Foundation.h>
#include <stdint.h>

// Pattern types for dictionary construction
typedef enum {
    PATTERN_EVEN,  // Occupy even bucket indices (0, 2, 4, ...)
    PATTERN_ODD    // Occupy odd bucket indices (1, 3, 5, ...)
} PatternType;

// Build a dictionary with keys that hash to specific bucket pattern
// and include NSNull as a key
NSDictionary* build_dict_with_pattern(PatternType pattern, uint64_t table_size);

// Extract the serialized key order from NSKeyedArchiver output
NSArray* extract_serialized_keys(NSDictionary *dict);

// Determine NSNull's position in the serialized key ordering
NSInteger find_nsnull_position(NSDictionary *dict);

// Determine NSNull's position given a serialized key array
NSInteger find_nsnull_position_in_keys(NSArray *keys);

// Validate that key ordering matches expected bucket order for the table size
bool validate_bucket_order(NSArray *keys, uint64_t table_size, PatternType pattern);

// Calculate NSNull hash modulo table_size from its position in two patterns
// Returns true on success, false if calculation fails
bool calculate_nsnull_mod(uint64_t table_size, NSInteger even_pos, NSInteger odd_pos,
                          uint64_t *result);

#endif // DICT_BUILDER_H
