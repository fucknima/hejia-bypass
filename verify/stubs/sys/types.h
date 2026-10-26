#pragma once
#ifdef __cplusplus
extern "C" {
#endif
/* 模拟真实 iOS SDK：这里【不】定义 caddr_t，也不提供 kinfo_proc */
typedef int pid_t;
typedef unsigned int u_int;
#ifdef __cplusplus
}
#endif
