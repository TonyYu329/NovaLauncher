# Nova Launcher · Windows 个人应用工作台

<!-- 文档控制在 200 行以内 -->

<!-- 2026-09-13 全面更新：V1.0 实际实现 = 方案②「HTML 界面 + PowerShell 本地宿主」，
     C#/WinUI 3 方案因本机无 .NET SDK 未采用（其文档保留为 V2.0 演进蓝图） -->

## 项目概览

| 属性 | 值 |
|------|-----|
| 项目名称 | Nova Launcher（Windows 个人应用工作台） |
| 项目描述 | 极简 Windows 应用启动器：HTML 渲染首页、已安装应用枚举、真实图标、搜索、拖拽排序、点击启动、全屏⇄窗口化无边框切换 |
| 技术栈 | HTML/CSS/JS（前端）+ PowerShell 5.1（HttpListener 宿主）+ Win32 P/Invoke（C# Add-Type）+ Edge/Chrome `--app` 无边框窗口 |
| 数据存储 | 纯 JSON：`apps.json`（应用）+ `settings.json`（设置），**存于程序执行目录 `data/`**（绿色自包含，随目录迁移） |
| 交付形态 | 绿色版免安装：整个 `NovaLauncher.Web/` 即产物，双击 `NovaLauncher.bat` 启动 |
| 平台 | 仅 Windows 10 / Windows 11 x64 |
| 权威文档 | `DOCS/02...极简方案.md`（V1.0 方向）、`DOCS/04...HTML+宿主方案开发计划.md`（**执行计划 M1-M36，权威**）；详细说明书为 V2.0 演进蓝图 |
| GitHub | https://github.com/TonyYu329/NovaLauncher（main） |
| 版本 | V0.0.1（首个发布快照 2026-09-13；里程碑 M1-M36）；最新 commit `3f5879b` |

## 构建、测试与校验

- 运行：双击 `NovaLauncher.Web\NovaLauncher.bat`（无需编译）
- 语法校验：`[System.Management.Automation.Language.Parser]::ParseFile()` 检查 ps1
- 诊断接口：`/api/win?op=rect`（窗口/客户区/页面视口）、`op=pwshot`（PrintWindow 离屏抓帧到 `.temp/`）、`op=hit`（WindowFromPoint 命中测试，验证 region 裁剪）、`op=front`（强制置前）；验证探针 `.temp\winprobe.ps1 -Label X -Op none|max|min`
- 验证宿主必须 **in-process 后台运行**（沙箱子进程无法执行脚本体）；宿主 25s 无页面心跳自退
- **窗口 UI 验证必须干净单次启动**（`.temp\clean-launch.ps1`：先 `op=close` 关窗 + 只杀 Nova BrowserProfile 的 chrome，再启动一次）——反复 stop/start 会留 Chrome 会话残留，造成 innerHeight 卡旧值 / 连接红点等**伪影**，勿在残留会话下结论；截图用 `op=pwshot`+Read，region 裁剪硬判据用 `op=hit`

## 目录结构

```text
NovaLauncher.Web/
├── NovaLauncher.bat            # 唯一入口（根目录仅此一个文件，M29）
└── data/
    ├── NovaLauncher.ps1        # 宿主：HttpListener + Win32 窗口管理（UTF-8 BOM）
    ├── nova-launcher.html      # 前端单文件
    ├── nova-logo.ico / nova-logo-256.png / README.md
    ├── apps.json / settings.json   # 数据（随程序目录）
    └── Icons/ BrowserProfile/ runtime.json host.log   # 运行态（gitignore）
```

## 关键架构约定

