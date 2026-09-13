# Windows Nova Launcher V1.0（HTML + 宿主方案）开发计划

> 文档版本：V1.0
> 产品代号：Nova Launcher
> 方案代号：**方案②**（HTML 界面 + 本地宿主）
> 依据文档：`DOCS/02Windows_Nova_Launcher_V1.0_极简方案.md`（V1.0 权威功能范围）
> 参考文档：`DOCS/03Windows_Nova_Launcher_V1.0_极简方案开发计划.md`（WinUI 3 实现基线，本方案为替代实现路径）
> 验证报告：`HTML宿主方案验证报告.md`（位于项目 `.traetemp/`）
> 技术基线：PowerShell 5.1 + .NET（System.Drawing / WinForms 互操作）+ Edge(`msedge --app`) + HTML/CSS/JS
> 平台范围：仅 Windows 10 / Windows 11 x64（需 Edge 或任意可 `--app` 的 Chromium 内核浏览器）
> 编制日期：2026-09-11
> 当前状态：**方案②已完整实现并通过验证；M9 / M10 / M11 / M12 / M13 / M14 / M15 / M16 / M17 / M18 增量（依据试用反馈回归）亦已完成**

---

## 0. 为什么是「HTML + 宿主」而不是 WinUI 3

原 `03` 计划以 C# + .NET 10 + WinUI 3 为技术基线。但在本机执行时发现一条硬约束：

> 本环境**未安装 .NET SDK** 与 Windows App SDK，且 WinUI 3 的构建链路无法在此环境跑通（仅有可下载的运行时，无编译器/SDK），因此 WinUI 3 方案无法在本机构建、调试与截图验收。

V1.0 的目标是「漂亮 + 好用 + 稳定」的启动页，而非某个具体 UI 框架。于是重新评估**实现路径**，结论如下：

| 方案 | 思路 | 结论 |
|------|------|------|
| ① 自定义协议 `nova://` | 注册 URI Scheme，HTML 点击后跳转协议唤起程序 | ❌ 每次点击浏览器弹「是否允许打开」确认框，体验差 |
| ② HTML + 本地宿主（**采用**） | 一个本地 HTTP 服务同时托管页面与「启动」API，页面同源调用 | ✅ 零安装、免运行时依赖、可真正拉起 EXE/LNK |
| ③ WebView2（C# 宿主） | 用 C# 写 WebView2 宿主内嵌 HTML，最干净 | ⚠️ 需要 .NET SDK 编译，本环境同样卡在构建环节 |
| （排除）HTA | 用 `mshta.exe` 跑 HTML | ❌ 走 IE/Trident 引擎，无现代外观与 CSS |

**核心原理**：浏览器沙箱中的 JS **没有 `Process.Start`**，纯 HTML 无法启动本地程序（这是红线，无法绕过）。因此必须有一个**本地宿主进程**来「代为启动」。`方案②` 让宿主**自己把页面吐出来**（`GET /`）→ 页面与 API **同源** → 无需任何 CORS / JSONP 技巧。

> 本方案**不改变** `02` 定义的功能范围（仍是那 5~9 个功能），只是把实现载体从 WinUI 3 换成「HTML 界面 + 本地宿主」。

---

## 1. 计划目标与范围

### 1.1 一句话目标

用**零安装、免运行时**的方式，交付一个「漂亮 + 好用 + 稳定」的 Windows 快捷方式启动页：

```text
双击 .bat → 宿主起服务 → 无边框窗口显示应用 → 点击图标 Start-Process 拉起真实程序
→ 用户添加/移除/拖拽排序 → JSON 保存 → 关窗即走（25s 内宿主自退）
```

### 1.2 开发策略

视觉优先、能力逐步加，与 `03` 一致，但具体载体变为「宿主 + 网页」：

```text
M0 环境验证 → M1 宿主骨架(端口/Token/心跳) → M2 页面托管+状态API → M3 图标提取
→ M4 启动/增删/排序API → M5 界面(Mica/磁贴/抽屉/双主题) → M6 编码陷阱修复
→ M7 端到端验证 → M8 绿色版交付与验收
```

### 1.3 V1.0 交付范围（IN，与 02 对齐）

| 编号 | 功能 | 本方案实现方式 |
|------|------|----------------|
| F1 | 添加 EXE/LNK | `msedge --app` 内页面「＋添加应用」→ 宿主 `/api/pick` 调系统文件框 |
| F2 | 显示真实图标 | 宿主 `PrivateExtractIcons` 取 256px，按路径 MD5 缓存为 PNG |
| F3 | 拖拽排序 | 页面拖拽 → `/api/move` 写 `sort` |
| F4 | 调整图标大小 | 页面滑块 → `/api/setting`，即时生效 |
| F5 | 点击启动 | 页面 `fetch /api/launch` → 宿主 `Start-Process` |
| F6 | 删除应用 | 设置页移除 → `/api/remove` |
| F7 | JSON 持久化 | `%LOCALAPPDATA%\NovaLauncher\apps.json` + `settings.json` |
| F8 | 深色/浅色主题 | 页面默认深色，可切换（CSS 变量驱动） |
| F9 | 炫酷动画 | Mica 背景、圆角、Hover 放大、抽屉滑入、阴影/光晕（CSS） |

### 1.4 明确不做（OUT，与 02/03 一致）

- ❌ 安装时间 / 使用频率 / 最近使用排序与统计
- ❌ 数据库（SQLite / ORM / Repository）
- ❌ 全局搜索、全局快捷键 `Ctrl+Space`
- ❌ 系统托盘常驻、云同步、插件市场

> 注：原列为 OUT 的「自动扫描已安装软件」与「UWP / 商店应用启动」已在 V1.0 **增量实现**：
> 宿主新增 `/api/installed`，枚举「开始菜单 `.lnk` + 注册表卸载项 + `Get-StartApps`」三类来源并按路径+名称去重；
> UWP 应用以 `shell:AppsFolder\<AUMID>` 经 `explorer.exe` 拉起（见 §2.4、§7）。

### 1.5 技术选型

| 层 | 技术 | 说明 |
|----|------|------|
| 宿主语言 | PowerShell 5.1 | 系统自带，无需安装 |
| 互操作 | `Add-Type` 内联 C# | `PrivateExtractIcons` / `DestroyIcon` P/Invoke，取 256px 图标 |
| 本地服务 | `System.Net.HttpListener` | 仅监听 `127.0.0.1`，随机空闲端口 |
| 启动程序 | `Start-Process`（走 ShellExecute） | EXE / LNK 均可；UWP 快捷方式不可 |
| 界面容器 | Edge `msedge --app=URL` | 无地址栏、无边框的应用窗口；独立 `user-data-dir` |
| 前端 | 单文件 HTML + CSS + 原生 JS | Mica 背景、磁贴网格、设置抽屉 |
| 序列化 | 手写 JSON 读写 | `apps.json` / `settings.json`，替代数据库 |
| 存储 | 本地 JSON 文件 | **程序所在目录**（绿色版自包含，`$DataDir = $ScriptDir`） |

**不引入**：.NET SDK、WinUI 3、任何第三方运行时/包。

---

## 2. 架构设计

### 2.1 总体结构

```text
┌─────────────────────────────────────────────┐
│  nova-launcher.html（由宿主托管，同源）        │
│  顶栏 ✦ NOVA + ⚙  │  磁贴网格  │  设置抽屉    │
└───────────────┬─────────────────────────────┘
                │  fetch /api/* （带随机 token）
┌───────────────▼─────────────────────────────┐
│  NovaLauncher.ps1（127.0.0.1:随机端口）        │
│  ├─ HttpListener：托管页面 / 状态 / 图标 / 指令 │
│  ├─ NovaIcon：PrivateExtractIcons 取 256px     │
│  ├─ 启动：Start-Process 拉起真实程序           │
│  └─ 存储：apps.json / settings.json 读写       │
└───────────────┬─────────────────────────────┘
                │  msedge --app=http://127.0.0.1:PORT/?t=TOKEN
┌───────────────▼─────────────────────────────┐
│  无边框应用窗口（独立 BrowserProfile）          │
└─────────────────────────────────────────────┘
```

### 2.2 同源与安全模型（关键设计）

| 项 | 设计 | 原因 |
|----|------|------|
| 绑定地址 | 仅 `127.0.0.1` | 不暴露到局域网，外部无法访问 |
| 端口 | 每次启动自动选空闲端口（`Port=0`） | 避免端口冲突 |
| 鉴权 | 每次启动随机生成 `ApiToken`，所有 `/api/*` 必须带 `?t=TOKEN` | 防任意本机网页越权调用；无 token → 403 |
| 心跳 | 页面每 3s 心跳一次 | 宿主感知窗口存活 |
| 自动退出 | 超过 25s 未收到心跳 → 宿主自退 | 关窗即走，不留后台进程、不占端口 |
| 浏览器隔离 | `--user-data-dir=$DataDir\BrowserProfile` | 不影响用户日常 Edge 配置、不弹「恢复页面」 |

### 2.3 源码目录结构（实际落地）

```text
NovaLauncher.Web/
├── NovaLauncher.bat      # 入口：UTF-8 无 BOM + CRLF；chcp 65001 后隐藏启动宿主
├── NovaLauncher.ps1      # 宿主：HTTP 服务 + 图标提取 + 启动 + 存储（UTF-8 带 BOM）
├── nova-launcher.html    # 界面：Mica 背景、磁贴、设置抽屉、明暗双主题（UTF-8 无 BOM）
└── README.md             # 用法、编码要求、数据目录、FAQ
```

### 2.4 API 接口表（宿主实际提供）

| 接口 | 方法 | 说明 | 鉴权 |
|------|------|------|------|
| `/` | GET | 返回 `nova-launcher.html`（同源托管） | 无需 token |
| `/api/ping` | GET | 心跳探测 | 需 token |
| `/api/state` | GET | 返回 `apps` + `settings` 全量状态 | 需 token |
| `/api/icon` | GET | `?i=&s=`（列表应用图标）或 `?p=&s=`（任意路径图标，供已安装应用面板）返回 PNG | 需 token |
| `/api/installed` | GET | `?sort=freq\|installed\|name\|path\|kind\|src&q=` 枚举系统已安装应用（开始菜单 `.lnk` + 注册表卸载项 + `Get-StartApps`），按「路径+名称」去重；**缺省 = 按使用频率降序**；枚举结果缓存 60 s | 需 token |
| `/api/launch` | GET | `?i=` 启动第 i 个应用（`shell:*` 走 `explorer.exe`） | 需 token |
| `/api/pick` | GET | 弹系统文件框选 EXE/LNK（**独立 STA 线程**），返回路径 | 需 token |
| `/api/add` | GET | `?p=&n=&k=` 追加应用（含 `kind`，支持 `shell:*` 路径） | 需 token |
| `/api/addbatch` | POST | JSON `{"items":[{"p","n","k"}]}`，批量追加；返回 `added / addedItems / failed[{name,path,why}]` | 需 token |

> **query 解码约定**：`Get-Query` 按 `application/x-www-form-urlencoded` 语义先还原 `+`→空格、再解 `%XX`；
> 前端则统一用 `encodeURIComponent`（空格→`%20`）。两端兼容，避免含空格路径（如 `C:\Program Files\...`）被解坏（M12）。
| `/api/remove` | GET | `?i=` 移除指定应用 | 需 token |
| `/api/move` | GET | `?from=&to=` 拖拽排序，更新 `sort` | 需 token |
| `/api/setting` | GET | `?k=&v=` 更新 iconSize/cols/theme | 需 token |
| `/api/reveal` | GET | `explorer` 打开数据目录 | 需 token |
| `/api/quit` | GET | 主动退出宿主 | 需 token |

> 全部 `/api/*` 在分发前统一校验 `?t=` 与 `$script:ApiToken` 是否一致，不一致返回 403。
> 宿主按路径分发，不区分 HTTP 方法；前端统一以 GET + query 调用。

### 2.5 数据模型与契约（与 03 一致）

**apps.json**（数组，按 `sort` 升序渲染）

```json
[
  { "name": "Chrome", "path": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "sort": 0, "kind": "" },
  { "name": "计算器", "path": "shell:AppsFolder\\Microsoft.WindowsCalculator_8wekyb3d8bbwe!App", "sort": 1, "kind": "uwp" }
]
```

> `kind` 取值：`""`（手动添加）| `lnk` | `registry` | `startapp` | `uwp`；仅作来源标记，不影响渲染。
> `path` 以 `shell:` 开头表示为 UWP/商店应用，`exists` 恒为 true，启动走 `explorer.exe shell:AppsFolder\...`。

**settings.json**

```json
{ "iconSize": 80, "cols": 6, "theme": "dark" }
```

### 2.6 运行期数据目录

数据默认落在**程序所在目录**（`$DataDir = $ScriptDir`），绿色版自包含、整包可迁移：

```text
<程序目录>\
├── apps.json        # 应用列表：name / path / sort / kind
├── settings.json    # 外观：iconSize / cols / theme
├── Icons\           # 图标缓存（PNG，按路径 MD5 命名）
├── runtime.json     # 运行中的端口/token/pid（退出时自动删除，供诊断）
├── host.log         # 运行日志（含「启动：xxx.exe」证据）
└── BrowserProfile\  # 独立浏览器配置
```

---

## 3. 开发阶段与里程碑（已执行）

> 下表既为计划，也标注了实际完成情况（方案②已整体落地并通过验证）。

### M0 · 环境与可行性验证

**目标**：确认本机可零依赖跑通方案②。

| 任务 | 说明 | 状态 |
|------|------|------|
| T0.1 | 检查 Edge / Chrome / WebView2 Runtime 可用性 | ✅ 138.0.3351.95 |
| T0.2 | 确认 PowerShell 5.1 HttpListener 可用 | ✅ |
| T0.3 | 排除自定义协议方案（确认每次弹确认框） | ✅ 已排除 |
| T0.4 | 确认「页面同源托管」可规避 CORS | ✅ |

