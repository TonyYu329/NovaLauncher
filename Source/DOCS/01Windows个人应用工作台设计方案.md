我想做一个在Windows系统上运行的应用程序，应用程序的主要功能是选择Windows系统里我常用的快捷方式。当我打开这个应用程序时，我所选择的应用程序的快捷方式的图标就显示在应用程序的首页，图标大小可确定，拖拽图标可以移动图标的位置和顺序。在此应用程序的右上角有一个设置按钮，点开设置按钮以后可以选择我已经安装的应用程序，可以按安装时间排序、使用频率排序等等排序方式，参考Windows系统安装应用程序界面的排序。给我一个详细的设计方案和技术方案，只在Windows平台下用。优先考虑界面，界面要炫酷。

我建议把这个应用定义为：

Windows「个人应用启动器」设计方案

它不是传统的“开始菜单”，而是一个专属于用户自己的 Windows 应用工作台：

打开应用 → 直接看到自己最常用的软件 → 点击图标即可启动 → 拖拽调整位置 → 设置中搜索/发现所有已安装软件 → 按安装时间、名称、使用频率等管理。

而且这个项目非常适合做成一个界面漂亮、动画流畅、使用频率高、常驻桌面的 Windows 小工具。

一、产品定位

暂定产品名可以叫：

Nova Launcher

或者更偏 Windows 风格：

Windows App Hub

中文可以叫：

星瀚应用中心

我个人更推荐产品定位名称：

个人应用工作台

因为它未来可以继续增加：

应用快捷方式
文件快捷方式
文件夹
常用网址
PowerShell 命令
工作项目
最近使用
AI 快捷入口

这样后续不会把产品架死在“软件启动器”上。

二、核心使用流程

用户第一次打开：

┌──────────────────────────────────────────────────────────┐
│  NOVA                         搜索应用       ⚙           │
│                                                          │
│       我的应用                                             │
│                                                          │
│   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐             │
│   │  VS  │   │微信  │   │Chrome│   │Edge  │             │
│   │      │   │      │   │      │   │      │             │
│   └──────┘   └──────┘   └──────┘   └──────┘             │
│                                                          │
│   ┌──────┐   ┌──────┐   ┌──────┐                        │
│   │Codex │   │QQ    │   │钉钉  │                        │
│   │      │   │      │   │      │                        │
│   └──────┘   └──────┘   └──────┘                        │
│                                                          │
│                                                          │
│                    最近使用                               │
│            Chrome · VSCode · 微信                         │
└──────────────────────────────────────────────────────────┘

设置：

┌────────────────────────────────────────────────────────────┐
│  应用管理                                      ×            │
│                                                            │
│  搜索应用……                                               │
│                                                            │
│  全部应用  │ 已添加 │ 未添加                              │
│                                                            │
│  排序：名称 ▼    安装时间    最近使用    使用次数          │
│                                                            │
│  □ Chrome                         2026-08-10              │
│  ☑ Visual Studio Code             2026-07-15              │
│  ☑ 微信                           2026-06-22              │
│  □ Photoshop                      2026-05-10              │
│  ☑ Microsoft Edge                 2026-04-01              │
│                                                            │
└────────────────────────────────────────────────────────────┘
三、界面设计——这是整个项目最重要的部分

既然你的要求是**“优先考虑界面，而且要炫酷”**，我不建议做传统 WinForms/WPF 那种普通管理软件风格。

建议采用：

WinUI 3 + Mica/Acrylic + Fluent Design + 自定义动画

Windows App SDK 目前已经进入 2.x，微软官方资料显示 Windows App SDK 2.4.0 是 2026 年 8 月 13 日发布的当前稳定版，WinUI 3 也是其中的原生 Windows UI 框架。

四、推荐的视觉风格

我建议做：

「深色科技工作台」

整体感觉类似：

Windows 11 + Raycast + Arc + Steam + macOS Launchpad

而不是：

