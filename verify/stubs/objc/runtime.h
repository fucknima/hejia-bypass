#pragma once
#include <objc/objc.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct objc_method *Method;
typedef void (*IMP)(void);
typedef enum { OBJC_ASSOCIATION_ASSIGN = 0, OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
               OBJC_ASSOCIATION_COPY_NONATOMIC = 3, OBJC_ASSOCIATION_RETAIN = 01401,
               OBJC_ASSOCIATION_COPY = 01403 } objc_AssociationPolicy;
Class objc_getClass(const char *name);
Class object_getClass(id obj);
Class *objc_copyClassList(unsigned int *outCount);
const char *class_getName(Class cls);
id objc_getAssociatedObject(id object, const void *key);
void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy);
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
const char *sel_getName(SEL sel);
BOOL sel_isEqual(SEL a, SEL b);
SEL sel_registerName(const char *str);
SEL NSSelectorFromString(void *name);
Method class_getClassMethod(Class cls, SEL name);
Method class_getInstanceMethod(Class cls, SEL name);
Method *class_copyMethodList(Class cls, unsigned int *outCount);
SEL method_getName(Method m);
IMP method_getImplementation(Method m);
IMP method_setImplementation(Method m, IMP imp);
const char *method_getTypeEncoding(Method m);
#ifdef __cplusplus
}
#endif
