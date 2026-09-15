# Nova Launcher · V0.0.5

极简的 Windows 应用启动页。**双击 `NovaLauncher.bat` 即用**，免安装、免运行时依赖。

## 架构（M40）

```
PowerShell 5.1 (-STA)
    ↓
WinForms Form (FormBorderStyle=None)
    ↓
DPI: Per Monitor V2 (GetDpiForWindow)
    ↓
Form.Shown → async WebView2 初始化
    ↓
CoreWebView2Controller
    ↓
HTML/CSS/JS UI
```

- **窗口层**：WinForms 无边框 Form，彻底解决顶部黑边问题
- **渲染层**：Microsoft WebView2（Edge Chromium），无浏览器边框
- **界面层**：HTML + CSS + JavaScript，自绘标题栏与窗口控制
- **DPI**：Per-Monitor V2，使用 `GetDpiForWindow(hwnd)`，监听 `WM_DPICHANGED`
- **初始化**：Form.Shown 事件中 async/await 初始化 WebView2，不阻塞 UI 线程

## 怎么用

1. 双击 `Source\NovaLauncher.bat`
2. 窗口自动进入**无边框最大化**（铺满工作区，任务栏照常可见）
3. 首次使用时空状态显示"将应用拖拽到此处以添加"——拖入 EXE/快捷方式，或点击 ＋ 选择文件
4. 点击图标 → 启动对应程序
5. 右上角 ⚙ 打开设置面板

## 外观设置

### 背景样式
- **毛玻璃（Mica）**：Windows 原生 Mica 效果
- **液态玻璃（Liquid Glass）**：渐变光晕 + 高光反射的现代玻璃效果
- **效果强度**：0-100 滑块，调节玻璃质感浓度
- **启用/禁用**：开关控制背景效果

### 窗体
- **背景透明度**：20%-100% 连续调节，控制窗口底色不透明度（低于 100% 时桌面清晰透出）
- **主题**：深色 / 浅色

### 背景图片
- **图片路径**：选择本地图片作为窗口背景
- **填充方式**：自适应 / 适应高度 / 适应宽度 / 平铺 / 拉伸
- **启用/禁用**：开关控制背景图片

### 图标
- **图标大小**：36-160px
- **每行图标数**：4-12
- **字体**：系统默认 / 微软雅黑 / 宋体 / 楷体 / 黑体 / Segoe UI / Consolas / Courier New
- **字体大小**：10-24px
- **字体颜色**：颜色选择器 + 十六进制输入
- **字体粗细**：常规 / 中等 / 粗体

## 应用管理

- **添加应用**：挑选 EXE / LNK
- **从已安装应用添加**：按使用频率 / 安装时间 / 名称排序
- **拖拽添加**：直接拖入快捷方式或 EXE
- **拖拽排序**：松手即保存
- **右键菜单**：打开 / 打开文件位置 / 重命名 / 移除
- **有效性检查**：一键体检所有应用路径

## 文件说明

| 文件 | 作用 |
|------|------|
| `Source\NovaLauncher.bat` | 唯一入口，双击启动 |
| `Source\data\NovaLauncher.ps1` | 宿主：WinForms + WebView2 + DWM 毛玻璃 |
| `Source\data\nova-launcher.html` | 界面：HTML/CSS/JS |
| `Source\data\nova-logo.ico` | 应用图标（任务栏/标题栏） |
| `Source\data\settings.json` | 全部外观设置 |
| `Source\data\apps.json` | 应用列表 |
| `Source\data\Icons\` | 图标缓存 |

## 数据存放

```
Source\
├── NovaLauncher.bat        # 入口
└── data\
    ├── NovaLauncher.ps1    # 宿主
    ├── nova-launcher.html  # 界面
    ├── nova-logo.ico       # 图标
    ├── apps.json           # 应用列表
    ├── settings.json       # 设置
    ├── Icons\              # 图标缓存
    └── host.log            # 运行日志
```

## 版本历史

### V0.0.5
- 背景模糊重构为 DWM 窗口级实时亚克力（移除桌面截屏方案），后隐藏该设置项
- 修复背景透明度滑块：低于 100% 即全透明的问题，实现 20%-100% 连续中间值
- 隐藏设置面板中的背景模糊选项
- 修复添加应用报错：`Thread` 构造函数重载不确定（显式指定 `ParameterizedThreadStart`）
- 空状态 ＋ 按钮可点击添加应用（复用设置面板的文件选择流程）
- 空状态提示改为"将应用拖拽到此处以添加"，引导拖拽或点击添加
- 清理无用代码与旧发布包

### V0.0.4
- 新增液态玻璃（Liquid Glass）背景样式
- 设置中可切换毛玻璃 / 液态玻璃样式
- 新增窗体整体透明度设置（20%-100%）
- 新增背景图片设置（路径 + 平铺/拉伸/自适应）
- 新增图标字体设置（字体/颜色/大小/粗细）
- 重新整理设置面板，风格统一
- 任务栏图标使用 nova-logo

### V0.0.3
- M40 架构重构：WinForms + WebView2Controller
- 彻底解决窗口化顶部黑边问题
- 新增毛玻璃效果开关和强度调节
- DPI Per-Monitor V2 支持

### V0.0.2
- 窗口化模式垂直居中
- 顶部黑边修复

## 常见问题

- **窗口一闪就没了**：看 `data\host.log`
- **图标显示为字符方块**：该 EXE 没有可提取的图标资源
- **想彻底重置**：删掉 `data\` 下的 `apps.json` / `settings.json` / `Icons`