Windows 控制面板

背景

使用：

Mica
半透明渐变
轻微模糊
大面积留白

例如：

深色背景
        ↓
轻微蓝紫色渐变
        ↓
透明玻璃面板
        ↓
悬浮应用卡片
五、首页 UI

首页建议采用：

顶部区域
NOVA                           🔍 搜索              ⚙

左侧 Logo。

中间或者右侧为搜索。

右上角设置。

六、应用图标设计

应用图标不要简单放一个 Image。

建议：

┌────────────────┐
│                │
│      ICON      │
│                │
│    Chrome      │
│                │
└────────────────┘

但是正常状态下：

完全弱化边框。

鼠标经过：

        ✨
   ┌──────────┐
   │   ICON   │
   │  Chrome  │
   └──────────┘

出现：

放大
光晕
阴影
半透明背景
轻微上移

例如：

默认

      Chrome
        ○


Hover

    ╭────────╮
    │   ○    │
    │ Chrome │
    ╰────────╯
       ↑
     放大
七、应用图标大小

设置中提供：

图标大小

○ 48
○ 64
● 80
○ 96
○ 112
○ 128

甚至增加：

自定义

允许用户：

36 ～ 160 px
八、布局模式

这个地方建议一开始就设计成可扩展。

模式一：网格
○ ○ ○ ○ ○
○ ○ ○ ○ ○
○ ○ ○
模式二：大图标
   ○     ○     ○

   ○     ○     ○
模式三：紧凑
○ ○ ○ ○ ○ ○ ○ ○

V1.0先实现：

固定网格 + 拖拽排序

后面可以增加自由布局。

九、拖拽排序

这是非常重要的体验。

例如：

Chrome    VSCode    微信    Edge

用户拖：

Chrome → 最后

自动变成：

VSCode    微信    Edge    Chrome

动画不能瞬间跳。

应该：

拖动 Chrome
      ↓
其他图标自动让位
      ↓
弹性动画
      ↓
释放
      ↓
位置固定

推荐效果：

150～250ms 的缓动动画。

十、拖拽交互

支持：

鼠标左键

拖拽。

双击

启动。

单击

默认直接启动。

右键

打开菜单：

启动
以管理员身份运行
打开文件位置
添加到首页
移出首页
修改名称
删除快捷方式
属性
十一、设置页面

这是第二核心页面。

点击右上角：

⚙

打开一个漂亮的侧边抽屉。

不要直接跳到传统 Settings 页面。

建议：

右侧滑入式管理面板

例如：

┌──────────────────────┬──────────────────────────────┐
│                      │ 应用管理                     │
│                      │                              │
│       首页           │ 🔍 搜索应用                  │
│                      │                              │
│       ……             │ 全部  已添加  未添加         │
│                      │                              │
│                      │ 排序：使用频率 ▼             │
│                      │                              │
│                      │ ☑ Chrome                     │
│                      │ ☑ VSCode                     │
│                      │ ☐ Photoshop                  │
│                      │ ☐ 微信                       │
│                      │ ☑ Edge                       │
│                      │                              │
└──────────────────────┴──────────────────────────────┘

这样会非常现代。

十二、应用发现机制

这一部分不要只扫描：

C:\Program Files

这会漏掉大量应用。

建议建立：

Windows Application Discovery Engine

分成五个数据源。

1. Start Menu 快捷方式

扫描：

%ProgramData%\Microsoft\Windows\Start Menu\Programs

以及：

%AppData%\Microsoft\Windows\Start Menu\Programs

这是最重要的来源之一。

可以直接获取 .lnk。

十三、2. 注册表软件

读取：

HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall

以及：

HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall

以及：

HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall

获取：

DisplayName
DisplayVersion
InstallDate
InstallLocation
Publisher
DisplayIcon
UninstallString

这样可以得到：

安装时间

十四、3. MSIX / AppX

通过 Windows Package API 获取：

