#pragma once
#include <stddef.h>
#define RTLD_DEFAULT ((void *)0)
typedef struct { const char *dli_fname; void *dli_fbase; const char *dli_sname; void *dli_saddr; } Dl_info;
void *dlsym(void *handle, const char *symbol);
int dladdr(const void *addr, Dl_info *info);
unsigned int _dyld_image_count(void);
