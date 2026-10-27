#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef const void *CFTypeRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef const struct __CFAllocator *CFAllocatorRef;
typedef long CFIndex;
typedef struct { CFIndex version; const void *retain; const void *release; const void *copyDescription; const void *equal; const void *hash; } CFDictionaryKeyCallBacks;
typedef struct { CFIndex version; const void *retain; const void *release; const void *copyDescription; const void *equal; } CFDictionaryValueCallBacks;
extern const CFAllocatorRef kCFAllocatorDefault;
extern const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks;
extern const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks;
CFDictionaryRef CFDictionaryCreate(CFAllocatorRef a, const void **k, const void **v, CFIndex n, const CFDictionaryKeyCallBacks *kb, const CFDictionaryValueCallBacks *vb);
void CFRelease(CFTypeRef cf);
CFDictionaryRef CFNetworkCopySystemProxySettings(void);
double CACurrentMediaTime(void);
typedef double CFTimeInterval;
#ifdef __cplusplus
}
#endif
