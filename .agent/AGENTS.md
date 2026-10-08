# Nova Launcher · Windows 个人应用工作台

<!-- 2026-09-15 全面更新：M40 架构重构 = WinForms + CoreWebView2Controller，移除 Chrome --app/HttpListener/SetWindowRgn/CSD -->

## 项目概览

| 属性 | 值 |
|------|-----|
| 项目名称 | Nova Launcher（Windows 个人应用工作台） |
| 项目描述 | 极简 Windows 应用启动器：WinForms 无边框窗口 + WebView2 渲染 HTML UI，应用管理、搜索、毛玻璃/液态玻璃主题、右键编辑、点击启动 |
| 技术栈（M40） | PowerShell 5.1 -STA + WinForms Form(FormBorderStyle=None) + CoreWebView2Controller + HTML/CSS/JS |
| 数据存储 | 纯 JSON：`apps.json`（应用）+ `settings.json`（设置），**存于程序执行目录 `data/`**（绿色自包含） |
| 交付形态 | 绿色版免安装：整个 `Source/` 即产物，双击 `Source\NovaLauncher.bat` 或 `Source\NovaLauncher.exe` 启动（exe 可右键固定任务栏） |
| 平台 | 仅 Windows 10 / Windows 11 x64（需 WebView2 Runtime） |
| 权威文档 | `DOCS/07Nova Launcher M40 详细开发任务拆解（可直接交给豆包执行）.md` |
| GitHub | https://github.com/TonyYu329/NovaLauncher（main） |
| 版本 | **V0.1.1**（GitHub Release，2026-10-08）；tag `v0.1.1`（附注） |
| 版本号来源 | 前端 `APP_META` 常量（`nova-launcher.html` 脚本头部）——抽屉副标题与「关于」弹窗共用，**升级只改这一处** |
| 发布人 | **Tony**（不是 GitHub 账号 TonyYu329，「关于」弹窗里填的是前者） |

## 构建、测试与校验

- 运行：双击 `Source\NovaLauncher.bat` 或 `Source\NovaLauncher.exe`（推荐，无控制台闪窗，可固定任务栏）
- 重编译启动器：在 `Source\` 下执行 `NovaLauncherExe.cs` 头注释里的 csc 命令（源码纯 ASCII，勿加中文）
- 任务栏单图标：**V0.1.0 起全自动**——exe 每次启动自注册开始菜单快捷方式（指向当前运行的 exe + AUMID），ps1 顶层在窗口创建前即声明 AUMID；固定项/运行图标经该注册解析。历史坑：`ExtendedProperty` 对 AUMID 只读（须 IPropertyStore P/Invoke）、AUMID 须在 lnk Save 之后写、重存固定 lnk 会剥 pin 元数据（exe 刻意不重写任务栏固定项），详见记忆库 ADR-NL013/NL014
- 背景图片透明度（V0.1.1 修复）：`.backdrop` 是背景场景层（背景图片 `#bgImageLayer` 就在其内），其 `opacity` 必须跟随透明度滑块**整组淡出**（`imgOn ? winOpacity : 1`），且图片生效时 `--bg-base` 置透明。**CSS `opacity` 只能加在容器上、不能只加图片那一层**——单层 alpha 会与下层膜叠加成 `2a−a²`（50% 显示成 75%、80% 显示成 96%）；改图片开关后须调 `applyStyle()` 重算
- 语法校验：`[System.Management.Automation.Language.Parser]::ParseFile()` 检查 ps1；`node --check` 检查前端 JS
- 验证：每次改完必须启动测试 + 截图目视，仅日志/数值不算完成
- 前端调试：DataDir 放 DEBUG.flag，写 `__SHOT__` 到 debug-js.txt 触发 CDP 截图

## 发布流程（四步验证，缺一不算发完）

V0.0.6 曾从过期副本打包，导致**已发布**的包缺功能。此后固定流程：