应用名称
Package Family Name
安装位置
Logo
Publisher
Version

这样可以发现 Windows Store 应用。

十五、4. Start Menu AppUserModelId

针对现代 Windows 应用增加：

AUMID

支持：

Shell:AppsFolder

中的应用。

这样可以进一步提高兼容率。

十六、5. 用户自定义应用

非常重要。

允许用户：

添加自定义程序

例如：

D:\Tools\xxx.exe
D:\AI\ComfyUI\run_nvidia_gpu.bat

甚至支持：

exe
lnk
bat
cmd
url

这样后面就不仅是“安装应用”。

十七、应用统一数据模型

不要把“安装程序”和“快捷方式”混为一个东西。

建议：

Application
    ↓
ApplicationShortcut
    ↓
Executable / LNK / AUMID

例如：

Chrome
 ├─ 显示名称
 ├─ 图标
 ├─ exe
 ├─ 快捷方式
 ├─ 安装时间
 ├─ 最后使用时间
 ├─ 使用次数
 └─ 首页排序
十八、使用频率排序

这里有一个非常关键的问题。

Windows 并不会给你的第三方程序直接提供一个完整、稳定、统一的“所有程序使用次数排行榜”。

所以不要依赖 Windows 提供。

应该自己统计。

每次用户从你的启动器启动：

Chrome

记录：

LaunchCount += 1
LastUsed = 当前时间

数据库：

Chrome
LaunchCount = 138
LastUsed = 2026-09-11 14:22:31

这样就可以排序：

最近使用
LastUsed DESC
使用次数
LaunchCount DESC
使用频率

可以做一个算法：

Score =
LaunchCount × 0.4
+ RecentScore × 0.6

这样“经常使用且最近用过”的应用排在前面。

十九、排序方式

建议至少：

名称 A-Z
名称 Z-A

安装时间：最新
安装时间：最早

最近使用
最少使用

使用次数：最多
使用次数：最少

厂商
应用大小

自定义排序

其中：

自定义排序

就是首页用户自己拖出来的顺序。

二十、非常值得增加的功能

建议设置界面增加：

排序方式

但：

首页永远以“用户自定义排序”为最高优先级。

也就是说：

设置页排序只是管理应用列表。

首页：

1 Chrome
2 VSCode
3 微信
4 Edge
5 PS

完全由用户控制。

二十一、首页搜索

建议首页顶部直接支持：

Ctrl + Space

呼出搜索。

例如：

       搜索应用……

       chrome

       ┌──────────────────────┐
       │ 🌐 Google Chrome      │
       │     最近使用 12:30    │
       └──────────────────────┘

输入：

ch

立即出现：

Chrome
ChatGPT
Chat

然后：

Enter

启动。

二十二、全局快捷键

建议增加：

Ctrl + Space

调出 Launcher。

逻辑：

任何程序
     ↓
Ctrl + Space
     ↓
NOVA 浮出
     ↓
输入软件名称
     ↓
Enter
     ↓
启动
     ↓
自动关闭

这会让软件从一个“桌面图标工具”升级成真正的：

Windows Launcher

二十三、窗口模式

建议支持两种模式。

普通模式
普通窗口

适合：

整理应用
拖拽
设置
快速启动模式
Ctrl + Space

出现：

┌────────────────────────────┐
│ 🔍 搜索应用                 │
│                            │
│ Chrome                     │
│ VSCode                     │
│ 微信                       │
│                            │
└────────────────────────────┘

启动以后自动关闭。

二十四、右键菜单高级功能

以后可以增加：

打开
打开文件位置
以管理员身份启动
复制路径
添加到首页
移动到...
创建快捷方式
重命名
卸载
属性

对于：

exe
lnk
MSIX
AUMID

分别处理。

二十五、技术架构

我推荐：

C# + .NET + WinUI 3

而不是：

Electron
Python + PySide
WPF
WinForms

原因很简单：

你的应用：

只做 Windows

