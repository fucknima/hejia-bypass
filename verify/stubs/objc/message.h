#pragma once
#include <objc/objc.h>
#ifdef __cplusplus
extern "C" {
#endif
/* 真实 SDK 中 objc_msgSend 无原型（必须强转），这里故意不声明为变参函数 */
id objc_msgSend(void);
#ifdef __cplusplus
}
#endif
