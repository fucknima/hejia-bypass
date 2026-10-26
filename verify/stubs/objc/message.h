#pragma once
#include <objc/objc.h>
#ifdef __cplusplus
extern "C" {
#endif
id objc_msgSend(id self, SEL op, ...);
void objc_msgSend_stret(void *stretAddr, id self, SEL op, ...);
#ifdef __cplusplus
}
#endif
