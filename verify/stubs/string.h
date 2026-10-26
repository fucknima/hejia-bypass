#pragma once
#ifdef __cplusplus
extern "C" {
#endif
#include <stddef.h>
void *memset(void *s, int c, size_t n);
char *strstr(const char *h, const char *n);
int strcmp(const char *a, const char *b);
#ifdef __cplusplus
}
#endif
