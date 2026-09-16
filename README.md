# Nova Launcher · V0.0.8

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

### V0.0.8
- **新增「关于」弹窗**：设置抽屉新增「关于」分区，显示软件名称、版本号、发布日期、发布人（`Esc` / `✕` / 点遮罩均可关闭）
- **版本号收敛到单一来源**：新增 `APP_META` 常量，抽屉副标题与「关于」弹窗共用；此前版本号散落在静态 HTML 与 JS 两处，升级时容易漏改
- **修复双击界面会选中文字**：`user-select:none` 原本只挂在 `.tile` 上，双击 ⚙ 设置按钮、NOVA 字样、分组标题等纯界面元素时会被浏览器选成蓝底白字。现全局禁用，并为可编辑控件与界面上的路径文本（应用路径 / 失效路径 / 数据目录）单独放行
- **修复设置图标 ⚙ 背景与窗口按钮不一致**：深色下 ⚙ 常驻一块 `--glass` 浅底，看起来像被选中高亮。根因是 `background:transparent` 只在浅色规则里有重置，深色没有；且"与窗口按钮一致"的覆盖挂在 `data-bgstyle="liquid"` 下，关闭毛玻璃（`bgstyle=none`）时不生效

### V0.0.7
- **背景模糊重构为前端雾面膜**：DWM 的 Mica/亚克力材质会把窗口背景整块顶掉（实测：背后放纯红窗口，透过任何 `DWMSBT_*` 材质红色分量都是 0），一旦启用，透明度滑块就再也拉不出桌面。现不再使用系统材质——窗口走纯透明框架、桌面真透出，模糊改由前端一层「雾面膜」表现
- **修复背景透明度在开启模糊时失效**：「是否透明」只由透明度滑块决定，模糊滑块不再把窗口强行拉进材质路径；两个滑块彻底解耦（模糊只改膜色调，不碰 alpha）
- **修复双击标题栏 logo/应用名区无反应**：`.brand` 从双击排除列表移除，标题栏双击与空白区一致地切换最大化/还原
- 隐藏背景模糊滑块（功能保留，改 `settings.json` 的 `bgBlur` 仍生效）
- 旧版 accent API 在 Win11 实测已退化为纯黑平层（无模糊），相关分支不再启用

### V0.0.6
- 拖拽方案重构为 NovaDrop（OLE IDropTarget）：关闭 WebView2 AllowExternalDrop，在主窗口+全部子窗口注册拖放目标，定时器重注册处理动态子窗口
- 支持任何文件/文件夹拖拽添加（记录绝对路径，不创建 .lnk）
- 拖拽悬停时显示"创建快捷方式"遮罩提示
- 指针事件实现应用图标拖拽排序
- 清理临时验证文件与旧发布解压目录

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
