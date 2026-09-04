# ClipVault

安全优先的 macOS 剪贴板历史工具。菜单栏常驻，全局热键呼出 Alfred 式搜索面板。

原生 Swift + AppKit/SwiftUI，**零第三方依赖、零网络请求**，所有数据仅保存在本机并以 AES-256-GCM 加密落盘。

## 为什么自己写一个

日常用的剪贴板工具会把复制过的所有东西存成明文——包括不小心复制的 token、密码、内部数据。ClipVault 的出发点就是堵住这类泄露：

| 风险 | ClipVault 的做法 |
|---|---|
| 密码管理器复制的密码被记录 | 尊重 `org.nspasteboard.ConcealedType` 标记，默认跳过（1Password / Bitwarden / KeePassXC 等都会打这个标记） |
| 手滑复制的 API key / token 留在历史里 | 内置凭证格式检测（GitHub / AWS / Slack / Stripe / JWT / PEM 私钥 / Bearer / `api_key=` 等），可选**不记录**或**记录但遮罩显示**（默认遮罩，列表里只见圆点，仍可复制） |
| 历史文件被备份 / 同步 / 翻走 | 历史与图片全部 AES-256-GCM 加密后落盘，目录 `0700`、文件 `0600`；也可切换「仅内存」模式，退出即清空、磁盘零痕迹 |
| 工具本身偷偷上传数据 | 全部源码在此仓库，无任何网络代码，可审计 |
| 敏感条目被其他剪贴板工具二次记录 | 从面板复制敏感条目时会反向打上 Concealed 标记 |
| 特定应用里复制的内容不想被记录 | 排除应用名单（默认已含主流密码管理器） |

## 使用

- **⌃⇧V**（可换 ⇧⌘V / ⌥⌘V / ⌃⌘V）呼出面板，或左键点菜单栏图标
- 直接打字搜索；**↑↓** 选择，**↩** 复制，**⌘1–9** 快速复制前 9 条，**⌘⌫** 删除选中，**esc** 关闭
- 右键菜单栏图标：设置 / 清空历史 / 退出
- 可选「自动粘贴」：选中后直接粘贴到当前应用（需要辅助功能权限，默认关闭，不开也不弹窗）

## 设置项

- 历史保留时长（1 小时 ～ 30 天 / 永久）、最多条数（100 ～ 3000）
- 是否保存图片、图片大小上限（2 ～ 50 MB）、单条文本大小上限（64 KB ～ 4 MB）
- 密钥检测策略（不记录 / 遮罩 / 关闭）、Concealed / Transient 跳过开关、排除应用
- 加密落盘 ↔ 仅内存 切换、一键清空
- 开机自启、全局热键

## 安装

**方式一（推荐，同事分发用）**：从 [Releases](../../releases) 下载 `ClipVault-x.y.z.dmg`，拖进「应用程序」。
因为是 ad-hoc 签名（没花 99 美元买开发者证书），首次打开需要：**右键 App → 打开 → 打开**；或者：

```bash
xattr -d com.apple.quarantine /Applications/ClipVault.app
```

**方式二（自己构建，最放心）**：

```bash
make install   # 构建 universal 二进制、打包、安装到 /Applications
```

只需要 Xcode Command Line Tools（`xcode-select --install`），不需要完整 Xcode。

## 测试

```bash
make test   # 32 个单元测试：捕获策略、密钥检测、存储、加密、权限
make e2e    # 端到端：真实启动 App + 真实剪贴板，验证捕获/遮罩/跳过/大小限制/磁盘无明文
```

> `make e2e` 运行约 15 秒，期间会占用系统剪贴板，结束时恢复原有文本内容。

## 权限说明

- 默认**零权限弹窗**：剪贴板轮询、全局热键（Carbon `RegisterEventHotKey`）都不需要授权
- 只有主动开启「自动粘贴」才会引导授予辅助功能权限
- macOS 15.4+ 引入了剪贴板隐私提醒，系统可能提示「ClipVault 读取了剪贴板」——属正常现象，在系统设置中允许即可

## 架构

```
Sources/ClipVaultCore/   纯逻辑层（可单测，无 AppKit 依赖）
  CapturePolicy         捕获决策：Concealed/Transient/排除应用/大小/密钥策略
  SecretDetector        凭证格式启发式检测
  HistoryStore          内存历史：去重置顶、过期清理、条数限制、搜索
  EncryptedDiskStore    AES-256-GCM 加密存储（元数据 + 图片 blob）
Sources/ClipVault/       App 层
  PasteboardWatcher     NSPasteboard changeCount 轮询（350ms，可调）
  HistoryController     调度：策略→缩略图→加密落盘→回写剪贴板
  PanelController/View  浮动搜索面板（无边框 NSPanel，不抢焦点）
  HotKeyCenter          Carbon 全局热键
  SettingsWindow        设置界面
```

详细设计与威胁模型见 [DESIGN.md](DESIGN.md)。
