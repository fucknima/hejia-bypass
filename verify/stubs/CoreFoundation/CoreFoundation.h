#pragma once
#ifdef __cplusplus
extern "C" {
#endif
#include <stddef.h>
typedef const void *CFTypeRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef const struct __CFAllocator *CFAllocatorRef;
typedef const struct __CFString *CFStringRef;
typedef long CFIndex;
typedef unsigned char Boolean;
typedef struct { CFIndex version; const void *retain; const void *release; const void *copyDescription; const void *equal; const void *hash; } CFDictionaryKeyCallBacks;
typedef struct { CFIndex version; const void *retain; const void *release; const void *copyDescription; const void *equal; } CFDictionaryValueCallBacks;
extern const CFAllocatorRef kCFAllocatorDefault;
extern const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks;
extern const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks;
CFDictionaryRef CFDictionaryCreate(CFAllocatorRef allocator, const void **keys, const void **values, CFIndex numValues, const CFDictionaryKeyCallBacks *keyCallBacks, const CFDictionaryValueCallBacks *valueCallBacks);
void CFRelease(CFTypeRef cf);
#ifdef __cplusplus
}
#endif
