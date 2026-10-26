#pragma once
#include <sys/types.h>
#define PT_DENY_ATTACH 31
int ptrace(int request, pid_t pid, caddr_t addr, int data);
