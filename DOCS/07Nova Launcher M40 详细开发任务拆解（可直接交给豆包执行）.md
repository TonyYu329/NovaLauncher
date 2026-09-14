# Nova Launcher M40 详细开发任务拆解（可直接交给豆包执行）

项目：Nova Launcher
版本：M40（V0.0.3 候选）
类型：Windows 桌面应用启动器
重构目标：**彻底移除 Chromium CSD 与 Chrome --app 依赖，改用 WinForms 无边框容器 + WebView2Controller 内嵌渲染架构，从根源消除顶部黑边与点击穿透；启用毛玻璃主题（Mica/Acrylic）；生产级 DPI（GetDpiForWindow + WM_DPICHANGED）与异步初始化（非阻塞 UI 线程）。**
开发方式：增量重构，保留现有 UI、业务逻辑、数据文件（apps.json / settings.json）与图标提取逻辑。
执行对象：豆包 / AI Coding Agent

---

## 0. 开发总原则（必须遵守）

### 不允许

- ❌ 不继续修补 CSD 高度（删除 Get-NovaCsd / Update-NovaCsdHeight / csd.cache）
- ❌ 不使用 SetWindowRgn 裁剪窗口（删除全部 SetWindowRgn / CreateRectRgn 调用）
- ❌ 不增加黑边补偿算法（删除 FrameW / FrameH / 不可见缩放边框补偿）
- ❌ 不通过 CSS margin/padding 修复窗口问题
- ❌ 不引入 Electron / CEF / 任何独立浏览器进程
- ❌ 不使用纯 Win32 CreateWindowEx 自建窗口（消息循环成本高）
- ❌ 不使用 WM_NCHITTEST 实现拖动（WebView2 子窗口会吃掉鼠标消息，父窗口收不到）
- ❌ 不依赖 `-webkit-app-region: drag`（在无边框 WebView2 中不生效）
- ❌ 不保留 HttpListener（WebView2 用虚拟主机映射 + WebMessage 替代）
- ❌ 不保留 Chrome / Edge --app 进程拉起逻辑
- ❌ **不使用 `GetDpiForSystem()`**（多显示器下只返回主显示器 DPI，窗口移到第二块屏幕后不更新，混合 DPI 环境错误）
- ❌ **不在 Form.Load 中用 `.GetAwaiter().GetResult()` / `.Result` / `.Wait()` 阻塞初始化**（WebView2 COM 回调需 UI 线程泵送，阻塞 UI 线程 = 死锁）
- ❌ 不使用纯色不透明背景（必须启用毛玻璃主题）

### 必须实现

- ✅ PowerShell 以 **-STA** 模式运行
- ✅ 进程创建任何窗口前先调用 **SetProcessDpiAwarenessContext(PMv2)**
- ✅ **WinForms Form** 作为窗口容器（FormBorderStyle = None，底层即 WS_POPUP）
- ✅ **CoreWebView2Controller** 直接绑定 Form.Handle（Composition Controller，非 WinForms WebView2 控件）
- ✅ **WebView2 异步初始化用 Form.Shown + WinForms Timer 轮询**，不阻塞 UI 线程（详见 §4 Task 4）
- ✅ **DPI 用 `GetDpiForWindow(form.Handle)`**，禁止 GetDpiForSystem；必须处理 `WM_DPICHANGED`（跨屏自动更新窗口尺寸与 WebView2.Bounds）
- ✅ **毛玻璃主题**：WinForms 层 DwmSetWindowAttribute 启用 Mica/Acrylic，WebView2 背景透明，HTML 层半透明透出系统毛玻璃（详见 §4 Task 4.5）
- ✅ HTML/CSS/JS 全屏占满 Form 客户区，顶部 0 像素黑边
- ✅ HTML 自绘标题栏（最小化 / 最大化还原 / 关闭按钮）
- ✅ 页面 ↔ 宿主统一走 **chrome.webview.postMessage / WebMessageReceived**
- ✅ 窗口拖动由 JS pointer 事件 → postMessage → 宿主 SetWindowPos/Form.Location 实现
- ✅ WinForms 负责窗口生命周期（创建、显示、最小化、关闭、消息循环）
- ✅ DPI 自动适配（PMv2 + GetDpiForWindow + 物理像素，controller.Bounds = Form.ClientRectangle）

---

## 1. M40 目标架构（技术栈已锁定）

### 分层结构

```
NovaLauncher.bat
  └─ powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden
       │              -File data\NovaLauncher.ps1
       │
       ├─ ① SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)   ← 进程第一行窗口相关代码
       │
       ├─ ② WinForms Form（FormBorderStyle=None）                 ← 窗口层（WS_POPUP）
       │      ├─ ShowInTaskbar = True
       │      ├─ StartPosition = Manual（自己算居中坐标）
       │      ├─ 无标题栏、无边框、无系统按钮
       │      ├─ DWM 毛玻璃（DwmSetWindowAttribute: Mica/Acrylic）
       │      ├─ WndProc 拦截 WM_DPICHANGED（跨屏 DPI 切换）
       │      └─ Form.Handle ──────────────────┐
       │                                        │
       ├─ ③ CoreWebView2Controller（绑定 HWND）←┘  ← 渲染控制器层
       │      ├─ 初始化：Form.Shown 事件 → WinForms Timer 50ms 轮询 Task.IsCompleted
       │      │   （不阻塞 UI 线程，避免 WebView2 COM 回调死锁）
       │      ├─ Bounds = Form.ClientRectangle（物理像素，随 Resize/DPI 变化更新）
       │      ├─ DefaultBackgroundColor = Transparent（透出毛玻璃）
       │      ├─ CoreWebView2
       │      │    ├─ SetVirtualHostNameToFolderMapping("nova.app", data目录)
       │      │    ├─ Navigate("https://nova.app/nova-launcher.html")
       │      │    ├─ add_WebMessageReceived(...)   ← 页面→宿主
       │      │    └─ PostWebMessageAsJson(...)     ← 宿主→页面
       │      └─ 缩放系数来自 GetDpiForWindow(hwnd)/96（非 GetDpiForSystem）
       │
       └─ ④ Application.Run($form)                  ← WinForms 消息循环（替代 HttpListener 轮询）
```

### 为什么是 WinForms Form 而不是纯 Win32

| 维度 | WinForms Form（选定） | 纯 Win32 CreateWindowEx |
|------|----------------------|------------------------|
| 消息循环 | Application.Run 现成 | 需手写 GetMessage/DispatchMessage |
| 窗口句柄 | form.Handle 现成 | CreateWindowEx + 注册窗口类 |
| Resize | form.Resize 事件现成 | 需处理 WM_SIZE |
| DPI | OnDpiChanged / 事件 | 需处理 WM_DPICHANGED |
| 本质 | FormBorderStyle=None 底层就是 WS_POPUP | 同 |
| 开发成本 | 最低 | 高，收益为零 |

