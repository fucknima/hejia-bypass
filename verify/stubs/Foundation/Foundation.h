#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#define nil ((id)0)

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef unsigned long NSStringEncoding;
static const NSStringEncoding NSUTF8StringEncoding = 4;

typedef uint64_t dispatch_time_t;
typedef long dispatch_once_t;
typedef void (^dispatch_block_t)(void);
typedef void *dispatch_queue_t;
typedef unsigned int qos_class_t;
#define QOS_CLASS_UTILITY ((qos_class_t)0x11)
#define NSEC_PER_SEC 1000000000ull
#define DISPATCH_TIME_NOW 0ull

dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);
void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
void *dispatch_get_main_queue(void);
void *dispatch_get_global_queue(long identifier, unsigned long flags);
void dispatch_once(dispatch_once_t *predicate, dispatch_block_t block);
void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);

@class NSString;
@interface NSObject
+ (Class)class;
- (Class)class;
+ (id)alloc;
+ (id)new;
- (id)init;
+ (instancetype)stringWithFormat:(NSString *)f, ...;
- (NSString *)description;
- (BOOL)isKindOfClass:(Class)c;
- (BOOL)respondsToSelector:(SEL)s;
- (id)performSelector:(SEL)s;
- (id)valueForKey:(NSString *)k;
@end

@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(void *)s objects:(id *)buf count:(NSUInteger)l;
@end

@interface NSString : NSObject
@property (readonly) const char *UTF8String;
+ (instancetype)stringWithUTF8String:(const char *)s;
- (BOOL)isEqualToString:(NSString *)s;
- (BOOL)hasPrefix:(NSString *)s;
- (BOOL)hasSuffix:(NSString *)s;
- (BOOL)containsString:(NSString *)s;
- (NSString *)stringByAppendingString:(NSString *)s;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b;
- (NSString *)stringByExpandingTildeInPath;
- (NSString *)lowercaseString;
- (NSString *)stringByAppendingPathComponent:(NSString *)c;
- (id)dataUsingEncoding:(NSStringEncoding)e;
- (BOOL)writeToFile:(NSString *)p atomically:(BOOL)a encoding:(NSStringEncoding)e error:(id *)err;
- (NSString *)description;
- (NSString *)stringByAppendingPathComponent:(NSString *)c;
@end

@interface NSMutableString : NSString
+ (instancetype)string;
- (void)appendString:(NSString *)s;
@end
@interface NSException : NSObject
@property (nonatomic, readonly) NSString *reason; @end
@interface NSNumber : NSObject
+ (NSNumber *)numberWithBool:(BOOL)b;
- (BOOL)boolValue;
- (long)longValue;
@end
@interface NSArray<T> : NSObject <NSFastEnumeration>
+ (instancetype)arrayWithObjects:(const T [])objects count:(NSUInteger)cnt;
@property (readonly) NSUInteger count;
- (T)objectAtIndexedSubscript:(NSUInteger)i;
@end

@interface NSMutableArray<T> : NSArray<T>
+ (instancetype)array;
+ (instancetype)arrayWithCapacity:(NSUInteger)n;
- (void)addObject:(T)o;
- (void)addObjectsFromArray:(NSArray *)a;
- (void)insertObject:(T)o atIndex:(NSUInteger)i;
- (void)removeObjectAtIndex:(NSUInteger)i;
- (void)removeLastObject;
- (T)lastObject;
- (void)setObject:(T)o atIndexedSubscript:(NSUInteger)i;
- (T)objectAtIndexedSubscript:(NSUInteger)i;
- (T)firstObject;
- (NSUInteger)indexOfObject:(T)o;
@end

@interface NSSet : NSObject <NSFastEnumeration>
@property (readonly) NSUInteger count;
@end
@interface NSDictionary<K, V> : NSObject
+ (instancetype)dictionaryWithObjects:(const V [])objects forKeys:(const K [])keys count:(NSUInteger)cnt;
- (V)objectForKeyedSubscript:(K)k;
@end

