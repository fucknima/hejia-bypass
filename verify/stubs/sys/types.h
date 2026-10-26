#pragma once
#include <stddef.h>
typedef int pid_t; typedef char *caddr_t; typedef unsigned int u_int;
int ptrace(int request, pid_t pid, caddr_t addr, int data);