- **浏览器启动参数**：`--app` + `--disable-features=CalculateNativeWinOcclusion`（M32 根因修复：禁用遮挡检测，防程序化 resize 后光栅化冻结出现 (32,32,32) 灰带）
- **任务栏图标三件套**：WM_SETICON + 窗口 AUMID（SHGetPropertyStoreForWindow）+ 开始菜单 AUMID.lnk（IShellLink QI IPropertyStore）；lnk 目标自动指向上级 bat
- **无边框（M33 重构）**：两形态都剥 WS_CAPTION/WS_THICKFRAME + SetWindowRgn 裁动态实测 CSD（≈28-30 逻辑 px，由页面 innerHeight 反推、「ih|外框高」双稳定指纹防竞态）；全屏靠窗口上移 csd 顶出 CSD；几何补偿不可见缩放边框 fw/fh（实测 14/7）；`WantWindowed` 记用户意图形态——最小化不是形态，还原必回意图形态（IsIconic 先 SW_RESTORE 再摆几何）；`Invoke-NovaWindowGuard` 守门每拍复核样式/几何 vs 意图；状态判断用矩形比较（含 fw/fh 补偿、容差 8px）非样式位
- **M34**：csd 持久化 `data\csd.cache`（启动瞬间即用、零暂态不露标题条）+ `Get-NovaCsd`（实测>缓存>兜底 34）+ CSD 闸门 [16,48]（区间外拒 artifacts 且**不锁 0**）+ GuardStreak≥4 暂停防抖；**严禁用 reload 修 --app 视口不跟随**（location.reload 复用同一 RenderWidgetHostView 无效，且引发每 3s 重载风暴→心跳中断→红点「未连接宿主」，M34 轮3 已回滚）
- **M35（DPI 根因）**：宿主启动主动 `SetProcessDpiAwarenessContext(PMV2)`（失败退 `SetProcessDPIAware`）——PowerShell 5.1 默认不感知而 Chrome --app 是 PMv2 感知，宿主用逻辑坐标摆物理窗口会让 Chrome 光栅化表面按逻辑尺寸 1:1 呈现→界面只铺左上/右底空白；开启后感知后全链路物理 px，`$script:DpiScale`（系统 DPI/96、页面 dpr 校准）换算逻辑常量（窗口化 1180×780、CSD 闸门 [16,48]、兜底 csd 34）；**坐标空间变更须清 `csd.cache`**
- **M36 窗口化拖动移窗**：仅 `body.is-windowed` 时标题栏可拖——页面 `pointerdown` 记鼠标/窗口基准 + `setPointerCapture`，`pointermove` 用 rAF 合帧 + in-flight 合并（在途只留最新点、不堆请求），位移 ×dpr 换物理 px 发宿主 `op=move`（`SetWindowPos` SWP_NOSIZE/NOZORDER/NOACTIVATE 只平移）；**不用 CSS `-webkit-app-region:drag`**（--app 窗被剥 WS_CAPTION + SetWindowRgn 裁顶栏后该属性实测不触发系统拖动、还会吞掉 DOM 鼠标事件）；拖动不改形态，守门不会把窗拉回
- **页面重绘双保险**：resize 防抖 150ms 后 body `translateZ(0)` 开关
- **HTTP**：127.0.0.1 随机端口 + token（runtime.json）；API 按路径分发不分方法；前端 `HOSTED = location.protocol === "http:"`，直开 file:// 走演示模式
- **已安装应用枚举**：开始菜单 .lnk + 注册表 Uninstall + Get-StartApps（UWP/AUMID），双重去重（先路径后名称）；使用频率 = UserAssist(ROT13) + FeatureUsage 相加；结果缓存 60s
- **编码铁律**：ps1 必须 UTF-8 **带 BOM**；bat 必须 UTF-8 无 BOM + CRLF
- **禁用 `$env:APPDATA` 等拼路径**：宿主进程环境可能被裁剪为空，一律用 `[System.Environment]::GetFolderPath(...)`
- **STA 线程**：「添加应用」文件框须独立 STA 线程（HttpListener 回调是 MTA）
- **V1.0 明确不做**：SQLite/ORM、全局快捷键、托盘、使用统计持久化（已装应用枚举与 UWP 启动已于 M14+ 实现）

## 通用规则

- **先调研再行动**：未阅读代码前严禁主观猜测；存疑时如实说明并给验证方案
- **专注需求本身**：仅完成指定任务，不额外拓展、不擅自重构无关代码
- **完成前自检**：逐项核对需求，说明修改内容、已验证项及暂无法验证的内容
- **高危操作提醒**：删除/强制推送/硬重置等危险操作前必须先确认
- **工具约定**：检索用 Grep/Glob；沙箱内 `reg.exe`/`schtasks.exe` 被拦截改用 PowerShell cmdlet
- **PowerShell 陷阱**：逗号（数组构造）优先级**高于** `+`，`@($a+$b, $c)` 解析为 `@($a+($b,$c))` 报 op_Addition —— 先算标量再组数组

## 开发与协作偏好

- **交互语言**：中文；代码注释中英文均可，以清晰为主
- **修改反馈**：每次修改完成后用表格打印「修改文件完整路径 + 说明」，标明确定/猜测；`修改记录.md` 追加记录（时间精确到秒、修改人 Tony）
- **Git 提交**：commit 前 add -A 后确认无大目录误入；push 本仓库走代理 `git -c http.proxy=http://127.0.0.1:31180 -c https.proxy=http://127.0.0.1:31181 push origin main`
- **本机环境注意**：F: 为 BitLocker 盘登录阶段不可达；C:/D: 磁盘紧张；`.workbuddy/` 目录是项目数据勿删

## 记忆库说明

| 记忆体系 | 位置 | 查阅时机 |
|--------|------|---------|
| WorkBuddy 项目记忆 | `.workbuddy/memory/`（MEMORY.md + 日期日志） | 会话开始自动注入/按需读取 |
| Obsidian 记忆库 | `D:\ObsidianData\02AgentMemoryBank`，项目入口 `01-项目区\NovaLauncher\@上下文-NovaLauncher.md` | 会话开始先读根导航；任务完成后按「记忆库上下文规则」写入（文件名含精确到秒时间戳） |

**写入流程（2026-09-13 固化）**：① GitHub 提交 → ② 读 `00-系统配置/00-根导航.md` → ③ 匹配项目写入 `@上下文` → ④ 补 `会话记录/`、`架构决策/`、`项目文档/`（文件名含精确到秒时间戳）→ ⑤ 更新 `02-全局知识/02-通用偏好与配置.md` → ⑥ 更新本文件 → ⑦ 输出写入的文件名清单。
