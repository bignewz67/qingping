# 清屏 QingPing

> iOS 16.3.1 上的「开屏广告自动跳过 + 误触跳转拦截 + 按 App 统计」。
> **不越狱也能跑**：TrollStore + TrollFools 把 `QingPing.dylib` 注入目标 App 即可；有越狱则直接装 deb。

| 交付物 | 路径 | 说明 |
| --- | --- | --- |
| 注入端（dylib） | `tweak/` | 自包含实现，**不依赖 Substrate/ElleKit**，TrollFools 可直接注入 |
| 统计端（App） | `ios/` | SwiftUI，iOS 16.0+，按 App 展示拦截次数 / 类型 / 时间线 |
| 图标 | `ios/Sources/Assets.xcassets` | 1024×1024，已生成 |
| 图标脚本 | `tools/make_icon.py` | 可重新生成 |

**从零到装机**：没有 Mac、不装 Xcode 也能出包 —— 见 [PUBLISH.md](PUBLISH.md)（网页上传 → GitHub Actions 编译 → TrollStore 装机）。

---

## 一、先说清楚：IPA 装得上 ≠ 拦得住

决定能力的是**签名方式**，不是「装没装上」：

| 安装方式 | 拿到的权限 | 清屏能做到什么 |
| --- | --- | --- |
| AltStore / Sideloadly / 普通证书自签 | 普通沙盒，与 App Store 版一致 | 只有统计界面 + 演示数据，**拦不住任何广告** |
| **TrollStore**（16.3.1 支持）+ TrollFools | 可注入 dylib 到其它 App，App 自身获得平台权限 | **能跳过开屏、拦误触、按 App 统计**；需逐个 App 注入 |
| 越狱（Dopamine 2 / palera1n） | root + 全局注入 | 一次装好，所有 App 覆盖 |

原因见下一节。

---

## 二、iOS 的权限与限制

### 2.1 核心事实

| 能力 | iOS 是否允许 | 说明 |
| --- | --- | --- |
| 读取其它 App 界面 / 控件 | ❌ | 没有 Android 的「无障碍服务」，进程完全隔离 |
| 模拟点击、注入触摸到其它 App | ❌ | 无公开 API；私有 API 会拒审（审核指南 2.5.1） |
| Hook 其它 App 的方法 | ❌ | 需要代码注入 |
| 常驻后台 | ❌ | 进后台约 30 秒被挂起，最终被回收 |
| 开机自启动 | ❌ | 没有 `BOOT_COMPLETED`，没有 LaunchDaemon 权限 |
| 拿到流量的「来源 App」 | ❌ | 见 2.2 |
| 修改其它 App 的启动页 | ❌ | 技术上做不到 |

### 2.2 网络层能做到什么

- `NEPacketTunnelProvider`（本地 VPN / DNS 过滤）：能按域名拦广告请求，**但拿不到源 App，无法按 App 统计**；要手动开 VPN、不能自启；开屏素材常预加载或走自有 CDN，拦不干净，误杀还会让宿主 App 白屏。
- `NEFilterDataProvider`（内容过滤）：系统里**唯一**能拿到 App 归属的能力，但 entitlement 需 Apple 特批，通常只对受监管设备开放。
- Safari 内容拦截器：只管 Safari。

### 2.3 「开机自启、清后台不掉」的真相

普通 App 没有开机启动项，`BGTaskScheduler` 是机会性调度，滥用 Background Modes 既违规又会被杀。

**所以正确架构不是保活，而是注入**：代码跑在目标 App 进程里 → 清后台不影响它 → 开机后目标 App 第一次启动就重新加载 → 天生满足「开机后自动运行」，还不需要任何常驻进程。

### 2.4 TrollStore 给了什么

TrollStore 用 CoreTrust 漏洞给 App 换签名，效果是：

- 安装的 App 不会过期（不用 7 天重签）；
- App 获得平台级权限，能读其它 App 的容器（清屏靠这个汇总统计）；
- 配合 **TrollFools**，可以把 dylib 注入到已安装的 App 里（包括 App Store 应用），不需要越狱。

限制：注入是**逐 App** 的；App 更新/重装后注入会消失，要重新注入；带完整性校验的 App（部分银行、游戏）可能闪退；系统 App 不可注入。

---

## 三、架构