1. **改版本** → 只改 `Source/data/nova-launcher.html` 的 `APP_META`；更新 `README.md` 标题+版本历史；追加 `Source/修改记录.md`
2. **打包** → 必须从 `Source/` 目录，用 .NET `ZipArchive` + `Encoding.UTF8`（**不能用 `Compress-Archive`**，PS5.1 下中文条目名会乱码）
   ```
   9 个条目（V0.0.9 修正，2026-09-30）：data/{nova-launcher.html, nova-logo.ico, NovaLauncher.ps1, lib/*.dll},
             NovaLauncher.bat, NovaLauncher.exe, README.md, 修改记录.md
   ```
   **`NovaLauncherExe.cs` 不打包**——源码属开发者文件，GitHub 仓库已有，绿色版只含可运行文件（用户 2026-09-30 确认）
   **注意**：打包脚本若含中文字面量（如 `修改记录.md`），脚本自身必须 UTF-8 BOM——.traetemp 无 BOM 脚本会被 PS5.1 按 ANSI 解码，中文路径变乱码找不到文件。规避法：用 `Get-ChildItem -Filter '*.md'` 模式匹配中文名文件，脚本保持纯 ASCII
   - **本地产物位置**：`Release\NovaLauncher-V<版本>.zip`（该目录 gitignore，不入库；2026-09-30 用户指定）
3. **比对** → 包内 `nova-launcher.html` / `NovaLauncher.ps1` 字节数必须等于源目录；用 .NET 回读中文条目名的 Unicode 码点
4. **实跑** → 解压到临时目录，启动 `NovaLauncher.bat`，确认窗口存活 + `host.log` 无报错
5. 最后 `git add`（**不含 `settings.json`**）→ commit → `tag -a` → push → `gh release create`

**注意**：`gh release delete --cleanup-tag` 会把**本地 tag 也删掉**；`gh release create` 自动建的 tag 是**轻量 tag**，仓库惯例（v0.0.5~v0.0.8）是**附注 tag**，需 `git tag -f -a` + `git push --force` 对齐。

## 目录结构

```text
Source/
├── NovaLauncher.bat            # 入口（start /min + powershell -NoProfile -STA -WindowStyle Hidden）
├── NovaLauncher.exe            # 启动器（V0.1.0）：WinExe 包装器，可固定任务栏，启动时自注册应用身份
├── NovaLauncherExe.cs          # 启动器源码（纯 ASCII，编译命令见头注释）
└── data/
    ├── NovaLauncher.ps1        # 宿主：WinForms + WebView2Controller（UTF-8 BOM，必须带BOM）
    ├── nova-launcher.html      # 前端单文件
    ├── nova-logo.ico
    ├── apps.json / settings.json   # 用户数据（gitignore，不提交）
    └── Icons/ WebView2Profile/ bgimages/ host.log   # 运行态（gitignore）
```

## 关键架构约定（M40）