### 为什么是 CoreWebView2Controller 而不是 WinForms WebView2 控件

| 维度 | CoreWebView2Controller（选定） | WinForms WebView2 控件 |
|------|-------------------------------|----------------------|
| 层级 | 直接绑定 HWND，渲染表面贴客户区 | 控件层再包一层，受 Control 布局约束 |
| 大小位置 | controller.Bounds 完全自控 | Dock/Anchor 间接控制 |
| 透明/扩展 | 支持 | 受限 |
| 依赖 DLL | 仅 Microsoft.Web.WebView2.Core.dll | Core + WinForms 两个 DLL |

### 最终目录（保持现有扁平结构，增量重构，不拆多 ps1）

```
NovaLauncher
│
├── NovaLauncher.bat                    （改：确认 -STA，注释更新）
│
├── data/
│   ├── NovaLauncher.ps1                （重构：WinForms + WebView2，单文件内用 #region 分模块）
│   ├── nova-launcher.html              （改：fetch /api/* 全部改为 postMessage）
│   ├── apps.json                       （不变）
│   ├── settings.json                   （不变）
│   ├── nova-logo.ico                   （不变，Form.Icon + 任务栏图标）
│   ├── nova-logo-256.png               （不变，favicon）
│   ├── lib/                            （新增：第三方 DLL）
│   │   └── Microsoft.Web.WebView2.Core.dll
│   ├── Icons/                          （运行时生成，图标缓存，.gitignore 已排除）
│   └── WebView2Profile/                （运行时生成，WebView2 用户数据目录，加入 .gitignore）
│
├── DOCS/                               （文档，不动）
├── README.md
└── .gitignore                          （改：新增 WebView2Profile/）
```

> 说明：M40 不拆 NovaWindowManager.ps1 / NovaHostBridge.ps1。单文件用 `#region 窗口层` `#region 通信层` `#region 业务层` 划分；如后续超过 2000 行再在 M41 拆分。

---

## 2. 环境准备

### Task 2.1：确认 WebView2 Runtime

WebView2 Runtime（Evergreen）在 Win10 20H2+ / Win11 系统自带。启动时检测注册表：

```
HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}  → pv 值
HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}            → pv 值
```

缺失则弹 MessageBox 提示「需要 WebView2 Runtime，是否打开下载页」，确认后用 `Start-Process "https://developer.microsoft.com/microsoft-edge/webview2/"` 打开。

### Task 2.2：获取 Microsoft.Web.WebView2.Core.dll

1. 下载 NuGet 包：`https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/<版本>`
   - 版本选择：与 Runtime 138.x 兼容的稳定版（如 1.0.2903.40 或更新），用 `1.0.2903.40`。
2. NuGet 包本质是 zip，解压后取：
   - `lib\net462\Microsoft.Web.WebView2.Core.dll`（PowerShell 5.1 对应 .NET Framework 4.6.2+，用 net462 目录）
3. 放到 `data\lib\Microsoft.Web.WebView2.Core.dll`。
4. 脚本中加载：

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$coreDll = Join-Path $DataDir 'lib\Microsoft.Web.WebView2.Core.dll'
Add-Type -Path $coreDll
```

> 只用 Core.dll，不需要 Microsoft.Web.WebView2.WinForms.dll / Wpf.dll。

### Task 2.3：.gitignore 增补

在 `.gitignore` 中追加：

```
# WebView2 用户数据目录（运行时生成）
data/WebView2Profile/
# WebView2 崩溃转储
data/*.dmp
```

---

## 3. 通信协议规范（WebMessage）

### 3.1 传输机制

| 方向 | API |
|------|-----|
| 页面 → 宿主 | `window.chrome.webview.postMessage(obj)` |
| 宿主 → 页面 | `$coreWebView2.PostWebMessageAsJson($jsonString)` |

### 3.2 请求-响应约定（带 id 配对）

postMessage 本身是单向的，业务 API 需要请求-响应。统一信封格式：

**页面 → 宿主（请求）：**
```json
{ "id": 17, "op": "launch", "data": { "i": 3 } }
```

**宿主 → 页面（响应）：**
```json
{ "id": 17, "ok": true, "data": { ... } }
```
失败：
```json
{ "id": 17, "ok": false, "msg": "未找到应用" }
```

**宿主 → 页面（主动推送，无 id）：**
```json
{ "event": "stateChanged", "data": { "state": "windowed" } }
```

### 3.3 页面端通信封装（nova-launcher.html 内）

```javascript
/* ===================== WebView2 通信层（替代 fetch /api/*） ===================== */
const WV2 = !!(window.chrome && window.chrome.webview);
let __reqId = 0;
const __pending = new Map();

function novaSend(op, data = {}) {
  // 返回 Promise；演示模式（直接双击 HTML 打开，无 chrome.webview）走 demo 兜底
  if (!WV2) return Promise.reject(new Error("no-host"));
  return new Promise((resolve, reject) => {
    const id = ++__reqId;
    __pending.set(id, { resolve, reject });
    window.chrome.webview.postMessage({ id, op, data });
  });
}

window.chrome.webview && window.chrome.webview.addEventListener("message", (e) => {
  let msg;
  try { msg = typeof e.data === "string" ? JSON.parse(e.data) : e.data; } catch (_) { return; }
  // 响应配对
  if (msg.id != null && __pending.has(msg.id)) {
    const p = __pending.get(msg.id);
    __pending.delete(msg.id);
    msg.ok === false ? p.reject(new Error(msg.msg || "操作失败")) : p.resolve(msg);
    return;
  }
  // 主动推送事件
  if (msg.event) handleHostEvent(msg.event, msg.data);
});