```
┌─────────────────────────────────────────┐
│ 目标 App（微信 / 抖音 / 淘宝…）          │
│  ┌───────────────────────────────────┐  │
│  │ QingPing.dylib（TrollFools 注入） │  │
│  │  · 识别开屏广告控制器             │  │
│  │  · 点「跳过」/ 移除广告视图       │  │
│  │  · 吞掉广告区域点击（防误触）     │  │
│  │  · 拦截 openURL 外跳              │  │
│  │  · 写统计：① 共享偏好域           │  │
│  │            ② 自己容器的副本       │  │
│  └───────────────────────────────────┘  │
└──────────────────┬──────────────────────┘
                   │ 清屏带平台权限读取
┌──────────────────▼──────────────────────┐
│ 清屏 App（TrollStore 安装，可随时被杀） │
│  · 扫描各 App 容器的 stats.json 汇总    │
│  · 回退读 /var/mobile/Library/Preferences│
│  · 按 Bundle ID 展示统计、写开关        │
└─────────────────────────────────────────┘
```

**双写统计**是有意为之：注入进 App Store 应用后，跨域写偏好不一定被放行，但写自己容器的 `Application Support` 一定成功。清屏优先读容器副本（最稳），读不到再退回共享偏好域（越狱路线）。

---

## 四、构建

> 本仓库在 Windows 上编写，无法在本机编译 iOS 产物；以下步骤需要 macOS + Xcode。

### 4.1 注入端

```bash
cd QingPing/tweak
make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

得到两个东西：

- `packages/com.qingping.tweak_1.0.0_iphoneos-arm64.deb` —— 越狱设备用；
- `.theos/obj/.../QingPing.dylib` —— **喂给 TrollFools 的裸动态库**。

代码是纯 Objective-C runtime 方法替换，没有 `MSHookMessageEx` 依赖，所以 TrollFools 注入后不会因缺符号加载失败。

### 4.2 统计端（出 IPA）

```bash
cd QingPing/ios
xcodegen generate && open QingPing.xcodeproj
```

1. Target → Signing，随便选个 Team（TrollStore 会重签，证书不重要）；
2. Product → Archive → Distribute App → **Development** 导出 IPA（或直接 `xcodebuild -exportArchive`）；
3. 把 IPA 拖进 iPhone 上的 TrollStore 安装。

> 没装 XcodeGen？新建 iOS App 工程（SwiftUI，iOS 16.0），把 `ios/Sources` 下除 `Info.plist` 外的文件拖进去，用现有 `Info.plist` 覆盖即可。

### 4.3 装 TrollStore（如果还没装）

iOS 16.3.1 用 **TrollInstallerX**（支持 14.0–16.6.1），按它仓库的说明装。装好后确认「TrollStore 能安装 IPA」。

### 4.4 给清屏加平台权限（关键，容易漏）

清屏要扫描各 App 容器里的 `stats.json` 才能汇总，这需要平台级文件权限。TrollStore 安装时**不一定**自动带上，如果打开清屏只看到「演示数据」，按下面处理：

1. 用仓库里的 `ios/QingPing.entitlements` 重新签名 IPA（`ldid -S<entitlements>` 或支持附加 entitlements 的签名工具）；
2. 重新装回 TrollStore；
3. 还是读不到 → 说明该 TrollStore 版本会剥离私有 entitlements，这时只能走越狱路线（清屏改读共享偏好域）。

注入端本身不需要这些权限：它只写自己容器的 `Application Support`。

---

## 五、注入与验收

1. TrollStore 里装好 `QingPing.ipa`（清屏本体）；
2. 装 **TrollFools**；
3. 打开 TrollFools → 选目标 App（微信/抖音/淘宝…）→ 注入 → 选 `QingPing.dylib`；
4. 打开目标 App，Console 里出现 `[QingPing] loaded into com.tencent.xin` 说明注入成功；
5. 开屏广告被点掉后出现 `[QingPing] splash skipped (...)`；
6. 回到清屏 → 概览页计数 +1，应用页出现该 App；
7. 把清屏从后台划掉，再触发一次开屏 —— 依然被拦（证明不依赖常驻）。

想停用：TrollFools 里「移除注入」，或在清屏设置里关掉总开关（5 秒内生效）。从「关闭」改回「开启」需要重开一次目标 App——注入是在启动时完成的。

---

## 六、实现原理

| Hook 点 | 作用 |
| --- | --- |
| `-[UIViewController viewDidAppear:]` | 全屏 + 类名命中广告关键字（Splash/BUAd/GDT/CSJ/KSAd/Pangle…）→ 判定开屏 |
| `-[UIViewController presentViewController:animated:completion:]` | 捕获模态开屏；拦截开屏期间的 App Store 落地页 |
| `-[UIWindow didAddSubview:]` | 捕获直接挂到窗口上的广告视图 |
| `-[UIView hitTest:withEvent:]` | 开屏期间吞掉广告区域点击（「跳过」按钮放行） |
| `-[UIApplication openURL:]` / `openURL:options:completionHandler:` | 拦截 `itms-apps://`、`apps.apple.com`、开屏期间的自定义 scheme |
| `-[SKStoreProductViewController loadProductWithParameters:completionBlock:]` | 拦截 App Store 半屏页 |

