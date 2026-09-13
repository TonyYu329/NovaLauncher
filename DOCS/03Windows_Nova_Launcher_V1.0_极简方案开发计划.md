# Windows Nova Launcher V1.0（极简方案）开发计划

> 文档版本：V1.0
> 产品代号：Nova Launcher
> 依据文档：`DOCS/02Windows_Nova_Launcher_V1.0_极简方案.md`（V1.0 权威范围）
> 参考文档：`DOCS/02Windows_Nova_Launcher_V1.0_详细产品与技术设计说明书.md`（V2.0 演进蓝图）
> 技术基线：C# + .NET 10 + WinUI 3 + Windows App SDK + System.Text.Json
> 平台范围：仅 Windows 10 / Windows 11 x64
> 编制日期：2026-09-11

---

## 1. 计划目标与范围

### 1.1 一句话目标

用**最少的代码**交付一个「漂亮 + 好用 + 稳定」的 Windows 快捷方式启动页：

```text
用户添加 EXE/LNK → 读取真实图标 → 首页显示 → 拖拽排序 → 调整图标大小 → 点击启动 → JSON 保存
```

### 1.2 开发策略（重要）

不按「先做全功能再美化」，而是**视觉优先、逐步加能力**：

```text
M0 环境骨架 → M1 视觉原型 → M2 数据存储 → M3 首页交互 → M4 拖拽排序
→ M5 图标大小/列数 → M6 设置面板 → M7 动画打磨 → M8 绿色版发布与验收
```

前 3 个阶段（M0–M2）必须先完成，尽早看到「漂亮的界面 + 能保存数据」。

### 1.3 V1.0 交付范围（IN）

| 编号 | 功能 | 说明 | 优先级 |
|------|------|------|--------|
| F1 | 添加 EXE/LNK | 设置页「＋添加应用」→ 文件选择器 → 选 EXE/LNK | P0 |
| F2 | 显示真实图标 | Shell API 读取目标图标并展示 | P0 |
| F3 | 拖拽排序 | 拖图标调整顺序，释放后保存 | P0 |
| F4 | 调整图标大小 | 滑块 36~160px，即时生效 | P0 |
| F5 | 点击启动 | 单击图标启动目标程序 | P0 |
| F6 | 删除应用 | 设置页移除、右键移除 | P0 |
| F7 | JSON 持久化 | `apps.json` + `settings.json` | P0 |
| F8 | 深色/浅色主题 | 默认深色，可切换 | P1 |
| F9 | 炫酷动画 | Mica/圆角/Hover/拖拽/阴影/光晕 | P1 |
| F10 | 每行图标数 | 4~8 / 自动 | P2 |

### 1.4 明确不做（OUT，防止范围蔓延）

> 以下均为 V2.0 演进项，V1.0 **一律不实现**：

- ❌ 自动扫描已安装软件（StartMenu / Registry / MSIX / AUMID）
- ❌ 安装时间 / 使用频率 / 最近使用排序与统计
- ❌ SQLite / ORM / Repository / Migration
- ❌ 全局搜索、全局快捷键 `Ctrl+Space`
- ❌ 系统托盘、云同步、插件市场、设置多页面
- ❌ 系统级卸载、清理注册表、系统优化、替换 Explorer Shell

### 1.5 技术选型

| 层 | 技术 | 说明 |
|----|------|------|
| 语言 | C# (.NET 10) | 单一语言 |
| UI | WinUI 3（Windows App SDK 最新稳定） | 原生 Windows 现代 UI |
| 序列化 | System.Text.Json | 读写 JSON，替代数据库 |
| 图标 | Windows Shell API | `ExtractAssociatedIcon` / `SHGetFileInfo` |
| 启动 | `ProcessStartInfo` / ShellExecute | EXE / LNK 启动 |
| 存储 | JSON 文件 | `%LOCALAPPDATA%\NovaLauncher\` |
| 打包分发 | 绿色版（非打包 + 自包含） | 免安装，解压即用 |

**不引入**：EF Core、Dapper、Serilog、DI 框架、Redis、SQLite、插件框架、搜索引擎。

---

## 2. 架构设计

### 2.1 极简分层

```text
┌────────────────────────────┐
│  UI  MainWindow / AppTile  │  XAML 视图 + 事件
└──────────────┬─────────────┘
               │
