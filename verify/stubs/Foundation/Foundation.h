#pragma once
#ifdef __cplusplus
extern "C" {
#endif
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <objc/objc.h>
typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#define nil ((id)0)
#define NS_ASSUME_NONNULL_BEGIN
#define NS_ASSUME_NONNULL_END
typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double NSTimeInterval;
typedef struct _NSZone NSZone;
typedef uint64_t dispatch_time_t;
typedef long dispatch_once_t;
#define NSEC_PER_SEC 1000000000ull
#define DISPATCH_TIME_NOW 0ull
typedef void (^dispatch_block_t)(void);
typedef void *dispatch_queue_t;
void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);
dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);
void dispatch_after(dispatch_time_t when, void *queue, dispatch_block_t block);
void *dispatch_get_main_queue(void);
void *dispatch_get_global_queue(long identifier, unsigned long flags);
typedef unsigned int qos_class_t;
#ifndef QOS_CLASS_UTILITY
#define QOS_CLASS_UTILITY ((qos_class_t)0x11)
#endif
void dispatch_once(dispatch_once_t *predicate, dispatch_block_t block);
#include <CoreFoundation/CoreFoundation.h>
CFDictionaryRef CFNetworkCopySystemProxySettings(void);
typedef struct { unsigned long state; id __unsafe_unretained *itemsPtr; unsigned long *mutationsPtr; unsigned long extra[5]; } NSFastEnumerationState;
@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len;
@end
@interface NSObject
+ (Class)class;
- (BOOL)isKindOfClass:(Class)c;
- (BOOL)respondsToSelector:(SEL)s;
- (id)performSelector:(SEL)s;
@end
@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)s;
- (BOOL)isEqualToString:(NSString *)s;
- (BOOL)hasPrefix:(NSString *)s;
- (BOOL)containsString:(NSString *)s;
- (NSString *)stringByAppendingString:(NSString *)s;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b;
- (NSString *)stringByExpandingTildeInPath;
@end
@interface NSURL : NSObject
+ (instancetype)fileURLWithPath:(NSString *)path;
+ (instancetype)URLWithString:(NSString *)s;
- (NSString *)path;
@end
@interface NSArray<T> : NSObject <NSFastEnumeration>
+ (instancetype)arrayWithObjects:(const T [])objects count:(NSUInteger)cnt;
@end
@interface NSDictionary<K, V> : NSObject
+ (instancetype)dictionaryWithObjects:(const V [])objects forKeys:(const K [])keys count:(NSUInteger)cnt;
@end
@interface NSFileManager : NSObject
+ (instancetype)defaultManager;
- (BOOL)fileExistsAtPath:(NSString *)p isDirectory:(BOOL *)d;
- (BOOL)fileExistsAtPath:(NSString *)p;
@end
@interface NSBundle : NSObject
+ (instancetype)mainBundle;
- (NSDictionary *)infoDictionary;
- (NSString *)pathForResource:(NSString *)n ofType:(NSString *)t;
- (NSString *)bundleIdentifier;
@end
NSString *NSStringFromClass(Class c);
NSString *NSStringFromSelector(SEL s);
void NSLog(NSString *format, ...);
#ifdef __cplusplus
}
#endif
