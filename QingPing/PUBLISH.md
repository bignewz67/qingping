# 发布与装机（从这台 Windows 到 iPhone）

> 目标：不装 Xcode、不买 Mac、不注册开发者账号，用 GitHub 的 macOS 机器编译，用 TrollStore 装机。
> 全程约 10 分钟，其中等待构建 5–10 分钟。

---

## 路线 A：不装 Git（推荐，纯网页）

### 1. 建仓库

1. 打开 <https://github.com/new>
2. Repository name：`qingping`
3. 可见性选 **Public**（公开仓库的 Actions 不计分钟数；私有仓库也能用，但每月只有约 200 分钟 macOS 额度）
4. 不要勾选 "Add a README file"
5. Create repository

### 2. 上传项目

1. 新仓库页面点 **uploading an existing file**
2. 打开资源管理器，进到 `D:\file`
3. 把 **`QingPing` 整个文件夹**拖进浏览器上传区（拖文件夹本身，不要进去全选文件）
4. 等进度条走完 → 底部 **Commit changes**

> 上传后仓库根目录应该是：`README.md`、`ios/`、`tweak/`、`tools/`、`.github/`。
> **重点确认 `.github/workflows/build.yml` 在**——它是隐藏目录，最容易漏。

### 3. 触发构建

1. 点仓库顶部 **Actions**
2. 第一次会提示启用 workflow，点 **I understand my workflows, go ahead and enable them**
3. 左侧选 **build** → 右侧 **Run workflow** → 绿色按钮

### 4. 下载产物

构建跑完（约 5–10 分钟）后，进这次运行记录，页面底部 **Artifacts**：

| Artifact | 里面是什么 | 用途 |
| --- | --- | --- |
| `QingPing-tweak` | `QingPing.dylib` + `com.qingping.tweak_*.deb` | dylib 给 TrollFools；deb 给越狱设备 |
| `QingPing-ipa` | `QingPing.ipa` | 给 TrollStore 安装 |

### 5. 传到手机并安装

1. 把 `QingPing.ipa` 传到 iPhone（AirDrop / iCloud 云盘 / 微信文件传输都行）
2. 在 iPhone 上点开它 → **用 TrollStore 打开** → Install
3. 装好后先别急着打开，继续下一步注入

### 6. 注入到目标 App

1. iPhone 上打开 **TrollFools**
2. 选一个目标 App（微信 / 抖音 / 淘宝…）
3. 注入 → 选 `QingPing.dylib`（先从 zip 里解出来传到手机）
4. 打开目标 App：Console 出现 `[QingPing] loaded into ...` 即成功

> App 更新后注入会消失，重新注一次即可。

---

## 路线 B：装了 Git 的命令行版

```powershell
# 安装（Windows 10/11 自带 winget）
winget install --id Git.Git -e

# 在项目目录初始化并提交
cd D:\file\QingPing
git init -b main
git add .
git commit -m "qingping: initial"
git remote add origin https://github.com/<你的用户名>/qingping.git
git push -u origin main
```

推送时如果要求密码，用 **Personal Access Token**（GitHub → Settings → Developer settings → Personal access tokens → 勾 `repo`），把它当密码填。

之后每次改完代码：

```powershell
git add . && git commit -m "update" && git push
```

Actions 会自动重跑。

---

## 常见问题

**Actions 里什么都没有 / 没有 build 这个 workflow**
`.github/workflows/build.yml` 没上传成功。补救：仓库页面 → Add file → Create new file → 文件名填 `.github/workflows/build.yml` → 把本地这个文件的内容整段粘进去 → Commit。

**构建红了，报 XcodeGen 相关**
看日志里 `xcodegen generate` 那一步。若提示 `project.yml` 找不到，说明上传时 `ios/` 层级错了（应该是仓库根下的 `ios/`）。

**构建红了，报签名相关**
正常，我们的构建显式关闭了签名（`CODE_SIGNING_ALLOWED=NO`）。如果这个报错出现在别的步骤，把日志贴出来。

**装上了但清屏只显示「演示数据」**
两种可能：① 还没注入任何 App（先按第 6 步注入并触发一次开屏）；② 清屏缺少平台权限，按 README 4.4 用 `ios/QingPing.entitlements` 重签。

**注入后目标 App 闪退**
个别 App 有反注入/完整性校验。TrollFools 里移除注入即可恢复，换别的 App 试。

**TrollStore 装 IPA 提示签名问题**
TrollStore 会自己重签，未签名包正常可装。若报错，确认 IPA 结构是 `Payload/QingPing.app`（我们的 workflow 就是这样打的）。

---

## 想改代码后重新出包

改完 → 上传/推送 → Actions 里等新的构建 → 重新下载 artifact。dylib 更新后要重新注入一次，IPA 更新后重装即可。