识别用双条件收敛，避免误伤信息流广告和新手引导：

1. 类名或视图层级命中广告关键字；
2. 视图覆盖屏幕 ≥ 60%，且处于启动/回前台后的时间窗（默认 15 秒，可配置）。

跳过策略：默认「模拟点跳过」（0.9 秒复查、最多 3 次），失败才按「模态 dismiss → 独立广告窗口隐藏 → 移除广告视图 → 移除子控制器」强制处理；每次成功只记 1 条。

---

## 七、数据格式

共享偏好域 `com.qingping.stats` 的 `root` 键，与容器内的 `stats.json` 结构一致：

```jsonc
{
  "version": 1,
  "updatedAt": 1762300000.0,
  "apps": {
    "com.tencent.xin": { "name": "微信", "splash": 14, "misclick": 4, "last": 1762299990.0 }
  },
  "daily": { "2026-11-04": 21 },
  "totals": { "splash": 60, "misclick": 33 },
  "recent": [
    { "bid": "com.tencent.xin", "name": "微信", "kind": "splash", "detail": "SplashAdView", "ts": 1762299990.0 }
  ]
}
```

- 写入：注入端，`flock` + 读改写，异步串行，不阻塞主线程；
- 读取：清屏 App；
- `recent` 只留最近 120 条；
- 开关域 `com.qingping.prefs` 的 `root`：`enabled`、`skipMode`(0 点跳过 / 1 强制关闭)、`touchGuard`、`ignoreList`、`detectWindow`。

> 若你的设备上「设置改了不生效」，说明清屏写不进共享偏好域。此时把清屏也用 Theos 打成 rootless deb（带平台权限）安装，或直接在注入端把默认值改成你想要的行为。

---

## 八、已知限制与风险

1. **逐个注入**：TrollFools 一次只能处理一个 App；App 更新后要重新注入（TrollFools 支持批量，但仍是手动的）。
2. **个别 App 会坏**：带完整性校验/反注入的 App 可能闪退，移除注入即可恢复。
3. **广告 SDK 会变**：类名和结构更新后要补 `QPAdClassKeywords()`；识别失败只会「不处理」，不影响 App 正常使用。
4. **强制关闭可能白屏**：所以默认用「点跳过」。
5. **误判引导页**：已用「全屏 + 广告类名/广告视图」双条件收敛，仍可在忽略名单排除。
6. **系统 App 不可注入**（含 Safari），这些不在覆盖范围。
7. **合规**：仅用于个人设备上的广告过滤研究，请勿商业分发或上架。

---

## 九、为什么不走 DNS 路线

本地 DNS 过滤拦不住预加载/自有域名的开屏素材，拿不到 App 归因（统计只能猜），还要常开 VPN、不能自启。要真功能就得注入；要上架就只能接受降级版。仓库里没有把降级版包装成「能拦截」。

---

## 十、没有 Mac？用 GitHub Actions 出包

Xcode 只在 macOS 上运行，但**不需要买 Mac**：把本目录推到一个 GitHub 仓库（`ios/`、`tweak/` 在仓库根下），`.github/workflows/build.yml` 会自动在 macOS 机器上：

1. 装 Theos → 编译 `tweak/` → 产出 `QingPing.dylib` 和 `.deb`；
2. 装 XcodeGen → 生成工程 → `xcodebuild` 编译 → 打包出**未签名 IPA**。

跑完在 Actions 页面下载两个 artifact 即可：

- `QingPing-tweak` → 取 `QingPing.dylib` 给 TrollFools；
- `QingPing-ipa` → 直接拖进 TrollStore。

几个要点：

- **不需要 Apple 开发者账号，也不需要证书**：TrollStore 装 IPA 时会用自己的 ldid 重签，未签名包能装。
- 免费额度：公开仓库的 Actions 不计量；私有仓库每月 2000 分钟，macOS runner 按 **10 倍**折算（约 200 分钟，一次构建约 5 分钟，够跑 40 次）。
- 想手动触发：Actions 页面 → build → Run workflow。

其他选择：租云 Mac（MacinCloud / MacStadium，按小时计费）、借一台能装 macOS 13+ 的 Mac（Xcode 14.3 起支持 iOS 16 SDK）。WSL2 + Linux 版 Theos 只能编 dylib，编不了 SwiftUI App，因为 Swift 的 UIKit 只在 Xcode 里。