**交付物**：可行性结论 = 方案②。

### M1 · 宿主骨架

**目标**：起一个安全、会自动退出的本地服务。

| 任务 | 说明 | 状态 |
|------|------|------|
| T1.1 | `HttpListener` 绑 `127.0.0.1`，`Port=0` 自动选端口 | ✅ |
| T1.2 | 启动随机 `ApiToken`；所有 `/api/*` 校验 | ✅ |
| T1.3 | 主循环 1.5s 轮询；3s 心跳；>25s 无心跳自退 | ✅ |
| T1.4 | `runtime.json` 写端口/token/pid，退出时删除 | ✅ |
| T1.5 | `msedge --app` 打开同源 URL（独立 user-data-dir） | ✅ |

**交付物**：可启动并自退的宿主。

### M2 · 页面托管与状态 API

**目标**：浏览器同源拿到数据与页面。

| 任务 | 说明 | 状态 |
|------|------|------|
| T2.1 | `GET /` 返回 `nova-launcher.html` | ✅ |
| T2.2 | `/api/state` 返回 apps+settings | ✅ |
| T2.3 | 中文参数乱码修复（`Get-Query` 走原始 query + `UnescapeDataString`） | ✅ |

### M3 · 真实图标提取

**目标**：清晰图标，不卡首屏。

| 任务 | 说明 | 状态 |
|------|------|------|
| T3.1 | `Add-Type` 内联 C# 调 `PrivateExtractIcons`（256px，回退 128/96/…/32） | ✅ |
| T3.2 | 按路径 MD5 缓存为 PNG 落 `Icons\` | ✅ |
| T3.3 | 添加时预热图标缓存；页面 `<img>` + 兜底字符 | ✅ |

### M4 · 启动 / 添加 / 移除 / 排序 API

| 任务 | 说明 | 状态 |
|------|------|------|
| T4.1 | `/api/launch` → `Start-Process`（ShellExecute，EXE/LNK 通用） | ✅ |
| T4.2 | `/api/pick` 调系统文件框选 EXE/LNK | ✅ |
| T4.3 | `/api/add` `/api/remove` `/api/move` 维护 apps.json | ✅ |
| T4.4 | `Get-Apps` 单元素数组强制 `,@($list)` 防拆包成标量 | ✅ |

### M5 · 界面（视觉与交互）

| 任务 | 说明 | 状态 |
|------|------|------|
| T5.1 | Mica 背景 + 顶栏 `✦ NOVA` + 设置齿轮 | ✅ |
| T5.2 | 磁贴网格（默认 6 列，自适应） | ✅ |
| T5.3 | 设置抽屉滑入：添加/移除/大小滑块/列数/主题 | ✅ |
| T5.4 | 深色/浅色双主题（CSS 变量切换） | ✅ |
| T5.5 | Hover 放大、圆角、阴影、背景光晕、`Esc` 关抽屉 | ✅ |
| T5.6 | 演示模式：直开 HTML 走内置示例，不启动任何程序 | ✅ |

### M6 · 编码与运行陷阱修复（本方案特有）

| 任务 | 说明 | 状态 |
|------|------|------|
| T6.1 | `.ps1` 必须 **UTF-8 带 BOM**（PS 5.1 否则按 GBK 解码中文注释→语法错误） | ✅ |
| T6.2 | `.bat` 必须 **UTF-8 无 BOM + CRLF**（带 BOM cmd 报错；LF 下中文注释被当命令执行） | ✅ |
| T6.3 | 中文应用名乱码 → `Get-Query` 走原始 query + `UnescapeDataString` | ✅ |
| T6.4 | 高 DPI 截图裁切 → 补 `SetProcessDPIAware()` | ✅ |

### M7 · 端到端验证

| 任务 | 说明 | 状态 |
|------|------|------|
| T7.1 | 接口 curl 7 项（页面/403/状态/添加/图标…） | ✅ 全过 |
| T7.2 | 真实启动证据：`host.log` 记录 `启动：notepad.exe` 等 | ✅ |
| T7.3 | 4 张截图（真实窗口深色 / 抽屉深色 / 浅色大图标 / 抽屉浅色） | ✅ |

### M8 · 绿色版交付与验收

| 任务 | 说明 | 状态 |
|------|------|------|
| T8.1 | `NovaLauncher.bat` 双击即用（隐藏控制台） | ✅ |
| T8.2 | `README.md` 写明用法/编码/数据目录/FAQ/演示模式 | ✅ |
| T8.3 | 验收清单逐项过（见 §6） | ✅ |
| T8.4 | 过程复盘沉淀为可复用 Skill `windows-html-native-launcher` | ✅ |

### M9 · V1.0 增量（依据试用反馈回归）

> 依据主人实际试用反馈增补：修「添加应用报错」、数据目录改到程序目录、拖拽添加、已安装应用面板。

| 任务 | 说明 | 状态 |
|------|------|------|
| T9.1 | 修「添加应用报错」：文件框改在独立 STA 线程弹出（原在 MTA 回调里 `ShowDialog` 抛错） | ✅ |
| T9.2 | 数据目录默认 = 程序执行目录（`$DataDir = $ScriptDir`，绿色版自包含） | ✅ |
| T9.3 | 文件拖入窗口即添加（`dataTransfer.items[].webkitGetAsEntry().fullPath`） | ✅ |
| T9.4 | 新增 `/api/installed` + 「从已安装应用添加」面板（搜索 / 四维排序 / 批量勾选） | ✅ |
| T9.5 | UWP / 商店应用支持：`shell:AppsFolder` 经 `explorer.exe` 启动 | ✅ |
| T9.6 | 已安装应用多来源去重（路径 + 名称）与 `.exe` 目标过滤 | ✅ |
| T9.7 | 宿主环境变量被裁剪时枚举不崩（`GetFolderPath` 替代 `$env:`） | ✅ |
| T9.8 | 回归验证：`/api/installed` 273 项、重复 0、添加/图标/kind 全过；4 张新截图 | ✅ |

### M10 · 已安装应用排序增强（使用频率 / 安装时间）

> 依据主人二次反馈增补：「从已安装应用添加」默认按使用频率排序，并增加安装时间排序。

| 任务 | 说明 | 状态 |
|------|------|------|
| T10.1 | 新增 `Get-UsageIndex`：`UserAssist`（ROT13 值名，偏移 4 处取 DWORD 启动次数）+ `FeatureUsage\AppSwitched / AppLaunch` 计数，索引键含「全路径 / 文件名 / AUMID」 | ✅ |
| T10.2 | 新增 `Get-InstallInfo`：注册表卸载项 `InstallDate` → 目标 exe `CreationTime` → UWP 包目录 `CreationTime` 三级回退 | ✅ |
| T10.3 | `Get-InstalledApps` 为每条记录附加 `freq` / `installedAt` / `installedRaw` 字段 | ✅ |
| T10.4 | `/api/installed` 新增 `sort=freq`（降序，**缺省**）与 `sort=installed`（新→旧，未知排最后） | ✅ |
| T10.5 | 前端下拉新增「按使用频率 / 按安装时间」并设为默认；每行显示「用过 N 次 · 安装日期」 | ✅ |
| T10.6 | 新增 `Get-InstalledAppsCached`：枚举结果缓存 60 s，避免改排序 / 搜索时全量重扫 | ✅ |
| T10.7 | 回归验证：273 项中 63 项有非零频率、217 项有安装日期；`freq`/`installedRaw` 均严格降序；字段缺失 0；2 张新截图 | ✅ |
| T10.8 | 修并行编辑覆盖事故：同一文件的两处编辑改为一前一后提交 | ✅ |

> 实测样例（本机）：频率榜 `终端 2012 次` > `Adobe Premiere Pro 2025 1327` > `微信 952`；
> 安装时间榜最新为 `ChatGPT / 手机连接 2026-09-12`。

### M11 · 勾选交互调整（默认全不选 + 全选 / 全不选）

> 依据主人三次反馈增补：打开面板时**默认一项都不勾选**，并在底部提供全选与全不选。

| 任务 | 说明 | 状态 |
|------|------|------|
| T11.1 | 复选框默认值由 `!already`（默认勾上）改为 `false`：打开面板零勾选，避免误触「添加选中」一次灌入几百项 | ✅ |
| T11.2 | 底部新增「全选 / 全不选」按钮（复用既有 `.btn-ghost`，加 `.modal-foot` 内 `width:auto` 覆盖） | ✅ |
| T11.3 | 底部提示改为实时计数：`273 个已安装应用 · 已选 268 个`（零勾选时提示「勾选后点「添加选中」」） | ✅ |
| T11.4 | 「全选」自动跳过已添加项（`checkbox` 为 `disabled`），不会把已添加的重复加一遍 | ✅ |
| T11.5 | 批量添加成功后当场把该行置灰为「已添加」，防止重复勾选 | ✅ |
| T11.6 | 回归验证：默认 `checked=0`；全选 `268/273`（跳过 5 项已添加）；全不选回到 0；改搜索后新结果集仍默认零勾选；2 张新截图 | ✅ |

### M12 · 批量添加丢项修复（URL 编码 + 失败可见性）

> 依据主人第四次反馈：在「从已安装应用添加」里勾选 **10 个，只有 3 个真的进了列表**。

| 任务 | 说明 | 状态 |
|------|------|------|
| T12.1 | **根因定位**：前端 `apiGet` 用 `URLSearchParams` 拼 query，按 `application/x-www-form-urlencoded` 规则把**空格编成 `+`**；宿主 `Get-Query` 却用 `[uri]::UnescapeDataString` 解码（**只认 `%XX`、不认 `+`**），于是 `C:\Program Files\...` 被解成 `C:\Program+Files\...` → `Test-Path` 失败 → 该条被**静默丢弃**。全机 **130/273** 个已安装应用路径含空格，故大面积丢项。旁证：图标请求用 `encodeURIComponent`（空格→`%20`）一直正常，故图标能显示、添加却丢 | ✅ |
| T12.2 | 宿主端修复：`Get-Query` 先 `Replace('+',' ')` 再 `UnescapeDataString`（标准 form-urlencoded 语义）；真 `+` 传来的是 `%2B`，该顺序不会误伤文件名含 `+` 的情况 | ✅ |
| T12.3 | 前端端修复：`apiGet` 弃用 `URLSearchParams`，改为自写 `encodeQuery()`（一律 `encodeURIComponent`，空格→`%20`），与 `/api/icon` 编码方式统一 | ✅ |
| T12.4 | 新增 `POST /api/addbatch`（JSON body）＋ `Read-JsonBody`：一次请求、逐项落盘，返回 `added / addedItems / failed[{name,path,why}]` | ✅ |
| T12.5 | 前端「添加选中」与拖拽添加改走批量接口；**失败行标红**（`.irow.failed`）并在 toast 中列出失败原因，不再静默吞掉 | ✅ |
| T12.6 | 回归验证：A 旧 `+` 编码单条 → `ok=true`；B 批量 10 个（**路径全部含空格**）→ `added=10, failed=0`，apps 14→24；C 混入坏路径 → `added=1, failed=1` 且原因为「文件不存在」；D 重复提交同一批 → 计数不增长。UI 实测：勾选 10 个 → 点「添加选中」→ `failed=0`、apps **+10**；2 张新截图 | ✅ |

### M13 · 每行图标数扩展到 12（自适应列宽）

> 依据主人第五次反馈：一屏想放更多图标，**每行要能排到 12 个**。

| 任务 | 说明 | 状态 |
|------|------|------|
| T13.1 | 设置项「每行图标数」由 4~8 扩到 **4~12**（`#colsSel` 新增 9 / 10 / 11 / 12 四档） | ✅ |
| T13.2 | 宿主 `/api/setting` 的 `cols` 夹取上限由 `Min(10,…)` 提到 `Min(12,…)`——否则前端给了 12，服务端会**静默压回 10** | ✅ |
| T13.3 | **关键**：网格列宽由固定 `calc(var(--icon-size) + 40px)` 改为 `minmax(0, calc(...))`。原公式下 12 列 × 104px 图标需 1728px，远超 `--window-size=1180` 的可用宽度 → 必然横向溢出；改后列宽按可用宽度**自动收缩**：4~8 列维持原尺寸，9~12 列等比压缩 | ✅ |
| T13.4 | 图标盒改 `width:min(100%, var(--icon-size))` + `aspect-ratio:1`，并加 `container-type:inline-size`，字形兜底字号改用 `42cqw`：列宽被压到比设定图标还窄时，图标与字形一起缩小，不会互相压盖 | ✅ |
| T13.5 | 回归验证：`--cols=12` 时 `trackCount=12`、**首行实测 12 个**、`gridScrollW == gridClientW`（无横向溢出）、图标盒 104→79px 自动收缩；API `cols=99 → 12`（上限夹取生效）；下拉框真实切换 10 → `--cols:10`、切回 12 → `--cols:12` 并落盘；深色 / 浅色 / 设置面板各 1 张截图 | ✅ |

> 实测（浏览器视口 1202px 宽）：12 列时单格 93px、图标盒 79px，`settings.json` 落盘 `cols: 12`。

### M14 · 拖拽排序落盘修复 + 图标与名字强绑定（依主人「测试拖拽排序，名字不能变、图标要与名字一一对应」）

> 实测结论：**拖拽排序从上线起就没真正保存过**；界面照常重排 → 与 `apps.json` 的真实顺序分叉 →
> 图标（当时按行号 `?i=N` 取）与名字整体错位。主人看到的「名字/图标对不上」即此。

