# HeJiaBypass — 移动爱家检测绕过 Tweak

针对 `com.cmcc.zhihuiguanjia`（移动爱家）的越狱 / 篡改 / 注入 / 调试 / 代理检测绕过。

## 背景：为什么"只解密"也会被判篡改

分析 `Payload/zhihuiguanjia.app/Frameworks/XJSpeechManager.framework` 得到的真实逻辑：

```
+[TamperingDetector isTampered]
    └─ 读 Info.plist 的 embedded.mobileprovision
       └─ 与框架 __const 段内置的 2 个 CDHash 白名单比对
+[TamperingDetector isTamperedWithExpectedTeamID:]
    └─ 从 mobileprovision 取 application-identifier 的 TeamID 段
       └─ 与内置常量 "JR9ACKVZRQ" 比较
```

- App Store 原版：CDHash 命中白名单、TeamID 匹配 → 通过
- **仅解密（不重签）**：文件页哈希与 CodeDirectory 对不上（实测主二进制
  67708 页中 3 页不一致，正是 CryptID 加密区）→ **CDHash 必然改变**
- 重签后：CDHash 重算仍不在白名单、TeamID 变成你自己的证书 → **必然判篡改**

所以这是"解密就报错"，与有没有修改代码无关。本 tweak 直接让这些检测返回安全值。

## 覆盖范围

| 模块 | 方法 | 处理 |
|---|---|---|
| `XJSpeechManager.JailbreakDetector` | `isJailbroken` | → NO |
| `XJSpeechManager.TamperingDetector` | `isTampered` / `isTamperedWithExpectedTeamID:` | → NO |
| `XJSpeechManager.InjectionDetector` | `isInjected` | → NO |
| `XJSpeechManager.DebugDetector` | `isBeingDebugged` | → NO |
| `XJSpeechManager.ProxyDetector` | `isProxyEnabled` / `isExternalProxyEnabled` / `isVPNTunnelActive` | → NO |
| `BBJailbreakDetector` | `isJailbroken` `hasSuspiciousFiles` `canWriteOutsideSandbox` `hasInjectedDynamicLibrary` `hasCydiaURLScheme` | → NO |
| `BBHookDetector` | `isHooked` `hasSuspiciousFiles` `hasSuspiciousEnv` `hasFunctionHooked` | → NO |
| `BBProxyDetector` | `isUsingProxy` | → NO |
| `BBAntiDebug` | `enable` `disableDebugger` `checkDebugger` | 置空 |
| `NSFileManager` | `fileExistsAtPath:isDirectory:` | 屏蔽 23 个越狱路径 |
| C 函数 | `sysctl` / `ptrace` / `CFNetworkCopySystemProxySettings` | 清除 P_TRACED / 屏蔽 PT_DENY_ATTACH / 返回空代理 |
| 主包 | `deviceAntiTamperAction:value:callbackHandle:`<br>`andlinkCheckEnvironmentWithType:result:failure:` | 运行期扫描全类后置空 |

## 编译

本地已做的验证（不依赖 macOS）：

```bash
./verify/compile_check.sh          # iOS 目标语法检查
./verify/strict_build.sh           # -Werror 严格编译成 arm64 .o
```

在 GitHub Actions 上出成品（需要 Theos，workflow 已附带）：

```
Actions → Build Tweak → 下载 artifact (HeJiaBypass.dylib)
```

## 手动安装（TrollStore / 越狱）

1. 解压已解密的 IPA，得到 `Payload/zhihuiguanjia.app`
2. 把 `HeJiaBypass.dylib` 放进 `zhihuiguanjia.app/`
3. 用 `insert_dylib` 或 `optool` 注入，或在 TrollStore 里用
   `TrollFools` / `Satella` 注入
4. 重签并安装

`HeJiaBypass.plist` 是过滤器，只对 `com.cmcc.zhihuiguanjia` 生效。

## 日志

安装后可用 `Console.app` 或 `idevicesyslog` 过滤 `[HeJiaBypass]`：

```
[HeJiaBypass] hook 类方法 [JailbreakDetector isJailbroken]
[HeJiaBypass] hook 类方法 [TamperingDetector isTampered]
[HeJiaBypass] hook [NSFileManager fileExistsAtPath:isDirectory:]
[HeJiaBypass] 主包扫描：deviceAntiTamper 命中 1 个类，andlinkCheckEnv 命中 1 个类
```

## 已知限制

- 服务端 `securityCheck` 请求签名（`setSignHeaderSafe:...`）**不在此 tweak 范围内**，
  改包后服务端仍可能判非法（这是服务端逻辑，客户端 hook 只能改本地判断）
- `isTamperedWithExpectedTeamID:` 的 hook 对**动态加载时机**敏感；
  已用 1/3/6/12 秒延迟重试兜底
- `deviceAntiTamperAction:value:callbackHandle:` 与
  `andlinkCheckEnvironmentWithType:result:failure:` 的所属类未在静态分析中确认，
  因此采用运行期全类扫描（仅限主 App 镜像，跳过系统库）

## 目录

```
Tweak.xm                 主源码
Makefile                 Theos 构建
control                  deb 包描述
HeJiaBypass.plist        注入过滤器
verify/                  本地验证（头文件桩 + 编译脚本 + 逻辑单测）
analysis/                二进制分析脚本
.github/workflows/       GitHub Actions 构建
```