而且：

高度强调 UI

WinUI 3 最适合。

微软当前 Windows 应用开发文档也明确将 WinUI 3 定位为 Windows 原生桌面 UI 框架，并支持 C#/.NET；Windows App SDK 独立于 Windows SDK 演进。

二十六、推荐技术栈
操作系统
Windows 10 / Windows 11

开发语言
C#

运行时
.NET 10

UI
WinUI 3

Windows API
Windows App SDK

数据
SQLite

ORM
Dapper / EF Core

图标
Windows Shell API

程序发现
Registry
Start Menu
MSIX/AppX
AUMID

全局快捷键
RegisterHotKey

动画
WinUI Composition

窗口效果
Mica / Acrylic

安装
MSIX 或传统 EXE Installer

如果以当前时间点正式开发，我建议直接使用最新稳定的 Windows App SDK 2.4.x，而不是 1.8。微软资料显示 2.4.0 于 2026-08-13 发布；1.8.11 同日仍作为旧版本稳定分支维护。

二十七、项目结构

建议直接按：

NovaLauncher
│
├─ NovaLauncher.App
│   ├─ App.xaml
│   ├─ MainWindow.xaml
│   ├─ Pages
│   │   ├─ HomePage.xaml
│   │   ├─ SettingsPage.xaml
│   │   └─ AppManagementPage.xaml
│   │
│   ├─ Controls
│   │   ├─ AppTile.xaml
│   │   ├─ AppGrid.xaml
│   │   ├─ SearchBox.xaml
│   │   ├─ SettingsDrawer.xaml
│   │   └─ AppContextMenu.xaml
│   │
│   └─ Resources
│       ├─ Styles
│       ├─ Animations
│       └─ Icons
│
├─ NovaLauncher.Core
│   ├─ Models
│   ├─ Services
│   ├─ Interfaces
│   └─ Algorithms
│
├─ NovaLauncher.Infrastructure
│   ├─ Registry
│   ├─ StartMenu
│   ├─ Shell
│   ├─ Msix
│   ├─ SQLite
│   └─ FileSystem
│
└─ NovaLauncher.Tests
二十八、核心模块
1. Application Discovery Service

负责：

扫描已安装软件
2. Shortcut Service

负责：

解析 .lnk
获取目标路径
获取参数
获取工作目录
3. Icon Service

这是非常重要的模块。

负责：

EXE → Windows 原生图标
LNK → 快捷方式图标
MSIX → App Logo

并做：

图标缓存。

否则每次打开首页重新读取 EXE 图标，会慢。

二十九、图标缓存

建立：

IconCache

例如：

AppId
IconHash
IconPath
LastUpdated

实际图片保存：

%LocalAppData%\NovaLauncher\Icons\

例如：

Icons\
    8a92f1.png
    7b31ab.png
    a921bc.png
三十、数据库设计

SQLite 就足够。

Applications
id
name
display_name
publisher
version
install_date
install_path
executable_path
shortcut_path
aumid
package_family_name
icon_hash
is_installed
created_at
updated_at
LauncherItems
id
application_id
sort_index
is_favorite
is_hidden
custom_name
icon_size
created_at
updated_at
UsageStats
id
application_id
launch_count
last_used_at
first_used_at
total_run_seconds
Settings
key
value

例如：

theme = dark
icon_size = 80
grid_columns = 6
global_hotkey = Ctrl+Space
startup_enabled = true
三十一、为什么不建议把所有东西塞到一个表

因为未来很容易出现：

一个应用
  ↓
多个启动入口

例如：

Visual Studio
├─ 正常启动
├─ Developer Command Prompt
└─ 某个解决方案

所以从一开始把：

Application

Shortcut

LauncherItem

分开，后续扩展会轻松很多。

三十二、首页数据结构

首页最终只需要：

LauncherItem[]

例如：

[
  Chrome,
  VSCode,
  WeChat,
  Edge,
  Photoshop,
  Codex
]

