#pragma once
#include <sys/types.h>
struct kinfo_proc { struct { int p_flag; } kp_proc; };
#define CTL_KERN 1
#define KERN_PROC 14
#define KERN_PROC_PID 1
int sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