function handleHostEvent(event, data) {
  if (event === "stateChanged") applyWinChrome(data.state);
}
```

### 3.4 宿主端消息分发（NovaLauncher.ps1 内）

```powershell
$coreWebView2.add_WebMessageReceived({
    param($sender, $e)
    try {
        $msg = $e.WebMessageAsJson | ConvertFrom-Json
        $id  = $msg.id
        $op  = $msg.op
        $data = $msg.data
        $result = Invoke-NovaApi $op $data      # 统一业务分发，返回 [pscustomobject]
        $resp = @{ id = $id; ok = $true;  data = $result } | ConvertTo-Json -Depth 10 -Compress
    } catch {
        $resp = @{ id = $id; ok = $false; msg = $_.Exception.Message } | ConvertTo-Json -Compress
    }
    $sender.PostWebMessageAsJson($resp)
})
```

### 3.5 op 清单（从现有 16 个 /api/* 端点迁移，语义不变）

| op | 入参 data | 返回 data | 说明 |
|----|-----------|-----------|------|
| `state` | `{}` | `{apps, settings, state, dpr}` | 初始状态 + 窗口形态 |
| `checkapps` | `{}` | `{total, okCount, bad:[...]}` | 校验应用路径有效性 |
| `launch` | `{i}` | `{ok}` | 启动第 i 个应用 |
| `pick` | `{}` | `{path, name}` | 弹出快捷方式选择对话框 |
| `add` | `{p, n, k}` | `{apps}` | 添加单个应用 |
| `addbatch` | `{items:[...]}` | `{apps}` | 批量添加 |
| `remove` | `{i}` | `{apps}` | 移除应用 |
| `rename` | `{i, p, n}` | `{apps}` | 改显示名（不动磁盘文件） |
| `move` | `{from, to}` | `{apps}` | 拖拽排序落盘 |
| `setting` | `{k, v}` | `{settings}` | 保存外观设置 |
| `reveal` | `{i}` | `{ok}` | 资源管理器定位文件 |
| `installed` | `{sort, q}` | `{apps:[...]}` | 枚举开始菜单/桌面已安装程序 |
| `quit` | `{}` | — | 退出宿主（关闭 Form） |
| `win.min` | `{}` | `{state}` | 最小化 |
| `win.max` | `{}` | `{state}` | 全屏 ⇄ 窗口化切换 |
| `win.close` | `{}` | — | 关闭窗口（等同 quit） |
| `win.rect` | `{}` | `{rect:{l,t,w,h}}` | 取窗口外框（拖动起点用） |
| `win.move` | `{x, y}` | `{ok}` | 拖动窗口（物理像素坐标） |
| `win.state` | `{}` | `{state}` | 仅取窗口形态 |

> 图标不走 op：用虚拟主机映射直接当静态资源加载（见 Task 6）。
> 心跳 `/api/ping` 取消：WebView2 生命周期由控制器托管，窗口关闭即触发 `form.FormClosed`，无需 25 秒心跳判活。

---

## 4. 分阶段任务（按顺序执行）

### Task 1：启动入口改造

**文件：`NovaLauncher.bat`**

当前第 27 行已含 `-STA`，确认保留并更新注释：

```bat
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0data\NovaLauncher.ps1" %*
```

**文件：`data\NovaLauncher.ps1` 顶部**

在所有窗口/绘图代码之前（param 块之后、加载任何程序集之后立即）：

```powershell
# ── DPI 感知：必须在创建 Form / WebView2 之前，否则坐标被系统虚拟化导致界面只铺左上 ──
$script:DpiAware = $false
try {
    $sig = @'
using System;
using System.Runtime.InteropServices;
public static class DpiNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    public static readonly IntPtr PMV2 = new IntPtr(-4);
    public const int WM_DPICHANGED = 0x02E0;
}
'@
    Add-Type -TypeDefinition $sig -Language CSharp
    if ([DpiNative]::SetProcessDpiAwarenessContext([DpiNative]::PMV2)) { $script:DpiAware = $true }
    elseif ([DpiNative]::SetProcessDPIAware()) { $script:DpiAware = $true }
} catch { }

# 获取当前窗口所在显示器的 DPI（多显示器/混合 DPI 下必须用窗口句柄，不能用 GetDpiForSystem）
function Get-NovaDpiScale([IntPtr]$hwnd) {
    if ($script:DpiAware -and $hwnd -ne [IntPtr]::Zero) {
        $dpi = [DpiNative]::GetDpiForWindow($hwnd)
        if ($dpi -gt 0) { return $dpi / 96.0 }
    }
    return 1.0
}
```

> **为什么不用 GetDpiForSystem**：该 API 只返回主显示器 DPI。窗口拖到第二块屏幕（如 150%）后，系统发 WM_DPICHANGED，但代码仍用主显示器（100%）的 DPI 算尺寸 → WebView2.Bounds 与客户区不匹配 → 界面只铺左上、右/底空白。这与 M39 黑边同属"窗口/DPI 边界问题"。

### Task 2：加载程序集与 WebView2 Core DLL

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:DataDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -Path (Join-Path $script:DataDir 'lib\Microsoft.Web.WebView2.Core.dll')
```

### Task 3：创建 WinForms 无边框容器窗口

```powershell
#region 窗口层
$script:WantWindowed = $false      # $false=全屏铺满工作区，$true=1180×780 居中小窗
$script:WinClientW = 1180          # 窗口化页面可见区（逻辑/CSS px）
$script:WinClientH = 780

# NovaForm 是子类化 Form（重写 WndProc 拦截 WM_DPICHANGED），定义见下方 WM_DPICHANGED 代码块
$form = New-Object NovaForm
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar   = $true
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::Transparent   # 毛玻璃前提：Form 背景透明，透出 DWM 毛玻璃
$form.Icon            = New-Object System.Drawing.Icon((Join-Path $script:DataDir 'nova-logo.ico'))
$form.Text            = 'Nova Launcher'
# 注意：Form.DoubleBuffered 是 protected 属性，PowerShell 不能直接设置；如需双缓冲需在 NovaForm 构造函数中设置

# 任务栏 AUMID（沿用现有逻辑，保证独立分组与图标）
# —— 保留现有 SetCurrentProcessExplicitAppUserModelID / SHGetPropertyStoreForWindow 代码 ——
#endregion
```

**窗口几何函数（替代 Set-NovaWinMaximized，删除 csd/fw/fh 补偿）：**

```powershell
function Set-NovaWindowLayout([switch]$Windowed) {
    $wa = [System.Windows.Forms.Screen]::FromHandle($form.Handle).WorkingArea
    if (-not $wa) { $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
    $dpr = Get-NovaDpiScale $form.Handle     # ← 用窗口句柄取当前屏幕 DPI，非 GetDpiForSystem

    if ($Windowed) {
        $cw = [int]($script:WinClientW * $dpr)
        $ch = [int]($script:WinClientH * $dpr)
        $cw = [Math]::Min($cw, $wa.Width)
        $ch = [Math]::Min($ch, $wa.Height)
        $form.Size = New-Object System.Drawing.Size($cw, $ch)
        $form.Location = New-Object System.Drawing.Point(
            $wa.X + [int](($wa.Width  - $cw) / 2),
            $wa.Y + [int](($wa.Height - $ch) / 2))
    } else {
        $form.Location = New-Object System.Drawing.Point($wa.X, $wa.Y)
        $form.Size = New-Object System.Drawing.Size($wa.Width, $wa.Height)
    }
    $script:WantWindowed = [bool]$Windowed
    # controller.Bounds 在 Resize 事件里统一更新，这里不重复
}
```

> 关键区别：Form 客户区 = 窗口大小（无标题栏/边框），WebView2 铺满客户区即页面可见区，**不需要任何 csd/fw/fh 补偿，不存在黑边**。

**WM_DPICHANGED 处理（跨屏 DPI 切换）：**

