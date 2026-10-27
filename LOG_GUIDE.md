# 日志在哪里 & 怎么打开「文件 App 可见」

## 直接回答

**之前那份日志你确实看不到，是我说错了。**

我把它写进了 App 自己的沙盒 `Library/Caches/HeJiaTool/`。这个目录：
- 只有 App 自己能访问
- 「文件」App **完全看不到**
- 只有越狱环境/第三方工具能读

要在「文件」App 里看到，必须**同时满足两个条件**，缺一不可：

| 条件 | 原来状态 | 现在 |
|---|---|---|
| ① 写到 App Group 共享容器 | 没写 | ✅ 已改（`group.com.cmcc.zhihuiguanjia`） |
| ② Info.plist 开启文件共享 | **关闭** | ⚠️ 需要你打补丁（见下） |

---

## 打补丁（重签前必须做）

解压 IPA 后，对 `Payload/zhihuiguanjia.app` 执行：

```bash
python3 packaging/info_plist_patch.py Payload/zhihuiguanjia.app
```

它会设置：
```
UIFileSharingEnabled            = True
LSSupportsOpeningDocumentsInPlace = True
```
（自动备份 `Info.plist.bak`）

**同时需要在签名时带上 App Group 权限**：

```bash
ldid -S packaging/entitlements.plist \
     -M \
     Payload/zhihuiguanjia.app/zhihuiguanjia
```

> 如果用 TrollStore / TrollFools 注入，它们通常会继承原 App 的 entitlements，
> 原 App 本身就声明了 `group.com.cmcc.zhihuiguanjia`，所以大概率能直接可用。
>
> 如果用个人证书重签，**必须**把 App Group 加到 profile 里，否则
> `containerURLForSecurityApplicationGroupIdentifier` 返回 nil。

---

## 装好之后

1. 打开 App，进「我的」页
2. 等 3 秒（广告扫描延后执行）
3. 打开「文件」App → **我的 iPhone** → 找到 **移动爱家** 文件夹
4. 里面会有 `HeJiaTool/` 目录：
   ```
   移动爱家/
   └── HeJiaTool/
       ├── HeJiaTool.log    主日志
       └── adscan.log       广告扫描明细
   ```

也可以在 App 内查看：我的页右上角工具图标 → 设置页 → 底部「日志与诊断」
→ 点一下会**复制路径**并弹窗显示。

---

## 启动时自检

`HeJiaTool.log` 开头会写：

```
App 10.11.0
日志目录: /private/var/mobile/Containers/Shared/AppGroup/xxx/HeJiaTool
AppGroup 可用: YES
Info.plist 文件共享: YES
```

**如果两行都是 NO**，说明：
- App Group 权限没带上 → 用上面的 `ldid -S` 命令
- Info.plist 没打补丁 → 跑那个 Python 脚本

---

## 兜底方案

如果折腾 entitlements 太麻烦，还有一个更简单的办法：

**用 `idevicesyslog` 之类的工具读系统日志**（需要电脑），
所有日志同时也通过 `fprintf(stderr)` 输出，格式：

```
10-27 08:09:01.123 [HeJiaNoAds] 拦截广告请求: https://...
```

不过这需要 Mac/PC，对你可能也不方便。