然后：

SortIndex

控制位置。

三十三、拖拽排序算法

假设：

A B C D E

拖：

E → B 前面

变成：

A E B C D

然后重新计算：

SortIndex

A = 0
E = 1
B = 2
C = 3
D = 4

数据持久化。

这样即使关闭软件：

下次启动位置完全不会变。

三十四、应用扫描策略

首次启动：

扫描
   ↓
建立应用索引
   ↓
读取图标
   ↓
写入 SQLite
   ↓
显示首页

以后：

增量扫描

而不是每次重新扫描整个电脑。

例如：

启动
 ↓
加载 SQLite
 ↓
首页立即显示
 ↓
后台扫描
 ↓
发现新软件
 ↓
更新数据库

这是非常关键的体验。

三十五、启动速度目标

目标：

冷启动 < 1 秒

首页：

先显示 UI

再后台：

加载图标
扫描新程序
更新统计

不要：

启动
 ↓
扫描 C 盘
 ↓
扫描注册表
 ↓
读取 500 个图标
 ↓
最后显示页面

这种方式会非常难用。

三十六、动画系统

建议统一定义：

Fast
120ms

Normal
180ms

Smooth
240ms

Slow
320ms

例如：

Hover
Scale 1.00 → 1.06
120ms
打开设置
X: 100% → 0%
Opacity: 0 → 1
240ms
拖动
Scale 1.00 → 1.08
Shadow ↑
三十七、主题

至少：

深色
浅色
跟随 Windows

但我建议默认：

深色

因为炫酷效果明显更好。

三十八、背景效果

未来可以做：

纯色

渐变

动态渐变

桌面壁纸模糊

动态光晕

甚至：

鼠标移动
       ↓
背景光晕跟随

例如：

                 鼠标
                   ↓
             ✦
      ╭────────────────╮
      │     Chrome     │
      │       ○        │
      ╰────────────────╯
             ╱
       光晕跟随

这个非常有科技感。

三十九、首页建议采用的最终布局

我最推荐这一版：

┌────────────────────────────────────────────────────────┐
│                                                        │
│  ✦ NOVA                               🔍      ⚙       │
│                                                        │
│                                                        │
│                  我的应用                              │
│                                                        │
│       ╭────╮     ╭────╮     ╭────╮     ╭────╮        │
│       │ VS │     │微信│     │🌐  │     │ ◉  │        │
│       ╰────╯     ╰────╯     ╰────╯     ╰────╯        │
│       VSCode      微信      Chrome       Edge         │
│                                                        │
│       ╭────╮     ╭────╮     ╭────╮     ╭────╮        │
│       │ PS │     │ ⚡ │     │ QQ │     │  │        │
│       ╰────╯     ╰────╯     ╰────╯     ╰────╯        │
│     Photoshop    Codex       QQ        其他           │
│                                                        │
│                                                        │
│                         最近使用                         │
│                  Chrome   VSCode   微信                 │
│                                                        │
└────────────────────────────────────────────────────────┘

整体：

少文字、大图标、强动画、玻璃感。

四十、V1.0 功能边界

不要一开始做太大。

V1.0必须完成
首页
应用图标
应用名称
应用启动
拖拽排序
添加/移除应用
图标大小
网格布局
深色/浅色
动画
搜索
设置
全部应用
已添加
未添加
名称排序
安装时间排序
最近使用排序
使用次数排序
搜索
添加/删除首页
系统能力
Start Menu 应用发现
Registry 应用发现
MSIX/AppX
.lnk
.exe
图标获取
图标缓存
SQLite
使用统计
四十一、V1.1

再增加：

Ctrl + Space
全局搜索

以及：

最近使用
最常使用
四十二、V1.2

增加：

文件夹

例如：

开发
├─ VSCode
├─ Visual Studio
├─ Git
├─ Postman
└─ Codex

首页：

      开发
       📁

