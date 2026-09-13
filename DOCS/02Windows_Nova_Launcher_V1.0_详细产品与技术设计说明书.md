# Windows Nova Launcher V1.0 产品需求、UI设计、技术架构与开发实施说明书

> 文档版本：V1.0  
> 产品代号：Nova Launcher  
> 产品定位：Windows个人应用工作台 / Personal Application Workspace  
> 平台范围：仅 Windows 10 / Windows 11 x64  
> 技术基线：C# + .NET 10 + WinUI 3 + Windows App SDK 2.4.x + SQLite  
> 目标：形成一款可长期驻留 Windows 桌面、以视觉体验和启动效率为核心的个人应用启动器。

---

# 1. 产品概述

## 1.1 产品定位

Nova Launcher 不是 Windows“开始菜单”的替代品，也不是传统的软件管理器，而是一个高度个性化的 Windows 应用启动工作台。

产品核心价值：

1. 用户可以把自己最常用的软件集中到一个首页。
2. 首页只展示用户主动选择的应用，不被系统安装数量干扰。
3. 图标可以拖拽调整顺序，布局和图标大小可定制。
4. 设置中心自动发现 Windows 中已经安装或存在的应用。
5. 支持按名称、安装时间、最近使用、使用次数等维度排序。
6. 启动器自动记录通过 Nova Launcher 启动的应用使用数据。
7. 支持全局快捷键快速呼出，逐步形成个人 Windows 工作台。
8. 界面视觉优先，强调现代、科技、流畅、轻量和高级感。

## 1.2 核心用户

主要面向：

- 软件数量较多的 Windows 高级用户
- 程序员、设计师、产品经理、管理人员
- 经常切换多个办公软件的用户
- 希望桌面简洁、应用集中管理的用户
- 希望通过键盘快速启动程序的高频用户

## 1.3 V1.0 核心场景

### 场景A：启动常用软件

用户打开 Nova Launcher：

首页立即显示：

- Chrome
- Edge
- Visual Studio Code
- 微信
- Photoshop
- Codex
- 其他个人常用软件

用户点击图标后直接启动目标应用。

### 场景B：整理首页

用户按住某个图标并拖动：

Chrome → 第一个位置

VSCode → 第二个位置

微信 → 第三个位置

释放鼠标后自动保存。

### 场景C：发现新安装软件

用户打开设置：

应用管理 → 全部应用

系统自动列出已安装应用。

用户可以：

- 搜索
- 排序
- 添加到首页
- 移出首页
- 打开文件位置
- 查看属性

### 场景D：快速启动

用户在 Windows 任意位置按：

Ctrl + Space

Nova Launcher 搜索框浮出。

输入：

chrome

按 Enter。

直接启动 Chrome，窗口自动退出或隐藏。

---

# 2. 产品原则

## 2.1 第一原则：界面优先

软件的第一感受必须是：

“漂亮、现代、顺滑。”

不得出现传统企业软件式的大量表格、厚重边框、复杂菜单。

## 2.2 第二原则：启动优先

从“打开 Nova”到“看到可点击的首页”应尽可能短。

数据库加载和应用发现必须异步化。

## 2.3 第三原则：用户控制优先

首页的顺序由用户控制。

系统可以提供推荐，但不得未经用户确认自动改变首页布局。

## 2.4 第四原则：数据可恢复

任何拖拽、添加、移除和设置变更都应该自动持久化。

应用异常退出后，不应丢失用户布局。

## 2.5 第五原则：为 V2.0 留扩展空间

V1.0 只做应用启动器，但核心模型必须抽象成 LauncherItem，后续可以扩展：

- 文件
- 文件夹
- URL
- 脚本
- 命令
- 项目
- AI工具

---

# 3. 产品信息架构

V1.0 一级结构：

```text
Nova Launcher
│
├── 首页 Home
│   ├── 我的应用
│   ├── 应用搜索
│   └── 最近使用
│
├── 应用管理 App Management
│   ├── 全部应用
│   ├── 已添加
│   └── 未添加
│
└── 设置 Settings
    ├── 外观
    ├── 首页布局
    ├── 快捷键
    ├── 启动行为
    └── 数据
```

---

# 4. 首页详细需求

## 4.1 首页整体结构

建议窗口尺寸：

- 默认：1100 × 720
- 最小：800 × 520
- 最大：跟随窗口
- DPI：必须支持 Windows 高 DPI

布局：