┌──────────────▼─────────────┐
│  AppService               │  添加/移除/排序/启动/图标
└──────────────┬─────────────┘
               │
┌──────────────▼─────────────┐
│  StorageService           │  apps.json / settings.json 读写
└────────────────────────────┘
```

> V1.0 **不强制 MVVM**，不引入 DI 容器；规模小，直接 `UI → AppService → JSON` 即可。

### 2.2 源码目录结构

```text
NovaLauncher/
├── App.xaml / App.xaml.cs        # 应用入口
├── MainWindow.xaml(.cs)          # 主窗口：顶栏 + 首页网格 + 设置抽屉
├── AppTile.xaml(.cs)             # 应用图标卡片（Hover/拖拽视觉）
├── AppItem.cs                    # 数据模型 name / path / sort
├── Settings.cs                   # 设置模型 iconSize / columns / theme
├── AppService.cs                 # 业务逻辑
├── StorageService.cs             # JSON 读写
├── Assets/                       # 图标、字体资源
└── NovaLauncher.csproj
```

### 2.3 数据模型

```csharp
// AppItem.cs —— 首页应用条目
public sealed class AppItem
{
    public string Name { get; set; } = "";   // 显示名称（默认取文件名，可改）
    public string Path { get; set; } = "";   // EXE / LNK 绝对路径
    public int    Sort { get; set; }         // 排序索引，越小越靠前
}

