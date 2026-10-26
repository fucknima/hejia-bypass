#pragma once
#include <objc/objc.h>
typedef struct objc_method *Method;
typedef void (*IMP)(void);
Class objc_getClass(const char *name);
Class object_getClass(id obj);
Method class_getClassMethod(Class cls, SEL name);
Method class_getInstanceMethod(Class cls, SEL name);
IMP method_getImplementation(Method m);
IMP method_setImplementation(Method m, IMP imp);
SEL sel_registerName(const char *str);
Class *objc_copyClassList(unsigned int *outCount);
const char *class_getName(Class cls);
typedef struct objc_method *Method;
Method *class_copyMethodList(Class cls, unsigned int *outCount);
SEL method_getName(Method m);
BOOL sel_isEqual(SEL a, SEL b);