```text
┌──────────────────────────────────────────────────────┐
│                                                      │
│  ✦ NOVA                              搜索    ⚙       │
│                                                      │
│                  我的应用                             │
│                                                      │
│       [图标] [图标] [图标] [图标] [图标]              │
│        Chrome VSCode 微信    Edge   PS               │
│                                                      │
│       [图标] [图标] [图标] [图标] [图标]              │
│        QQ    Codex Terminal Git  其他                │
│                                                      │
│                                                      │
│                  最近使用                             │
│           Chrome · VSCode · 微信                      │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## 4.2 顶栏

左：

- 产品 Logo
- 产品名称 NOVA

右：

- 搜索按钮
- 设置按钮
- 可选：最小化/关闭

要求：

- 顶栏无厚重边框
- 使用 Mica/Acrylic
- 鼠标 hover 有轻微高亮
- 设置按钮必须有 Tooltip

## 4.3 首页标题

默认：

“我的应用”

允许用户在设置中修改：

- 我的应用
- 常用应用
- 工作台
- My Apps
- 自定义标题

## 4.4 应用卡片

每个应用卡片由：

```text
AppTile
├── Icon
├── Name
├── HoverBackground
├── HoverShadow
└── ContextMenu
```

组成。

默认显示：

- 应用图标
- 应用名称

推荐默认大小：

80 × 104 px。

图标默认：

64 × 64 px。

可配置图标大小：

36 ~ 160 px。

## 4.5 应用卡片状态

### Default

- 无边框
- 图标正常
- 名称正常

### Hover

- 缩放 1.03 ~ 1.08
- 卡片背景轻微出现
- 阴影增强
- 图标亮度轻微提高
- 过渡 120~180ms

### Pressed

- 缩放 0.98
- 轻微位移
- 触发点击动画

### Dragging

- 缩放约 1.06~1.10
- 增加阴影
- 背景透明度提高
- 原位置显示占位区域

### Disabled

- 半透明
- 鼠标不可用
- Tooltip 说明原因

## 4.6 首页点击行为

单击：

直接启动。

双击：

不重复启动，不做特殊动作。

右键：

显示上下文菜单。

## 4.7 应用右键菜单

标准菜单：

```text
启动
以管理员身份运行
打开文件位置
复制路径
移出首页
重命名
属性
```

若目标不可用：

```text
重新定位
删除记录
```

---

# 5. 拖拽排序详细设计

## 5.1 排序模式

默认：

“用户自定义排序”。

每个 LauncherItem 有一个 sort_index。

## 5.2 拖拽流程

```text
MouseDown
  ↓
判断是否进入 DragThreshold
  ↓
开始拖拽
  ↓
计算鼠标所在位置
  ↓
确定目标索引
  ↓
其他项目执行位移动画
  ↓
释放鼠标
  ↓
更新 SortIndex
  ↓
数据库持久化
```

## 5.3 DragThreshold

鼠标移动超过 6~10 px 才进入拖拽。

避免用户点击时误触拖动。

## 5.4 拖拽占位

拖动某项后：

```text
A B C D E

拖动 D → B 和 C 之间

A B [D] C E
```

目标位置显示动画占位。

## 5.5 排序持久化

释放拖拽时一次性保存。

不要每次鼠标移动都写 SQLite。

事务：

```text
BEGIN
UPDATE LauncherItems
SET sort_index = ...
COMMIT
```

## 5.6 排序恢复

应用启动时按照：

```sql
ORDER BY sort_index ASC
```

读取。

---

# 6. 首页图标布局

## 6.1 网格

V1.0采用网格布局。

默认：

6列。

可配置：

- 4列
- 5列
- 6列
- 7列
- 8列
- 自动

## 6.2 间距

水平：

16~32 px。

垂直：

16~28 px。

随窗口尺寸进行自适应。

## 6.3 自适应原则

不要使用大量固定坐标。

使用：

- Grid
- ItemsRepeater
- UniformGrid或自定义 Layout

保证窗口缩放后布局稳定。

---

# 7. 设置中心详细设计

## 7.1 设置打开方式

点击：

右上角齿轮。

默认：

右侧抽屉滑入。

动画：

- 180~260ms
- Opacity
- Translation X

## 7.2 设置一级区域

```text
应用管理
外观
首页
快捷键
启动
数据
关于
```

## 7.3 应用管理界面

顶部：

```text
应用管理

[ 搜索应用........................ ]

全部应用 | 已添加 | 未添加