| 任务 | 说明 | 状态 |
|------|------|------|
| T14.1 | **根因一（致命）**：`/api/move` 里写的是 `$apps = @(Get-Apps)`。`Get-Apps` 用 `return ,@($list)` 保持数组形态，而 **`@()` 包裹「返回数组的函数调用」得到的是「1 个元素」的数组**（唯一元素是那个数组本身）→ `$apps.Count` 恒为 1 → 校验 `$to -ge 1` 一律成立 → **每次拖拽都被判「索引越界」**，顺序永远写不回 `apps.json`。实测：`$a=f` → `.Count=3`；`@(f)` → `.Count=1`；`@($a)` → `.Count=3` | ✅ |
| T14.2 | 宿主修复：改为 `$apps = Get-Apps` ＋ `$n = @($apps).Count`（对「变量」用 `@()` 才安全），并把这段陷阱写进注释 | ✅ |
| T14.3 | **根因二（放大器）**：前端 `dragend` 只 `await API.move(...)`，**不检查 `ok`**。宿主返回 `ok:false` 时界面照样本地重排 → 界面与落盘分叉。改为 `ok === false` 即抛错，并在 `catch` 里 `refresh()` 拉回宿主真实顺序 + toast 报错（失败可见，延续 M12 原则） | ✅ |
| T14.4 | **结构性修复**：主界面图标由「按行号」`/api/icon?i=N` 改为**按路径** `/api/icon?p=…`（宿主早已支持）。行号会随排序变化，一旦任何环节让界面顺序与落盘顺序不一致，按行号取图必然错位；按路径取时，图标与标签来自**同一个 app 对象**，天然一一对应 | ✅ |
| T14.5 | `shell:`（UWP/商店）应用直接返回 `null` 走字形兜底，不再白发一次 404 请求 | ✅ |
| T14.6 | 回归验证（宿主 8799 + 真实浏览器）：接口 `move 0→4` → `{"ok":true}` 且文件顺序同步变化；合成「真实鼠标式」拖拽（dragstart → 沿直线 10 帧 dragover → drop → dragend）四例：①第1格→第5格落点=第4格 ②最后一格→第1格落点=第1格 ③第1格→最后一格落点=第19格 ④拖到自己=无变化；每例都断言 **界面顺序==前端内存顺序==apps.json 顺序**；每例后逐个磁贴做**图标哈希比对**（把磁贴上的图片画进 canvas 取哈希，与「该磁贴名字对应应用的图标」比对）→ **19/19 一致，0 错位**；刷新页面后顺序与图标依然一致 | ✅ |

> 证据：`.traetemp\截图\20260912-拖拽排序\`（拖拽前 / 拖拽后 / 刷新后）。
> 3 个应用（终端、记事本(商店版)、DeepSeek+Harness）路径为 `shell:AppsFolder\…`，无本地图标 → 走彩色字形兜底，属预期。

---

### M15 · 屏蔽主界面右键菜单（依主人「主界面要屏蔽右键菜单」）

> 实测结论：**右键菜单是浏览器的原生 UI，不在 DOM 里**，Edge/Chromium **没有**关闭它的启动参数，
> 因此只能在页面侧拦 `contextmenu` 事件。

| 任务 | 说明 | 状态 |
|------|------|------|
| T15.1 | 在 `document` 上注册 **capture 阶段**的 `contextmenu` 监听：`preventDefault()` ＋ `stopPropagation()`。capture 阶段最先拿到事件，无需等冒泡到目标就能截断，对磁贴/网格/角标/面板一律生效 | ✅ |
| T15.2 | **放行可编辑文本控件**：`isEditableTarget()` 判定 `textarea` / `contenteditable` / `input` 的 text·search·url·email·password·tel·number 类型。若一刀切全屏蔽，搜索框的**右键粘贴、拼写检查**会一起失效（`range` 等非文本输入不在放行之列） | ✅ |
| T15.3 | 回归验证（宿主 8799 + 真实浏览器）：在 `document` 挂**最末尾**的冒泡监听回读 `defaultPrevented`，对四处各合成一次 `contextmenu`（`cancelable:true`）→ 磁贴 `true`／网格 `true`／顶部角标 `true`（均已拦截）、搜索框 `false`（已放行）；`isEditableTarget` 自检 `[搜索框 true, 磁贴 false, body false, 滑杆 false]`；页面 19 个磁贴正常渲染、无 JS 报错 | ✅ |
| T15.4 | 说明：被拦截的事件因 `stopPropagation` **不会冒泡到 document**，所以末尾的冒泡监听只会收到「被放行」的那一条——这本身即是拦截生效的旁证（而非漏测） | ✅ |

> 证据：`.traetemp\截图\20260912-右键屏蔽\01-右键屏蔽验证.png`（深色主界面，19 个应用，界面无异常）。

---

### M16 · 无边框全屏 + 右上角窗口三键（依主人「主界面打开后要全屏显示，右上角增加最小化、最大化和关闭3个图标」）

> 关键认知：**网页不能直接控制浏览器窗口**。`window.close()` 只对脚本打开的窗口有效、
> `resizeTo/moveTo` 受安全限制且改不了标题栏——必须由**宿主**代为操作 Win32 窗口，
> 页面通过 HTTP 把「最小化/最大化/关闭」请求交给宿主。
>
> 也**不能用** `--start-fullscreen`：那是浏览器自身的全屏态（F11），宿主读不到、也无法与
> 页面的状态机同步；`--kiosk` 又会连退出通道一起禁掉（退出困难）。

> ⚠ **后续调整（见 M19）**：本节当时的「铺满整屏（`Bounds`）」在 M19 已改为「铺满**工作区**（`WorkingArea`，任务栏可见）」，
> 并额外把 Chromium **自绘的那条标题栏**挪出屏幕；`$script:FsApplied` 亦已更名为 `$script:MaxApplied`。

| 任务 | 说明 | 状态 |
|------|------|------|
| T16.1 | 宿主内新增 `NovaWindow` P/Invoke 类：`GetWindowLong`/`SetWindowLong`（`GWL_STYLE`）、`SetWindowPos`（**必须带 `SWP_FRAMECHANGED`**，否则改了样式不生效，要等下一次真实改尺寸）、`IsWindow`/`IsWindowVisible`/`IsIconic`、`GetWindowThreadProcessId`、`EnumWindows`、`GetForegroundWindow`、`ShowWindow`、`PostMessage(WM_CLOSE)` | ✅ |
| T16.2 | 窗口定位靠 **`EnumWindows` 按标题 + 浏览器进程名白名单**（`msedge`/`chrome`）匹配，而不是 `$proc.MainWindowHandle`——Edge 常把新窗口交给**已存在**的浏览器进程，启动进程本身可能立刻退出，`MainWindowHandle` 恒为 0。多个同名窗口时**优先取当前前台窗口**（用户刚点的那一个） | ✅ |
| T16.3 | `/api/win` 接口，`op=min`（`ShowWindow SW_MINIMIZE`）/ `op=max`（在「无边框全屏 ↔ 带标题栏窗口化」间切换）/ `op=close`（`PostMessage WM_CLOSE`，走正常关闭流程触发前端心跳中断）/ `op=state`（只读，返回 `minimized`/`fullscreen`/`windowed`，供前端同步按钮图标）。无边框 = 去掉 `WS_CAPTION | WS_THICKFRAME`，再把 `SetWindowPos` 铺满该屏幕 `Bounds` | ✅ |
| T16.4 | **惰性应用全屏，不在启动阶段死等**：首开浏览器要新建 `user-data-dir`，可能远超原来 6 秒的等待窗口；死等会把 HTTP 服务一起卡住（页面永远停在「连接中…」）。改为在「空闲节拍（每 1.5s）＋页面首次拉状态＋心跳」三处各试一次，拿到句柄就切；`$script:FsApplied` 保证**只切一次**，之后用户手动「还原为窗口」不会被抢回全屏 | ✅ |
| T16.5 | 前端：标题栏右侧加 `.wctrl` 三键（`#winMin`/`#winMax`/`#winClose`，SVG 线条图标），`body:not(.hosted)` 时整组隐藏（纯静态打开不显示死按钮）；`API.win(op)` 走同源 `/api/win`；`#winMax` 按 `state` 切换「最大化/还原」两个 SVG；加载后先拉一次 `op=state` 同步图标 | ✅ |
| T16.6 | 回归验证：启动后 **3 秒内自动进入无边框全屏**（`op=state` 回读 `fullscreen`；窗口矩形 `0,0 2561x1440` ＝整块 2560×1440 屏）；`min` → `minimized`、`max`（还原）→ `windowed`、再 `max` → `fullscreen`、`close` → 窗口销毁且宿主因心跳中断自动退出；前端三键渲染与接线正确、`body.hosted` 生效 | ✅ |
| T16.7 | 已知限制：本会话环境**无法截真实窗口图**（`Graphics.CopyFromScreen` 报「句柄无效」——拿不到交互桌面），故以「Win32 直接读出的窗口矩形」作为无边框全屏的客观证据 | ⚠️ |

> 证据：`op=state` 状态机回读（`fullscreen`/`windowed`/`minimized`）+ 窗口矩形 `0,0 2561x1440`；
> 前端三键验证输出见 `.temp\ui\winbtns.js` 执行结果。

---

### M17 · 精简主界面文案（依主人「去掉主界面上的『我的应用』以及说明性的文字，以及下方的『19 个应用』和排序与保存等文字，全部去掉」）

> 设计取向：主界面只留**图标 + 名字**，做成 Nova Launcher 那种干净桌面。
> 功能信息不靠文字承载——失效应用由磁贴自身标红（`.tile.missing` 的 `::after` 角标 + 红色名字）呈现，
> 与文件是否存在的真相同源，比底部一行汇总更不容易失真。

| 任务 | 说明 | 状态 |
|------|------|------|
| T17.1 | 删除主区 `.hero` 区块（`<h1>我的应用</h1>` ＋ 说明行「拖拽图标排序 · 点击启动 · 也可把程序直接拖进窗口添加」） | ✅ |
| T17.2 | 删除主区底部 `<div class="hint" id="hint">` 一并其 JS 写入逻辑（原「共 N 个应用 · 顺序已保存」＋「N 个路径失效」），`hintEl` 变量同步移除，不留空引用 | ✅ |
| T17.3 | 顺带清掉 `.hero` 的 CSS 规则；`.main` 顶距由 `6px` 调 `18px` 补回视觉呼吸位（原由 hero 的 `margin` 提供） | ✅ |
| T17.4 | 空状态（0 应用时才有）压成一行：保留 `＋` 与「还没有任何应用」，去掉三段操作说明——正常有应用时不出现，但完全空白会失去可发现性 | ✅ |
| T17.5 | 回归验证（宿主 8799 + 真实浏览器）：`.hero` 已移除 ✓、`#hint` 已移除 ✓；主区可见文本仅剩 19 个应用名；禁用词（我的应用／个应用／顺序已保存／拖拽图标排序／路径失效／点击右上角设置）**零命中**；19 个磁贴正常渲染；首个磁贴距主区顶 22px；无 JS 报错 | ✅ |

> 证据：`.traetemp\截图\20260912-精简主界面\01-主界面无标题文案.png`（主界面仅标题栏 + 图标网格）。
> 未改动项：设置抽屉内的分区标题 `<h3>我的应用</h3>`（那是面板内的**分区标签**，与「外观」并列，属功能区分而非主界面装饰），
> 以及标题栏的 `NOVA` 标记与连接状态指示（后者是断连预警，保留；显示形式于 M18 改为圆点）。

---

### M18 · 连接状态改为圆点指示（依主人「已连接宿主文字改为绿色图标，未连接改为红色图标并提示未连接宿主；正常时没有文字提示」）

> 设计取向：**正常态不出文字**，用一个绿点表达「一切正常」；只有异常（未连接）才升级为「红点 + 文字」。
> 这样界面在 99% 的时间里是干净的，而一旦断连又能被一眼注意到。

| 任务 | 说明 | 状态 |
|------|------|------|
| T18.1 | 标题栏角标由文字 `<span class="badge">已连接宿主</span>` 改为 **`<i class="dot">` + `<span class="badge-txt">`** 结构，用 `data-state` 驱动样式（`pending` / `online` / `offline`），颜色与文字**同源**于一个状态字段，避免「颜色和文字各改一处走岔」 | ✅ |
| T18.2 | 主题变量补 `--ok` / `--ok-glow` / `--danger-glow`：深色 `#57d98a`，浅色 `#1aa35a`（与既有 `--danger` 的明度取向对齐），圆点带 4px 同级光晕让状态在满屏 2560px 下也看得清 | ✅ |
| T18.3 | 状态语义：`online` → 绿点、**文字 `display:none`**；`offline` → 红点 + 文字「未连接宿主」+ 红色描边药丸底 + **`conn-pulse` 呼吸动画**（断连需要主动吸引注意）；`pending` → 灰点、无文字（转瞬即逝的中间态） | ✅ |
| T18.4 | 前端新增 `setConn(state, title)` 单一入口；`init()` 三处分支改走它（宿主正常 → `online`；直接打开 HTML → `offline`；请求异常 → `offline`）。`title` 保留细粒度说明（如「宿主已退出或无法访问」），**不占视觉空间但悬停可查** | ✅ |
| T18.5 | 心跳兼作**存活探测**：原 `API.ping()` 是 fire-and-forget（`.catch(()=>{})`），现在按响应结果回调 `connOk()` / `connFail()`；**连续失败 2 次才翻红**，避免网络/GC 抖动造成误报 | ✅ |
| T18.6 | 回归验证（宿主 8799 + 真实浏览器 + 直接打开 HTML）三态：① `online` → 圆点 `rgb(87,217,138)`、无动画、文字 `display:none`、角标可见文本为空；② 调 `/api/quit` 让宿主退出后等 9s → 圆点 `rgb(255,138,138)`、`conn-pulse` 动画、可见文本「未连接宿主」；③ `file://` 直接打开（演示模式）→ 同为红点 + 「未连接宿主」 | ✅ |

