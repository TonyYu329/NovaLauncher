# Nova Launcher · Windows 个人应用工作台

<!-- 2026-09-15 全面更新：M40 架构重构 = WinForms + CoreWebView2Controller，移除 Chrome --app/HttpListener/SetWindowRgn/CSD -->

## 项目概览

| 属性 | 值 |
|------|-----|
| 项目名称 | Nova Launcher（Windows 个人应用工作台） |
| 项目描述 | 极简 Windows 应用启动器：WinForms 无边框窗口 + WebView2 渲染 HTML UI，应用管理、搜索、毛玻璃/液态玻璃主题、右键编辑、点击启动 |
| 技术栈（M40） | PowerShell 5.1 -STA + WinForms Form(FormBorderStyle=None) + CoreWebView2Controller + HTML/CSS/JS |
| 数据存储 | 纯 JSON：`apps.json`（应用）+ `settings.json`（设置），**存于程序执行目录 `data/`**（绿色自包含） |
| 交付形态 | 绿色版免安装：整个 `Source/` 即产物，双击 `Source\NovaLauncher.bat` 启动 |
| 平台 | 仅 Windows 10 / Windows 11 x64（需 WebView2 Runtime） |
| 权威文档 | `DOCS/07Nova Launcher M40 详细开发任务拆解（可直接交给豆包执行）.md` |
| GitHub | https://github.com/TonyYu329/NovaLauncher（main） |
| 版本 | V0.0.5（已发布 GitHub Release）；最新 commit `8f8f6e3`（已 push main） |

## 构建、测试与校验

- 运行：双击 `Source\NovaLauncher.bat`（无需编译，bat 全英文 ASCII）
- 语法校验：`[System.Management.Automation.Language.Parser]::ParseFile()` 检查 ps1；`node --check` 检查前端 JS
- 验证：每次改完必须启动测试 + 截图目视，仅日志/数值不算完成
- 前端调试：DataDir 放 DEBUG.flag，写 `__SHOT__` 到 debug-js.txt 触发 CDP 截图

## 目录结构

```text
Source/
├── NovaLauncher.bat            # 唯一入口（start /min + powershell -NoProfile -STA -WindowStyle Hidden）
└── data/
    ├── NovaLauncher.ps1        # 宿主：WinForms + WebView2Controller（UTF-8 BOM，必须带BOM）
    ├── nova-launcher.html      # 前端单文件
    ├── nova-logo.ico
    ├── apps.json / settings.json   # 用户数据（gitignore，不提交）
    └── Icons/ WebView2Profile/ bgimages/ host.log   # 运行态（gitignore）
```

## 关键架构约定（M40）

- **窗口**：WinForms FormBorderStyle=None，OnHandleCreated 运行时 SetWindowLongPtr 加 WS_MINIMIZEBOX（任务栏点击最小化/恢复）
- **DPI**：Per-Monitor V2（SetProcessDpiAwarenessContext PMv2）+ GetDpiForWindow（**禁止 GetDpiForSystem**，多显示器不准）+ WM_DPICHANGED 处理
- **WebView2 初始化**：Form.Shown + Timer 轮询异步初始化（**禁止 .GetAwaiter().GetResult()/.Result 阻塞 UI 线程**，会死锁）
- **通信**：前端 chrome.webview.postMessage({op,data}) → 后端 WebMessageReceived → op 分发 → PostWebMessageAsJson 响应
- **毛玻璃**：DWM DWMWA_SYSTEMBACKDROP_TYPE（Mica=2/Acrylic=3/TabbedMica=4），WebView2 DefaultBackgroundColor=Transparent
- **文件拖拽**：纯 WM_DROPFILES（DragAcceptFiles + WndProc 0x0233），**禁用前端 HTML5 拖拽**（dragover 不 preventDefault），后端直接 Add-AppPath 不搜索，限制 .exe/.lnk/.bat/.cmd
- **编码铁律**：ps1 必须 UTF-8 **带 BOM**（PS5.1 中文注释否则语法错误）；bat 必须全英文 ASCII + CRLF
- **数据落程序执行目录**：`$DataDir = $ScriptDir`，绿色自包含，禁用 `$env:APPDATA` 拼路径

## 已知问题

- **文件拖拽真实触发失败**：WM_DROPFILES 模拟测试成功，但真实拖拽被 WebView2 子窗口（Chrome_RenderWidgetHostHWND）拦截，待子类化子窗口转发 WM_DROPFILES

## PowerShell 陷阱

- `if(0)` 为 false，索引判断必须用 `if($null -ne $data.i)`（曾导致 i=0 启动越界）
- `New-Object System.Threading.Thread($sb)` 有 ThreadStart/ParameterizedThreadStart 两个单参重载，需显式指定类型
- WebMessageReceived 在 UI 线程触发，弹 OpenFileDialog 必须直接在 UI 线程 ShowDialog，不能另开 STA 线程（会跨线程 COM 崩溃）
- FormBorderStyle=None 时 MinimizeBox 属性被忽略，必须运行时 SetWindowLongPtr 加 WS_MINIMIZEBOX(0x20000)

## 通用规则

- **先调研再行动**：未阅读代码前严禁主观猜测；存疑时如实说明并给验证方案
- **专注需求本身**：仅完成指定任务，不额外拓展、不擅自重构无关代码
- **完成前自检**：逐项核对需求，说明修改内容、已验证项及暂无法验证的内容
- **每次改完必须测试通过并截图给证据**

## 开发与协作偏好

- **交互语言**：中文；代码注释中英文均可，以清晰为主
- **修改反馈**：每次修改完成后用表格打印「修改文件完整路径 + 说明」
- **Git 提交**：中文 commit，格式 `<type>: <简述>`；apps.json/settings.json 是用户私人数据不纳入提交
- **记忆库**：`D:\ObsidianData\02AgentMemoryBank\01-项目区\NovaLauncher\@上下文-NovaLauncher.md`
- **claude-hud 状态栏**：离线备份 `F:\AISoftware\claudecode\skills\claude-hub`（`bash install.sh` 一键恢复）；`modelSource: "both"` 为本地扩展（显示名 · 真实ID）；`humanizeModelName()` 把裸 ID 美化（`deepseek-flash[1m]` → `DeepSeek Flash[1m]`）。本地扩展**只在 `dist/`**（`src/` 是上游原版），三份 dist 须一致：`cache/claude-hud/claude-hud/0.8.0/`（生效）、`cache/claude-hub-local/…`、备份包 `plugin/`

## 记忆库写入流程

① GitHub 提交 → ② 读 `00-系统配置/00-根导航.md` → ③ 匹配项目写入 `@上下文` → ④ 补 `会话记录/`、`架构决策/`、`项目文档/`（文件名含精确到秒时间戳）→ ⑤ 更新 `02-全局知识/02-通用偏好与配置.md` → ⑥ 更新本文件 → ⑦ 输出写入的文件名清单。