排序：
[名称 A-Z ▼]
```

排序选项：

- 名称 A-Z
- 名称 Z-A
- 安装时间最新
- 安装时间最早
- 最近使用
- 使用次数最多
- 使用次数最少
- 发布者
- 自定义

## 7.4 应用列表

每行：

```text
[复选框] [图标] Chrome       Google     2026-08-10
[复选框] [图标] VSCode       Microsoft  2026-07-15
```

推荐：

每行高度 64~76 px。

避免传统 DataGrid 风格。

## 7.5 添加逻辑

点击：

“添加到首页”

立即：

- 写 LauncherItem
- 分配新的 sort_index
- 首页出现新卡片
- 播放进入动画

## 7.6 删除首页

点击：

“移出首页”

只删除 LauncherItem。

不要删除 Application 数据。

这样后续仍能重新添加。

---

# 8. 应用发现系统

必须建立统一 Application Discovery Service。

## 8.1 数据来源

V1.0至少支持：

1. 当前用户 Start Menu
2. 所有用户 Start Menu
3. Registry Uninstall
4. MSIX/AppX
5. Shell AppsFolder / AUMID
6. 用户自定义路径

## 8.2 Start Menu

扫描：

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs
%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs
```

递归查找：

```text
*.lnk
*.url
```

V1.0主要处理 .lnk。

## 8.3 Registry

读取：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall
HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall
HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
```

主要字段：

```text
DisplayName
DisplayVersion
Publisher
InstallDate
InstallLocation
DisplayIcon
UninstallString
```

## 8.4 MSIX / AppX

获取：

- DisplayName
- PackageFullName
- PackageFamilyName
- Version
- InstallLocation
- Logo
- Publisher

## 8.5 AUMID

支持现代 Windows 应用。

记录：

```text
AUMID
PackageFamilyName
ApplicationUserModelId
```

启动优先使用稳定标识，而不是猜测 exe 路径。

## 8.6 自定义程序

用户可以：

```text
添加自定义应用
```

选择：

- EXE
- LNK
- BAT
- CMD
- URL

如果 V1.0 GUI 中支持选择文件，则内部统一转化为 LauncherItem/Application。

---

# 9. 应用去重规则

同一个软件可能来自：

- Start Menu
- Registry
- MSIX
- AUMID

必须统一。

## 9.1 去重优先级

优先：

```text
AUMID
PackageFamilyName + AppId
ExecutablePath
Shortcut Target
DisplayName + Publisher
```

## 9.2 Canonical Application Id

内部生成稳定 ID。

推荐：

```text
application_id = SHA256(
    normalized_identity
)
```

例如：

```text
sha256("exe|c:\program files\google\chrome\application\chrome.exe")
```

## 9.3 路径规范化

统一：

- 大小写处理
- 路径分隔符
- 环境变量展开
- 绝对路径
- 去掉尾部分隔符

---

# 10. 图标系统

## 10.1 Icon Service

提供：

```text
GetApplicationIcon(Application application)
```

根据应用来源选择：

```text
LNK      → Shell shortcut icon
EXE      → ExtractAssociatedIcon / Shell
MSIX     → Package logo
AUMID    → Package logo
```

## 10.2 图标缓存

缓存目录：

```text
%LOCALAPPDATA%\NovaLauncher\Icons\
```

文件名：

```text
IconHash.png
```

## 10.3 图标缓存 Key

建议由：

```text
ApplicationId
+
IconSource
+
IconSourceLastWriteTime
```

生成。

如果 exe 更新时间变化：

重新加载图标。

## 10.4 缓存尺寸

建议同时缓存：

- 32
- 48
- 64
- 96
- 128
- 256

或者优先缓存 256 高质量源图，运行时缩放。

## 10.5 图标加载策略

首页：

第一批只加载可见区域。

其余：

后台异步。

避免一次加载上百个 EXE 图标导致启动卡顿。

---

# 11. 搜索功能

## 11.1 首页搜索

点击：

搜索按钮。

同时支持键盘：

Ctrl + Space。

## 11.2 搜索字段

搜索：

- Name
- DisplayName
- Publisher
- ExecutableName
- InstallLocation

## 11.3 搜索权重

推荐：

```text
名称完全匹配        100
名称前缀            80
名称包含            60
发布者              40
exe文件名           30
安装路径            20
```

## 11.4 搜索结果

显示：

```text
Chrome
Google Chrome
最近使用：今天 14:23
```

## 11.5 键盘操作

```text
↑ ↓
Enter
Esc
```

必须完整支持。

---

# 12. 使用统计

## 12.1 统计原则

只统计通过 Nova Launcher 启动的应用。

不要默认做系统级行为监控。

这样实现简单、透明，也避免隐私问题。

## 12.2 记录字段

```text
launch_count
last_used_at
first_used_at
total_run_seconds
```

## 12.3 启动记录

成功调用启动：

```text
LaunchCount += 1
LastUsedAt = now
```

失败：

只记录错误日志，不增加成功使用次数。

## 12.4 最近使用

按照：

```sql
ORDER BY last_used_at DESC
```

## 12.5 使用次数

按照：

```sql
ORDER BY launch_count DESC
```

## 12.6 使用频率评分

推荐：

```text
UsageScore =
    LaunchCountWeight * normalizedLaunchCount
    +
    RecentWeight * recentScore
