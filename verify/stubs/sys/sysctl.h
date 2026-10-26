#pragma once
#ifdef __cplusplus
extern "C" {
#endif
#include <sys/types.h>
#include <stddef.h>
/* 真实 iOS SDK 只提供这些宏，不提供 struct kinfo_proc */
#define CTL_KERN 1
#define KERN_PROC 14
#define KERN_PROC_PID 1
int sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp,
           void *newp, size_t newlen);
#ifdef __cplusplus
}
#endif
