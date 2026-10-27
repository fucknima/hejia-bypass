#pragma once
#ifdef __cplusplus
extern "C" {
#endif
typedef int pid_t;
void _exit(int code);
int usleep(unsigned int usec);
int getpid(void);
#ifdef __cplusplus
}
#endif