```

默认：

```text
LaunchCountWeight = 0.4
RecentWeight = 0.6
```

recentScore可采用：

```text
exp(-ageHours / decayHours)
```

默认 decayHours = 168。

---

# 13. 启动服务

建立：

```text
ILaunchService
```

核心方法：

```csharp
Task<LaunchResult> LaunchAsync(Application application);
Task<LaunchResult> LaunchAsAdminAsync(Application application);
```

## 13.1 EXE

使用 ProcessStartInfo。

## 13.2 LNK

优先：

Shell Execute。

## 13.3 AUMID

调用 Windows Shell 能力启动。

## 13.4 BAT/CMD

通过：

```text
cmd.exe /c
```

启动。

## 13.5 URL

使用默认浏览器：

```text
Process.Start(url)
```

---

# 14. 启动异常处理

可能情况：

- 文件不存在
- 路径改变
- 权限不足
- 应用已卸载
- AUMID失效
- Shortcut失效

处理方式：

```text
应用启动失败

目标位置：
D:\xxx\xxx.exe

[重新定位] [移出首页] [取消]
```

如果是首页应用：

显示一个小警告标识。

---

# 15. 重新定位

用户选择：

“重新定位”。

打开文件选择器。

匹配：

- exe
- lnk

找到以后：

更新 Application。

不改变 LauncherItem 的：

- sort_index
- custom_name
- is_favorite

---

# 16. 外观设计

## 16.1 默认主题

Dark。

建议风格：

“Fluent + Glass + Tech”。

## 16.2 主题

支持：

- 跟随系统
- 浅色
- 深色

## 16.3 背景

V1.0：

- Mica
- Acrylic
- 渐变背景

V1.1：

- 壁纸模糊
- 动态光晕

## 16.4 动态光晕

可以在背景绘制：

- 大型径向渐变
- 缓慢漂移

必须限制动画强度。

设置：

“减少动画”。

---

# 17. 动画规范

定义统一动画常量。

```text
Fast = 120ms
Normal = 180ms
Medium = 240ms
Slow = 320ms
```

## 17.1 Hover

120~160ms。

## 17.2 Settings Drawer

200~260ms。

## 17.3 App Added

180~260ms。

## 17.4 Drag Reorder

150~220ms。

## 17.5 Search Result

100~160ms。

不得所有动画都使用同一个时间。

---

# 18. 窗口行为

## 18.1 普通启动

打开标准窗口。

## 18.2 关闭

关闭窗口时：

默认退出。

可设置：

“关闭窗口后最小化到托盘”。

## 18.3 系统托盘

V1.0可选，建议实现。

右键：

```text
打开 Nova
搜索应用
设置
退出
```

## 18.4 开机启动

设置：

“随 Windows 启动”。

建议使用：

Windows Startup / App Startup机制。

不要通过修改 Registry Run 进行隐藏式行为。

---

# 19. 全局快捷键

默认：

```text
Ctrl + Space
```

用户可在设置中重新配置。

注册失败：

显示：

“快捷键已被其他软件占用。”

允许重新设置。

快速启动模式：

```text
Ctrl + Space
 ↓
搜索面板
 ↓
输入
 ↓
Enter
 ↓
启动
 ↓
