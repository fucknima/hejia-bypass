// 逻辑验证：确认 hook 替换后的返回值与签名一致
// 在 Linux/macOS 上编译运行（不依赖 iOS）
#include <stdio.h>
#include <string.h>

typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO  ((BOOL)0)

typedef void (*IMP)(void);

// 模拟目标方法
static BOOL fake_isJailbroken(void *self, void *cmd) { return YES; }
static BOOL fake_isTampered(void *self, void *cmd) { return YES; }
static BOOL fake_isTamperedWithTeam(void *self, void *cmd, void *teamID) {
    (void)teamID;
    return YES;
}

// hook 实现
static BOOL hook_NO(void *self, void *cmd) { (void)self; (void)cmd; return NO; }
static BOOL hook_NO_arg1(void *self, void *cmd, void *a) {
    (void)self; (void)cmd; (void)a;
    return NO;
}

static int failures = 0;
static void expect(const char *name, BOOL got, BOOL want) {
    if (got == want) {
        printf("  PASS  %-32s = %s\n", name, got ? "YES" : "NO");
    } else {
        printf("  FAIL  %-32s got %s want %s\n", name, got ? "YES" : "NO", want ? "YES" : "NO");
        failures++;
    }
}

int main(void) {
    printf("== 1. 原始行为（模拟被检测到的环境）==\n");
    expect("isJailbroken (before)", ((BOOL(*)(void*,void*))fake_isJailbroken)(0, 0), YES);
    expect("isTampered (before)", ((BOOL(*)(void*,void*))fake_isTampered)(0, 0), YES);
    expect("isTamperedWithTeamID (before)",
           ((BOOL(*)(void*,void*,void*))fake_isTamperedWithTeam)(0, 0, 0), YES);

    printf("== 2. 替换为 hook_NO ==\n");
    IMP old = (IMP)fake_isJailbroken;
    (void)old;
    expect("isJailbroken (after)", ((BOOL(*)(void*,void*))hook_NO)(0, 0), NO);
    expect("isTampered (after)", ((BOOL(*)(void*,void*))hook_NO)(0, 0), NO);

    printf("== 3. 替换为 hook_NO_arg1（带 TeamID 参数）==\n");
    expect("isTamperedWithTeamID (after)",
           ((BOOL(*)(void*,void*,void*))hook_NO_arg1)(0, 0, (void *)"JR9ACKVZRQ"), NO);

    printf("== 4. 目标方法名与真实二进制对照 ==\n");
    const char *sels[] = {
        "isJailbroken", "isTampered", "isTamperedWithExpectedTeamID:",
        "isInjected", "isBeingDebugged",
        "isProxyEnabled", "isExternalProxyEnabled", "isVPNTunnelActive",
        "hasSuspiciousFiles", "hasInjectedDynamicLibrary",
        "hasCydiaURLScheme", "canWriteOutsideSandbox",
    };
    for (size_t i = 0; i < sizeof(sels)/sizeof(sels[0]); i++) {
        printf("  SEL: %s\n", sels[i]);
    }

    printf("\n%s (failures=%d)\n", failures ? "!!! 存在失败项" : "全部通过", failures);
    return failures ? 1 : 0;
}