> 证据：`.traetemp\截图\20260912-连接状态指示\`（`01-已连接-绿点无文字.png` 为 4 倍放大图，可见绿点与光晕、无任何文字；
> `02-未连接-红点带提示.png`、`03-演示模式-红点带提示.png`）。
> 说明：圆点尺寸曾设 9px，满屏 2560px 下偏小、辨识度不足，遂调为 **11px** 并加强光晕。

---

### M19 · 最大化（非全屏）+ 隐藏浏览器自绘标题栏（依主人「系统启动时不要全屏，要最大最大化展示系统的。最上边的标题栏去掉。也就是 launcher 文字的底下的标题栏要去掉」）

> 设计取向：**「最大化」= 铺满工作区、任务栏照常可用**，不是 `Bounds` 全屏；屏幕最顶端必须**只剩页面自己的 NOVA 标题栏**。
> 关键发现（本轮最有价值的一条）：去掉 `WS_CAPTION` 之后**仍然有一条标题栏**，而它**不是 Windows 画的** ——
> 是 Chromium 在客户区顶部自绘的 Windows 10+ custom titlebar（内容是页面标题 + 最小化/最大化/关闭三键）。
> 它不受 Win32 样式控制，也**没有开关能关掉**。所以「去标题栏」这件事在本方案里要分两层做：
> ① Win32 层去掉系统边框；② 再把浏览器自绘的那一条**从屏幕上挪走**。

| 任务 | 说明 | 状态 |
|------|------|------|
| T19.1 | 术语与实现从「全屏」改为「最大化」：`Set-NovaWinFullscreen`→`Set-NovaWinMaximized`、`Invoke-StartupFullscreen`→`Invoke-StartupMaximize`、`$FsApplied`→`$MaxApplied`、窗口状态值 `'fullscreen'`→`'maximized'`（前端 `applyWinChrome` 同步），逐个替换调用点并 grep 复核，避免新旧命名混用 | ✅ |
| T19.2 | 铺满**工作区**而非整屏：`Set-NovaWinMaximized` 取 `Screen.WorkingArea`（已扣任务栏）；`Bounds` 才是全屏、会把任务栏一起盖住。实测窗口底边 = 工作区底边 1368，任务栏（1368→1440）完全可见可用 | ✅ |
| T19.3 | 隐藏浏览器自绘标题栏：把窗口整体**上移该栏高度**、高度同步加回（**底边保持不动**）→ 那条栏被顶到屏幕上边缘之外，屏幕 y=0 直接就是页面自己的 NOVA 栏。高度**不写死**，由页面回报 `window.innerHeight` 反推 | ✅ |
| T19.4 | 高度反推要点：`高 = 客户区高 − innerHeight × 尺度系数`；系数取决于**宿主进程是否 DPI 感知**（`IsProcessDPIAware`，只查询无副作用）—— 感知时为 `devicePixelRatio`（150% 缩放即 1.5），不感知时系统已把 Win32 坐标虚拟化成逻辑像素、与 CSS 像素同尺度，系数为 1。实测本机宿主不感知 → 系数 1 → 算出 **29 逻辑像素**（≈43.5 物理像素）。算不出合理值（负数或 &gt; 200）就**放弃偏移**：宁留一条栏，也不要页面被推掉一截 | ✅ |
| T19.5 | 契约扩展：`/api/state`、`/api/ping` 增加 `ih` / `dpr` 上报；`/api/win?op=state` 回包增加 `bar`（自绘标题栏高度），便于外部直接排查「栏藏住没有、算得对不对」 | ✅ |
| T19.6 | 顺手修一个**真 bug**：`Start-Process -ArgumentList` 传**数组**时，PS 5.1 会把 `'--user-data-dir=' + 路径` 拆成两段（`=` 后凭空多一个空格），浏览器收到**空值** → 退回**用户自己的 Chrome 配置**：`BrowserProfile` 建不出来、书签/扩展/登录态被借走。改为拼**整条命令行字符串**传入后修复（实测 `BrowserProfile` 正常生成） | ✅ |
| T19.7 | 回归验证：`/api/win?op=state` → `{state:"maximized", bar:29}`；窗口矩形 `0,-44 2561×1412`（底边 1368 = 工作区底边）；`max` ⇄ `maximized` 往返后偏移保持；整屏截图确认「顶部只有 NOVA 栏 + 底部任务栏在」 | ✅ |

> 证据：`.traetemp\截图\20260912-最大化去标题栏\`
> - `01-窗口实拍-浏览器自绘栏占窗口0至43行.png`：`PrintWindow` 抓窗口，可见那条自绘栏（含「Nova Launcher」与三键）占窗口第 0–43 行；
> - `02-改造前对比-自绘栏正好落在屏幕可见区.png`：改造前同尺寸抓图，那条栏正好压在屏幕最上方（即主人要删的那条）；
> - `03-窗口几何与自绘栏边界-关键数据.txt`：窗口矩形 `0,-44 2561×1412`（**底边 1368 = 工作区底边**）+ 自绘栏第 0–43 行 → 映射到屏幕 y = −44..−1，**完全在屏幕之上**；屏幕 y=0 即窗口第 44 行 = 页面内容；
> - `NovaLauncher.Web\host.log`：「浏览器自绘标题栏高度 = 29 px（客户区=904 innerHeight=875 dpr=1.5 感知=False）」。
> - 会话前半段抓屏可用时，整屏实拍已直接确认「顶部只有页面自己的 NOVA 栏、底部任务栏可见（18:00 / 2026-09-12）」；
>   后半段本机 `BitBlt` 抓屏失效（连试 8 次均返回 `False`，见 `04-抓屏能力探测日志.txt`），故最终归档以**窗口几何**为准 —— 底边贴合工作区底边证明任务栏未被遮挡，栏所在行映射为负屏幕坐标证明它已不在可见区。
>
> 试过并**否掉**的方案：`--disable-windows10-custom-titlebar`（实测无效，那条栏照画，只是按钮换成 Chrome 风格）、
> `--kiosk`（能真正无边框，但等于全屏、盖住任务栏，且 `--kiosk="url"` 这种写法加载不出页面）。

---

### M20 · 启动置前 + 图标右键移除 + 拖入快捷方式（依主人「从软件上打开的应用程序要显示在前端，不能藏在软件的后端。在图标上点右键，可以选择移除该快捷方式。软件要支持快捷方式的拖入并增加图标。」）

> 三条需求分别对应三个独立问题，其中最值得记的是两条**平台事实**：
> ① 由**后台进程**拉起的应用，新窗口拿不到前台资格，会老老实实停在我们这个铺满工作区的窗口后面；
> ② 浏览器出于安全**不会暴露拖入文件的绝对路径**，`webkitGetAsEntry().fullPath` 只给得到文件名。

| 任务 | 说明 | 状态 |
|------|------|------|
| T20.1 | 启动后置前：`Launch-App` 启动前**快照**所有「可见 + 有标题 + 尺寸像正常窗口」的顶层窗口，启动后轮询取**差集**，新出现的那个就是本次拉起的应用窗口。用差集而非按进程找 —— `.lnk` 要经 shell 中转、`shell:AppsFolder`（UWP）交给 explorer 拉起，`-PassThru` 拿到的进程往往不是真正拥有窗口的那个 | ✅ |
| T20.2 | 置前分两层做，别混为一谈：**A「显示在最前」（z 序）不需要任何权限**，用 `SetWindowPos(HWND_TOPMOST)` 再取消 `HWND_NOTOPMOST`（带 `SWP_NOMOVE\|SWP_NOSIZE`，不动 M19 的上移偏移），窗口必落在所有非置顶窗口之上；**B「拿到键盘焦点」**才受前台锁限制，依次用 `PeekMessage` 建消息队列 → `AttachThreadInput` 借前台线程资格 → 临时清零 `SPI_SETFOREGROUNDLOCKTIMEOUT`（随后还原）→ 仍失败则轻敲一次 ALT（补上「刚收到过用户输入」这条硬条件） | ✅ |
| T20.3 | 目标选取与收尾：优先「进程就是被启动的那个」，同档取**面积最大**（启动闪屏通常明显小于主窗口，后出现的主窗口自然胜出，无需特意等待）；命中后再观察 0.7s 让主窗口取代闪屏；最后再压一次焦点（有些应用初始化完会自己抢一次）。已运行的单实例应用不产生新窗口 → 启动进程很快退出时提前收工，不干等满超时 | ✅ |
| T20.4 | 图标右键菜单：自绘三项目（**打开 / 打开文件位置 / 移除快捷方式**），标题行显示应用名；移除做成**菜单原地二次确认**（第一次点变色为「再点一次确认移除」，不做弹窗也不误删）。位置贴边时自动翻到另一侧 | ✅ |
| T20.5 | ⚠ 承接 M15：全局右键拦截是 **capture 阶段 + `stopPropagation()`**，冒泡阶段挂在图标上的监听器**永远收不到事件** —— 菜单触发必须并入同一个 `contextmenu` 处理器（并放行菜单自身、放行可编辑控件） | ✅ |
| T20.6 | `/api/reveal` 扩展：带 `i` / `p` 时用 `explorer.exe /select,"路径"` **定位并选中**该快捷方式；不带参数保持原行为（打开数据目录）。商店应用（`shell:AppsFolder`）明确提示「没有可定位的文件」，不假装成功 | ✅ |
| T20.7 | 拖入真正可用：前端改为同时上报**路径 + 文件名**（`p` / `n`），宿主演进到「按名称解析」—— 在**用户桌面 / 公共桌面 / 用户与所有用户开始菜单（递归）/ 开始菜单 Programs / 快速启动 / 下载**里按文件名建索引（缓存 60s），命中优先取 `.lnk`；名字对不上时退一步按**基名**匹配（拖来 `Chrome.exe`、桌面只有 `Chrome.lnk` 也能接上）。索引一次建好 248 条，实测解析命中 | ✅ |
| T20.8 | 解析兜底与诚实失败：`Resolve-AppRef` 外层包 try/catch（**解析牵扯文件系统枚举，任何意外都不该把请求打成 500**，最差也要能回一句「没找到」）；解析失败时的原因写清楚「已查桌面 / 开始菜单 / 快速启动 / 下载，可改用「添加应用」手动选择」 | ✅ |
| T20.9 | 顺手修一个**真 bug（会 500）**：`Get-ShortcutSearchRoots` 里用 `Join-Path $env:APPDATA ...` 拼快速启动 / 下载目录 —— **本机环境里 `$env:APPDATA`、`$env:USERPROFILE` 是空的**，`Join-Path` 收到空 Path 直接抛「无法将参数绑定到参数"Path"，因为该参数是空值」，整个 `/api/addbatch` 500。改用 `[Environment]::GetFolderPath()`（走 shell API，这些环境下仍返回正确路径）+ `Join-Safe` 空值护栏 | ✅ |
| T20.10 | 回归验证（宿主侧，`/api` 层）：置前 `appZ=0 < novaZ=1`；名称解析 → 真实快捷方式；不存在名字 → `failedCount=1` 且 HTTP 200；绝对路径分支正常；`/api/reveal?i=` 正常 | ✅ |
| T20.11 | 回归验证（页面侧，CDP 真实交互）：右键 `.tile` → 菜单打开且标题为应用名、三项目正确；点一次「移除快捷方式」→ 文案变「再点一次确认移除」且**数据未动**；再点一次 → 图标数 43→42、`apps.json` 对应条目消失、菜单关闭 | ✅ |

> 证据：`.traetemp\截图\20260912-右键菜单与拖入添加\`
> - `01-图标右键菜单.png`：真实页面截图，图标上右键弹出「打开 / 打开文件位置 / 移除快捷方式」，标题行为该应用名；
> - `02-宿主侧验证-启动置前与名称解析.txt`：T1–T4 全 PASS，其中置前一条为 `probe: {"appHwnd":…,"appZ":0,…,"novaZ":1,…}` —— **z 序 0 在 1 之前即「应用在 launcher 前面」**；同批探测到 `logonui:1`（当时桌面处于锁屏），说明**z 序置前不依赖锁屏状态**，而键盘焦点（`fgHwnd:0`）在此状态下本就拿不到 —— 这正是 T20.2 要把 A/B 两层分开的原因；
> - `03-页面侧验证-右键菜单交互.txt`：R1–R4 全 PASS（含「第一次点击不删数据」的安全断言）；
> - `NovaLauncher.Web\host.log`：`发现新窗口：字符映射表（charmap pid=15084 490x425）` → `置前：…（charmap，键盘焦点=False，z序=0）`；`快捷方式索引已建立：248 个文件名 / 248 个基名` → `按名称解析：LiveCaptions.lnk → C:\Users\…\Start Menu\Programs\Accessibility\LiveCaptions.lnk`。

> 本轮踩到的两个环境坑（已写入技能库）：
> ① **PS 5.1 的 `Add-Type` 用老编译器（C# 5）**：`out uint _` / `out MSG m` 这类 C# 7 内联 out 声明会报「无效的表达式项」，必须先把变量声明出来再传 `out`；
> ② 在本机跑 **`agent-browser` 会顺带清掉已有的 Chrome/Edge 进程** —— launcher 窗口被带关，宿主因「前端心跳中断（窗口已关闭）」自动退出。做前端验证时改用**系统已有的 Chrome + `--remote-debugging-port` + CDP**（node 22 自带 WebSocket，零依赖、无下载、不受磁盘紧张影响），并注意**页面挂在根路径 `/`**，不是 `/nova-launcher.html`。

### M21 · 图标右键重命名（依主人「右键图标可以重新命名」）

> 原则延续 M20：**只动 Nova 里的记录，不动磁盘上的文件** —— 重命名改的是 `apps.json` 里的显示名，
> 快捷方式本体（文件名、目标）原封不动；图标按 `path` 读取（M14 的决定在这里再次兑现），
> 改 `name` 不会引起图标与名字错位。

| 任务 | 说明 | 状态 |
|------|------|------|
| T21.1 | 宿主新增 `^/api/rename$`：定位**优先用 `p`（路径稳定）**、拿不到再退回 `i`（行号会随拖拽变化，不宜作主键）；空名（trim 后为空）拒绝、名称截断 60 字符、缺 token 403；同名时幂等返回不重写落盘 | ✅ |
| T21.2 | 前端右键菜单新增第三项「**重命名**」：菜单**原地变身**成「输入框 + 确定 / 取消」（与移除的二次确认同一交互模式，不弹系统对话框）；回车确定、Esc / 取消返回菜单态 | ✅ |
| T21.3 | 交互细节：输入框 `keydown` 必须 `stopPropagation()` —— 否则 Esc 会命中全局 keydown 把整个菜单关掉；空名提交被拦并就地提示「名称不能为空」；输入框自动**聚焦 + 全选**（等菜单 `.open` 之后的 `setTimeout(0)` 再 focus）；`renameApp()` 就地更新 `state.apps[i].name` 并同时重绘网格与设置抽屉列表 | ✅ |
| T21.4 | 演示模式实现 `demoRename()`（localStorage 持久化），file:// 直开也能体验完整交互 | ✅ |
| T21.5 | 双层回归验证：**API 层 11/11 PASS**（按 path / 按 i 正例落盘核对、空名拒绝、不存在拒绝、缺 token 403、还原后与备份**逐字节一致**）；**UI 层 CDP 13/13 PASS**（右键出四项、点「重命名」出现输入框、预填 + 聚焦 + 全选、空名拦截、回车后菜单关闭且界面与 `apps.json` 同步更新、还原后刷新页面名字复原） | ✅ |

> 证据：`.traetemp\截图\20260912-重命名与图标\`（`01-右键菜单-含重命名.png`、`02-重命名编辑态.png`、
> `03-重命名完成.png`、`04-还原后.png`）；`.temp\rename-node-result.txt`（API 层）、`.temp\rename-ui-result.txt`（UI 层）。
>
> 测试脚本侧的教训（非应用 bug）：菜单按钮的 `textContent` 是「**图标 + 文字**」（如 `✎重命名`），
> 自动化匹配必须用 `.mi .tx` 子元素的文字；输入框聚焦走 `setTimeout(0)`，断言聚焦要等一拍（`awaitPromise`）。

### M22 · 应用图标与顶栏 Logo 同款（依主人「给自己做一个漂亮的图标，图标和软件左上角的保持一致」）

> 关键认知：`--app` 模式下浏览器窗口的**任务栏 / Alt-Tab 图标来自页面 favicon**。此前 `/favicon.ico`
> 一直 404，任务栏里显示的是浏览器默认图标 —— 所以「给应用一个图标」=「给页面一个 favicon」。

| 任务 | 说明 | 状态 |
|------|------|------|
| T22.1 | 图标源 SVG **完全复刻**顶栏 `.brand .mark`：135° 渐变 `#6d8bff→#9b7cff`（深色主题 accent/accent-2）、圆角比例 30%（9/30）、白色四角星 ✦ 居中、四角透明 | ✅ |
| T22.2 | 渲染管线：无头 Edge 截图。两个实测陷阱：① **SVG 必须写死 `width`/`height` 像素属性**（只给 viewBox 时浏览器按默认/视口尺寸解释，实测内容被放大裁切或偏移到角落）；② 需 `--force-device-scale-factor=1` + `--default-background-color=00000000`（保透明圆角）。且老 headless 一次成功后**易挂起**（单例锁），每尺寸独立 `--user-data-dir` + 限时收尾 | ✅ |
| T22.3 | 尺寸链：256px 无头 Edge 直出（保渐变与星形的矢量精度）；64/48/32/16 用 GDI+ `HighQualityBicubic` 从 256 缩放（渐变图标缩放无损观感） | ✅ |
| T22.4 | ICO 打包（零依赖，node 自写 PNG 解码 + DIB 编码）：**256px 条目用 PNG 压缩、小尺寸用经典 32bpp BMP（DIB，自下而上 BGRA + AND 掩码）**—— 全 PNG 条目 GDI+ 的 `Icon.ToBitmap()` 解不了（实测报「请求的范围扩展超过了数组的结尾」），混合格式才是最大兼容写法 | ✅ |
| T22.5 | 接入：宿主把 `/favicon.ico` 与 `/nova-logo.ico` 改为**免 token** 托管 `nova-logo.ico`（图标无敏感信息，token 化反而会让 `<link>` 写法复杂化）；页面新增 `<link rel="icon" href="nova-logo.ico?v=1">`（`?v=` 备好日后改图标的缓存钥匙）；相对路径写法让 file:// 演示模式也生效 | ✅ |
| T22.6 | 验证：GDI+ 四尺寸（16/32/48/64）`Icon` 加载 + `ToBitmap` 全通过并逐尺寸提取视觉核对；实机 `/nova-logo.ico`、`/favicon.ico` 与本地文件**逐字节一致**（41,345 B）、MIME `image/x-icon`、页面含 `<link>`、其余接口不受影响（6/6 PASS） | ✅ |