子类化 Form 的 WndProc，拦截 `WM_DPICHANGED (0x02E0)`。窗口从 100% 显示器拖到 150% 显示器时，系统发此消息，lParam 指向建议的新窗口矩形。处理方式：

```powershell
# 用 Add-Type 定义一个继承 Form 的子类，重写 WndProc
$sig = @'
using System;
using System.Windows.Forms;
public class NovaForm : Form {
    public Action DpiChanged;
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x02E0) {  // WM_DPICHANGED
            // lParam 指向 RECT（建议的新窗口位置/大小），直接采纳
            NativeMethods.RECT rc = (NativeMethods.RECT)System.Runtime.InteropServices.Marshal.PtrToStructure(
                m.LParam, typeof(NativeMethods.RECT));
            this.Location = new System.Drawing.Point(rc.Left, rc.Top);
            this.Size = new System.Drawing.Size(rc.Right - rc.Left, rc.Bottom - rc.Top);
            DpiChanged?.Invoke();
            m.Result = IntPtr.Zero;
            return;
        }
        base.WndProc(ref m);
    }
}
public static class NativeMethods {
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
Add-Type -TypeDefinition $sig -ReferencedAssemblies System.Windows.Forms,System.Drawing
# 用 NovaForm 替代普通 Form
$form = New-Object NovaForm
$form.DpiChanged = {
    # DPI 变化后同步 WebView2.Bounds（新客户区物理像素）
    if ($script:WebController) { $script:WebController.Bounds = $form.ClientRectangle }
}
```

### Task 4：初始化 CoreWebView2Controller（异步，不阻塞 UI 线程）

> **为什么不能用 .GetAwaiter().GetResult()**：WebView2 的 CreateAsync / CreateCoreWebView2ControllerAsync 是 COM 异步操作，完成时需通过 UI 线程消息循环回调。若在 Form.Load 中用 `.GetAwaiter().GetResult()` 阻塞 UI 线程 → COM 回调等不到 UI 线程 → **死锁**（PoC 中用 DoEvents 循环勉强可行，但生产环境必须用真正的异步）。
>
> **PowerShell 5.1 没有 async/await**，用 **WinForms Timer 轮询 Task.IsCompleted** 实现异步：Timer.Tick 在 UI 线程触发，每次检查任务状态，未完成就返回（UI 线程继续处理消息），完成后进入下一步。这是 PowerShell 5.1 下最可靠的非阻塞异步模式。

```powershell
#region 渲染层
$script:WebController = $null
$script:WebView       = $null
$script:InitStep      = 0     # 0=未开始 1=等CreateAsync 2=等CreateController 3=完成
$script:InitEnvTask   = $null
$script:InitCtrlTask  = $null
$script:InitTimer     = $null

function Start-NovaWebViewInit {
    $script:InitStep = 0
    $script:InitTimer = New-Object System.Windows.Forms.Timer
    $script:InitTimer.Interval = 50
    $script:InitTimer.Add_Tick({ Step-NovaWebViewInit })
    $script:InitTimer.Start()
}

function Step-NovaWebViewInit {
    switch ($script:InitStep) {
        0 {
            # Step 0: 启动 CreateAsync（不等待，立即返回）
            $profileDir = Join-Path $script:DataDir 'WebView2Profile'
            if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
            $envOpts = New-Object Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions
            $script:InitEnvTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $profileDir, $envOpts)
            $script:InitStep = 1
        }
        1 {
            # Step 1: 轮询 CreateAsync 是否完成
            if ($script:InitEnvTask.IsCompleted) {
                if ($script:InitEnvTask.IsFaulted) { throw $script:InitEnvTask.Exception.InnerException }
                $script:InitEnvironment = $script:InitEnvTask.Result
                $script:InitCtrlTask = $script:InitEnvironment.CreateCoreWebView2ControllerAsync($form.Handle)
                $script:InitStep = 2
            }
        }
        2 {
            # Step 2: 轮询 CreateControllerAsync 是否完成
            if ($script:InitCtrlTask.IsCompleted) {
                if ($script:InitCtrlTask.IsFaulted) { throw $script:InitCtrlTask.Exception.InnerException }
                $script:WebController = $script:InitCtrlTask.Result
                $script:WebView       = $script:WebController.CoreWebView2
                # 背景透明（透出毛玻璃）
                try { $script:WebView.DefaultBackgroundColor = [System.Drawing.Color]::Transparent } catch {}
                $script:WebController.Bounds    = $form.ClientRectangle
                $script:WebController.IsVisible = $true
                Register-NovaVirtualHost
                Register-NovaWebMessage
                $script:WebView.Navigate('https://nova.app/nova-launcher.html')
                $script:InitTimer.Stop()
                $script:InitTimer.Dispose()
                $script:InitStep = 3
                Write-Log "WebView2 初始化完成（异步）"
            }
        }
    }
}
#endregion
```

**在 Form.Shown（非 Load）中启动异步初始化：**

```powershell
$form.Add_Shown({
    if ($script:InitStep -eq 0) { Start-NovaWebViewInit }
})
```

> 用 Shown 而非 Load：Shown 在窗口首次可见后触发，此时 Handle 已创建、消息循环已运行，Timer 能正常泵送。Load 在 Handle 创建后、显示前触发，此时消息循环尚未完全启动。

### Task 4.5：毛玻璃主题（Mica / Acrylic）

**WinForms 层启用 DWM 系统毛玻璃：**

```powershell
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DwmGlass {
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    public const int DWMWA_SYSTEMBACKDROP_TYPE = 38;  // Win11 22H2+
    public const int DWMSBT_MAINWINDOW = 2;           // Mica
    public const int DWMSBT_TRANSIENTWINDOW = 3;      // Acrylic
    public const int DWMSBT_TABBEDWINDOW = 4;         // Mica Alt
    [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref MARGINS m);
    [StructLayout(LayoutKind.Sequential)] public struct MARGINS { public int L,T,R,B; }
}
'@

function Enable-NovaGlass([IntPtr]$hwnd) {
    # 先把帧扩展到客户区（毛玻璃的前提）
    $m = New-Object DwmGlass+MARGINS
    $m.L = -1; $m.T = -1; $m.R = -1; $m.B = -1   # -1 = 整个窗口启用玻璃
    [DwmGlass]::DwmExtendFrameIntoClientArea($hwnd, [ref]$m) | Out-Null
    # 尝试 Mica（Win11）；失败则 Acrylic；Win10 两者都失败时退化为半透明纯色
    $val = [DwmGlass]::DWMSBT_MAINWINDOW
    $hr = [DwmGlass]::DwmSetWindowAttribute($hwnd, [DwmGlass]::DWMWA_SYSTEMBACKDROP_TYPE, [ref]$val, 4)
    if ($hr -ne 0) {
        $val = [DwmGlass]::DWMSBT_TRANSIENTWINDOW
        [DwmGlass]::DwmSetWindowAttribute($hwnd, [DwmGlass]::DWMWA_SYSTEMBACKDROP_TYPE, [ref]$val, 4) | Out-Null
    }
}
```