@interface NSData : NSObject
+ (instancetype)dataWithBytes:(const void *)b length:(unsigned long)l;
@end

@interface NSError : NSObject
@property (readonly) long code;
@property (readonly) NSString *domain;
@end

@interface NSURL : NSObject
+ (instancetype)fileURLWithPath:(NSString *)p;
+ (instancetype)URLWithString:(NSString *)s;
@property (readonly) NSString *absoluteString;
@property (readonly) NSString *path;
@end

@interface NSURLRequest : NSObject
@property (readonly) NSURL *URL;
+ (instancetype)requestWithURL:(NSURL *)u;
@end

@interface NSURLResponse : NSObject @end
@interface NSCachedURLResponse : NSObject @end
@interface NSURLCache : NSObject
+ (instancetype)sharedURLCache;
- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)r;
- (void)removeAllCachedResponses;
@end

@interface NSURLSession : NSObject
+ (instancetype)sharedSession;
- (id)dataTaskWithRequest:(NSURLRequest *)r
        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h;
@end

@interface NSFileManager : NSObject
+ (instancetype)defaultManager;
- (BOOL)fileExistsAtPath:(NSString *)p isDirectory:(BOOL *)d;
- (BOOL)fileExistsAtPath:(NSString *)p;
- (BOOL)createDirectoryAtPath:(NSString *)p withIntermediateDirectories:(BOOL)i attributes:(id)a error:(id *)e;
- (id)containerURLForSecurityApplicationGroupIdentifier:(NSString *)g;
- (BOOL)removeItemAtPath:(NSString *)p error:(id *)e;
@end

@interface NSBundle : NSObject
+ (instancetype)mainBundle;
- (NSDictionary *)infoDictionary;
- (NSString *)pathForResource:(NSString *)n ofType:(NSString *)t;
- (NSString *)bundleIdentifier;
- (NSString *)bundlePath;
- (NSURL *)appStoreReceiptURL;
@end

@interface NSUserDefaults : NSObject
+ (instancetype)standardUserDefaults;
- (BOOL)boolForKey:(NSString *)k;
- (void)setBool:(BOOL)v forKey:(NSString *)k;
- (id)objectForKey:(NSString *)k;
- (void)setObject:(id)o forKey:(NSString *)k;
- (void)removeObjectForKey:(NSString *)k;
- (BOOL)synchronize;
@end

@interface NSOperationQueue : NSObject
+ (instancetype)mainQueue;
@end
@interface NSNotificationCenter : NSObject
+ (instancetype)defaultCenter;
- (void)postNotificationName:(NSString *)n object:(id)o;
- (id)addObserverForName:(NSString *)n object:(id)o queue:(id)q usingBlock:(void (^)(id note))b;
- (void)removeObserver:(id)o;
@end

@interface NSNotification : NSObject @end

@interface NSThread : NSObject
+ (BOOL)isMainThread;
@end

NSString *NSStringFromClass(Class c);
NSString *NSStringFromSelector(SEL s);
void NSLog(NSString *format, ...);


typedef unsigned long NSSearchPathDirectory;
typedef unsigned long NSSearchPathDomainMask;
static const NSSearchPathDirectory NSCachesDirectory = 13;
static const NSSearchPathDirectory NSDocumentDirectory = 9;
static const NSSearchPathDomainMask NSUserDomainMask = 1;
NSString *NSTemporaryDirectory(void);
NSArray<NSString *> *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory d, NSSearchPathDomainMask m, BOOL e);
@interface NSDate : NSObject
+ (instancetype)date;
- (NSString *)description;
@end
@interface NSDateFormatter : NSObject
@property (nonatomic, copy) NSString *dateFormat;
- (NSString *)stringFromDate:(NSDate *)d;
@end

#ifdef __cplusplus
}
#endif