> 证据：`NovaLauncher.Web\nova-logo.ico`（5 尺寸）+ `nova-logo-256.png`（预览用）；
> `.traetemp\截图\20260912-重命名与图标\`（`02-重命名编辑态.png` 可见新图标已随页面生效）；
> `.temp\icon-serve-result.txt`（6/6 PASS）、`.temp\icon-ico-validate.txt`、`.temp\icon-scale-result.txt`。

### M23 · 启动图标预热（依主人「软件启动后，若 Icons 目录未读到该应用的图标就到该应用的实际位置去提取」）

> 之前的提取是**惰性**的：页面请求 `/api/icon` 才现场提取并落缓存，冷启动第一次打开网格时
> 图标要逐个「蹦」出来。M23 把补提动作挪到**宿主启动后**：Icons 目录里缺哪张，就去应用
> 实际位置提取落盘，此后打开即是秒显。

| 任务 | 说明 | 状态 |
|------|------|------|
| T23.1 | 缓存键提取为公共函数 `Get-IconKey`（路径小写 MD5 前 16 位），`Get-IconBytes` 与预热共用，杜绝键算法两处漂移 | ✅ |
| T23.2 | `.lnk` 兜底：`.lnk` 本体不是 PE 文件，`PrivateExtractIcons` 提不出图标 → 新增 `Resolve-LinkTarget` 解析快捷方式实际目标，改从目标提取（缓存仍以快捷方式路径为键，页面请求方式不变）。`/api/icon` 的即席请求同样受益 | ✅ |
| T23.3 | 预热排队：启动时扫 `apps.json`（跳过 `shell:` 与失效路径）× 尺寸 {256, 当前网格 `iconSize`}，逐项查 `Icons\` 缓存，缺的排进 `$script:PreheatQueue` | ✅ |
| T23.4 | 分批补提不阻塞：主循环**空闲节拍**（每 1.5s 无请求时）每拍最多补 6 张；期间真实请求随时插队（请求路径的 `Get-IconBytes` 先走，预热补到时命中缓存直接返回）。队列清空记日志 | ✅ |
| T23.5 | 验证：① 删一张 256 缓存 + 全新 `iconSize=100` 尺寸 → 启动日志「缺 38 张」→ 空闲节拍补提完成，被删文件复原、37 张 `-100.png` 全部落盘（Icons 227→265）；② 临时 `.lnk` 请求 `/api/icon` → 日志「快捷方式本体提不出图标，已改从目标提取」，返回 200 + 有效 PNG | ✅ |

> 证据：`host.log`（「图标预热：Icons 目录缺 38 张…」「图标预热完成」「快捷方式本体提不出图标，已改从目标提取」）。

### M24 · 设置界面一键检查应用有效性（依主人「软件设置界面支持一键对所有添加的应用检查是否有效」）

> 动机：图标挪走、程序被卸载后，网格里的图标还挂着，点了才报「路径失效」——失效只能**事后撞见**。
> M24 把检查变成**主动动作**：设置抽屉里一键逐项体检，失效项集中亮出来、当场清掉。

| 任务 | 说明 | 状态 |
|------|------|------|
| T24.1 | 宿主 `^/api/checkapps`：逐项验证——路径为空 / 文件不存在 / `.lnk` 经 `Resolve-LinkTarget` 深挖目标（快捷方式在、目标被卸载也判「快捷方式目标不存在」）/ `shell:` 协议跳过；返回 `{ total, okCount, bad: [{i, name, path, reason}] }` | ✅ |
| T24.2 | 前端「我的应用」区新增「🩺 检查应用有效性」按钮 + 结果面板（红边卡片，只列失效项不打扰正常项）：每项展示名称 / 失效原因 / 路径，附「移除」；多于 1 项时附「全部移除（N）」 | ✅ |
| T24.3 | 检查结果**回写** `state.apps[i].exists` → 网格与抽屉列表即时标红「（路径失效）」，与既有失效样式（M14）贯通 | ✅ |
| T24.4 | 移除后**重跑检查**而不是在旧结果上做行号算术——删除后宿主行号位移，重查最可靠；「全部移除」倒序删规避位移 | ✅ |
| T24.5 | 验证：注入 1 条幽灵路径 + 1 条「目标被卸载」的 lnk → 接口 83ms 返回 `total=43 ok=41 bad=2`，原因文案精确；倒序删两条 → 复检 `bad=0`；apps.json 事后与备份逐字节恢复（41 条、零残留） | ✅ |

> 证据：实测 `/api/checkapps`（200 / 83ms / bad 原因「文件不存在」「快捷方式目标不存在」）、
> `/api/remove` 倒序删两条 200 + 复检 bad=0、apps.json 恢复后 41 条零测试残留。

### M25 · 设置抽屉区块重排（依主人「将设置中的主题和外观移动到设置页面的最上方」）

| 任务 | 说明 | 状态 |
|------|------|------|
| T25.1 | 抽屉 `<aside class="drawer">` 内三个 `.sec` 区块重排为 **外观（图标大小 / 每行图标数 / 主题）→ 我的应用 → 数据**；纯 DOM 顺序调整，所有元素 id 与事件绑定不变（绑定按 id 查找，与位置无关），零逻辑改动 | ✅ |

> 证据：`grep <h3>` 顺序确认 外观(509) → 我的应用(538) → 数据(547)；JS `node --check` 通过（未改动）。

### M26 · 重制应用图标（依主人「nova 图标不完整，只有上半块」）

> 根因排查：用自写解析器逐条目解码部署中的 `nova-logo.ico`，发现**所有源 PNG 下半部透明像素
> 远多于上半部**（256px：上 1/4 透明 4,402 / 中 9,606 / 下 1/4 16,128；圆角方块本应上下对称
> 各约 4,500）——残缺在**源图**，无头 Edge 渲染时就只出了上半块，ICO 忠实打包了残缺源图。
> M22 当时的目视核对结论有误（且 GDI+ 提取核对同样没发现，因为残缺的是 alpha 通道而非结构）。

| 任务 | 说明 | 状态 |
|------|------|------|
| T26.1 | 诊断工具：自写 ICO 条目解析器（XOR 像素 + AND 掩码逐位统计、上/下半透明分布对比），并模拟「alpha 渲染」与「传统掩码渲染」两条路径复现 | ✅ |
| T26.2 | 放弃无头浏览器渲染，**node 逐像素光栅化**：135° 渐变（CSS 语义 `t=(x+y)/2S`）+ 30% 圆角方块（SDF 判内）+ 白色四角星（8 顶点多边形），2x2 超采样抗锯齿，256/64/48/32/16 全尺寸一次生成，零浏览器依赖 | ✅ |
| T26.3 | 渲染即自检：上/下半透明差 **0.0%**（全尺寸 PASS）、256 中心 RGB=255,255,255（星心）、四角 alpha=0、上蓝下紫渐变方向正确 | ✅ |
| T26.4 | 重建 ICO（混合格式不变：256 PNG + 小尺寸 BMP），复检每个 BMP 条目上/下半掩码透明位完全对称（142/142、76/76、34/34、6/6）；GDI+ 全条目 `ToBitmap` 通过；体积 41,345→**36,254 B**（几何图形 PNG 压缩率更高） | ✅ |
| T26.5 | 破缓存：favicon 链接 `?v=1`→`?v=2`（BrowserProfile 的 favicon DB 缓存了残缺旧图，不改版本号看不到新图标） | ✅ |

> 证据：`.temp\raster-result.txt`（5 尺寸对称性 PASS）、`.temp\ico-analyze.txt`（掩码对称）、
> `.temp\icon-ico-validate2.txt`（GDI+ 解析）、数值采样（四角透明/星心纯白/渐变方向正确）。

### M27 · 窗口三键不依赖宿主（依主人「未连接宿主时点击关闭失败，三键不能依赖宿主」）

> 场景：`--app` 无边框窗口里系统三键已被去掉，自绘三键走 `/api/win`；宿主一旦退出
> （心跳断/崩溃），点关闭只弹「窗口操作失败」，无边框窗口连 Alt+F4 之外的出路都没有。

| 任务 | 说明 | 状态 |
|------|------|------|
| T27.1 | **关闭键永不依赖宿主**：API 失败立即降级 `window.close()`（`--app` 窗口可被脚本关闭）；再失败才提示 Alt+F4 | ✅ |
| T27.2 | `host-dead` 降级态：心跳连续失败（connFail）或窗口操作失败时进入；最小化/最大化置灰（Web 平台无原生窗口 API，宿主不在无法执行），关闭键改走浏览器关窗 | ✅ |
| T27.3 | 提示语改造：不再弹含糊的「窗口操作失败」，降级态点击最小化/最大化给出「宿主已退出…可点 ✕ 关闭窗口」的明确指引 | ✅ |
| T27.4 | 端到端验证（`--app` Chrome + CDP）：宿主存活时 min/max 正常（A1/A2）；`/api/quit` 杀宿主 → 心跳 ~6s 内自动进降级态（B1）→ 降级态点击有明确提示（B2）→ 点 ✕ 真实关窗 target 消失（B3） | ✅ 6/6 PASS |

> 平台边界（如实记录）：最小化/最大化在浏览器里**没有**原生 API，宿主退出后这两键只能置灰；
> 「不依赖宿主」的完整能力边界 = 关闭键 100% 可用 + 降级态明确告知。
>
> 证据：`.temp\ui\winctrl-test.mjs` 6/6 PASS（A1 min / A2 max 切换 / B1 降级态 / B2 提示文案 / B3 真实关窗）。
> 测试环境坑（已沉淀到技能库）：沙箱注入的 HTTP_PROXY 会劫持 node fetch（`env -u` 清除）；
> 沙箱在工具调用结束时会回收 Chrome（须与测试同调用完成）；`rm -rf` 被 safe-delete 守卫拦截（换新 profile 名规避）。

---

### M28 · 任务栏图标修复（依主人「任务栏图标不是 nova-logo.ico」）

> 现象：M22/M26 做好的 `nova-logo.ico` 经 favicon 生效于标题栏/Alt-Tab，但**任务栏按钮
> 一直是浏览器图标**。根因有三层，每层都实测证伪了「只做前一层就够」：
> ① 任务栏根本不看窗口图标（favicon 只管标题栏/Alt-Tab）→ 需要 `WM_SETICON`；
> ② 有了 WM_SETICON 任务栏还是 Chrome 图标：Win10/11 任务栏按钮按 **AppUserModelID**
>    分组取图标，Chromium 给 --app 窗口挂了浏览器的 AUMID，且**按钮在窗口显示那一刻
>    就定型，事后改窗口属性不会重新分组** → 需要自定义 AUMID + 强制重建按钮；
> ③ 有了自定义 AUMID 但没有对应快捷方式时，图标仍回退浏览器 exe → 需要 **AUMID
>    快捷方式**（官方「应用注册」机制：窗口 AUMID 与开始菜单某快捷方式的 AUMID 一致时，
>    按钮的分组/图标/显示名全部取自该快捷方式）。

| 任务 | 说明 | 状态 |
|------|------|------|
| T28.1 | C# 增补：`LoadImage`/`WM_SETICON`（大图标=任务栏、小图标=标题栏）+ `SHGetPropertyStoreForWindow` 写窗口 AUMID + ShellLink QI `IPropertyStore` 写 .lnk 的 `PKEY_AppUserModel_ID` | ✅ |
| T28.2 | `Set-NovaWindowIcon` 四步流程：每次启动幂等重建 `%APPDATA%\...\Start Menu\Programs\Nova Launcher.lnk`（目标=`NovaLauncher.bat`、图标=`nova-logo.ico`、AUMID=`Nova.Launcher`）→ 设窗口 AUMID → `WS_EX_TOOLWINDOW` 短暂切换强制任务栏重建按钮 → `WM_SETICON` | ✅ |
| T28.3 | 时序坑防御：浏览器 favicon 解析完会自己再 SetIcon 覆盖 → 每拍 `WM_GETICON` 读回大图标句柄比对，不一致即重设，连续 8 拍稳定才收工（上限 40 次兜底） | ✅ |
| T28.4 | 端到端验证：UIA 实测任务栏按钮由「Google Chrome - 1 个运行窗口」变为 **「Nova Launcher - 1 个运行窗口」**；lnk 属性读回 `Nova.Launcher`；窗口 AUMID 读回一致；`WM_GETICON` 读回 = 我们加载的 HICON | ✅ |

> 排障实录（每条都踩过，沉淀到技能库 §25）：
> · 只 `WM_SETICON` 无效（任务栏按 AUMID 取图标）；
> · 只设窗口 AUMID 无效（无快捷方式回退 exe 图标 + 按钮不重新分组）；
> · `SHGetPropertyStoreFromParsingName` 拿的 store 对 lnk 的 AUMID 是**只读视图**（SetValue 返 S_FALSE 静默不落盘），必须走 **IShellLink 自身的 IPropertyStore**；
> · `IPersistFile::Load(path, 0)` 是只读打开 → 写属性必被拒 `STG_E_ACCESSDENIED`，须 `STGM_READWRITE|SHARE_DENY_NONE`（0x42）；
> · WScript.Shell 写完 lnk 后必须显式 `ReleaseComObject` 再用 ShellLink 打开，否则文件仍被持有同报 ACCESSDENIED；
> · 锁屏下 GDI 抓屏全黑，UIA 仍可读任务栏结构 —— 验证任务栏用 UIA 而非截图。
>
> 副产物：`Nova Launcher.lnk` 常驻开始菜单（绿色版每次启动幂等重建，目录挪走后路径自动修正），
> 用户可右键它「固定到任务栏/开始屏幕」，任务栏图标同样是 nova-logo。

---

### M29 · 目录重组：根目录只留 bat 入口（依主人「根目录只保留 NovaLauncher.bat，其他文件均移入 data 文件夹」）

> 动机：交付目录更干净——根目录只有 1 个双击入口，程序本体与全部数据收纳进 `data\`。
> 得益于 M0 就定下的 `$DataDir = $ScriptDir` 设计（ps1 在哪数据就在哪），**ps1 挪进 data\ 后
> 所有数据路径自动跟随，宿主代码一行不用改**；实际只动了 3 处：
> ① bat 的 `-File` 指向 `data\NovaLauncher.ps1`；
> ② 开始菜单 lnk 的目标改为**上级目录**的 bat（`Split-Path $ScriptDir -Parent`）；
> ③ `.gitignore` 的 6 条路径加 `data/` 前缀。

| 任务 | 说明 | 状态 |
|------|------|------|
| T29.1 | 停宿主 → 建 `data\` → 根目录除 `NovaLauncher.bat` 外 12 项全部移入（BrowserProfile/Icons/apps.json/settings.json/ps1/html/ico/README/host.log/runtime.json/NovaLauncher.lnk），0 失败 | ✅ |
| T29.2 | bat 入口指向 `data\NovaLauncher.ps1`；ps1 内 lnk 目标改指上级目录 bat；`.gitignore` 路径前缀更新 | ✅ |
| T29.3 | 端到端验证：语法 0 错误；完整启动——无边框最大化、图标预热补提 2 张、开始菜单 lnk 重建（目标=根 bat）、AUMID/任务栏按钮重建、WM_SETICON 稳定；HTTP 实测 `/api/installed` 274 项、`/favicon.ico` 36254 B、页面 72605 B | ✅ |
| T29.4 | 文档同步：两级 README 目录结构/数据存放/排查路径、本文件交付物清单、修改记录 | ✅ |

---

### M30 · 窗口化也无系统标题栏（依主人「全屏时点击最大化按钮，系统标题也不能出现」）

> M27 的设计是「无边框最大化 ⇄ 带标题栏的窗口化」；主人要求切换后**任何状态都不出现系统
> 标题栏**。改动两处：
> ① `Set-NovaWinMaximized -Windowed` 不再把 WS_CAPTION/WS_THICKFRAME 加回去 —— 窗口化 =
>    无边框居中小窗 1180×780（物理 @1.5x = 1770×1170），页面自己的顶栏与三键自然露出；
> ② `Get-NovaWinState` 原来靠「有没有 WS_CAPTION」区分状态，窗口化也无边框后失效 ——
>    改为**窗口矩形与工作区矩形比较**（含 csd 上移偏移，容差 2px）。
> 前端零改动（`applyWinChrome` 按 `state !== "windowed"` 判断，语义不变）。

| 任务 | 说明 | 状态 |
|------|------|------|
| T30.1 | `-Windowed` 分支：去掉「加回 WS_CAPTION/WS_THICKFRAME/WS_SYSMENU/…」，与最大化分支统一先剥边框，再摆到工作区居中 | ✅ |
| T30.2 | `Get-NovaWinState` 改矩形比较（x/y/w/h 四条 ±2px，最大化时 y 含 `-csd`、高度含 `+csd`） | ✅ |
| T30.3 | 端到端验证（Win32 实测往返）：全屏→窗口化 rect(396,99) 1770×1170 居中、`WS_CAPTION=False`；窗口化→全屏 rect 顶部 −59 上移 csd、宽度=工作区、同样无边框；再切回无误。API state 返回与实际样式一致 | ✅ |

> 排障插页：验证时发现屏幕上有**两个**「Nova Launcher」窗口 —— Chrome 从 BrowserProfile
> 恢复了上次会话多弹出一个孤儿窗口（宿主每拍实时 `Get-NovaWin`，操作的是当前有效那个，
> 孤儿窗直接 WM_CLOSE 即可）。属测试环境残留，非代码缺陷。

---

### M31 · 窗口化 CSD 残条修复（依主人「全屏→窗口化，标题栏还是出现了」）

> M30 实测 `WS_CAPTION` 全程 False 后主人仍看到「标题栏」——再排障：PrintWindow 抓窗口
> 顶部拿到铁证，那条灰条是 **Chromium 自绘标题条（CSD，「⚡ Nova Launcher ─ □ ✕」，
> 实测高 46 物理px ≈ 31 逻辑px，不随状态变）**，不是 Win32 标题栏。全屏时宿主把窗口
> 上移 csd 逻辑px 把它顶出屏幕上缘；窗口化时窗口居中、没有「顶出屏幕」的余地，CSD 就
> 露出来了 —— 这正是主人看到的东西。
> 修复：C# 增补 `SetWindowRgn`/`CreateRectRgn`；窗口化时把窗口顶部 32 逻辑px（实测 31
> +1px 余量）直接裁掉；切回全屏时清除 region（上移方案下再裁会裁到页面）。
> 注意：PrintWindow 会无视 region 渲染完整表面，验证必须用屏幕 BitBlt 抓屏。

| 任务 | 说明 | 状态 |
|------|------|------|
| T31.1 | C# 导入 `SetWindowRgn`/`CreateRectRgn`；`Set-NovaWinMaximized` 尾部按状态裁剪/清除 region | ✅ |
| T31.2 | 逐行取色定位 CSD 分界（窗口化与全屏窗口内 y=0–44 都是 CSD 灰 (31,32,32)，y≈46 起才是页面色） | ✅ |
| T31.3 | 屏幕抓屏实测往返：窗口化顶部 y=0 即页面色 (20,20,20)；全屏窗口上移出屏顶部非 CSD 灰；两态均无标题条 | ✅ |

---

### M32 · 窗口化切换后「下半屏未光栅化」修复（依主人截图：内容贴上方、底部大片纯色）

> 主人全屏→窗口化后截图：应用内容只占上部，底部约 1/4 是纯色 (32,32,32)。
> 排障结论（CDP `Page.getLayoutMetrics` + `Page.captureScreenshot` 铁证）：
> **Win32 矩形精确居中 (264,66) 1180×780、页面布局正确（视口 1167×745，图标 90css），
> 坏帧是 Chromium 的「未光栅化瓦片」滞留**——resize 后新暴露区域还没画出来，
> 而 Chromium 的**原生窗口遮挡检测**（CalculateNativeWinOcclusion）在窗口被其他窗口
> 盖住时暂停光栅化，半成品帧就无限期停在屏上。截图里图标「变小」是窗口化布局
> 本来就更密（iconSize=100、cols=10 时瓦片按可用宽度收缩），不是缩放错误。
> 修复两件套：① Chrome 启动参数加 `--disable-features=CalculateNativeWinOcclusion`；
> ② 页面 resize 稳定后对 body 做一次 `translateZ(0)` 开关强制整帧重绘。
> 另：`SetWindowPos` 补 `SWP_NOCOPYBITS`（丢弃旧位图）；`/api/win` 保留 `rect`
> （窗口/页面尺寸诊断）与 `pwshot`（PrintWindow 离屏抓帧）两个诊断操作。
> 排障经验：`RedrawWindow`/`WM_SIZE`/`±1px` 伸缩/前台化/最小化还原/DWM Cloak
> 六种强制重绘手段**全部无法**唤醒被遮挡检测冻结的光栅化，只能从根因（遮挡检测）下手。

| 任务 | 说明 | 状态 |
|------|------|------|
| T32.1 | Chrome 启动参数加 `--disable-features=CalculateNativeWinOcclusion` | ✅ |
| T32.2 | 页面 resize 防抖 150ms 后强制整帧重绘（body transform 开关） | ✅ |
| T32.3 | `SetWindowPos` 加 `SWP_NOCOPYBITS`；新增 `rect`/`pwshot` 诊断操作 | ✅ |
| T32.4 | 3 轮最大化⇄窗口化压力实测：逐行扫描 4 张窗口化帧均无 (32,32,32) 灰带 | ✅ |

---

## 4. 任务清单（WBS 汇总）

| ID | 阶段 | 任务 | 状态 | 关键交付 |
|----|------|------|------|----------|
| T0.1–T0.4 | M0 | 可行性验证 | ✅ | 方案②可行结论 |
| T1.1–T1.5 | M1 | 宿主骨架 | ✅ | 安全自退服务 |
| T2.1–T2.3 | M2 | 页面托管+状态 | ✅ | 同源访问 |
| T3.1–T3.3 | M3 | 图标提取 | ✅ | 256px 缓存 |
| T4.1–T4.4 | M4 | 启动/增删/排序 | ✅ | 真实启动 |
| T5.1–T5.6 | M5 | 界面 | ✅ | 双主题炫酷 UI |
| T6.1–T6.4 | M6 | 编码陷阱修复 | ✅ | 零编码报错 |
| T7.1–T7.3 | M7 | 端到端验证 | ✅ | 报告+截图 |
| T8.1–T8.4 | M8 | 交付验收 | ✅ | 绿色版+Skill |
| T9.1–T9.8 | M9 | 增量回归（试用反馈） | ✅ | 修添加报错 / 程序目录 / 拖拽 / 已安装面板 |
| T10.1–T10.8 | M10 | 已安装应用排序增强 | ✅ | 默认按使用频率 + 安装时间排序 |
| T11.1–T11.6 | M11 | 勾选交互调整 | ✅ | 默认全不选 + 全选/全不选 + 已选计数 |
| T12.1–T12.6 | M12 | 批量添加丢项修复 | ✅ | `+` 编码修正 + `/api/addbatch` + 失败可见 |
| T13.1–T13.5 | M13 | 每行图标数扩展到 12 | ✅ | 4~12 档 + 自适应列宽（不溢出） |
| T14.1–T14.6 | M14 | 拖拽排序落盘修复 + 图标按路径取 | ✅ | `/api/move` 可用 + 图标/名字强绑定 |
| T15.1–T15.4 | M15 | 屏蔽主界面右键菜单 | ✅ | capture 拦 `contextmenu` + 可编辑控件放行 |
| T16.1–T16.7 | M16 | 无边框全屏 + 右上角窗口三键 | ✅ | `/api/win` + Win32 去边框铺满 + 惰性应用全屏 |
| T17.1–T17.5 | M17 | 精简主界面文案 | ✅ | 主界面只留图标与名字，零说明文字 |
| T18.1–T18.6 | M18 | 连接状态改圆点指示 | ✅ | 绿点无文字 / 红点 + 「未连接宿主」 |
| T19.1–T19.7 | M19 | 最大化（非全屏）+ 隐藏浏览器自绘标题栏 | ✅ | 铺满工作区 + 上移隐藏 Chromium 自绘栏 + 修 `--user-data-dir` 断裂 |
| T20.1–T20.11 | M20 | 启动置前 + 图标右键移除 + 拖入快捷方式 | ✅ | 差集找新窗口 + TOPMOST 置前；右键三项目（原地二次确认）；拖入按名称解析并落盘 |
| T21.1–T21.5 | M21 | 图标右键重命名 | ✅ | `/api/rename`（p 优先 i 兜底）+ 菜单原地编辑态（回车/Esc、聚焦全选、空名拦截） |
| T22.1–T22.6 | M22 | 应用图标与顶栏 Logo 同款 | ✅ | `nova-logo.ico`（256 PNG + 小尺寸 BMP 混合格式）+ favicon 免 token 托管 |
| T23.1–T23.5 | M23 | 启动图标预热 | ✅ | Icons 缺失即排队，空闲节拍到应用实际位置补提；`.lnk` 解析目标兜底 |
| T24.1–T24.5 | M24 | 一键检查应用有效性 | ✅ | `/api/checkapps`（文件 + lnk 目标深挖）+ 抽屉失效面板（单独/全部移除、即时标红） |
| T25.1 | M25 | 设置抽屉区块重排 | ✅ | 外观（含主题）移到抽屉最上方：外观 → 我的应用 → 数据 |
| T26.1–T26.5 | M26 | 重制应用图标（修复「只有上半块」） | ✅ | 根因=无头渲染源图下半透明；改 node 逐像素光栅化 + 渲染即自检 + favicon ?v=2 破缓存 |
| T27.1–T27.4 | M27 | 窗口三键不依赖宿主 | ✅ | 关闭键 API 失败即降级 `window.close()`；host-dead 降级态（min/max 置灰+明确提示）；E2E 6/6 PASS |
| T28.1–T28.4 | M28 | 任务栏图标修复 | ✅ | WM_SETICON + 窗口 AUMID + AUMID 快捷方式 + TOOLWINDOW 重建按钮；UIA 实测按钮变「Nova Launcher」 |
| T30.1–T30.3 | M30 | 窗口化也无系统标题栏 | ✅ | 窗口化改无边框居中小窗；状态判断改矩形比较；Win32 实测往返全程无 WS_CAPTION |
| T31.1–T31.3 | M31 | 窗口化 CSD 残条修复 | ✅ | `SetWindowRgn` 裁掉 Chromium 自绘标题条（46 物理px）；屏幕抓屏实测两态均无标题条 |
| T32.1–T32.4 | M32 | 窗口化切换后半帧未光栅化修复 | ✅ | 禁用 Chromium 遮挡检测 + 页面 resize 强制重绘 + `SWP_NOCOPYBITS`；3 轮压测帧帧完整 |
| — | — | **合计** | — | **方案② 已交付** |

> 估时为单人熟练开发参考值，实际含编码陷阱排查约 1 个工作日。

---

## 5. UI / 交互与动画规范

> 与 `03` 视觉规范一致，以下为 HTML/CSS 实现侧约定。

### 5.1 视觉规范

| 项 | 规范 |
|----|------|
| 背景 | Mica 风格（CSS 渐变 + 克制径向光晕模拟） |
| 圆角 | 卡片/容器 12px；弹窗 16px |
| 边框 | 弱化，靠层次与阴影 |
| 阴影 | 轻量 |
| 字体 | 系统默认（Segoe UI 等） |
| 图标 | 真实软件图标；UI 图标用字符/Segoe 字形兜底 |
| 默认主题 | 深色 |

### 5.2 尺寸与布局

| 项 | 规范 |
|----|------|
| 窗口默认 | `msedge --window-size=1180,780` |
| 图标大小 | 36~160px（滑块，默认 80） |
| 网格列数 | 默认 6；可 4~8 |
| 缺失图标回退 | 字符方块；路径失效显示红色「!」标记 |

### 5.3 交互行为

| 操作 | 行为 |
|------|------|
| 单击图标 | 启动目标程序 |
| 拖拽 | 调整顺序，释放写 `sort` |
| 设置齿轮 | 右侧抽屉滑入（非跳转页面） |
| `Esc` | 关闭设置抽屉 |
| 直开 HTML | 进入演示模式，不启动任何程序 |

---

## 6. 验收标准与实测证据

### 6.1 功能验收（✅ 已实测）

- [x] 文件框可添加 `.exe` / `.lnk`，首页立即出现且图标正确（8 个应用已添加，`apps.json` 中文正确）
- [x] 单击图标能启动目标程序（`host.log` 实证 `启动：notepad.exe` / `msedge.exe` / `powershell.exe`）
- [x] 拖拽可调整顺序并持久化（`/api/move` → `apps.json`）
- [x] 图标大小、列数、主题切换即时生效并持久化
- [x] 移除应用后首页消失且 `apps.json` 同步
- [x] `apps.json` / `settings.json` 存在且格式正确；损坏可回退不崩溃

### 6.1b 增量回归验收（✅ 已实测，见 `.traetemp/shots/`）

- [x] 「＋ 添加应用」不再报错 —— 文件框改在独立 STA 线程弹出（原 MTA 回调抛 `ThreadStateException` 被顶层吞掉→500）
- [x] 数据目录 = 程序执行目录 —— 抽屉副标题显示实际路径 `…\NovaLauncher.Web`；`runtime.json.dataDir` 一致
- [x] 拖 EXE/LNK 进窗口即添加 —— 拖入显示虚线投放区「把应用程序拖到这里即可添加」
- [x] 「从已安装应用添加」—— 实测枚举 **273** 项（开始菜单 147 / 注册表 42 / Get-StartApps 84），支持搜索与
  排序维度为 **使用频率（默认）· 安装时间 · 名称 · 路径 · 类型 · 来源**，`已添加` 项自动标记，可勾选后「添加选中」批量加入；
  实测 63/273 项有非零使用频率、217/273 项有安装日期，两个新维度的排序结果均严格降序（M10）；
  **打开面板默认零勾选**，底部「全选 / 全不选」+ 实时已选计数，全选自动跳过已添加项（M11）；
  **批量添加勾 10 个即入 10 个**（含空格路径不再丢失），失败项会标红并说明原因（M12）
- [x] 多来源去重 —— 同名应用不再重复（`duplicate_names=0`）
- [x] UWP / 商店应用可加入 —— `path=shell:AppsFolder\<AUMID>`，`exists` 恒 true，可经 `explorer.exe` 启动
- [x] 图标 —— `/api/icon?p=<任意路径>` 可取到 PNG（实测 `137 80 78 71` 魔数）
- [x] 环境裁剪健壮 —— 宿主 `$env:APPDATA` 为空时仍能枚举（`GetFolderPath` 兜底）

### 6.2 性能与健壮性验收（✅ 已实测）

- [x] 同源托管，无 CORS；页面约 30KB，秒开
- [x] 关闭窗口后宿主 25s 内自退，`runtime.json` 自动删除，无残留进程
- [x] 高 DPI（150%）下截图不裁切（补 `SetProcessDPIAware`）
- [x] 所有 `/api/*` 无 token 返回 403

### 6.3 安全验收（✅ 已实测）

- [x] 仅 `127.0.0.1`；随机端口；随机 token 校验
- [x] 独立 `BrowserProfile`，不影响日常 Edge

---

## 7. 风险与对策

| 风险 | 影响 | 对策 / 现状 |
|------|------|-------------|
| `.ps1` 被 PS 5.1 按 GBK 解码 | 中文注释语法错误，宿主起不来 | ✅ `.ps1` 强制 UTF-8 带 BOM |
| `.bat` LF 换行 / 带 BOM | 中文注释被当命令执行、cmd 报错 | ✅ `.bat` UTF-8 无 BOM + CRLF |
| 中文应用名经 `QueryString` 乱码 | 添加后名称乱码 | ✅ `Get-Query` 走原始 query + `UnescapeDataString` |
| 关窗后宿主残留 | 占端口、后台进程 | ✅ 25s 无心跳自退 |
| 图标提取慢卡首屏 | 体验差 | ✅ 256px 回退链 + MD5 磁盘缓存 |
| UWP / 商店应用启动 | `Start-Process` 拉不起 | ✅ 已实现：`path` 以 `shell:` 开头时改走 `explorer.exe shell:AppsFolder\<AUMID>` |
| 宿主进程环境被裁剪（`$env:APPDATA` / `$env:ProgramData` 为空） | 枚举已安装应用时 `Join-Path $null` 抛错 → `/api/installed` 返回 500 | ✅ 已修复：改用 `[System.Environment]::GetFolderPath()` 取已知文件夹，不再依赖 `$env:` |
| 同一应用被多来源重复收录（`.lnk` 指向 exe，`Get-StartApps` 又返回 AUMID/路径） | 「已安装应用」列表出现重复项 | ✅ 已修复：按「路径 + 名称」双重去重；`Get-StartApps` 中经典应用（AppID 为路径）按 exe 收录，UWP 才加 `shell:` 前缀 |
| 「添加应用」文件框在 MTA 线程弹出 | `ThreadStateException` → 页面报「添加应用出错」 | ✅ 已修复：文件框在独立 STA 线程 + `ManualResetEvent` 中弹出 |
| 前端 query 编码与宿主解码不一致（`URLSearchParams` 把空格编成 `+`，宿主 `UnescapeDataString` 不认 `+`） | 含空格路径（`C:\Program Files\...`）被解坏 → `Test-Path` 失败 → **批量添加静默丢项**（全机 130/273 个应用受影响） | ✅ 已修复：前端改 `encodeURIComponent`（空格→`%20`）；宿主 `Get-Query` 补 `+`→空格还原；新增 `POST /api/addbatch` 逐项回报，失败行标红说明原因（M12） |
| `@(Get-Apps)`：`@()` 包裹**返回数组**的函数调用 → 得到「1 个元素」的数组，`.Count` 恒为 1 | 参数校验 `$to -ge 1` 一律成立 → **拖拽排序每次都被判「索引越界」**，顺序从不落盘（界面却已重排） | ✅ 已修复：改 `$apps = Get-Apps` + `$n = @($apps).Count`（M14） |
| 资源（图标）用**行号**寻址 `?i=N`，而顺序是可变的 | 只要界面顺序与落盘顺序有任何分叉，图标就与名字**整体错位**（本次即为故障现象） | ✅ 已修复：改用**按路径** `?p=<path>` 寻址，图标与标签同源于一个 app 对象（M14） |
| 右键菜单是**浏览器原生 UI**，不在 DOM 中；Edge/Chromium **无关闭它的启动参数** | 用 `--app=` 无地址栏窗口时右键仍会弹出「返回/重新加载/另存图片/检查」，破坏启动器的完整感 | ✅ 已处理：页面在 **capture 阶段**拦 `contextmenu`（`preventDefault` + `stopPropagation`），见 M15 |
| 一刀切屏蔽右键会连带废掉**右键粘贴/拼写检查** | 搜索框等可编辑控件里右键无菜单，粘贴只能靠 Ctrl+V | ✅ 已处理：`isEditableTarget()` 放行 text/search/url/email/password/tel/number/textarea/contenteditable（M15） |
| **网页无法直接控制浏览器窗口**（`window.close()` 只对脚本开窗有效；`resizeTo/moveTo` 受限且改不了标题栏） | 「右上角最小化/最大化/关闭」无法纯前端实现 | ✅ 已处理：由**宿主**代操作 Win32 窗口，页面经 `/api/win` 下发请求（M16） |
| 用 `--start-fullscreen` / `--kiosk` 做全屏 | 前者是浏览器自身全屏态，宿主读不到也无法与页面状态机同步；后者连退出通道一起禁掉，退出困难 | ✅ 已处理：不用浏览器全屏参数，改为**去 `WS_CAPTION|WS_THICKFRAME` + `SetWindowPos`**（M16；M19 起改为铺满**工作区**，不再铺满整屏） |
| 改窗口样式后不生效 | `SetWindowLong` 改了 `GWL_STYLE` 却要等下一次真实改尺寸才刷新 | ✅ 已处理：`SetWindowPos` 必带 **`SWP_FRAMECHANGED`**（M16） |
| 靠 `$proc.MainWindowHandle` 找浏览器窗口拿不到句柄 | Edge 常把新窗口交给**已存在**的浏览器进程，启动进程本身立刻退出，`MainWindowHandle` 恒为 0 | ✅ 已处理：改 `EnumWindows` **按标题 + 浏览器进程名白名单**匹配；同名多窗口时优先取**当前前台**那个（M16） |
| 启动阶段**死等**窗口出现再切全屏 | 首开浏览器要新建 `user-data-dir`，可能远超等待窗口；死等会把 HTTP 服务一起卡住（页面永远「连接中…」） | ✅ 已处理：改**惰性应用**——空闲节拍（1.5s）/ 首次拉状态 / 心跳三处各试一次，`$script:MaxApplied` 保证只切一次，之后用户手动还原不会被抢回（M16，命名于 M19 更新） |
| 去掉 `WS_CAPTION` 后**仍有一条标题栏** | 那条**不是 Windows 画的**，是 Chromium 自身在客户区顶部自绘的 custom titlebar（页面标题 + 三键）。不受 Win32 样式控制、**没有任何开关能关掉**（`--disable-windows10-custom-titlebar` 实测无效） | ✅ 已处理：把窗口整体上移该栏高度、高度同步加回（底边不动）→ 那条栏被顶出屏幕上边缘；栏高由页面 `innerHeight` 反推、不写死（M19） |
| 反推栏高时**混算 DPI 尺度** | 宿主进程不 DPI 感知时，Win32 返回的是**被虚拟化过的逻辑坐标**（150% 缩放下是物理像素的 2/3），与页面 CSS 像素同尺度；若一律乘 `devicePixelRatio` 会算成原来的 1.5 倍 → 页面被顶掉一大截 | ✅ 已处理：先 `IsProcessDPIAware()` 判定，感知才乘 `dpr`、不感知系数取 1；算不出合理值（负数 / &gt;200）直接**放弃偏移**（M19） |
| PS 5.1 `Start-Process -ArgumentList` 传**数组** | 会把 `'--user-data-dir=' + 路径` 拆成两段（`=` 后凭空多一个空格）→ 浏览器收到空值 → 退回**用户自己的 Chrome 配置**：`BrowserProfile` 建不出来、书签/扩展/登录态被借走 | ✅ 已修复：拼**整条命令行字符串**后再传（M19） |
| 主界面堆叠说明性文字（标题、操作提示、底部「共 N 个应用 · 顺序已保存」） | 视觉噪音大，且「路径失效」这类汇总文字与真实状态**可能不同步** | ✅ 已处理：主界面只留**图标 + 名字**；失效应用改由磁贴自身标红（`.tile.missing`）呈现，与真相同源（M17） |
| 状态用**文字**表达必占视觉位（「已连接宿主」常驻），且颜色与文字容易**各改一处走岔** | 正常态界面不够干净；改动时漏掉一处就出现「红点配绿字」之类矛盾 | ✅ 已处理：改为**圆点 + `data-state` 单一状态源**同时驱动颜色与文字显隐；正常态绿点不出文字，只有异常才出文字（M18） |
| 心跳**只发不收**：宿主崩了页面并不知情 | 界面仍显示「已连接」，用户点图标才报错，故障被延迟发现 | ✅ 已处理：`ping()` 按响应结果回调 `connOk`/`connFail`，**连续失败 2 次**才翻红点（防抖动误报）（M18） |
| 由**后台进程**启动的应用拿不到前台资格 | 前台锁只认「当前前台进程」或「刚收到用户输入」的进程，宿主两条都不满足 → 新窗口开出来了却停在我们这个铺满工作区的窗口**后面**（「应用藏在软件后端」） | ✅ 已处理：分两层解决 —— **「显示在最前」用 `SetWindowPos(HWND_TOPMOST→NOTOPMOST)`，不需任何权限、必然生效**；「键盘焦点」再依次用建消息队列 / `AttachThreadInput` / 临时清零前台锁超时 / 轻敲 ALT 争取（M20） |
| 靠 `-PassThru` 的进程去找「刚启动的应用窗口」 | `.lnk` 要经 shell 中转、`shell:AppsFolder`（UWP）交给 explorer 拉起，拿到的进程**往往不是**真正拥有窗口的那个 | ✅ 已处理：改用**顶层窗口差集**（启动前后各拍一次快照），只要求「这张脸以前没见过」，与谁创建它无关（M20） |
| 浏览器**不暴露拖入文件的绝对路径** | `webkitGetAsEntry().fullPath` 只给得到文件名（`/Chrome.lnk`），`file.path` 又只有 Electron/WebView2 才提供 → `Test-Path` 必然失败 → **拖入添加完全不可用** | ✅ 已处理：前端改为同时上报**文件名**，宿主在桌面 / 公共桌面 / 开始菜单（递归）/ 快速启动 / 下载建索引**按名称解析**，命中优先取 `.lnk`，并可退一步按基名匹配（M20） |
| `Join-Path $env:APPDATA ...` 拼快速启动 / 下载目录 | 本机环境里 `$env:APPDATA`、`$env:USERPROFILE` 是**空的** → `Join-Path` 抛「无法将参数绑定到参数"Path"，因为该参数是空值」→ 整个 `/api/addbatch` **500** | ✅ 已修复：改用 `[Environment]::GetFolderPath()`（走 shell API，这些环境下仍返回正确路径）+ `Join-Safe` 空值护栏；并给解析器包 try/catch，任何意外都只回「没找到」而不是 500（M20） |
| 全局右键拦截在 **capture 阶段 + `stopPropagation()`** | `stopPropagation` 会阻断捕获链继续下行 → 冒泡阶段挂在图标上的 `contextmenu` 监听器**永远收不到事件** → 图标右键菜单点了没反应 | ✅ 已处理：菜单触发**并入同一个 capture 处理器**（并放行菜单自身与可编辑控件），不另挂监听器（M20） |
| PS 5.1 的 `Add-Type` 用的是**老编译器（C# 5）** | C# 7 的内联 out 声明 `out uint _` / `out MSG m` 报「无效的表达式项」→ `Add-Type` 失败 → 整个宿主起不来 | ✅ 已处理：先把变量声明出来，再作为 `out` 实参传入（M20） |
| 「移除快捷方式」一点即删、不可撤销 | 右键误点就丢图标 | ✅ 已处理：菜单**原地二次确认**——第一次点把该项变为「再点一次确认移除」，不做弹窗也不打扰（M20） |
| ICO 条目**全用 PNG 压缩** | GDI+ 老体系（`Icon.ToBitmap`）解不了 PNG 条目，报「请求的范围扩展超过了数组的结尾」；部分老程序的图标选择器同样读不出 | ✅ 已处理：**256px 用 PNG、16/32/48/64 用经典 32bpp BMP（DIB）** 的混合格式——GDI+ 四尺寸提取全通过（M22） |
| 无头浏览器截图**视口/DPI 陷阱** | SVG 不写死像素尺寸时按默认/视口解释，内容被放大裁切或偏到角落；`--default-background-color` 不设则透明角被垫成白底 | ✅ 已处理：svg 写死 `width`/`height` + `--force-device-scale-factor=1` + `--default-background-color=00000000`；老 headless 有单例锁易挂起，每尺寸独立 `--user-data-dir` + 限时收尾（M22） |
| 在本机跑浏览器自动化守护进程（`agent-browser`） | 会连带清掉已有的 Chrome/Edge 进程 → launcher 窗口被关 → 宿主按「前端心跳中断（窗口已关闭）」**自动退出** | ⚠️ 已知：做前端验证改用**系统已有的 Chrome + `--remote-debugging-port` + CDP**（node 22 自带 WebSocket，零依赖零下载）；另注意页面挂在**根路径 `/`**，不是 `/nova-launcher.html`（M20） |
| 干净机器零依赖程度 | 未知 | ⚠️ 仅本机验证；Edge 为 Win10/11 自带，理论上零装 |
| 浏览器被卸载 | 起不来 | ⚠️ 容错：尝试 Edge，失败回退系统默认 `start $url` |

---

## 8. 交付物清单

| 交付物 | 位置 | 说明 |
|--------|------|------|
| 宿主入口 | `NovaLauncher.Web\NovaLauncher.bat`（1234 B） | 双击即用（M29 起为目录根**唯一文件**，指向 data\ 内宿主） |
| 宿主主体 | `NovaLauncher.Web\data\NovaLauncher.ps1`（107428 B） | HTTP + 图标（**启动预热缺失项 + `.lnk` 解析目标兜底**）+ 启动（**启动后把新窗口置前**）+ 已安装应用枚举 + 使用频率/安装时间索引 + 批量添加 + **快捷方式按名称解析** + `explorer /select` 定位 + **Win32 窗口控制（`/api/win`：最小化/最大化/关闭/状态）** + **任务栏图标三件套（M28：WM_SETICON + 窗口 AUMID + AUMID 快捷方式 + TOOLWINDOW 重建按钮）**；M29 起宿主与数据同住 `data\`，根目录仅剩 bat 入口 |
| 界面 | `NovaLauncher.Web\data\nova-launcher.html`（80579 B） | 同源页面（拖拽投放 + 拖拽排序 + 已安装应用面板 + 六维排序 + 全选/全不选 + 失败提示 + **标题栏窗口三键**）；主界面**只留图标与名字**；连接状态为**绿点/红点**指示；图标**右键菜单**（打开 / 打开文件位置 / **重命名** / 移除快捷方式，含二次确认）；设置抽屉**一键检查应用有效性** + **外观区块置顶**；**窗口三键不依赖宿主**（关闭键降级浏览器关窗 + host-dead 降级态） |
| 应用图标 | `NovaLauncher.Web\data\nova-logo.ico`（36254 B，256/64/48/32/16）+ `nova-logo-256.png`（4200 B） | 与顶栏 Logo 同款；**任务栏/标题栏/Alt-Tab 图标（M28：宿主启动时经 AUMID 快捷方式 + WM_SETICON 三件套生效，另在开始菜单生成 `Nova Launcher.lnk` 可直接固定）**（M22 首做，M26 重制修复残缺） |
| 说明 | `NovaLauncher.Web\data\README.md`（约 9.2 KB） | | 用法 / 编码 / 数据目录 / FAQ |
| 验证报告 | `.traetemp\HTML宿主方案验证报告.md` | 首版 7 项接口 + 启动证据 + 4 截图 |
| 回归截图 | `.traetemp\截图\20260912-增量验证\`（10 张 PNG） | 主界面 / 设置抽屉 / 拖拽投放区 / 已安装应用面板 / 按使用频率 / 按安装时间 / 默认全不选 / 全选 / 勾选 10 个 / 添加后 |
| 增量截图 | `.traetemp\截图\20260912-拖拽排序\`（3 张）、`20260912-右键屏蔽\`（1 张）、`20260912-精简主界面\`（1 张）、`20260912-连接状态指示\`（3 张）、`20260912-最大化去标题栏\`（4 个）、`20260912-右键菜单与拖入添加\`（4 个） | 拖拽前/后/刷新后落盘；右键拦截验证；**主界面无标题文案**（M17）；**连接状态三态**（M18）；**最大化铺满工作区 + 自绘栏移出屏幕**（M19）；**图标右键菜单 + 置前 z 序 + 名称解析 + 页面侧交互**（M20） |
| 复用技能 | `~/.workbuddy/skills/windows-html-native-launcher/` | 沉淀本方案与 PS 5.1 编码陷阱 |
| 设计文档 | `DOCS/` | 01/02/03/（本 04） |

---

## 9. 里程碑进度看板

```text
M0 环境验证       [████████████]  已完成
M1 宿主骨架       [████████████]  已完成
M2 页面托管+状态  [████████████]  已完成
M3 图标提取       [████████████]  已完成
M4 启动/增删/排序 [████████████]  已完成
M5 界面(双主题)   [████████████]  已完成
M6 编码陷阱修复   [████████████]  已完成
M7 端到端验证     [████████████]  已完成
M8 绿色版交付     [████████████]  已完成
M9 增量回归(反馈) [████████████]  已完成
M10 排序增强      [████████████]  已完成
M11 勾选交互      [████████████]  已完成
M12 批量添加修复  [████████████]  已完成
M13 每行12图标    [████████████]  已完成
M14 拖拽落盘+图标 [████████████]  已完成
M15 屏蔽右键菜单  [████████████]  已完成
M16 全屏+窗口三键 [████████████]  已完成
M17 精简主界面文案 [████████████]  已完成
M18 连接状态圆点   [████████████]  已完成
M19 最大化+去自绘栏 [████████████]  已完成
M20 置前+右键+拖入  [████████████]  已完成
M21 右键重命名      [████████████]  已完成
M22 同款应用图标     [████████████]  已完成
M23 启动图标预热     [████████████]  已完成
M24 一键有效性检查   [████████████]  已完成
M25 抽屉外观置顶     [████████████]  已完成
M26 重制应用图标     [████████████]  已完成
M27 三键不依赖宿主   [████████████]  已完成
M28 任务栏图标修复   [████████████]  已完成
M29 目录重组(只留bat) [████████████]  已完成
M30 窗口化无边框      [████████████]  已完成
M31 CSD 残条修复      [████████████]  已完成
M32 半帧未光栅化修复  [████████████]  已完成
```

---

## 10. 与 03 / AGENTS.md 的关系（待办）

- **功能范围**：本方案 100% 覆盖 `02` 极简方案定义的 V1.0 功能；`03` 是其「WinUI 3 实现计划」，本 `04` 是「HTML+宿主实现计划」，**互为替代实现路径**。
- **AGENTS.md 待同步**：`.agent\AGENTS.md` 的「技术栈 / 目录结构 / 打包」三节仍描述 WinUI 3，**与 `NovaLauncher.Web` 代码不一致**。按「指定文件才改」的约定，已标记**待用户确认后再同步**。
- **已提前实现**（原列后续/OUT）：UWP/商店应用启动、系统已安装应用枚举（见 M9）；
  使用频率与安装时间排序（`02` 定义的 V2.0 统计能力，见 M10）。
- **后续增强**（未做）：干净机器零依赖实测；使用频率的持久化统计（当前取自系统 `UserAssist`，不落自己的库）。

> 本方案核心价值：在本机**无 .NET SDK / 无法构建 WinUI 3** 的前提下，仍交付了一个能真正启动程序、零安装、可视觉验收的 V1.0 启动页；并把全部踩坑（PS 5.1 编码、同源托管、安全自退）沉淀为可复用技能。