**调用时机：** Form.Shown 中、WebView2 初始化前调用 `Enable-NovaGlass $form.Handle`。

**HTML 层配合：**
- `body { background: transparent }` 或 `background: rgba(238,240,245,0.7)`（半透明透出毛玻璃）
- 卡片/抽屉用 `backdrop-filter: blur(20px)` + 半透明背景，增强层次
- 标题栏用半透明深色/浅色，与毛玻璃融合
- 深浅主题切换时调整 body 透明度（深色主题透明度可更低，更通透）

> **降级策略**：Win10 不支持 DWMWA_SYSTEMBACKDROP_TYPE，DwmExtendFrameIntoClientArea 会启用传统毛玻璃（Aero Glass 风格模糊）。若连传统毛玻璃也不可用（Win10 某些版本），WebView2 透明背景 + Form.BackColor 半透明纯色兜底，视觉上仍优于纯色不透明。

### Task 5：本地资源虚拟主机映射（替代 HttpListener 静态托管）

```powershell
function Register-NovaVirtualHost {
    # 把 data 目录映射为 https://nova.app/，HTML/CSS/JS/内置图片直接当静态资源加载
    $kind = [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow
    $script:WebView.SetVirtualHostNameToFolderMapping('nova.app', $script:DataDir, $kind)
}
```

- 页面地址：`https://nova.app/nova-launcher.html`
- 内置 logo：`https://nova.app/nova-logo-256.png`
- favicon：页面 `<link rel="icon" href="https://nova.app/nova-logo-256.png">`
- 动态图标：见 Task 10。

### Task 6：图标方案迁移

**保留现有 `PrivateExtractIcons` 图标提取与 MD5 缓存逻辑（data/Icons/<md5>.png）不变。**

两种加载方式，选 **方式 A（推荐）**：

**方式 A：预热 + 虚拟主机静态服务**
- 沿用现有启动预热逻辑：apps.json 加载后把所有图标提取到 `data/Icons/<路径MD5>.png`。
- 因为 `data` 目录已整体映射到 `nova.app`，页面图标 URL 直接为：
  ```javascript
  iconUrl(p) { return "https://nova.app/Icons/" + md5(p) + ".png"; }
  ```
- 新增应用时，宿主在 add/addbatch 处理中同步提取图标后再返回，前端拿到响应时图标已存在。
- 缺图标时页面用现有字形兜底（onerror 逻辑保留）。

**方式 B（备选）：WebResourceRequested 动态拦截**
- 若不希望预热，用 `AddWebResourceRequestedFilter('https://nova.app/api/icon/*', ...)` 拦截，在事件里现场提取并返回 PNG 流。
- 方式 B 实现更复杂，M40 先用方式 A。

### Task 7：宿主端 WebMessage 分发（通信层）

```powershell
#region 通信层
function Register-NovaWebMessage {
    $script:WebView.add_WebMessageReceived({
        param($sender, $e)
        $id = $null
        try {
            $msg  = $e.WebMessageAsJson | ConvertFrom-Json
            $id   = $msg.id
            $op   = [string]$msg.op
            $data = $msg.data
            $ret  = Invoke-NovaApi $op $data
            $resp = @{ id = $id; ok = $true; data = $ret } | ConvertTo-Json -Depth 12 -Compress
        } catch {
            $resp = @{ id = $id; ok = $false; msg = $_.Exception.Message } | ConvertTo-Json -Compress
        }
        $sender.PostWebMessageAsJson($resp)
    })
}

# 统一业务分发：op → 现有业务函数。业务函数本体（Get-Apps / Save-Apps / 启动应用 /
# 枚举已安装 / 图标提取 / 对话框）全部保留，仅把「读 HTTP 查询参数」改为「读 $data 字段」，
# 把「Send-Json 写响应流」改为「return 对象」。
function Invoke-NovaApi([string]$op, $data) {
    switch ($op) {
        'state'      { return Get-NovaStatePayload }
        'checkapps'  { return Test-NovaApps }
        'launch'     { Invoke-LaunchApp ([int]$data.i); return @{ ok = $true } }
        'pick'       { return Get-NovaPickedFile }
        'add'        { return Add-NovaApp $data.p $data.n $data.k }
        'addbatch'   { return Add-NovaAppsBatch $data.items }
        'remove'     { return Remove-NovaApp ([int]$data.i) }
        'rename'     { return Rename-NovaApp ([int]$data.i) $data.p $data.n }
        'move'       { return Move-NovaApp ([int]$data.from) ([int]$data.to) }
        'setting'    { return Set-NovaSetting $data.k $data.v }
        'reveal'     { Invoke-RevealApp ([int]$data.i); return @{ ok = $true } }
        'installed'  { return Get-InstalledApps $data.sort $data.q }
        'win.min'    { $form.WindowState = 'Minimized'; return @{ state = Get-NovaWinState } }
        'win.max'    { Toggle-NovaWindow; return @{ state = Get-NovaWinState } }
        'win.close'  { $form.BeginInvoke([Action]{ $form.Close() }); return @{ ok = $true } }
        'win.rect'   { $r = $form.Bounds; return @{ rect = @{ l=$r.X; t=$r.Y; w=$r.Width; h=$r.Height } } }
        'win.move'   { Move-NovaWindow ([int]$data.x) ([int]$data.y); return @{ ok = $true } }
        'win.state'  { return @{ state = Get-NovaWinState } }
        'quit'       { $form.BeginInvoke([Action]{ $form.Close() }); return @{ ok = $true } }
        default      { throw "未知操作：$op" }
    }
}
#endregion
```

### Task 8：窗口行为（拖动 / 最小化 / 最大化 / 关闭 / Resize）

**8.1 Resize → 同步 WebView2 Bounds：**

```powershell
$form.Add_Resize({
    if ($script:WebController) {
        # 最小化时不改 Bounds（客户区为 0 会导致渲染表面异常）
        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
            $script:WebController.Bounds = $form.ClientRectangle
        }
    }
})
```

**8.2 全屏 ⇄ 窗口化切换：**

```powershell
function Toggle-NovaWindow {
    if ($script:WantWindowed) {
        Set-NovaWindowLayout                   # 切全屏
        Push-NovaState 'maximized'
    } else {
        Set-NovaWindowLayout -Windowed         # 切窗口化
        Push-NovaState 'windowed'
    }
}

function Get-NovaWinState {
    if ($form.WindowState -eq 'Minimized') { return 'minimized' }
    if ($script:WantWindowed) { return 'windowed' }
    return 'maximized'
}

# 宿主主动推送窗口形态（供前端同步按钮图标）
function Push-NovaState($state) {
    if ($script:WebView) {
        $json = @{ event = 'stateChanged'; data = @{ state = $state } } | ConvertTo-Json -Compress
        $script:WebView.PostWebMessageAsJson($json)
    }
}
```

