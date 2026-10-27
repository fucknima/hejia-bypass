#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void *memset(void *s, int c, size_t n);
void *memcpy(void *d, const void *s, size_t n);
char *strstr(const char *h, const char *n);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, unsigned long n);
unsigned long strlen(const char *s);
char *strncpy(char *d, const char *s, unsigned long n);
#ifdef __cplusplus
}
#endif