- **启动器（V0.1.0）**：NovaLauncher.exe 用系统 csc 编译（零依赖）；定位零硬编码（`data\NovaLauncher.ps1` 相对 exe，`powershell.exe` 走 PATH 与 bat 的 where 一致，找不到弹窗）；与 bat 参数完全一致（-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden）；**启动时自注册应用身份**——每次拉起 powershell 前创建/校准开始菜单快捷方式 `%APPDATA%\...\Start Menu\Programs\NovaLauncher.lnk`（target=当前 exe + IconLocation + AUMID=NovaLauncher.App），修复"固定后启动不同实例"，全新电脑零配置
- **任务栏 AUMID（V0.1.0 全自动）**：单图标 = 双向声明——ps1 **顶层**（任何窗口句柄创建之前）`SetCurrentProcessExplicitAppUserModelID("NovaLauncher.App")`（放晚了按钮绑宿主身份）+ exe 自注册的开始菜单快捷方式携带 AUMID。Win11 运行图标从系统级 AUMID 注册解析，无注册回退宿主 powershell.exe 图标。手动修复坑（历史代码已沉淀进 exe）：`ExtendedProperty` 对 AUMID **只读**（须 P/Invoke `SHGetPropertyStoreFromParsingName` GPS_READWRITE + IPropertyStore，PKEY {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3} pid 5）；AUMID 须在 lnk `Save` **之后**写（Save 清扩展属性）；GPS 读回 empty 是缓存假象，以 lnk 二进制含 UTF-16 字符串为准；**不重写任务栏固定项**（重存剥 pin 元数据）
- **单实例保护（V0.0.9 修正）**：ps1 头部命名 Mutex `Local\NovaLauncher.SingleInstance`——重复启动（桌面/任务栏任一入口）时按标题 'Nova Launcher'（EnumWindows+GetWindowTextW；**FindWindowW 对该无边框窗口失效**）找到既有窗口 → SW_RESTORE+SetForegroundWindow → exit 0。`$form.Text='Nova Launcher'` 是定位依据，勿改。改 ps1 后必须：补 BOM（Edit 工具会丢）→ 同步到实际部署副本（当前 `E:\Person\backup\lantian\sw\NovaLauncher-V0.0.9\data\`）
- **窗口**：WinForms FormBorderStyle=None，OnHandleCreated 运行时 SetWindowLongPtr 加 WS_MINIMIZEBOX（任务栏点击最小化/恢复）
- **DPI**：Per-Monitor V2（SetProcessDpiAwarenessContext PMv2）+ GetDpiForWindow（**禁止 GetDpiForSystem**，多显示器不准）+ WM_DPICHANGED 处理
- **WebView2 初始化**：Form.Shown + Timer 轮询异步初始化（**禁止 .GetAwaiter().GetResult()/.Result 阻塞 UI 线程**，会死锁）
- **通信**：前端 chrome.webview.postMessage({op,data}) → 后端 WebMessageReceived → op 分发 → PostWebMessageAsJson 响应
- **窗口背景 / 毛玻璃**：只用 `DWMWA_SYSTEMBACKDROP_TYPE` 的 `DWMSBT_NONE`（透明框架）或 `glassEnabled` 的 Mica=2/Acrylic=3，WebView2 DefaultBackgroundColor=Transparent
  - ⚠ **DWM 材质会把窗口背景整块顶掉**：实测背后放纯红窗口（220,30,30），透过任何 `DWMSBT_*` 材质红色分量都是 **0**。一旦启用，桌面再也透不出来，**透明度滑块必然失效**；且系统模糊半径固定、无可调 API。所以「背景模糊」改用前端「雾面膜」（`veil()` 按 `blurK` 把基色向磨砂色插值，**只改色调不碰 alpha**），两个滑块才得以解耦。旧版 accent API 在 Win11 已退化为纯黑平层且无模糊，不再启用
  - 「真模糊 + 自由透明度」在本方案下不可兼得，唯一出路是自绘桌面快照（曾试过、因不实时而撤）
- **界面风格切换机制**：所有样式挂在 `<html>` 的 `data-theme`(dark/light) × `data-bgstyle`(liquid/mica/none) 双属性 + 纯 CSS 属性选择器（`html[data-bgstyle="liquid"] ...`），**零 JS 内联**；切换主题只改 `data-theme`。液态玻璃 = 三层透明栈（宿主 DWM 透明 / `.backdrop` 彩色场景 / `.icon-card` 白膜+`backdrop-filter:blur`）；浅色主题必须写 `[data-theme="light"][data-bgstyle="liquid"]` 独立覆盖组，否则白膜不可见
  - **默认风格当前为 Mica**（`glassEnabled:false`、`bgStyle:"mica"`）；若要默认液态玻璃需改 html 内 **4 处**：三处 state 默认值（含补 `bgStyle:"liquid"`，L2617 的 `Object.assign` 兜底缺该项）、`applyStyle` 兜底 "mica"→"liquid"、存量用户 `settings.json` 不动、设置抽屉分段控件高亮同源。**尚未实施**
- **文件拖拽**：NovaDrop（OLE `IDropTarget`），注册在主窗口 + 全部子窗口并定时重注册（WebView2 会创建 `Chrome_RenderWidgetHostHWND` 覆盖客户区）；`AllowExternalDrop=false`；**禁用前端 HTML5 拖拽**（dragover 不 preventDefault）；后端直接 Add-AppPath 不搜索，限制 .exe/.lnk/.bat/.cmd
- **界面选中策略**：全局 `user-select:none`，仅对**「内容」**放行——可编辑控件（`input`/`textarea`/`contenteditable`）与界面上的路径文本（`.rpath`/`.chk-why`/`#drawerSub`/`.about-meta`）。判据是**内容 vs 界面**；一刀切会让输入框拖选、右键粘贴和路径复制一起失效
- **编码铁律**：ps1 必须 UTF-8 **带 BOM**（PS5.1 中文注释否则语法错误）；bat 必须全英文 ASCII + CRLF
- **数据落程序执行目录**：`$DataDir = $ScriptDir`，绿色自包含，禁用 `$env:APPDATA` 拼路径

## 已知问题

- 暂无阻塞项

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