**8.3 拖动（JS → win.move → 宿主移动 Form）：**

```powershell
function Move-NovaWindow([int]$x, [int]$y) {
    # x,y 为页面算出的窗口新左上角（物理像素）。Form.Location 即物理坐标（PMv2 感知）。
    if ($form.WindowState -eq 'Minimized') { return }
    $form.Location = New-Object System.Drawing.Point($x, $y)
}
```

> 前端拖动逻辑（pointerdown 记基准 → pointermove 算新坐标 → win.move）整体保留，
> 仅把 `apiGet("/api/win",{op:"move",x,y})` 换成 `novaSend("win.move",{x,y})`，
> 把 `op:"rect"` 换成 `novaSend("win.rect")`。物理像素换算仍用 `devicePixelRatio`。

**8.4 关闭即退出：**

```powershell
$form.Add_FormClosed({
    try { if ($script:WebController) { $script:WebController.Close() } } catch { }
    [System.Windows.Forms.Application]::Exit()
})
```

### Task 9：前端改造（nova-launcher.html）

**9.1 通信层替换**

- 删除 `TOKEN`、`apiGet`、`apiPost`、`encodeQuery`、`/api/ping` 心跳轮询、`hostDead` 降级逻辑。
- 加入 §3.3 的 `novaSend` / 消息监听封装。
- `API` 对象所有方法改为 `novaSend`：

```javascript
const API = {
  state()      { return novaSend("state"); },
  launch(i)    { return novaSend("launch", { i }); },
  pick()       { return novaSend("pick"); },
  addPath(p,n,k){ return novaSend("add", { p, n, k }); },
  addBatch(items){ return novaSend("addbatch", { items }); },
  remove(i)    { return novaSend("remove", { i }); },
  rename(i,p,n){ return novaSend("rename", { i, p, n }); },
  move(from,to){ return novaSend("move", { from, to }); },
  setting(k,v) { return novaSend("setting", { k, v }); },
  reveal(i)    { return novaSend("reveal", { i }); },
  installed(s,q){ return novaSend("installed", { sort: s||"name", q: q||"" }); },
  checkApps()  { return novaSend("checkapps"); },
  quit()       { return novaSend("quit"); },
};
```

- 响应结构从旧的 `{ok, ...}` 改为读 `msg.data`：`const r = await API.launch(i);` 后业务字段在 `r.data`。统一在 novaSend resolve 时返回完整信封，业务代码取 `.data.xxx`。

**9.2 窗口按钮**

```javascript
$("winMin").onclick   = () => novaSend("win.min");
$("winMax").onclick   = async () => { const r = await novaSend("win.max"); applyWinChrome(r.data.state); };
$("winClose").onclick = () => novaSend("win.close");
```

**9.3 拖动**

- `setupTitlebarDrag` 保留，`apiGet("/api/win",{op:"move",x,y})` → `novaSend("win.move",{x,y})`；
  `apiGet("/api/win",{op:"rect"})` → `novaSend("win.rect")`（rect 在 `r.data.rect`）。
- 全屏/窗口化都允许拖动标题栏（窗口化移动窗口；全屏时拖动可还原为窗口化跟随鼠标——可选增强，M40 先保持「仅窗口化可拖」）。

**9.4 图标 URL**

```javascript
// 方式 A：虚拟主机静态图标
iconUrl(p) {
  return "https://nova.app/Icons/" + md5Hex(p) + ".png";
}
```
（md5 算法与宿主 PrivateExtractIcons 缓存命名一致；如前端无 md5 实现，改为宿主在 state 里直接下发每个 app 的 iconUrl，前端零计算——**推荐此做法**：state.data.apps 每项带 `icon` 字段，前端直接用。）

**9.5 初始化时序**

- 页面加载后 `API.state()` 拿 `{apps, settings, state}` 渲染；不再轮询心跳。
- 监听 `stateChanged` 事件同步最大化/还原图标。
- 直接双击 HTML 打开（无 chrome.webview）时保留「演示模式」：`WV2===false` 走 localStorage 兜底（现有演示模式逻辑保留）。

### Task 10：业务函数迁移（保留逻辑，改数据出入口）

现有以下函数**逻辑全部保留**，只改调用方式：

| 现有函数 | 改动 |
|----------|------|
| Get-Apps / Save-Apps / Get-Settings / Save-Settings | 不变 |
| 图标提取（PrivateExtractIcons P/Invoke + MD5 缓存 + 预热） | 不变，仅图标 URL 改虚拟主机 |
| 启动应用（Start-Process / shell: / .lnk 解析 + 新窗口前置快照差集） | 不变 |
| Bring-NewWindowToFront / ForceForeground | 不变 |
| 枚举已安装（开始菜单/桌面 .lnk 扫描） | 不变 |
| OpenFileDialog 选择快捷方式 | 改为在 STA UI 线程弹出（WinForms 下天然 STA，直接用 System.Windows.Forms.OpenFileDialog） |
| 窗口图标 WM_SETICON / AUMID | Form.Icon + AUMID 保留，SetCurrentProcessExplicitAppUserModelID 保留 |
| Write-Log | 保留，日志改写到 data/host.log（.gitignore 已排除） |

### Task 11：删除旧代码（清单，逐段删除）

在 `NovaLauncher.ps1` 中删除：

1. **HttpListener 全部代码**：`System.Net.HttpListener` 创建、前缀注册、`GetContext` 主循环、路由 switch（`^/api/ping$` 等 16 个分支）、`Send-Json`、token 生成与校验、静态文件响应、`/api/icon` 图片流响应。
2. **Chrome / Edge 进程拉起**：`chrome.exe`/`msedge.exe` 路径探测、`--app` 参数拼装、`--user-data-dir`、Start-Process 浏览器、BrowserProfile 目录逻辑。
3. **CSD 相关**：`$script:CsdHeight / CsdKnown / CsdTries / CsdLastKey / CsdCacheFile / CsdFallback / CsdCache`、`Get-NovaCsd`、`Update-NovaCsdHeight`、csd.cache 读写与清除逻辑。
4. **Region 相关**：`SetWindowRgn`、`CreateRectRgn` P/Invoke 声明与全部调用。
5. **不可见缩放边框补偿**：`$script:FrameW / FrameH / FrameKnown` 及其测量逻辑。
6. **旧窗口操作**：`Set-NovaWinMaximized`（含上移 csd、WS_CAPTION/WS_THICKFRAME 剥离）、`Get-NovaWinState`（基于窗口矩形比对工作区的旧判定）、`Invoke-NovaWindowGuard`（窗口守门，WebView2 架构下窗口几何完全自控，无需守门）、`Invoke-StartupMaximize`、查找 Chrome 窗口句柄的 `Get-NovaWin`（按标题/进程名找浏览器窗口）。
7. **心跳与自动退出**：25 秒无心跳退出逻辑、前端 3 秒心跳。
8. **诊断接口**：`/api/win` 下的 PrintWindow 截图、hit-test、clear-region 等诊断分支（如需保留诊断，后续用 WebMessage 单独的 `diag.*` op，M40 先删）。