自动隐藏
```

---

# 20. 快速搜索窗口

推荐做成独立轻量窗口。

大小：

600 × 420 左右。

结构：

```text
┌─────────────────────────────────────┐
│  🔍 搜索应用                         │
│                                     │
│  Chrome                             │
│  VSCode                             │
│  微信                               │
│                                     │
│  ↑↓ 选择       Enter 启动      Esc 关闭 │
└─────────────────────────────────────┘
```

默认不显示复杂设置。

---

# 21. 数据库设计

数据库：

SQLite。

数据库文件：

```text
%LOCALAPPDATA%\NovaLauncher\Data\launcher.db
```

---

## 21.1 Applications

```sql
CREATE TABLE Applications (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    display_name TEXT,
    publisher TEXT,
    version TEXT,
    install_date TEXT,
    install_path TEXT,
    executable_path TEXT,
    shortcut_path TEXT,
    aumid TEXT,
    package_family_name TEXT,
    source_type INTEGER NOT NULL,
    icon_key TEXT,
    is_installed INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

## 21.2 LauncherItems

```sql
CREATE TABLE LauncherItems (
    id TEXT PRIMARY KEY,
    application_id TEXT NOT NULL,
    sort_index INTEGER NOT NULL,
    custom_name TEXT,
    is_favorite INTEGER NOT NULL DEFAULT 1,
    is_hidden INTEGER NOT NULL DEFAULT 0,
    icon_size INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(application_id) REFERENCES Applications(id)
);
```

## 21.3 UsageStats

```sql
CREATE TABLE UsageStats (
    application_id TEXT PRIMARY KEY,
    launch_count INTEGER NOT NULL DEFAULT 0,
    last_used_at TEXT,
    first_used_at TEXT,
    total_run_seconds INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(application_id) REFERENCES Applications(id)
);
```

## 21.4 Settings

```sql
CREATE TABLE Settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT NOT NULL
);
```

## 21.5 ScanSources

```sql
CREATE TABLE ScanSources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_type INTEGER NOT NULL,
    source_path TEXT,
    last_scan_at TEXT,
    scan_hash TEXT
);
```

---

# 22. 枚举定义

建议：

```csharp
public enum ApplicationSourceType
{
    StartMenu = 1,
    Registry = 2,
    Msix = 3,
    AppUserModelId = 4,
    Custom = 5
}
```

---

# 23. 核心领域对象

## Application

```csharp
public sealed class Application
{
    public string Id { get; init; }
    public string Name { get; set; }
    public string? Publisher { get; set; }
    public string? ExecutablePath { get; set; }
    public string? ShortcutPath { get; set; }
    public string? Aumid { get; set; }
    public ApplicationSourceType SourceType { get; set; }
    public DateTimeOffset? InstallDate { get; set; }
    public bool IsInstalled { get; set; }
}
```

## LauncherItem

```csharp
public sealed class LauncherItem
{
    public string Id { get; init; }
    public string ApplicationId { get; init; }
    public int SortIndex { get; set; }
    public string? CustomName { get; set; }
    public bool IsFavorite { get; set; }
    public int? IconSize { get; set; }
}
```

---

# 24. 服务层设计

建议接口：

```text
IApplicationDiscoveryService
IApplicationRepository
ILauncherRepository
IUsageService
ILaunchService
IIconService
IShortcutService
ISearchService
ISettingsService
IHotkeyService
IThemeService
IStartupService
```

---

# 25. MVVM结构

页面：

```text
HomePage
HomeViewModel

AppManagementPage
AppManagementViewModel

SettingsPage
SettingsViewModel
```

控件：

```text
AppTile
AppGrid
SearchOverlay
SettingsDrawer
```

使用：

```text
CommunityToolkit.Mvvm
```

实现：

- ObservableObject
- RelayCommand
- AsyncRelayCommand

---

# 26. 启动流程

```text
App Start
  ↓
Initialize DI
  ↓
Initialize SQLite
  ↓
Load Settings
  ↓
Load LauncherItems
  ↓
Render Home
  ↓
Async Application Discovery
  ↓
Update Application Index
  ↓
Async Icon Load
  ↓
Ready
```

关键点：

“首页渲染不得等待完整扫描。”

---

# 27. 应用发现流程

```text
Start Scan
  ↓
StartMenu Scanner
  ↓
Registry Scanner
  ↓
MSIX Scanner
  ↓
AUMID Scanner
  ↓
Custom Scanner
  ↓
Normalize
  ↓
Deduplicate
  ↓
Upsert Applications
  ↓
Mark Missing Applications
  ↓
Finish
```

---

# 28. 增量扫描

数据库已有数据时：

只重新扫描变化来源。

建议：

启动时：

快速检查。

后台：

完整同步。

设置页面打开时：

如果距上次扫描超过：

10分钟。

再触发一次发现扫描。

---

# 29. 已卸载应用处理

扫描后发现：

```text
Application.IsInstalled = false
```

不要自动删除。

原因：

可能用户临时移动程序。

首页仍存在时：

显示：

“目标不可用”。

连续多次确认不存在后可以提示：

“发现应用已不可用，是否从首页移除？”

---

# 30. 文件夹规划

应用目录：

```text
%LOCALAPPDATA%\NovaLauncher\
```

结构：

```text
NovaLauncher
├── Data
│   └── launcher.db
├── Icons
├── Logs
├── Cache
├── Backups
└── Settings
```

---

# 31. 数据备份

用户设置页：

“导出数据”。

导出：

```text
launcher-backup.json
```

包含：

- 首页布局
- 自定义名称
- 设置
- 应用识别信息

不直接复制 exe。

恢复时重新扫描本机应用并匹配。

---

# 32. 配置文件

推荐：

SQLite 保存业务数据。

JSON 只用于：

- Debug
- 导出
- Import
- 临时配置

不要把所有状态写 JSON。

---

# 33. 日志

使用：

Serilog。

日志目录：

```text
%LOCALAPPDATA%\NovaLauncher\Logs\
```

级别：

- Information
- Warning
- Error

Release 默认不记录敏感路径之外的过度信息。

---

# 34. 错误码体系

建议：

```text
NOVA1001 = ApplicationNotFound
NOVA1002 = LaunchFailed
NOVA1003 = ShortcutInvalid
NOVA1004 = PermissionDenied
NOVA1005 = AumidLaunchFailed
NOVA1006 = IconLoadFailed
NOVA1007 = DatabaseError
NOVA1008 = HotkeyRegisterFailed
NOVA1009 = ScanFailed
NOVA1010 = InvalidConfiguration
```

---

# 35. 性能指标

## 冷启动

目标：

Windows SSD 环境：

- 首屏可操作 < 1秒
- 数据库初始化正常 < 500ms
- 图标异步加载

## 热启动

目标：

< 500ms。

## 搜索

目标：

本地应用索引情况下：

< 100ms。

## 拖拽

要求：

60 FPS 为目标。

## 数据库

首页查询：

< 50ms。

---

# 36. 内存目标

正常空闲：

建议：

< 200MB。

快速搜索模式：

尽可能保持：

< 150MB。

不得持续扫描导致内存增长。

---

# 37. CPU目标

空闲状态：

接近 0%。

只有：

- 扫描
- 搜索
- 图标加载

期间短暂升高。

不得轮询整个磁盘。

---

# 38. 安全与权限

原则：

- 默认普通用户运行
- 不需要管理员权限
- 不修改系统关键配置
- 不注入其他进程
- 不监控其他应用内容
- 不读取其他应用私密数据

仅使用 Windows 官方能力进行：

- 软件发现
- 图标获取
- 启动应用
- 注册快捷键

---

# 39. UI视觉细节规范

## 字体

优先：

Windows 默认 Fluent Typography。

避免捆绑第三方字体。

## 图标

优先：

Segoe Fluent Icons。

应用图标：

使用真实软件图标。

## 圆角

推荐：

12px。

重要弹窗：

16px。

## 阴影

轻量。

避免明显黑色阴影。

## 边框

尽可能弱化。

## 背景

以玻璃透明感为主。

---

# 40. 首页视觉优先级

界面必须遵循：

```text
背景
 ↓
标题
 ↓
应用图标
 ↓
应用名称
 ↓
其他信息
```

不要让：

- 时间
- 软件版本
- Publisher
- 安装日期

等信息干扰首页。

这些内容只在设置和右键菜单中出现。

---

# 41. 响应式设计

窗口变化：

### 1200+

6~8列。

### 1000

6列。

### 800

4~5列。

### 最小窗口

3~4列。

不要出现：

- 图标重叠
- 文本裁切
- 卡片出屏

---

# 42. 多显示器

V1.0至少支持：

- 当前显示器打开
- 记住上次窗口位置
- DPI切换正确

---

# 43. DPI

必须支持：

- 100%
- 125%
- 150%
- 175%
- 200%

不得出现：

- 图标模糊
- UI错位
- 点击区域错误

---

# 44. 无障碍

最基本支持：

- 键盘操作
- Tab 导航
- Enter 启动
- Esc 关闭搜索
- Tooltip
- 高对比度可用

---

# 45. 设置项完整定义

## 外观

```text
主题
[跟随系统 / 浅色 / 深色]

背景材质
[Mica / Acrylic / Solid]

动画
[完整 / 简化 / 关闭]

背景效果
[开 / 关]
```

## 首页

```text
图标大小
[滑块 36~160]

列数
[自动/4/5/6/7/8]

图标名称
[显示/隐藏]

标题
[自定义]

最近使用
[显示/隐藏]
```

## 快捷键

```text
全局启动快捷键
Ctrl + Space
```

## 启动

```text
随 Windows 启动
[开/关]

关闭窗口后
[退出 / 托盘]

启动时扫描
[快速 / 标准]
```

## 数据

```text
立即扫描
清理无效应用
导出数据
导入数据
打开数据目录
查看日志
```

---

# 46. 关于页面

显示：

```text
Nova Launcher
Version 1.0.0

Windows Personal Application Workspace

检查更新
开源许可
反馈问题
```

---

# 47. V1.0 不做的功能

为了控制项目范围，以下不进入 V1.0：

- 系统级软件卸载
- 清理注册表
- 系统优化
- 文件搜索
- AI助手
- 云同步
- 多用户同步
- 在线应用商店
- 插件市场
- 自动修改 Windows 桌面
- 替换 Explorer Shell

这些功能后续单独规划。

---

# 48. V1.1规划

加入：

1. 全局快速搜索优化
2. 最近使用
3. 最常使用
4. 托盘
5. 推荐应用
6. 更丰富背景效果
7. 文件和文件夹快捷方式

---

# 49. V2.0扩展架构

把 LauncherItem 抽象成：

```text
LauncherItem
├── Application
├── File
├── Folder
├── Url
├── Script
├── Command
└── Project
```

最终：

```text
我的工作台

应用
文件
文件夹
网址
脚本
项目
AI
```

这样 Nova Launcher 可以进一步成为：

> Windows 个人工作操作系统入口。

---

# 50. 项目目录设计

```text
NovaLauncher.sln

src
├── NovaLauncher.App
├── NovaLauncher.Core
├── NovaLauncher.Infrastructure
└── NovaLauncher.Contracts

tests
├── NovaLauncher.Core.Tests
└── NovaLauncher.Infrastructure.Tests

docs
├── PRD.md
├── UI.md
├── Architecture.md
├── Database.md
└── DevelopmentPlan.md
```

---

# 51. App项目目录

```text
NovaLauncher.App
│
├── App.xaml
├── App.xaml.cs
├── MainWindow.xaml
├── MainWindow.xaml.cs
│
├── Views
│   ├── HomePage.xaml
│   ├── AppManagementPage.xaml
│   └── SettingsPage.xaml
│
├── ViewModels
│   ├── HomeViewModel.cs
│   ├── AppManagementViewModel.cs
│   └── SettingsViewModel.cs
│
├── Controls
│   ├── AppTile.xaml
│   ├── AppGrid.xaml
│   ├── SearchOverlay.xaml
│   └── SettingsDrawer.xaml
│
├── Resources
│   ├── Styles
│   ├── Templates
│   ├── Animations
│   └── Icons
│
└── Assets
```

---

# 52. Core项目

```text
NovaLauncher.Core
│
├── Models
├── Enums
├── Interfaces
├── Services
├── Algorithms
└── Utilities
```

这里不得引用 WinUI。

确保核心逻辑可测试。

---

# 53. Infrastructure项目

```text
NovaLauncher.Infrastructure
│
├── Database
├── Discovery
│   ├── StartMenu
│   ├── Registry
│   ├── Msix
│   └── Aumid
│
├── Shell
├── Icons
├── Launch
├── Hotkey
└── Logging
```

---

# 54. 依赖原则

```text
App
 ↓
Core
 ↑
Infrastructure
```

Core 不依赖 Infrastructure。

App 不直接访问 SQLite。

所有业务操作通过 Service 完成。

---

# 55. 开发阶段

## Phase 1：UI Prototype

完成：

- MainWindow
- 首页
- AppTile
- Hover
- Drag
- Settings Drawer

使用假数据。

目标：

先把视觉体验做出来。

## Phase 2：数据库

完成：

- SQLite
- Migrations
- Applications
- LauncherItems
- UsageStats
- Settings

## Phase 3：应用发现

完成：

- Start Menu
- Registry
- MSIX
- AUMID

## Phase 4：图标

完成：

- Shell Icon
- Cache
- Async Loading

## Phase 5：启动

完成：

- EXE
- LNK
- AUMID
- BAT/CMD
- URL

## Phase 6：搜索

完成：

- 首页搜索
- 全局搜索
- 键盘操作

## Phase 7：使用统计

完成：

- LaunchCount
- LastUsed
- Recent Apps
- Frequency Sort

## Phase 8：设置与安装

完成：

- Theme
- Startup
- Hotkey
- Export/Import
- Installer

---

# 56. UI开发验收

必须满足：

1. 窗口出现后无明显卡顿。
2. 首页应用图标真实显示。
3. Hover有动画。
4. 拖动有动画。
5. 拖放后顺序准确。
6. 重启后顺序不变。
7. 调整图标大小立即生效。
8. 窗口缩放布局正常。
9. 深色主题完整。
10. 设置抽屉打开和关闭流畅。

---

# 57. 应用发现验收

测试环境至少包含：

- 传统 Win32
- 绿色软件
- Start Menu 快捷方式
- MSIX
- AppX
- 32位软件
- 64位软件
- 中文软件
- 英文软件
- 软件卸载后残留记录

测试目标：

发现结果稳定、去重正确。

---

# 58. 启动验收

至少测试：

- EXE
- LNK
- AUMID
- BAT
- CMD
- URL
- 管理员权限程序

失败时必须给出可理解的错误信息。

---

# 59. 性能验收

### 冷启动

首页可操作：

< 1秒为目标。

### 搜索

< 100ms为目标。

### 拖拽

主观上无明显卡顿。

### 100个应用

首页和设置列表仍可流畅。

### 500个应用

搜索与列表仍可接受。

---

# 60. 数据一致性验收

操作：

添加 → 关闭 → 打开。

移除 → 关闭 → 打开。

拖拽 → 关闭 → 打开。

修改名称 → 关闭 → 打开。

图标大小修改 → 关闭 → 打开。

全部必须保持。

---

# 61. 异常验收

模拟：

- 应用被卸载
- exe移动
- lnk损坏
- 数据库锁定
- icon读取失败
- 快捷键冲突
- 扫描异常
- 权限不足

不能导致整个 Launcher 崩溃。

---

# 62. 发布方式

V1.0推荐：

Windows x64。

安装程序：

优先 MSIX。

同时可以提供：

- x64 安装包
- Portable 便携版（后续）

默认安装：

```text
%LocalAppData%\Programs\NovaLauncher
```

不要求管理员权限时优先使用当前用户安装。

---

# 63. 更新机制

V1.0：

提供“检查更新”。

可以先做手动更新。

V1.1以后：

增加自动更新。

更新不得覆盖：

- SQLite
- 用户设置
- 图标缓存
- 用户备份

---

# 64. 日志与诊断

设置页提供：

“打开日志目录”。

同时提供：

“导出诊断包”。

诊断包包含：

- 版本
- Windows版本
- 数据库状态
- 最近错误
- 配置摘要

不得包含：

- 用户文件内容
- 浏览器数据
- 聊天内容
- 密码
- Cookie

---

# 65. Codex开发要求

Codex实施时必须遵守：

1. 所有代码必须可编译。
2. 不允许伪造 Windows API。
3. 不允许为了快速完成而删除分层。
4. 不允许用硬编码路径代替 Windows API。
5. 不允许把整个项目写进 MainWindow。
6. UI和业务逻辑分离。
7. Repository与ViewModel分离。
8. 所有异步扫描不能阻塞 UI。
9. 所有用户设置必须持久化。
10. 所有关键操作必须有日志或错误处理。

---

# 66. Codex实现顺序

必须按以下顺序：

```text
1. 创建解决方案
2. 创建Core
3. 创建Infrastructure
4. 创建App
5. 初始化MVVM
6. 创建SQLite
7. 建立数据库模型
8. 做UI假数据
9. 完成首页视觉
10. 完成AppTile
11. 完成拖拽
12. 完成Settings Drawer
13. 完成Application Discovery
14. 完成Icon Service
15. 完成Launch Service
16. 完成Search Service
17. 完成Usage Service
18. 完成Global Hotkey
19. 完成Startup
20. 完成Backup
21. 完成异常处理
22. 完成测试
23. 完成安装包
```

---

# 67. 首个可运行版本定义

第一个版本不要求完整扫描。

必须可以：

```text
打开 Nova
 ↓
显示 6 个假应用
 ↓
点击启动
 ↓
拖动排序
 ↓
保存顺序
 ↓
设置改变图标大小
 ↓
关闭
 ↓
重新打开
```

先确保：

> “视觉体验 + 核心交互”正确。

再接 Windows 系统能力。

---

# 68. 第一阶段 UI 成功标准

用户第一次看到软件时，应产生：

“这不像普通 Windows 工具。”

用户操作后应产生：

“拖拽起来很舒服。”

用户第二次使用时应产生：

“我习惯从这里启动软件了。”

这是产品的核心目标。

---

# 69. 推荐默认配置

```text
主题：深色
材质：Mica
图标：80px
列数：6
应用名称：显示
动画：完整
背景效果：开启
最近使用：显示
托盘：开启
开机启动：关闭
全局快捷键：Ctrl + Space
```

---

# 70. V1.0最终产品形态

最终用户打开 Nova Launcher：

```text
                 ✦ NOVA

                                      🔍    ⚙


                       我的应用


          ◉          ◉          ◉          ◉

        Chrome      VSCode       微信       Edge


          ◉          ◉          ◉          ◉

         PS          Codex      Terminal     QQ


                       最近使用

              Chrome   VSCode   微信
```

然后：

```text
Ctrl + Space
       ↓
┌─────────────────────────────┐
│  🔍 输入应用名称             │
│                             │
│  Chrome                     │
│  VSCode                     │
│  微信                       │
└─────────────────────────────┘
```

最终目标：

> **让 Windows 用户把 Nova Launcher 当成自己真正的“应用入口”。**

---

# 71. 后续产品路线

## V1.x

应用启动器。

## V2.0

个人工作台。

## V3.0

智能工作空间：

```text
工作
开发
办公
设计
AI
娱乐
```

每个空间拥有独立 Launcher Layout。

最终可实现：

```text
早上进入“工作空间”
下午进入“开发空间”
晚上进入“娱乐空间”
```

同时逐渐加入：

- 文件
- 文件夹
- 项目
- URL
- 脚本
- AI Agent

形成真正的：

> **Windows Personal Workspace**