// Settings.cs —— 全局设置
public sealed class Settings
{
    public int     IconSize     { get; set; } = 80;    // 36~160
    public int     Columns      { get; set; } = 6;     // 4~8，0=自动
    public string  Theme        { get; set; } = "dark"; // dark | light
    public bool    ReduceMotion { get; set; } = false;
}
```

### 2.4 数据契约（JSON）

**apps.json**（数组，按 `sort` 升序渲染）

```json
[
  { "name": "Chrome", "path": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "sort": 0 },
  { "name": "VSCode", "path": "C:\\Program Files\\Microsoft VS Code\\Code.exe", "sort": 1 }
]
```

**settings.json**

```json
{
  "iconSize": 80,
  "columns": 6,
  "theme": "dark",
  "reduceMotion": false
}
```

### 2.5 运行期数据目录

```text
%LOCALAPPDATA%\NovaLauncher\
├── apps.json        # 首页应用列表
├── settings.json    # 设置
└── Icons\           # 图标缓存（可选，加速二次加载）
```

> 首次运行目录/文件不存在时自动创建并写入默认值；文件损坏时回退默认并备份为 `.bak`。

---

## 3. 开发阶段与里程碑

### M0 · 环境与骨架

**目标**：跑通一个带 Mica 背景的空白 WinUI 3 窗口。

| 任务 | 说明 |
|------|------|
| T0.1 | 创建 WinUI 3 项目（Windows App SDK），目标 .NET 10，x64 |
| T0.2 | 采用**非打包(Unpackaged)模式**，配置 `app.manifest` DPI 感知 |
| T0.3 | 建立目录结构与命名空间 |
| T0.4 | 主窗口套用 Mica 背景 + 圆角，`dotnet build` 通过 |

**交付物**：可运行的空白窗口。
**验收**：`dotnet build` 零错误，窗口正常显示 Mica 效果。

### M1 · 视觉原型（UI Shell）

**目标**：用假数据做出「炫酷首页」的静态视觉。

| 任务 | 说明 |
|------|------|
| T1.1 | 主窗口布局：顶栏（`✦ NOVA` + 设置齿轮）+ 内容区网格 |
| T1.2 | `AppTile` 控件：图标 + 名称，默认/悬停/按下三态 |
| T1.3 | 网格容器（`ItemsRepeater` / `GridView`），自适应列宽 |
| T1.4 | 深色/浅色主题资源字典（`ThemeDictionaries`） |
| T1.5 | 定义动画常量：`Fast=120 / Normal=180 / Medium=240 / Slow=320`(ms) |

**交付物**：静态首页视觉稿（硬编码 8~10 个假图标）。
**验收**：默认深色、悬停放大、圆角与阴影符合规范。

### M2 · 数据模型与存储

**目标**：数据可读写、可持久化。

| 任务 | 说明 |
|------|------|
| T2.1 | 定义 `AppItem` / `Settings` 模型 |
| T2.2 | `StorageService`：`System.Text.Json` 读写两个 JSON |
| T2.3 | 数据目录创建 + 默认值 + 损坏回退（`.bak`） |
| T2.4 | 启动时加载 `settings.json` → 应用主题/图标大小/列数 |

**交付物**：`StorageService` + 单测（读写往返）。
**验收**：重启应用后设置不丢失；空文件/坏文件不崩溃。

### M3 · 首页交互（展示 + 启动）

**目标**：真实应用出现在首页，点击可启动。

| 任务 | 说明 |
|------|------|
| T3.1 | 首页绑定 `List<AppItem>`（按 `sort`） |
| T3.2 | 图标加载：Shell API 读取真实图标 + 内存/磁盘缓存 |
| T3.3 | 异步分批加载图标（首屏不被阻塞） |
| T3.4 | 单击启动：EXE → `ProcessStartInfo`；LNK → ShellExecute |
| T3.5 | 启动失败提示「重新定位 / 移除」 |

**交付物**：可展示、可启动的首页。
**验收**：冷启动首屏可操作 < 1s；点击能拉起目标程序。

### M4 · 拖拽排序

**目标**：拖拽自由整理，顺序持久化。

| 任务 | 说明 |
|------|------|
| T4.1 | 拖拽阈值 6~10px，避免点击误触 |
| T4.2 | 拖拽视觉：放大 1.06~1.10 + 阴影 + 半透明占位 |
| T4.3 | 拖拽过程其他项弹性让位（150~220ms） |
| T4.4 | 释放后重排 `sort`，**一次性**写 `apps.json`（事务式，不逐帧写盘） |
| T4.5 | 重启后顺序完全一致 |

**交付物**：拖拽排序功能。
**验收**：拖动流畅（目标 60FPS），重启顺序不变。

### M5 · 图标大小与列数

**目标**：首页尺寸/密度可调。

| 任务 | 说明 |
|------|------|
| T5.1 | 设置项：图标大小滑块 36~160 |
| T5.2 | 设置项：每行图标数 4~8 / 自动 |
| T5.3 | 变更即时生效并写 `settings.json` |

**交付物**：尺寸调节能力。
**验收**：拖动滑块首页实时变化，重启保持。

### M6 · 设置面板（添加/移除）

**目标**：用户可自行管理应用列表。

| 任务 | 说明 |
|------|------|
| T6.1 | 右侧滑入式设置抽屉（200~260ms 过渡） |
| T6.2 | 「＋ 添加应用」→ `FileOpenPicker`（`.exe` / `.lnk`） |
| T6.3 | 读取名称（默认文件名）+ 图标 → 追加 `AppItem(sort = max+1)` |
| T6.4 | 列表每项「移除」按钮（仅移除记录，不卸载程序） |
| T6.5 | 首页右键菜单：启动 / 打开文件位置 / 移除 |
| T6.6 | 主题切换（深色/浅色）即时生效 |

**交付物**：完整设置面板。
**验收**：添加后立即出现在首页；移除后立即消失且 JSON 同步。

### M7 · 动画与视觉打磨

**目标**：达到「炫酷」标准。

| 任务 | 说明 |
|------|------|
| T7.1 | 统一过渡：Hover 120~160ms、抽屉 200~260ms、新增 180~260ms |
| T7.2 | 背景光晕（径向渐变，缓慢漂移），强度克制 |
| T7.3 | 「减少动画」开关（关闭光晕/漂移动画） |
| T7.4 | 圆角(12px)/阴影/边框弱化统一校色 |

**交付物**：打磨后的视觉体验。
**验收**：动画分级正确，无卡顿，低配机可关动画。

### M8 · 绿色版发布与验收

**目标**：输出免安装的绿色版（单个文件夹 / ZIP，双击即用）。

| 任务 | 说明 |
|------|------|
| T8.1 | 配置绿色版发布：`WindowsPackageType=None`、`SelfContained=true`、`WindowsAppSDKSelfContained=true`、`RuntimeIdentifier=win-x64` |
| T8.2 | 入口 `App.xaml.cs` 做一次 Bootstrap 初始化（非打包模式必需） |
| T8.3 | `dotnet publish -c Release` 输出单文件夹；**禁用** `PublishSingleFile` / `PublishTrimmed`（WinUI 不支持） |
| T8.4 | 冷启动性能实测（< 1s） |
| T8.5 | 手动验收：功能清单逐项过，压缩为 ZIP 分发 |

**绿色版发布配置（csproj）**：

```xml
<WindowsPackageType>None</WindowsPackageType>
<SelfContained>true</SelfContained>
<WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
<RuntimeIdentifier>win-x64</RuntimeIdentifier>
<PublishSingleFile>false</PublishSingleFile>
<PublishTrimmed>false</PublishTrimmed>
```

**发布命令**：

```bash
dotnet publish -c Release -r win-x64
```

**交付物**：`NovaLauncher-win-x64.zip`（解压即用，内含 `NovaLauncher.exe`）。
**验收**：在**未安装 .NET / Windows App SDK 运行时**的干净 Windows 10/11 上解压双击即可运行；程序清单为单个文件夹，免安装、不写注册表。

---

## 4. 任务清单（WBS 汇总）

| ID | 阶段 | 任务 | 依赖 | 估时 | 关键交付 |
|----|------|------|------|------|----------|
| T0.1–T0.4 | M0 | 项目骨架 + Mica 窗口 | — | 0.5d | 可运行空窗口 |
| T1.1–T1.5 | M1 | 首页视觉原型（假数据） | M0 | 1.0d | 静态炫酷首页 |
| T2.1–T2.4 | M2 | 模型 + StorageService | M0 | 0.5d | JSON 读写 |
| T3.1–T3.5 | M3 | 首页展示 + 图标 + 启动 | M1,M2 | 1.5d | 可用首页 |
| T4.1–T4.5 | M4 | 拖拽排序 + 持久化 | M3 | 1.0d | 拖拽排序 |
| T5.1–T5.3 | M5 | 图标大小 / 列数 | M2,M3 | 0.5d | 尺寸可调 |
| T6.1–T6.6 | M6 | 设置面板 + 添加/移除 | M3 | 1.5d | 应用管理 |
| T7.1–T7.4 | M7 | 动画与视觉打磨 | M4,M6 | 1.0d | 炫酷体验 |
| T8.1–T8.5 | M8 | 绿色版发布 + 验收 | 全部 | 0.5d | ZIP 绿色版 |
| — | — | **合计** | — | **≈ 8 人天** | V1.0 交付 |

> 估时为单人熟练开发参考值，不含需求反复与美化返工。

---

## 5. UI / 交互与动画规范

### 5.1 视觉规范

| 项 | 规范 |
|----|------|
| 背景 | Mica（默认）+ 可选 Acrylic/渐变 + 克制的径向光晕 |
| 圆角 | 卡片/容器 12px；弹窗 16px |
| 边框 | 尽量弱化，靠层次与阴影分层 |
| 阴影 | 轻量，避免明显黑边 |
| 字体 | Windows 默认 Fluent Typography（不捆绑第三方字体） |
| 图标 | 使用真实软件图标；UI 图标用 Segoe Fluent Icons |
| 默认主题 | 深色 |

### 5.2 尺寸与布局

| 项 | 规范 |
|----|------|
| 窗口默认 | 1100 × 720（最小 800 × 520） |
| 卡片默认 | 80 × 104 px；图标默认 64 × 64 px |
| 图标大小 | 36 ~ 160 px（滑块） |
| 网格列数 | 默认 6；可 4/5/6/7/8 / 自动 |
| 间距 | 水平 16~32px，垂直 16~28px，自适应 |
| 响应式 | 1200+ → 6~8 列；1000 → 6 列；800 → 4~5 列；最小窗口 3~4 列 |

### 5.3 动画分级

| 场景 | 时长 | 效果 |
|------|------|------|
| Hover | 120~160ms | 缩放 1.03~1.08 + 阴影增强 |
| Settings 抽屉 | 200~260ms | 位移 X + 透明度 |
| 新增应用 | 180~260ms | 缩放 + 淡入 |
| 拖拽重排 | 150~220ms | 弹性让位 |
| 搜索结果 | 100~160ms | 淡入 |

> 常量：`Fast=120 / Normal=180 / Medium=240 / Slow=320`(ms)。**禁止所有动画使用同一时长。**

### 5.4 交互行为

| 操作 | 行为 |
|------|------|
| 单击图标 | 启动目标程序 |
| 双击 | 不重复启动 |
| 右键 | 启动 / 打开文件位置 / 移除 / 属性 |
| 拖拽 | 超过 6~10px 进入拖拽，释放保存顺序 |
| 设置齿轮 | 右侧抽屉滑入，非跳转新页面 |

---

## 6. 验收标准

### 6.1 功能验收

- [ ] 能通过文件选择器添加 `.exe` / `.lnk`，首页立即出现且图标正确
- [ ] 单击图标能启动目标程序
- [ ] 拖拽可调整顺序，重启后顺序不变
- [ ] 图标大小滑块、每行图标数、主题切换均即时生效并持久化
- [ ] 移除应用后首页消失且 `apps.json` 同步
- [ ] `apps.json` / `settings.json` 存在且格式正确；损坏时可回退不崩溃

### 6.2 性能验收

- [ ] 冷启动到首屏可操作 < 1s（SSD）
- [ ] 空闲 CPU 接近 0%，内存 < 200MB
- [ ] 拖拽目标 60FPS

### 6.3 健壮性验收

- [ ] 目标路径失效时给出「重新定位/移除」提示，不崩溃
- [ ] 首次运行自动创建数据目录与默认文件
- [ ] 高 DPI（100%–200%）下图标不模糊、UI 不错位

---

## 7. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 图标提取慢导致首屏卡顿 | 体验差 | 分批异步加载 + 磁盘缓存（`Icons/`）|
| LNK 目标解析失败 | 无法启动 | 优先 ShellExecute；失败给重新定位 |
| 拖拽与点击误触 | 体验差 | 拖拽阈值 6~10px |
| JSON 写入中断损坏 | 数据丢失 | 临时文件 + 原子替换；损坏备份 `.bak` |
| WinUI 3 / Windows App SDK 版本兼容 | 构建失败 | 锁定稳定版本基线，记录于项目说明 |
| 范围蔓延（想加扫描/统计） | 延期 | 严格遵守 1.4 OUT 清单，V2.0 再加 |
| 高 DPI 图标模糊 | 视觉差 | 按 DPI 多尺寸缓存或高分辨率源缩放 |

---

## 8. 交付物清单

| 交付物 | 位置 | 说明 |
|--------|------|------|
| 源码工程 | `NovaLauncher/`（`NovaLauncher.csproj` 等） | 全部 XAML + C# |
| 绿色版 | `NovaLauncher-win-x64.zip` | 解压即用，免安装 |
| 运行期数据 | `%LOCALAPPDATA%\NovaLauncher\` | apps.json / settings.json |
| 修改记录 | 项目根 `修改记录.md` | 每次修改追加 |
| 设计文档 | `DOCS/` | 01/02(详细)/02(极简)/03(本计划) |

---

## 9. 里程碑进度看板（建议）

```text
M0 环境骨架       [░░░░░░░░░░]  未开始
M1 视觉原型       [░░░░░░░░░░]  未开始   ← 先做，尽早看到界面
M2 数据存储       [░░░░░░░░░░]  未开始
M3 首页交互       [░░░░░░░░░░]  未开始
M4 拖拽排序       [░░░░░░░░░░]  未开始
M5 图标大小/列数  [░░░░░░░░░░]  未开始
M6 设置面板       [░░░░░░░░░░]  未开始
M7 动画打磨       [░░░░░░░░░░]  未开始
M8 绿色版发布     [░░░░░░░░░░]  未开始
```

---

> 本计划严格受 `02...极简方案.md` 约束：**先以极少代码把「漂亮 + 好用 + 稳定」的核心体验做出来**，所有应用扫描、数据库、统计、全局快捷键等能力待 V1.0 稳定后再逐项加回（见详细设计说明书）。
