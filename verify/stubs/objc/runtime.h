#pragma once
#include <objc/objc.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct objc_method *Method;
typedef void (*IMP)(void);
Class objc_getClass(const char *name);
Class object_getClass(id obj);
Class *objc_copyClassList(unsigned int *outCount);
const char *class_getName(Class cls);
const char *sel_getName(SEL sel);
BOOL sel_isEqual(SEL a, SEL b);
Method class_getClassMethod(Class cls, SEL name);
Method class_getInstanceMethod(Class cls, SEL name);
Method *class_copyMethodList(Class cls, unsigned int *outCount);
SEL method_getName(Method m);
IMP method_getImplementation(Method m);
IMP method_setImplementation(Method m, IMP imp);
const char *method_getTypeEncoding(Method m);
SEL sel_registerName(const char *str);
#ifdef __cplusplus
}
#endif