> 删除后 `NovaWindow` C# P/Invoke 类中：保留 ForceForeground 所需的 SetWindowPos/ShowWindow/SetForegroundWindow 等（启动外部应用前置用）；删除仅服务于 Chrome 窗口改造的部分（SetWindowRgn/CreateRectRgn/DwmSetWindowAttribute 等）。

### Task 12：窗口状态持久化

**文件：`data/settings.json`** 增加窗口字段（不新建 window.json，减少文件数）：

```json
{
  "...现有外观字段不变...": "",
  "win": { "state": "maximized", "x": null, "y": null, "w": 1180, "h": 780 }
}
```

- 启动：读 `win.state`，maximized → 铺满工作区；windowed → 恢复 x/y/w/h（校验不超出屏幕，越界则回退居中）。
- 拖动结束（win.move 后）/ 切换形态 / 关闭时：保存当前 `form.Location`、`form.Size`、state。
- 最小化不写状态。

### Task 13：启动主流程（替换旧主循环）

```powershell
# 程序入口（脚本末尾）
try {
    Initialize-NovaData          # 加载 apps.json / settings.json（现有逻辑）
    $form.Add_Shown({
        if ($script:InitStep -eq 0) {
            Set-NovaWindowLayout     # 默认全屏铺满；若 settings.win.state=windowed 则居中
            Enable-NovaGlass $form.Handle   # 毛玻璃主题（Mica/Acrylic）
            Start-NovaWebViewInit    # 异步初始化 WebView2（Timer 轮询，不阻塞 UI）
            Prewarm-NovaIcons        # 图标预热（现有逻辑，确保 WebView 加载前图标就绪）
        }
    })
    [System.Windows.Forms.Application]::Run($form)
}
finally {
    try { if ($script:WebController) { $script:WebController.Close() } } catch { }
}
```

> 注意：用 `Form.Shown` 而非 `Form.Load`——Shown 在窗口首次可见后触发，此时 Handle 已创建且消息循环已运行，Timer 能正常泵送。WebView2 初始化用 Timer 轮询 `Task.IsCompleted`（50ms/次），**不阻塞 UI 线程**，彻底避免 COM 回调死锁。毛玻璃 `Enable-NovaGlass` 必须在 WebView2 初始化前调用（先设 DWM 属性，再让 WebView2 透明背景叠加其上）。

---

## 5. 删除/新增/修改文件总表

| 文件 | 操作 | 说明 |
|------|------|------|
| `NovaLauncher.bat` | 修改 | 确认 -STA，更新注释（不再拉起浏览器） |
| `data/NovaLauncher.ps1` | 大改 | 删 HttpListener/Chrome/CSD/Region；新增 WinForms(NovaForm)+WebView2 窗口层与通信层；GetDpiForWindow+WM_DPICHANGED；Form.Shown+Timer 异步初始化；DWM 毛玻璃；业务函数保留 |
| `data/nova-launcher.html` | 修改 | fetch→postMessage；删心跳/TOKEN；图标 URL；窗口按钮与拖动改 op；body/card 半透明背景配合毛玻璃；backdrop-filter 层次 |
| `data/lib/Microsoft.Web.WebView2.Core.dll` | 新增 | NuGet 提取，net462 版本 |
| `data/apps.json` | 不变 | |
| `data/settings.json` | 增补 win 字段 | 窗口状态持久化 |
| `data/nova-logo.ico` / `nova-logo-256.png` | 不变 | |
| `.gitignore` | 修改 | 增 `data/WebView2Profile/`、`*.dmp`；删除已无用的 `data/csd.cache`（保留也无害） |
| `data/BrowserProfile/` | 删除 | Chrome 配置目录，不再需要（运行时目录，已 gitignore，手动删一次） |

---

## 6. 测试与验收标准（必须逐项截图留证）

### 6.1 黑边（核心验收）

- [ ] 窗口化启动：窗口顶部 **0 像素黑边**，页面标题栏（自绘 NOVA + 三按钮）紧贴窗口上边缘。截图。
- [ ] 全屏启动：铺满工作区，顶部无黑边、底部不压任务栏、无白边。截图。
- [ ] 顶部自绘标题栏区域鼠标点击：**命中页面**（按钮可点、拖动可拖），不穿透到桌面。用 `WindowFromPoint` 或实测点击验证。
- [ ] 窗口垂直居中（窗口化 1180×780 相对工作区上下左右居中）。

### 6.2 窗口行为

- [ ] 最小化 → 任务栏可还原，还原后回到原形态、无黑边。
- [ ] 全屏 ⇄ 窗口化切换 100 次无异常、无黑边、无错位。
- [ ] 窗口化拖动标题栏，窗口跟手移动，无撕裂、无延迟、WebView2 内容不空白。
- [ ] 关闭按钮关闭窗口，宿主进程（powershell）与 WebView2 进程（msedgewebview2）全部退出，无残留（任务管理器核对）。
- [ ] 启动外部应用后，新窗口能被拉到前台（ForceForeground 逻辑保留验证）。

### 6.3 业务回归（现有功能不得丢）

- [ ] 应用网格显示真实图标（虚拟主机图标加载成功，无裂图）。
- [ ] 添加（单个/批量）、移除、重命名、拖拽排序落盘正常，重启后顺序保持。
- [ ] 启动 .lnk / shell: / exe 三类应用正常。
- [ ] 设置项：图标大小、每行个数、深/浅主题全部生效并持久化。
- [ ] 「打开文件位置」、已安装程序枚举、失效路径检测正常。

### 6.4 DPI

- [ ] 100% / 125% / 150% / 175% 四档缩放：页面铺满客户区、无缩放错位、图标清晰、窗口化尺寸正确（1180×780 逻辑像素）。
- [ ] 运行中切换 DPI / 拖动到不同缩放显示器：WM_DPICHANGED 触发，窗口尺寸与 controller.Bounds 自动跟随、不错位、无黑边。

### 6.5 毛玻璃主题