点击展开。

四十三、V2.0

这时候产品就可以真正开始“玩起来”：

应用
文件
网址
项目
命令
脚本
AI

统一成为：

Launcher Item

例如：

Chrome
D:\Work
GitHub
ComfyUI
启动AI.bat
ChatGPT
医院AI项目

这样未来就不是：

“一个管理应用快捷方式的软件”

而会变成：

个人 Windows 工作台。

四十四、我特别建议的一项功能

增加：

「自动推荐」

例如系统发现：

Chrome 使用 182 次
VSCode 使用 165 次
微信 使用 141 次
Edge 使用 9 次
PS 使用 3 次

可以在设置里显示：

推荐添加

🔥 Chrome
🔥 VSCode
🔥 微信

然后：

一键添加到首页。

四十五、进一步做成“智能桌面”

以后甚至可以：

工作模式

        开发
  VSCode   Git   Chrome
  Terminal Docker Postman


办公模式

  Word     Excel    Outlook
  Teams    Chrome   微信

用户点击：

工作模式

自动切换首页应用布局。

这就是非常有商业化潜力的第二阶段。

四十六、最终推荐技术方案
模块	技术
平台	Windows
UI	WinUI 3
Windows 框架	Windows App SDK 2.4.x
开发语言	C#
Runtime	.NET 10
数据库	SQLite
ORM	Dapper
UI动画	WinUI Composition
背景	Mica / Acrylic
应用发现	Registry + Start Menu + MSIX
快捷方式	Windows Shell API
图标	Shell Icon API + Cache
全局快捷键	RegisterHotKey
安装包	MSIX
架构	MVVM + Service
发布	x64 优先

Windows App SDK 的当前版本线支持 Windows 10 1809 及以后版本，同时可以针对 Windows 11 做更好的视觉效果；正式开发时可以把 Windows 11 作为主要体验目标，Windows 10 作为兼容目标。

四十七、项目最终架构
                    ┌─────────────────────┐
                    │      NOVA UI        │
                    │      WinUI 3        │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │     ViewModel       │
                    └─────────┬───────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
 App Discovery           Launch Service        Usage Service
        │                     │                     │
        ├─ StartMenu          ├─ EXE               ├─ Count
        ├─ Registry           ├─ LNK               ├─ LastUsed
        ├─ MSIX               ├─ AUMID             └─ Score
        └─ Custom             └─ Admin
        │
        ▼
 ┌─────────────────────┐
 │ Application Database│
 │      SQLite         │
 └─────────┬───────────┘
           │
           ├── Applications
           ├── LauncherItems
           ├── UsageStats
           └── Settings
四十八、我建议你这个项目的开发顺序

不要按照“先把功能全部做出来，再美化界面”的传统软件开发方式。

你的项目应该反过来：

第一阶段
视觉原型
        ↓
第二阶段
首页交互
        ↓
第三阶段
拖拽动画
        ↓
第四阶段
应用发现
        ↓
第五阶段
数据库
        ↓
第六阶段
搜索
        ↓
第七阶段
使用统计
        ↓
第八阶段
全局快捷键
        ↓
第九阶段
安装部署

尤其是前四步，应该优先完成。

因为这个产品真正的竞争力不是：

“能找到 Windows 软件。”

而是：

“打开以后非常舒服，而且比 Windows 开始菜单更好用。”

五十、如果让我直接定一个 V1.0

我会最终定成：

产品名：Nova Launcher

定位：Windows 个人应用工作台

核心体验：

Ctrl + Space 呼出
→ 搜索 / 点击应用
→ 一键启动
→ 首页只保留自己真正常用的软件
→ 拖拽自由整理
→ 炫酷玻璃界面
→ 自动统计使用习惯
→ 根据使用频率智能推荐应用

这套架构已经足够直接进入开发，而且后续可以自然扩展成“应用 + 文件 + 网址 + 项目 + AI”的个人 Windows 工作台。