- [ ] Win11：窗口背景透出 Mica 系统毛玻璃，页面半透明区域可见桌面/底层窗口模糊效果。截图。
- [ ] Win10：DwmExtendFrameIntoClientArea 传统毛玻璃生效，或降级为半透明纯色，不出现纯色不透明的"死白/死黑"背景。
- [ ] 深浅主题切换时毛玻璃效果跟随（深色主题更通透，浅色主题适度不透明保证可读性）。
- [ ] 卡片/抽屉 backdrop-filter 模糊层次正常，不出现毛玻璃与 WebView2 透明背景冲突的黑块。

### 6.6 性能

- [ ] 双击 bat 到界面可交互 < 3 秒（异步初始化不阻塞 UI，首帧可见 < 1.5 秒）。
- [ ] 空闲 CPU < 1%，内存（powershell + webview2 合计）< 300MB。

### 6.7 演示模式

- [ ] 直接双击 nova-launcher.html（浏览器打开）：走 localStorage 演示兜底，不报错、不卡在等待宿主。

---

## 7. 风险与回退

| 风险 | 现象 | 应对 |
|------|------|------|
| WebView2 Runtime 缺失 | CreateAsync 失败 | Task 2.1 注册表检测 + 下载提示 |
| ~~Load 事件里 GetAwaiter().GetResult() 死锁~~ | ~~启动卡住~~ | **已修复：改用 Form.Shown + WinForms Timer 轮询 Task.IsCompleted，不阻塞 UI 线程**（见 Task 4） |
| 多显示器混合 DPI 下界面错位 | 窗口拖到第二块屏幕后只铺左上、右/底空白 | **已修复：GetDpiForWindow(hwnd) 替代 GetDpiForSystem；NovaForm.WndProc 拦截 WM_DPICHANGED 自动更新尺寸与 Bounds**（见 Task 1/3） |
| 毛玻璃在 Win10 不生效 | 背景纯色不透明 | DwmExtendFrameIntoClientArea 传统毛玻璃兜底；再不行则 WebView2 透明 + Form 半透明纯色兜底（见 Task 4.5） |
| PowerShell 5.1 事件脚本块作用域取不到 $form/$script 变量 | 回调里变量为空 | 事件内用 `$script:form` / `$this`；或用 `Get-Variable -Scope script`；必要时用 C# 编译一个控制器包装类 |
| Add_Type 加载 Core.dll 报依赖缺失 | FileNotFound | 确认只用 net462 目录 DLL；WebView2 原生组件由 Runtime 提供，不需额外 native dll |
| 虚拟主机映射后图标 404 | 图标未预热完成 | add 流程同步提图；state 下发 iconUrl；img.onerror 字形兜底 |
| 拖动高频 postMessage 卡顿 | 拖动掉帧 | 沿用现有 rAF 合帧 + in-flight 合并策略；postMessage 比 localhost HTTP 更快，应无问题 |
| 中文/空格路径 | 资源加载失败 | 虚拟主机映射用绝对路径，URL 中图标名是 MD5 无中文；HTML 引用固定文件名无空格 |

**回退方案**：M40 在独立分支/副本开发（先复制当前 data/NovaLauncher.ps1 为 `NovaLauncher.ps1.m39.bak`），验证不通过则用 .bak 恢复，V0.0.2 已在 GitHub 不受影响。

---

## 8. 执行顺序（严格按此推进，每步可独立验证）

```
Step 1  Task 2  获取 WebView2.Core.dll 放到 data/lib/，写最小加载测试（能 Add-Type 成功）
   ↓
Step 2  Task 1+3 建无边框 Form（先不接 WebView2），-STA + PMv2 + GetDpiForWindow，能弹出一个居中无边框窗口 → 截图
   ↓
Step 3  Task 4+4.5+5 接 WebView2Controller（Form.Shown + Timer 异步初始化）+ 毛玻璃 DWM，Navigate 最简 HTML，铺满客户区无黑边 → 截图（关键里程碑：证明无黑边 + 毛玻璃）
   ↓
Step 4  Task 7+9.1 打通 postMessage 双向通信（页面按钮 → 宿主处理 → 回传）→ 截图
   ↓
Step 5  Task 8 实现 win.move 拖动 + win.min/win.max/win.close + Resize 同步 Bounds → 截图/录屏
   ↓
Step 6  Task 5+6+10 虚拟主机映射真实 nova-launcher.html + 图标加载，替换通信层
   ↓
Step 7  Task 7/9  迁移全部业务 op（launch/add/remove/move/setting/installed...），业务回归
   ↓
Step 8  Task 11 删除全部旧代码（HttpListener/Chrome/CSD/Region/守门/心跳）
   ↓
Step 9  Task 12 窗口状态持久化 + WM_DPICHANGED 跨屏验证
   ↓
Step 10 §6 全量验收（黑边/窗口行为/业务/DPI/毛玻璃/性能/演示模式），逐项截图
   ↓
Step 11 更新 README、修改记录.md，版本号 V0.0.3，提交 GitHub 打 tag
```

**每个 Step 完成后必须：运行 → 截图验证 → 确认无回归，再进入下一步。**

---

## 9. 给执行者的最终指令

基于当前 Nova Launcher V0.0.2（M39，Chrome --app + HttpListener + SetWindowRgn 架构）代码，
按本文档执行 M40 无边框窗口重构。

技术栈锁定：
- PowerShell 5.1，-STA 启动
- 进程首行 SetProcessDpiAwarenessContext(PMv2)
- WinForms Form（FormBorderStyle=None）作为窗口容器，不用纯 Win32
- CoreWebView2Controller 绑定 Form.Handle，不用 WinForms WebView2 控件
- **WebView2 初始化用 Form.Shown + WinForms Timer 轮询，禁止 .GetAwaiter().GetResult() / .Result / .Wait() 阻塞 UI 线程**
- **DPI 用 GetDpiForWindow(hwnd)，禁止 GetDpiForSystem；必须处理 WM_DPICHANGED**
- **毛玻璃主题：DwmSetWindowAttribute(Mica/Acrylic) + WebView2 透明背景 + HTML 半透明**
- SetVirtualHostNameToFolderMapping 映射本地资源
- chrome.webview.postMessage / WebMessageReceived 统一通信，删除 HttpListener
- JS pointer 事件 + win.move 实现拖动，不用 WM_NCHITTEST / -webkit-app-region

硬性要求：
1. 保留现有应用扫描/启动/图标提取/增删改/排序/设置全部业务逻辑与 UI 设计
2. 窗口化 1180×780 垂直居中、全屏铺满工作区，两种形态顶部均 0 像素黑边
3. 顶部区域点击不穿透、可拖动、按钮可点
4. 彻底删除 CSD、SetWindowRgn、csd.cache、FrameW/H、窗口守门、心跳、Chrome --app、HttpListener
5. 不通过 CSS 修复黑边
6. 每完成一个 Step 运行并截图留证

完成后输出：
- 修改文件列表
- 删除代码列表（函数级）
- 新增代码说明
- 分步截图证据
- §6 验收清单逐项结果
