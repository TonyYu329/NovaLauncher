<#
=============================================================================
① 首次创建人      ：Tony
② 首次创建时间    ：2026-09-11 16:03:30
③ 代码功能简介    ：Nova Launcher 本地宿主（方案②）。以 127.0.0.1 随机端口启动
                    一个 HttpListener 作为本地服务：托管前端页面、读写 apps.json /
                    settings.json、通过 Windows Shell API 提取真实 EXE/LNK 图标、
                    接收前端指令并用 Start-Process 启动真实程序。仅监听回环地址，
                    所有 /api/* 接口需携带随机 token，防止任意网页调用。
④ 最后修改人      ：Tony
⑤ 最后修改时间    ：2026-09-13 13:55:22

【修改摘要】
- 2026-09-12 M21 新增 ^/api/rename：按 p（路径优先）/ i 定位应用改显示名，
  空名拒绝、长度截 60、缺 token 403；只改 apps.json，不动磁盘上的快捷方式文件。
- 2026-09-12 M22 /favicon.ico 与 /nova-logo.ico 改为托管 nova-logo.ico（免 token）：
  --app 模式的窗口/任务栏图标来自页面 favicon，此前 404 导致显示浏览器默认图标。
- 2026-09-12 M23 新增 ^/api/checkapps：逐项验证已添加应用有效性（文件存在性 +
  .lnk 经 Resolve-LinkTarget 深挖目标，目标被卸载/挪走也判失效）；shell: 协议跳过。
  供设置抽屉「一键检查」使用，失效项返回 i/name/path/reason 由前端集中展示。
- 2026-09-13 M38 修复窗口化顶部黑边：csd.cache 原按测量时单位（物理/逻辑 px）混存，
  DPI 感知状态变化后单位不匹配 → SetWindowRgn 过裁。现统一缓存逻辑 px，Get-NovaCsd
  读取时按当前 DpiAware 换算成与 GetClientRect 同单位；缓存闸门改为固定逻辑区间 [20,40]。

【编码要求】本文件必须保存为 UTF-8 **带 BOM**。
  Windows PowerShell 5.1 在读取无 BOM 的 .ps1 时会按系统 ANSI(GBK) 解码，
  中文注释与字符串会被打乱并直接导致语法错误。这是本项目对该文件
  「UTF-8 无 BOM」总规范的唯一例外（.bat 相反，必须无 BOM）。
=============================================================================
使用：由 NovaLauncher.bat 调用；也可手动执行
      powershell -ExecutionPolicy Bypass -STA -File NovaLauncher.ps1
=============================================================================
#>

[CmdletBinding()]
param(
    [int]$Port = 0,          # 0 = 自动挑选空闲端口
    [switch]$NoBrowser,      # 不自动打开窗口（调试用）
    [string]$ApiToken = ''   # 指定 API token（调试用），默认随机生成
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
# $PSScriptRoot 比 $MyInvocation.MyCommand.Definition 更可靠：
# 在 Start-Job / 点源调用等场景下后者可能为空。
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$HtmlPath  = Join-Path $ScriptDir 'nova-launcher.html'
$LogoIco   = Join-Path $ScriptDir 'nova-logo.ico'
$DataDir   = $ScriptDir   # 默认数据目录 = 程序执行目录（绿色版自包含：apps.json/settings.json/Icons/runtime.json 均落此）
$IconDir   = Join-Path $DataDir 'Icons'
$AppsFile  = Join-Path $DataDir 'apps.json'
$SetFile   = Join-Path $DataDir 'settings.json'
$RunFile   = Join-Path $DataDir 'runtime.json'
$LogFile   = Join-Path $DataDir 'host.log'

foreach ($d in @($DataDir, $IconDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# 追加一行带时间戳的日志到 host.log；写失败静默忽略——日志绝不能反过来拖垮主流程。
function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

# ---------------------------------------------------------------------------
# 真实图标提取：PrivateExtractIcons 可拿到 256px 大图标（比 ExtractAssociatedIcon 的 32px 清晰）
# ---------------------------------------------------------------------------
if (-not ('NovaIcon' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class NovaIcon
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint PrivateExtractIcons(string szFileName, int nIconIndex, int cxIcon, int cyIcon,
                                                   IntPtr[] phicon, uint[] piconid, uint nIcons, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public static byte[] Png(string path, int size)
    {
        int[] tries = new int[] { size, 256, 128, 96, 64, 48, 32 };
        foreach (int s in tries)
        {
            if (s <= 0) continue;
            IntPtr[] h = new IntPtr[1];
            uint[] id = new uint[1];
            uint n = 0;
            try { n = PrivateExtractIcons(path, 0, s, s, h, id, 1, 0); }
            catch { continue; }
            if (n == 0 || h[0] == IntPtr.Zero) continue;
            try
            {
                using (Icon ic = Icon.FromHandle(h[0]))
                using (Bitmap bm = ic.ToBitmap())
                using (MemoryStream ms = new MemoryStream())
                {
                    bm.Save(ms, ImageFormat.Png);
                    return ms.ToArray();
                }
            }
            catch { }
            finally { DestroyIcon(h[0]); }
        }
        return null;
    }
}
'@
}

# ---------------------------------------------------------------------------
# 窗口控制：把 Edge 的 --app 窗口做成「无边框最大化」，并支持最小化 / 最大化还原 / 关闭
#   页面右上角那三个按钮最终都落到这里。
#   为什么不用启动参数：Edge/Chromium 没有「无边框窗口」开关；--kiosk 太重（连 F11/右键
#   都禁掉、退出困难、且会盖住任务栏=全屏而非最大化）；--start-fullscreen 是浏览器自己的
#   全屏态（盖住任务栏、且我们拿不到它的状态）；--start-maximized 对 --app 窗口不生效。
#   所以用经典 Win32 手法：去掉 WS_CAPTION/WS_THICKFRAME，再把窗口摆到**主屏工作区**
#   （Screen.WorkingArea，已扣掉任务栏），得到「没有标题栏、但任务栏照常可见可用」的
#   最大化观感；状态也完全由我们掌握 —— 「最大化」按钮只要看窗口样式里还有没有
#   WS_CAPTION 就能判断当前是最大化还是窗口化。
#   ⚠ 关键：用 WorkingArea 而不是 Bounds。Bounds 会把任务栏一起盖住，那是「全屏」而不是「最大化」。
#
#   ── 第三层标题栏：浏览器自绘标题栏 ────────────────────────────────────────
#   去掉 WS_CAPTION 后，窗口**看起来**仍然有一条标题栏，内容是「Nova Launcher」+ 最小化/
#   最大化/关闭按钮。它不是 Windows 画的：`GetWindowLong` 里 WS_CAPTION 已经没了，
#   这条是 Chromium 自己在客户区顶部画出来的（Windows 10+ 的 custom titlebar）。
#   试过并否掉的方案：
#     · --disable-windows10-custom-titlebar —— 实测无效，那条栏照画（按钮换成 Chrome 风格而已）；
#     · --kiosk —— 能全无边框，但等于全屏（盖任务栏）、且 --kiosk="url" 这种写法加载不出页面；
#     · 找「去掉自绘标题栏」的开关 —— 不存在。
#   最终手法：**把窗口整体上移「自绘标题栏高度」个像素，高度同时加上同样多**。
#   这样那条栏被顶到屏幕上边缘之外，窗口底边仍贴住工作区底边 —— 屏幕最上方直接就是页面
#   自己的 NOVA 标题栏，任务栏不受影响。
#   高度不写死：由页面把 window.innerHeight 报回来，与客户区高度相减实时算出（差几倍取决于
#   进程是否 DPI 感知，见 Update-NovaCsdHeight），换 DPI / 换机器都不会错位。
#
#   ⚠ 这里面的 C# 由 PowerShell 5.1 的 Add-Type 编译，用的是**老编译器（C# 5）**：
#     不能用 C# 7 的语法 —— 内联 out 声明（`out uint _` / `out MSG m`）、
#     字符串插值 `$"..."`、元组、`?.`、模式匹配，统统会报「无效的表达式项」。
#     写之前先把变量声明出来，再往 out 里传。
# ---------------------------------------------------------------------------
if (-not ('NovaWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class NovaWindow
{
    public const int GWL_STYLE      = -16;
    public const int WS_CAPTION     = 0x00C00000;
    public const int WS_THICKFRAME  = 0x00040000;
    public const int WS_MINIMIZEBOX = 0x00020000;
    public const int WS_MAXIMIZEBOX = 0x00010000;
    public const int WS_SYSMENU     = 0x00080000;

    public const int SW_MINIMIZE = 6;
    public const int SW_RESTORE  = 9;

    public const uint SWP_NOSIZE       = 0x0001;
    public const uint SWP_NOMOVE       = 0x0002;
    public const uint SWP_NOZORDER     = 0x0004;
    public const uint SWP_NOACTIVATE   = 0x0010;
    public const uint SWP_SHOWWINDOW   = 0x0040;
    public const uint SWP_FRAMECHANGED = 0x0020;

    public const uint WM_CLOSE = 0x0010;

    // 把窗口强行置前时用到：前台锁超时（SPI_SET/GETFOREGROUNDLOCKTIMEOUT）
    public const uint SPI_GETFOREGROUNDLOCKTIMEOUT = 0x2000;
    public const uint SPI_SETFOREGROUNDLOCKTIMEOUT = 0x2001;
    public const uint SPIF_SENDCHANGE              = 0x0002;

    public static readonly IntPtr HWND_TOP       = IntPtr.Zero;
    public static readonly IntPtr HWND_TOPMOST    = new IntPtr(-1);
    public static readonly IntPtr HWND_NOTOPMOST  = new IntPtr(-2);

    public const byte  VK_MENU          = 0x12;
    public const uint  KEYEVENTF_KEYUP  = 0x0002;
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll", SetLastError = true)] public static extern int  GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll", SetLastError = true)] public static extern int  SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int  GetWindowTextW(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    public delegate bool EnumProc(IntPtr h, IntPtr p);

    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint p1, IntPtr p2, uint winIni);
    // 只为「强制创建本线程的消息队列」而调用：AttachThreadInput 对没有消息队列的
    // 线程会直接失败，而 HttpClient/线程池线程默认是没有队列的。
    [DllImport("user32.dll", EntryPoint = "PeekMessageW")]
    public static extern bool PeekMessage(out MSG m, IntPtr h, uint min, uint max, uint remove);
    [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    // 窗口区域裁剪：M31 用于裁掉 Chromium 画在窗口顶部的自绘标题条（CSD）
    [DllImport("user32.dll")] public static extern int  SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
    [DllImport("gdi32.dll")]  public static extern IntPtr CreateRectRgn(int x1, int y1, int x2, int y2);

    // -----------------------------------------------------------------------
    // 把窗口推到前台。
    //
    // 为什么不能直接 SetForegroundWindow：前台锁（foreground lock）规定，只有
    // 「当前前台进程」或「刚收到过用户输入」的进程才有资格设置前台窗口。
    // 我们是由**后台宿主进程**拉起应用的，这两条都不满足，所以系统会让新窗口
    // 冒出来却仍停在我们这个铺满工作区的 launcher 后面 —— 这正是「应用藏在软件后端」的根因。
    //
    // 分两件事做，别混为一谈：
    //   A. 「显示在最前面」（z 序）—— **不需要任何权限**，所以是可以保证的：
    //      SetWindowPos(HWND_TOPMOST) 再 SetWindowPos(HWND_NOTOPMOST)，
    //      窗口就落在所有非置顶窗口之上。用户要的「显示在前端」这条到这里就满足了。
    //      （只改 z 序：SWP_NOMOVE | SWP_NOSIZE，不会动我们给窗口设的上移偏移。）
    //   B. 「拿到键盘焦点」—— 需要前台资格，尽力而为：
    //      ① PeekMessage 先给本线程建出消息队列，否则 AttachThreadInput 必然失败；
    //      ② AttachThreadInput 把自己挂到当前前台线程上，借它的资格；
    //      ③ 临时把 SPI_SETFOREGROUNDLOCKTIMEOUT 置 0（随后还原），进一步放行；
    //      ④ 还不行就轻敲一下 ALT —— 前台锁把「本进程刚收到过用户输入」当硬条件，
    //         一次合成的 ALT 按下/抬起正好补上这条（AutoHotkey 的经典手法）。
    // A 必成、B 尽力，全程 try/finally，任何一步失败都不抛异常。
    // 返回值 = 是否拿到键盘焦点（z 序那步不做返回值判断，它总是尽量执行）。
    // -----------------------------------------------------------------------
    public static bool ForceForeground(IntPtr h)
    {
        if (h == IntPtr.Zero || !IsWindow(h)) return false;
        uint oldTimeout = 0;
        bool timeoutChanged = false;
        uint fgTid = 0, myTid = GetCurrentThreadId();
        bool attached = false;
        bool focused = false;
        try
        {
            MSG msg;
            PeekMessage(out msg, IntPtr.Zero, 0, 0, 0);      // ① 建消息队列

            if (IsIconic(h)) ShowWindow(h, SW_RESTORE);

            // A. 抬到 z 序最前 —— 无需权限，必然生效
            SetWindowPos(h, HWND_TOPMOST,   0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_NOACTIVATE);
            SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_NOACTIVATE);

            IntPtr fg = GetForegroundWindow();
            uint fgPid = 0;
            if (fg != IntPtr.Zero) fgTid = GetWindowThreadProcessId(fg, out fgPid);
            if (fgTid != 0 && fgTid != myTid) attached = AttachThreadInput(myTid, fgTid, true);   // ②

            IntPtr t = Marshal.AllocHGlobal(4);              // ③
            try
            {
                if (SystemParametersInfo(SPI_GETFOREGROUNDLOCKTIMEOUT, 0, t, 0))
                {
                    oldTimeout = (uint)Marshal.ReadInt32(t);
                    if (oldTimeout != 0 && SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, IntPtr.Zero, SPIF_SENDCHANGE))
                        timeoutChanged = true;
                }
            }
            finally { Marshal.FreeHGlobal(t); }

            focused = SetForegroundWindow(h);
            if (!focused)                                    // ④
            {
                keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
                keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
                focused = SetForegroundWindow(h);
            }
            BringWindowToTop(h);
            return focused;
        }
        catch { return false; }
        finally
        {
            if (timeoutChanged)
            {
                IntPtr t2 = Marshal.AllocHGlobal(4);
                try { Marshal.WriteInt32(t2, (int)oldTimeout); SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, t2, SPIF_SENDCHANGE); }
                finally { Marshal.FreeHGlobal(t2); }
            }
            if (attached) AttachThreadInput(myTid, fgTid, false);
        }
    }

    // 目标窗口在 z 序里的位置：0 = 最上层（EnumWindows 按 z 序自上而下枚举）。
    // 用来客观验证「应用确实在 launcher 前面」——比截图可靠，也不受桌面是否锁屏影响。
    public static int ZOrderIndexOf(IntPtr target)
    {
        int idx = -1, n = 0;
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr p)
        {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(8);
            GetWindowTextW(h, sb, sb.Capacity);
            if (sb.Length == 0) return true;
            if (h == target) { idx = n; found = h; return false; }
            n++;
            return true;
        }, IntPtr.Zero);
        return idx;
    }

    // 快照当前所有「可见 + 有标题 + 尺寸像正常窗口」的顶层窗口句柄。
    // 启动应用前后各拍一张，差集就是「这次新冒出来的窗口」——比按进程找窗口可靠得多：
    // .lnk / shell: 启动会经过 shell 中转，拿到的进程往往不是真正拥有窗口的那个。
    public static IntPtr[] SnapshotTopLevel(int minW, int minH)
    {
        System.Collections.Generic.List<IntPtr> list = new System.Collections.Generic.List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr p)
        {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(512);
            GetWindowTextW(h, sb, sb.Capacity);
            if (sb.Length == 0) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            if ((r.R - r.L) < minW || (r.B - r.T) < minH) return true;
            list.Add(h);
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }

    public static string TitleOf(IntPtr h)
    {
        StringBuilder sb = new StringBuilder(512);
        GetWindowTextW(h, sb, sb.Capacity);
        return sb.ToString();
    }

    public static uint PidOf(IntPtr h) { uint pid = 0; GetWindowThreadProcessId(h, out pid); return pid; }

    // 进程名，取不到就返回空串（进程可能已退出 / 无权限）
    public static string ProcNameOf(uint pid)
    {
        try { return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; }
        catch { return ""; }
    }

    // 客户端区尺寸：用来反推浏览器自绘标题栏的高度（见 Update-NovaCsdHeight）
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

    // M33 诊断：判定屏幕某点是否命中本窗口。SetWindowRgn 裁掉的区域**不会**命中本窗口
    // （会落到背后的窗口/桌面），所以这是验证「标题条是否真的被裁掉」的硬判据，
    // 不受 PrintWindow（无视 region）与屏幕抓屏（会被前台窗口污染）的干扰。
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    // WindowFromPoint 返回的是**最深的子窗口**（Chrome 渲染子窗口），不是顶层窗口；
    // 要与本窗口句柄比对必须先用 GetAncestor(GA_ROOT) 归到根窗口。
    public const uint GA_ROOT = 2;
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);

    // 只查询、无副作用：判断本进程是否 DPI 感知。Win32 坐标系与页面 CSS 像素差几倍，全看它。
    [DllImport("user32.dll")] public static extern bool IsProcessDPIAware();

    // M35 根因修复：主动把本进程设为 Per-Monitor V2 DPI 感知（不再「只查询不改」）。
    // 不感知时系统把 Win32 坐标虚拟化成逻辑像素，而 Chrome --app 是 PMv2 感知（物理像素）；
    // 宿主用逻辑坐标去摆一个物理窗口 → Chrome 光栅化表面按逻辑尺寸分配并 1:1 呈现
    // → 界面只铺屏幕左上角、右/底大片空白（用户实锤截图）。设感知后双方同处物理坐标系。
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    public static readonly IntPtr DPI_CTX_PMV2 = new IntPtr(-4);   // PROCESS_PER_MONITOR_DPI_AWARE_V2

    // -----------------------------------------------------------------------
    // 设置窗口图标（任务栏 / Alt-Tab / 标题栏图标都来自它）。
    // 背景：Edge/Chrome 的 --app 窗口，任务栏图标默认是浏览器 exe 自己的图标；
    // 页面 <link rel="icon"> 在 Edge 这条路径上覆盖不了任务栏（那是给标签页/标题栏用的）。
    // 唯一可靠的办法：宿主拿到窗口句柄后 SendMessage(WM_SETICON) 直接设。
    // 关键事实：
    //   · HICON 是**系统级**句柄 —— 本进程 LoadImage 出来的 HICON 发给别的进程的窗口同样有效；
    //   · WM_GETICON 读回来的就是当初设置的那个句柄值 —— 所以能用「读回值 == 我们设置的值」
    //     判断图标有没有被浏览器偷偷改回去（浏览器在 favicon 解析完时会自己再 SetIcon 一次）。
    // -----------------------------------------------------------------------
    public const uint  IMAGE_ICON      = 1;
    public const uint  LR_LOADFROMFILE = 0x00000010;
    public const int   SM_CXICON = 11, SM_CYICON = 12, SM_CXSMICON = 49, SM_CYSMICON = 50;
    public const uint  WM_SETICON = 0x0080;
    public const uint  WM_GETICON = 0x007F;
    public static readonly IntPtr ICON_SMALL = IntPtr.Zero;      // wParam: 小图标（标题栏 / Alt-Tab 小图）
    public static readonly IntPtr ICON_BIG   = new IntPtr(1);    // wParam: 大图标（任务栏）

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadImage(IntPtr hinst, string lpszName, uint uType, int cxDesired, int cyDesired, uint fuLoad);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    // -----------------------------------------------------------------------
    // 设置窗口的 AppUserModelID（任务栏图标的另一半根因）。
    //   Win10/11 的任务栏按 **AUMID** 分组取图标：Chromium 给 --app 窗口挂的是浏览器自己的
    //   AUMID（如 Chrome/Edge 的安装注册项），所以任务栏永远显示浏览器 exe 的图标，
    //   WM_SETICON 设的窗口图标它根本不看（那条只影响标题栏 / Alt-Tab）。
    //   解法 = 给窗口换一个自定义 AUMID（Nova.Launcher.<hwnd>）。这个 AUMID 没有对应的
    //   开始菜单快捷方式，任务栏就退回用窗口大图标（WM_SETICON 那个）—— 这正是
    //   Electron 应用「app.setAppUserModelId + 窗口图标」拿到自定义任务栏图标的同一套手法。
    //   SHGetPropertyStoreForWindow 支持跨进程调用（内部走窗口属性），宿主可以直接改浏览器的窗口。
    // -----------------------------------------------------------------------
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        void GetCount(out uint cProps);
        void GetAt(uint iProp, out PROPERTYKEY pkey);
        void GetValue(ref PROPERTYKEY pkey, out PROPVARIANT pv);
        void SetValue(ref PROPERTYKEY pkey, ref PROPVARIANT pv);
        void Commit();
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY { public Guid fmtid; public uint pid; }
    // 只用得到 VT_LPWSTR；其余字段是占位，保证内存布局正确
    [StructLayout(LayoutKind.Sequential)]
    public struct PROPVARIANT { public ushort vt; public ushort r1, r2, r3; public IntPtr p; }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore store);
    [DllImport("ole32.dll")] public static extern IntPtr CoTaskMemAlloc(uint cb);
    [DllImport("ole32.dll")] public static extern void CoTaskMemFree(IntPtr p);

    public static int SetWindowAppUserModelId(IntPtr hwnd, string aumid)
    {
        Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropertyStore store;
        int hr = SHGetPropertyStoreForWindow(hwnd, ref iid, out store);
        if (hr != 0) return hr;
        try
        {
            PROPERTYKEY pk;
            pk.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");   // PKEY_AppUserModel_ID
            pk.pid = 5;
            PROPVARIANT pv;
            pv.vt = 31;                                                    // VT_LPWSTR
            pv.r1 = 0; pv.r2 = 0; pv.r3 = 0;
            pv.p = Marshal.StringToCoTaskMemUni(aumid);
            try { store.SetValue(ref pk, ref pv); } finally { CoTaskMemFree(pv.p); }
            store.Commit();
            return 0;
        }
        finally { Marshal.ReleaseComObject(store); }
    }

    // 给 .lnk 快捷方式写 AppUserModelId 属性。任务栏规则：窗口 AUMID 与「开始菜单里的
    // 某条快捷方式的 AUMID」一致时，按钮的分组、图标、显示名全部取自该快捷方式 ——
    // 这是官方文档化的应用注册机制，也是绿色版拿到原生任务栏图标的唯一可靠途径。
    // ⚠ 必须走 IShellLink 对象自身的 IPropertyStore（属性会嵌入 .lnk 的扩展数据块）。
    //   走 SHGetPropertyStoreFromParsingName 拿到的 store 对 AUMID 是只读视图：
    //   SetValue 返回 S_FALSE 静默不落盘（实测踩过）。
    public static int SetLnkAppUserModelId(string path, string aumid)
    {
        object link = null;
        try
        {
            Type t = Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046"));   // CLSID_ShellLink
            link = Activator.CreateInstance(t);
            IPersistFile pf = (IPersistFile)link;          // QI: 加载 / 保存 .lnk
            try { pf.Load(path, 0x42); }   // STGM_READWRITE|STGM_SHARE_DENY_NONE —— 传 0 是只读打开，后面 SetValue 必被拒（实测踩过）
            catch (COMException) { return unchecked((int)0x00010001); }          // 分步码 1：Load 失败
            IPropertyStore ps;
            try { ps = (IPropertyStore)link; }             // QI: ShellLink 自带的属性存储
            catch (InvalidCastException) { return unchecked((int)0x00010002); }  // 分步码 2：QI 失败
            PROPERTYKEY pk;
            pk.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");   // PKEY_AppUserModel_ID
            pk.pid = 5;
            PROPVARIANT pv;
            pv.vt = 31;                                    // VT_LPWSTR
            pv.r1 = 0; pv.r2 = 0; pv.r3 = 0;
            pv.p = Marshal.StringToCoTaskMemUni(aumid);
            try { ps.SetValue(ref pk, ref pv); }
            catch (COMException) { return unchecked((int)0x00010003); }          // 分步码 3：SetValue 失败
            finally { CoTaskMemFree(pv.p); }
            try { ps.Commit(); }
            catch (COMException) { return unchecked((int)0x00010004); }          // 分步码 4：Commit 失败
            try { pf.Save(path, true); }
            catch (COMException ce) { return ce.ErrorCode; }                     // Save 原样返回（如 0x80030005）
            return 0;
        }
        catch (COMException ce) { return ce.ErrorCode; }
        catch (InvalidCastException) { return unchecked((int)0x80004002); }   // E_NOINTERFACE
        finally { if (link != null) Marshal.ReleaseComObject(link); }
    }

    // 找「可见 + 标题含关键词 + 进程名在白名单内」的顶层窗口。
    // 用标题匹配而不是 $proc.MainWindowHandle：Edge/Chrome 常把窗口交给已存在的浏览器进程，
    // 启动进程本身可能立刻退出（MainWindowHandle 恒为 0）。
    // 返回全部命中项：标题可能重名（例如同时开着一个调试用的同名窗口），
    // 交给调用方用「优先前台窗口」来消歧。
    public static IntPtr[] FindAll(string keyword, string[] procNames)
    {
        System.Collections.Generic.List<IntPtr> hits = new System.Collections.Generic.List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr p)
        {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(512);
            GetWindowTextW(h, sb, sb.Capacity);
            string t = sb.ToString();
            if (t.Length == 0) return true;
            if (t.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) < 0) return true;
            if (procNames != null && procNames.Length > 0)
            {
                uint pid = 0; GetWindowThreadProcessId(h, out pid);
                bool hit = false;
                try
                {
                    string pn = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName;
                    foreach (string n in procNames)
                        if (string.Equals(pn, n, StringComparison.OrdinalIgnoreCase)) { hit = true; break; }
                }
                catch { }
                if (!hit) return true;
            }
            hits.Add(h);
            return true;
        }, IntPtr.Zero);
        return hits.ToArray();
    }
}
'@
}

# 缓存窗口句柄；句柄可能因窗口关闭而失效，所以每次都用 IsWindow 复核一遍
$script:WinHandle = [IntPtr]::Zero
function Get-NovaWin {
    if ($script:WinHandle -ne [IntPtr]::Zero -and [NovaWindow]::IsWindow($script:WinHandle)) {
        return $script:WinHandle
    }
    # 标题取页面 <title>（Nova Launcher）；限定浏览器进程名，避免误伤同名窗口
    $hits = @([NovaWindow]::FindAll('Nova Launcher', @('msedge', 'chrome')))
    $h = [IntPtr]::Zero
    if ($hits.Count -eq 1) {
        $h = $hits[0]
    } elseif ($hits.Count -gt 1) {
        # 多个同名窗口：优先当前前台那个（用户刚点的就是它），否则取第一个
        $fg = [NovaWindow]::GetForegroundWindow()
        if ($hits -contains $fg) { $h = $fg } else { $h = $hits[0] }
    }
    $script:WinHandle = $h
    return $h
}

# maximized = 无边框铺满工作区（任务栏仍可见）；windowed = 无边框小窗（居中 1180×780）。
# M30 前用「有没有 WS_CAPTION」判断；窗口化也改无边框后此法失效 —— 改比窗口矩形与
# 工作区矩形（含 csd 上移偏移）。M33：几何里多了「不可见缩放边框 fw/fh」补偿项，
# 判定同步带上；容差由 2px 放宽到 8px，吸收 DPI 取整与守门重摆的微小抖动。
function Get-NovaWinState([IntPtr]$h) {
    if ([NovaWindow]::IsIconic($h)) { return 'minimized' }
    $r = New-Object 'NovaWindow+RECT'
    if (-not [NovaWindow]::GetWindowRect($h, [ref]$r)) { return 'windowed' }
    $scr = [System.Windows.Forms.Screen]::FromHandle($h)
    if (-not $scr) { $scr = [System.Windows.Forms.Screen]::PrimaryScreen }
    $wa = $scr.WorkingArea
    $csd = Get-NovaCsd
    $fw  = $script:FrameW;    if ($fw  -lt 0) { $fw  = 0 }
    $fh  = $script:FrameH;    if ($fh  -lt 0) { $fh  = 0 }
    if ([Math]::Abs($r.L - ($wa.X - [int]($fw / 2))) -le 8 -and
        [Math]::Abs($r.T - ($wa.Y - $csd)) -le 8 -and
        [Math]::Abs(($r.R - $r.L) - ($wa.Width + $fw)) -le 8 -and
        [Math]::Abs(($r.B - $r.T) - ($wa.Height + $csd + $fh)) -le 8) { return 'maximized' }
    return 'windowed'
}

# 浏览器自绘标题栏（CSD）的高度。0 = 还不知道 / 没有 → 不做偏移，至少不会画错。
# 由页面回报的 innerHeight 反推（见 Update-NovaCsdHeight）。
$script:CsdHeight = 0
$script:CsdKnown  = $false
$script:CsdTries  = 0        # 连续推算失败次数：到上限才放弃，避免一次竞态就永久锁死
$script:CsdLastKey = ''      # 上一次采样的「innerHeight|外框高」指纹，用来识别「页面+窗口都已稳定」

# 启动瞬间 csd 还没实测出来（要等页面心跳上报 innerHeight，约 6-7s）。若此时按 0 摆窗，
# 浏览器自绘标题条会整条暴露在屏幕顶部好几秒 —— 用户实测到的「打开后界面显示异常」。
# 所以「未实测时的生效值」优先用上次运行实测并持久化的值（同机器/DPI/浏览器下 csd 很稳定，
# 启动瞬间即精确、零暂态）；没有缓存再用保守值 34（≥ 实测见过的最大 32，确保标题条一定被
# 顶出屏幕+裁掉；代价是顶部暂态多削几 px，远轻于露标题条）。实测成功后立即精确重摆并回写。
$script:CsdCacheFile = Join-Path $DataDir 'csd.cache'
$script:CsdFallback  = 34
$script:CsdCache     = -1
try {
    if (Test-Path $script:CsdCacheFile) {
        $cv = 0
        if ([int]::TryParse((Get-Content $script:CsdCacheFile -Raw).Trim(), [ref]$cv)) { $script:CsdCache = $cv }
    }
} catch { }
# 当前生效的 CSD 偏移：实测值 > 上次缓存 > 保守兜底。摆窗/判定/命中测试统一走它，
# 保证「摆窗用的 csd」与「判定期望的 csd」始终一致（否则守门会误判反复重摆）。
# M38：缓存统一存逻辑 px（与 DPI 感知状态无关）。读取时按当前 DpiAware 换算成与
# GetClientRect 同单位：感知=True(物理 px)→乘 DpiScale；感知=False(逻辑 px)→直接用。
function Get-NovaCsd {
    if ($script:CsdKnown) { $c = $script:CsdHeight }
    elseif ($script:CsdCache -ge 0) {
        if ($script:DpiAware) { $c = [int]([Math]::Round($script:CsdCache * $script:DpiScale)) }
        else { $c = $script:CsdCache }
    }
    else {
        if ($script:DpiAware) { $c = [int]([Math]::Round($script:CsdFallback * $script:DpiScale)) }
        else { $c = $script:CsdFallback }
    }
    if ($c -lt 0) { $c = 0 }
    return $c
}

# 窗口外框与客户区的差 = Chrome --app 窗口即使被剥掉 WS_CAPTION/WS_THICKFRAME 后仍保留的
# 一圈**不可见缩放边框**（实测外框 1707×941 → 客户区 1694×934：左右各 7、底部 7）。
# 摆窗口时必须把它补回来，否则「页面实际可见区」比设计值小一圈 —— 这正是窗口化后
# 界面显示异常的成因之一（外框 1180×780 时客户区只有 1166×773，再裁掉顶部就更小）。
$script:FrameW = 0
$script:FrameH = 0
$script:FrameKnown = $false

# 用户当前想要的形态（$true = 窗口化）。**最小化不是一种形态**：还原时必须回到这里
# 记着的形态，否则会出现「最小化前是全屏、还原后变小窗且露出自绘标题条」。
$script:WantWindowed = $false

# 本进程 DPI 感知（M35：主动开启 Per-Monitor V2，不再「只查询不改」）。
# 原因：PowerShell 5.1 默认不感知 → Win32 坐标被系统虚拟化成逻辑像素；而 Chrome --app 是
# PMv2 感知（物理像素）。宿主用逻辑坐标摆物理窗口 → Chrome 光栅化表面按逻辑尺寸分配、
# 1:1 呈现 → 界面只铺左上、右/底空白（用户截图实锤）。开启感知后双方同处物理坐标系。
# 坐标系与页面 CSS 像素的换算系数：感知 → dpr；不感知（开启失败的兜底）→ 1。
$script:DpiAware = $false
try {
    if ([NovaWindow]::SetProcessDpiAwarenessContext([NovaWindow]::DPI_CTX_PMV2)) { $script:DpiAware = $true }
    elseif ([NovaWindow]::SetProcessDPIAware()) { $script:DpiAware = $true }
} catch { }
if (-not $script:DpiAware) { try { $script:DpiAware = [NovaWindow]::IsProcessDPIAware() } catch { } }
# 逻辑→物理换算系数：启动瞬间页面还没报 dpr 时也要能摆窗，先用系统 DPI；
# 页面心跳报回 dpr 后再校准（Update-NovaCsdHeight）。
$script:DpiScale = 1.0
try { $sd = [NovaWindow]::GetDpiForSystem(); if ($sd -gt 0) { $script:DpiScale = $sd / 96.0 } } catch { }

# M38：缓存统一存逻辑 px，与 DPI 感知状态无关。旧缓存（混合单位）一律清除重测。
# 启动时检测：若缓存值超出逻辑区间 [20,40]，自动清缓存强制重新实测，避免错误值持久化。
try {
    if (Test-Path $script:CsdCacheFile) {
        $cv = 0
        if ([int]::TryParse((Get-Content $script:CsdCacheFile -Raw).Trim(), [ref]$cv)) {
            if ($cv -lt 20 -or $cv -gt 40) {
                Remove-Item -Path $script:CsdCacheFile -Force -ErrorAction SilentlyContinue
                Write-Log "CSD 缓存值 $cv 超出逻辑安全区间 [20,40]（DpiScale=$($script:DpiScale)），已自动清除，启动后将重新实测"
                $script:CsdCache = -1
            }
        }
    }
} catch { }

# 让页面在 /api/state、/api/ping 里带上 window.innerHeight 与 devicePixelRatio，这里反推：
#   自绘标题栏高度 = 客户区高度 − innerHeight × 尺度系数
# 换 DPI、换显示器、换浏览器版本都自动跟上，不必写死 29/43/47 这类魔数。
function Update-NovaCsdHeight([string]$ihRaw, [string]$dprRaw) {
    # M31.2 诊断：页面每次上报都刷新最近值（op=rect 可查 Chrome 是否感知到新尺寸）
    $script:LastPageIh = $ihRaw
    $script:LastPageDpr = $dprRaw

    $h = Get-NovaWin
    if ($h -eq [IntPtr]::Zero) { return }
    # 最小化时客户区是 144×19 这种残值，量了必定算错 → 直接跳过，等还原后再量
    if ([NovaWindow]::IsIconic($h)) { return }

    $rc = New-Object 'NovaWindow+RECT'
    if (-not [NovaWindow]::GetClientRect($h, [ref]$rc)) { return }
    $client = $rc.B - $rc.T
    if ($client -le 0) { return }
    
    # 顺手量「外框 − 客户区」= 不可见缩放边框，摆窗时按它补偿（见变量注释）
    $rw = New-Object 'NovaWindow+RECT'
    $ow = 0; $oh = 0
    if ([NovaWindow]::GetWindowRect($h, [ref]$rw)) { $ow = $rw.R - $rw.L; $oh = $rw.B - $rw.T }
    if ($ow -le 200 -or $oh -le 200) { return }     # 最小化 / 尚未成形的残值，量了必错
    $fw = $ow - ($rc.R - $rc.L)
    $fh = $oh - $client
    if ($fw -ge 0 -and $fw -le 40 -and $fh -ge 0 -and $fh -le 40) {
        if (-not $script:FrameKnown -or $fw -ne $script:FrameW -or $fh -ne $script:FrameH) {
            $script:FrameW = $fw; $script:FrameH = $fh; $script:FrameKnown = $true
            Write-Log "窗口不可见缩放边框 = 宽 ${fw}px / 高 ${fh}px（外框 ${ow}x${oh} − 客户区 $($rc.R - $rc.L)x$client）"
        }
    }
    
    if ($script:CsdKnown) { return }
    $ih = 0.0
    if (-not [double]::TryParse($ihRaw, [ref]$ih)) { return }
    if ($ih -le 0) { return }
    $dpr = 1.0
    if ($dprRaw) { [double]::TryParse($dprRaw, [ref]$dpr) | Out-Null }
    if ($dpr -le 0) { $dpr = 1.0 }
    $scale = if ($script:DpiAware) { $dpr } else { 1.0 }
    if ($script:DpiAware -and $dpr -gt 0) { $script:DpiScale = $dpr }   # 用页面实测 dpr 校准逻辑→物理系数
    $inner = [int][Math]::Round($ih * $scale)
    
    # ── 防竞态（M33）──────────────────────────────────────────────────────
    # 页面的 fetch 是异步的、Chrome 重排也有滞后：请求发出时窗口还是旧尺寸，宿主处理
    # 请求时窗口可能刚被 SetWindowPos 改过 —— 于是「新客户区 − 旧 innerHeight」算出负数
    # （host.log 实锤两种：客户区=773 innerHeight=875 → -102；客户区=780 innerHeight=875 → -95）。
    # 旧实现在这里直接把 CsdKnown 置真并把 CsdHeight 锁死成 0，后果是全屏上移 0px →
    # 浏览器自绘标题栏整条暴露在屏幕里（Bug 1 的偶发根因）。
    # 现在用「innerHeight + 窗口外框高度」两个量做指纹：只有连续两次**都**相同才认为
    # 页面重排完成且窗口已落定，才接受这个样本；否则静默等下一次心跳（3s 一次）。
    # 不写死任何高度值、也不因单次异常就锁死判定。
    $key = "$ihRaw|$oh"
    if ($key -ne $script:CsdLastKey) {
        $script:CsdLastKey = $key
        return
    }

    $bar = $client - $inner

    # 合理性闸门（M34 收紧 → M37 再收紧）：CSD 是 Chromium 画在客户区顶部的固定高条，
    # 历次实测（不同 DPI/浏览器版本）都在 28-32 逻辑 px。旧闸门 [16,48] 太松，曾错误接受
    # 42（DPI 切换 artifacts）→ 窗口化顶部被多裁出黑边（用户截图实锤）。
    # 收紧为 [20,40]：仍覆盖正常波动，但拒绝 42 这类异常值。区间外是布局卡死 artifacts。
    # 拒绝后静默等下一次心跳；**不锁 0**——缓存+保守初值兜底，锁 0 反而露标题栏。
    # 闸门区间是**逻辑**px；感知时 bar 为物理 px，按 scale 放大比较。
    $gLo = 20 * $scale; $gHi = 40 * $scale
    if ($bar -lt $gLo -or $bar -gt $gHi) {
        $script:CsdTries++
        if ($script:CsdTries -eq 1 -or $script:CsdTries % 8 -eq 0) {
            Write-Log "CSD 推算被拒（客户区=$client innerHeight=$ih → $bar 超出 [$([int]$gLo),$([int]$gHi)]，疑 Chromium 布局卡死），等下一次心跳（累计拒绝 $($script:CsdTries)）"
        }
        return
    }
    $script:CsdTries = 0

    $script:CsdHeight = $bar
    $script:CsdKnown  = $true
    # M38：缓存统一存逻辑 px（除以测量时的 scale，消除 DPI 感知状态差异），
    # 下次启动无论感知与否都能正确换算使用。
    $logicalBar = [int]([Math]::Round($bar / $scale))
    try { Set-Content -Path $script:CsdCacheFile -Value "$logicalBar" -Encoding ASCII } catch { }
    Write-Log "浏览器自绘标题栏高度 = $bar px（客户区=$client innerHeight=$ih dpr=$dpr 感知=$($script:DpiAware)）→ 缓存逻辑值 $logicalBar"

    # 已经摆过窗口（那时偏移量还是 0）→ 用刚算出的偏移按当前形态重摆一次
    if ($script:MaxApplied) {
        if ($script:WantWindowed) { Set-NovaWinMaximized $h -Windowed } else { Set-NovaWinMaximized $h }
        Write-Log "已按新偏移重新定位窗口（形态=$(if ($script:WantWindowed) { '窗口化' } else { '全屏' })，上移 $bar px）"
    }
}

# 切到无边框全屏（-Windowed 则切到无边框窗口化）—— 任何状态都不出现系统标题栏，
# 也不出现浏览器自绘的 CSD 标题条。
function Set-NovaWinMaximized([IntPtr]$h, [switch]$Windowed) {
    # ── 先脱离最小化态（Bug 1 根因修复）────────────────────────
    # 窗口处于最小化时直接 SetWindowPos **不生效**：Windows 会先把窗口还原到它自己
    # 记着的 rcNormalPosition，把我们请求的几何覆盖掉。实测路径：全屏 → 点最小化 →
    # 再切最大化，窗口落到 1180×780 居中的旧「窗口化」位置，而代码走的是全屏分支
    # 并清除了 region → 浏览器自绘标题条整条暴露在屏幕里（用户看到的「系统标题栏」）。
    if ([NovaWindow]::IsIconic($h)) {
        [NovaWindow]::ShowWindow($h, [NovaWindow]::SW_RESTORE) | Out-Null
        Start-Sleep -Milliseconds 150     # 等还原落定，否则后面的 SetWindowPos 仍会被吃掉
    }

    $style = [NovaWindow]::GetWindowLong($h, [NovaWindow]::GWL_STYLE)
    $flags = [uint32]([NovaWindow]::SWP_FRAMECHANGED -bor [NovaWindow]::SWP_NOZORDER -bor [NovaWindow]::SWP_NOACTIVATE -bor 0x0100) # 0x0100 = SWP_NOCOPYBITS：丢弃旧位图，强制浏览器按新尺寸整帧重绘（M31.2：不加会出现旧帧错位/整体缩小的残影）

    $scr = [System.Windows.Forms.Screen]::FromHandle($h)
    if (-not $scr) { $scr = [System.Windows.Forms.Screen]::PrimaryScreen }
    $wa = $scr.WorkingArea

    $csd = Get-NovaCsd
    $fw  = $script:FrameW;    if ($fw  -lt 0) { $fw  = 0 }
    $fh  = $script:FrameH;    if ($fh  -lt 0) { $fh  = 0 }

    # 两种形态都保持无边框：WS_CAPTION / WS_THICKFRAME 一律去掉。
    # （M30 前窗口化会把标题栏加回来，主人要求全屏点最大化后也不能出现系统标题栏。）
    $style = $style -band (-bnot ([NovaWindow]::WS_CAPTION -bor [NovaWindow]::WS_THICKFRAME))
    [NovaWindow]::SetWindowLong($h, [NovaWindow]::GWL_STYLE, $style) | Out-Null

    if ($Windowed) {
        # 无边框窗口化：目标是页面**可见区** 1180×780（逻辑/CSS px，感知时先×DpiScale 换物理）。
        # 外框必须把「不可见缩放边框 fw/fh」与「被 region 裁掉的 CSD」补回来，否则可见区会被
        # 这两块吃掉（历史 bug：直接拿 1180×780 当外框 → 可见区只剩 ~741px 且顶部被削一条）。
        $tw = [int](1180 * $script:DpiScale)
        $th = [int](780  * $script:DpiScale)
        $pw = [Math]::Min($tw, $wa.Width  - $fw)
        $ph = [Math]::Min($th, $wa.Height - $csd - $fh)
        if ($pw -lt [int](320 * $script:DpiScale)) { $pw = [int](320 * $script:DpiScale) }
        if ($ph -lt [int](240 * $script:DpiScale)) { $ph = [int](240 * $script:DpiScale) }
        $w  = $pw + $fw
        $ht = $ph + $csd + $fh
        $x  = $wa.X + [int](($wa.Width  - $w) / 2)
        $y  = $wa.Y + [int](($wa.Height - $ht) / 2)
    } else {
        # 铺满**工作区**（WorkingArea 已扣任务栏）→ 观感「最大化」且任务栏可用；用 Bounds 会盖住任务栏=全屏。
        # 上移 csd 把自绘标题栏顶出屏幕上边缘；左右各补一半 fw、底部补 fh，使「客户区−csd」
        # 恰好等于工作区（不补则底边会露一条桌面缝）。
        $w  = $wa.Width + $fw
        $ht = $wa.Height + $csd + $fh
        $x  = $wa.X - [int]($fw / 2)
        $y  = $wa.Y - $csd
    }
    # SetWindowPos 前必须带 SWP_FRAMECHANGED，否则改了样式不生效（要等下一次真实改尺寸）
    [NovaWindow]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, $w, $ht, $flags) | Out-Null

    # -----------------------------------------------------------------------
    # 裁掉 Chromium 自绘标题条（CSD，客户区顶部那条「Nova Launcher ─ □ ✕」，非 Win32 标题栏）。
    # 两条防线并用、两种形态一致，任何一条失效都不露标题栏：
    #   · 上移 csd → CSD 落到屏幕外（主防线，仅全屏生效）；
    #   · SetWindowRgn 再裁顶部 csd → 上移失效时 CSD 仍被裁掉（兜底）。
    # region 绑定窗口坐标，每次摆窗按新尺寸重设；最小化/还原不丢 region。
    # -----------------------------------------------------------------------
    if ($csd -gt 0) {
        $rgn = [NovaWindow]::CreateRectRgn(0, $csd, $w, $ht)
        [void][NovaWindow]::SetWindowRgn($h, $rgn, $true)
    } else {
        [void][NovaWindow]::SetWindowRgn($h, [IntPtr]::Zero, $true)
    }

    # 摆窗读回诊断（M34）：SetWindowPos 的目标值不等于实际值 —— Chrome 会在
    # WM_WINDOWPOSCHANGING 里按自己的约束覆盖请求几何（用户那次启动守门反复重摆的根因）。
    # 旧日志只打目标值，排查时完全是盲区；现在偏差 >2px 就把实际值记下来。
    $rb = New-Object 'NovaWindow+RECT'
    if ([NovaWindow]::GetWindowRect($h, [ref]$rb)) {
        if ([Math]::Abs($rb.L - $x) -gt 2 -or [Math]::Abs($rb.T - $y) -gt 2 -or
            [Math]::Abs(($rb.R - $rb.L) - $w) -gt 2 -or [Math]::Abs(($rb.B - $rb.T) - $ht) -gt 2) {
            Write-Log "摆窗读回偏差：目标 ${w}x${ht} @(${x},${y}) 实际 $($rb.R - $rb.L)x$($rb.B - $rb.T) @($($rb.L),$($rb.T))（浏览器/系统覆盖了请求几何）"
        }
    }

    $script:WantWindowed = [bool]$Windowed
    $shape = if ($Windowed) { '窗口化' } else { '全屏' }
    $rgnTxt = if ($csd -gt 0) { "裁顶部 $csd" } else { '无' }
    Write-Log "摆窗：形态=$shape 外框=${w}x${ht} @(${x},${y}) csd=$csd 边框=${fw}/${fh} region=$rgnTxt"
}

# ---------------------------------------------------------------------------
# 窗口守门：浏览器和 Windows 会在我们背后改窗口，实测两条：
#   ① 最小化后还原，Windows 按 rcNormalPosition 复位，我们上移的 csd 偏移可能丢失；
#   ② 窗口状态变化后浏览器可能把 WS_CAPTION / WS_THICKFRAME 加回来 → 系统标题栏冒出来。
# 空闲节拍（1.5s）里复核「样式位 + 几何 vs 用户意图」，不符就重摆一次（幂等：
# 符合预期时只读两个 Win32 值，零副作用）。这与 Set-NovaWindowIcon 的「每拍读回比对」
# 是同一手法：不信任外部会保持我们的设置，自己盯。
# ---------------------------------------------------------------------------
$script:GuardFixes = 0
$script:GuardStreak = 0   # 连续「纠正后仍不符」的拍数：到上限暂停自动重摆，避免窗口无限抖动
function Invoke-NovaWindowGuard {
    if (-not $script:MaxApplied) { return }
    $h = Get-NovaWin
    if ($h -eq [IntPtr]::Zero -or -not [NovaWindow]::IsWindow($h)) { return }
    if ([NovaWindow]::IsIconic($h)) { return }     # 最小化中不干预，还原后下一拍自然纠

    # 勿用 location.reload 修「视口不跟随」：reload 复用同一渲染视图、重建不了 --app 视口，
    # 还会造成重载风暴打断心跳（M34 已回滚）。innerHeight 与客户区之差是 DPI 测量差，非缺陷。

    if (-not $script:CsdKnown) { return }          # 偏移量还没量准前不反复摆窗

    $style = [NovaWindow]::GetWindowLong($h, [NovaWindow]::GWL_STYLE)
    $styleBad = ($style -band ([NovaWindow]::WS_CAPTION -bor [NovaWindow]::WS_THICKFRAME)) -ne 0

    $state = Get-NovaWinState $h
    $want  = if ($script:WantWindowed) { 'windowed' } else { 'maximized' }

    if (-not $styleBad -and $state -eq $want) { $script:GuardStreak = 0; return }

    $script:GuardStreak++
    if ($script:GuardStreak -ge 4) {
        if ($script:GuardStreak -eq 4) {
            Write-Log "窗口守门连续 $($script:GuardStreak) 拍纠正仍不符（实测=$state 期望=$want），暂停自动重摆以免窗口无限抖动；请查「摆窗读回偏差」日志定位覆盖源"
        }
        return
    }
    $script:GuardFixes++
    Write-Log "窗口守门纠正 #$($script:GuardFixes)：样式异常=$styleBad 实测形态=$state 期望=$want → 重新摆窗"
    if ($script:WantWindowed) { Set-NovaWinMaximized $h -Windowed } else { Set-NovaWinMaximized $h }
}

# 启动时把窗口切成无边框最大化。
# 不在启动阶段死等窗口：首开浏览器要新建 user-data-dir，可能比 6 秒还久，
# 死等会把 HTTP 服务一起卡住（页面一直「连接中…」）。改成惰性触发 —— 主循环每 1.5 秒、
# 以及页面每次来请求时各试一次，拿到句柄就切；$script:MaxApplied 保证只切一次，
# 之后用户手动点「还原为窗口」不会被抢回最大化。
$script:MaxApplied = $false
function Invoke-StartupMaximize {
    if ($script:MaxApplied) { return }
    $h = Get-NovaWin
    if ($h -eq [IntPtr]::Zero) { return }
    Set-NovaWinMaximized $h          # 内部会置 $script:WantWindowed = $false
    $script:MaxApplied = $true
    Write-Log "已切换为无边框全屏（铺满工作区，任务栏可见；上移 $($script:CsdHeight)px 隐藏浏览器自绘标题栏）：hwnd=$h —— 窗口化同样无边框，任何状态无系统标题栏"
}

# ---------------------------------------------------------------------------
# 把任务栏 / Alt-Tab / 标题栏图标设成 nova-logo.ico（任务栏图标的根因修复）。
#   三件套缺一不可（每件都实测过「只做它没用」）：
#   ① WM_SETICON —— 管标题栏 / Alt-Tab 图标；Win10/11 任务栏**不看**窗口图标。
#   ② 窗口 AUMID —— 声明「我不是浏览器」。但 Win11 任务栏按钮在窗口显示那一刻就定型，
#      事后改属性不会重新分组；且光有自定义 AUMID 没有对应快捷方式时，图标仍回退到浏览器 exe。
#   ③ AUMID 快捷方式（%APPDATA%\...\Start Menu\Programs\Nova Launcher.lnk，内含同名
#      AUMID 属性、图标指向 nova-logo.ico）—— 官方文档化的「应用注册」：任务栏按
#      「窗口 AUMID ↔ 快捷方式 AUMID」匹配后，按钮的图标和显示名全部取自快捷方式。
#   时序坑：
#   · 按钮不会自己重新分组 → 用 WS_EX_TOOLWINDOW 短暂切换强制任务栏重建按钮（第 ④ 步）。
#   · 浏览器 favicon 解析完会自己再 SetIcon 覆盖 → 每拍用 WM_GETICON 读回比对，不一致
#     就重设；连续 8 拍（约 12 秒）确认稳定才收工。上限 40 次兜底防空转。
# ---------------------------------------------------------------------------
$script:IconBig     = [IntPtr]::Zero   # LoadImage 出来的大图标句柄（任务栏用）
$script:IconSmall   = [IntPtr]::Zero   # 小图标句柄（标题栏 / Alt-Tab 小图用）
$script:IconConfirm = 0                # 连续确认「图标还是我们的」的次数
$script:IconTries   = 0                # 总尝试次数（兜底上限用）
$script:AumidSet    = $false           # AUMID / 快捷方式 / 重新分组只需一次
$script:NovaAumid   = 'Nova.Launcher'  # 窗口与快捷方式必须用同一个稳定字符串

# ①③ 的前置：确保「Nova Launcher.lnk」存在且图标 / 目标 / AUMID 都指向当前位置。
#   每次启动都重建（幂等、开销毫秒级）：绿色版整个文件夹被挪走后图标路径照样是对的。
function New-NovaTaskbarShortcut {
    $startMenu = [System.Environment]::GetFolderPath('ApplicationData')
    if (-not $startMenu) { Write-Log '取不到 ApplicationData，跳过任务栏快捷方式'; return $false }
    $lnkPath = Join-Path $startMenu 'Microsoft\Windows\Start Menu\Programs\Nova Launcher.lnk'
    try {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($lnkPath)
        # ps1 本体在 data\ 子目录里，bat 入口在其上一级（目录根）——指向根上的 NovaLauncher.bat
        $lnk.TargetPath       = Join-Path (Split-Path $ScriptDir -Parent) 'NovaLauncher.bat'
        $lnk.WorkingDirectory = Split-Path $ScriptDir -Parent
        $lnk.IconLocation     = "$LogoIco,0"
        $lnk.Description       = 'Nova Launcher'
        $lnk.Save()
        # ⚠ 必须先把 WScript.Shell 的 COM 引用显式释放，否则文件仍被它持有，
        #   下一句 ShellLink 写属性会 STG_E_ACCESSDENIED（0x80030005，实测踩过）。
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($lnk)
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws)
        $lnk = $null; $ws = $null
        $hr = [NovaWindow]::SetLnkAppUserModelId($lnkPath, $script:NovaAumid)
        if ($hr -ne 0) { Write-Log "写快捷方式 AUMID 失败：hr=0x$('{0:X}' -f $hr)"; return $false }
        Write-Log "已就位任务栏快捷方式：$lnkPath（AUMID=$($script:NovaAumid)，图标=nova-logo.ico）"
        return $true
    } catch {
        Write-Log "创建任务栏快捷方式失败：$($_.Exception.Message)"
        return $false
    }
}

# 每拍执行的图标 worker：设大/小图标并用 WM_GETICON 读回比对，被浏览器 favicon 覆盖就重设，
# 连续 8 拍稳定即收工（上限 40 次防空转）；AUMID/快捷方式/重新分组只置一次。策略详见上方三件套说明。
function Set-NovaWindowIcon {
    if ($script:IconConfirm -ge 8) { return }   # 已稳定，收工
    if ($script:IconTries -ge 40)  { return }   # 兜底上限
    $h = Get-NovaWin
    if ($h -eq [IntPtr]::Zero) { return }

    if (-not $script:AumidSet) {
        # ③ 快捷方式（要先于「重建按钮」那步存在，任务栏重建时才解析得到）
        $lnkOk = New-NovaTaskbarShortcut
        # ② 窗口 AUMID：与快捷方式同名，任务栏才会按「独立应用」对待并取快捷方式的图标
        $hr = [NovaWindow]::SetWindowAppUserModelId($h, $script:NovaAumid)
        if ($hr -eq 0) { Write-Log "已设置窗口 AUMID=$($script:NovaAumid)" }
        else { Write-Log "设置窗口 AUMID 失败：hr=0x$('{0:X}' -f $hr)" }
        # ④ 强制任务栏重建按钮（按钮在窗口显示时就定型，事后必须踢一脚）：
        #    短暂加 WS_EX_TOOLWINDOW（不显示在任务栏）再移除，任务栏重新登记时读到新 AUMID。
        if ($lnkOk -and $hr -eq 0) {
            try {
                $ex = [NovaWindow]::GetWindowLong($h, -20)   # GWL_EXSTYLE
                [NovaWindow]::SetWindowLong($h, -20, ($ex -bor 0x80)) | Out-Null   # WS_EX_TOOLWINDOW
                Start-Sleep -Milliseconds 700                # 给任务栏留出撤按钮的时间（仅此一次，不卡请求）
                [NovaWindow]::SetWindowLong($h, -20, $ex) | Out-Null
                Write-Log '已触发任务栏按钮重建（WS_EX_TOOLWINDOW 切换）'
            } catch { Write-Log "重建任务栏按钮失败：$($_.Exception.Message)" }
        }
        $script:AumidSet = $true
    }

    # 图标句柄只加载一次（HICON 是系统级句柄，进程存活期间一直有效）
    if ($script:IconBig -eq [IntPtr]::Zero) {
        if (-not (Test-Path $LogoIco)) {
            Write-Log "未找到 $LogoIco，跳过任务栏图标设置"
            $script:IconTries = 40
            return
        }
        $cx  = [NovaWindow]::GetSystemMetrics([NovaWindow]::SM_CXICON)
        $cy  = [NovaWindow]::GetSystemMetrics([NovaWindow]::SM_CYICON)
        $scx = [NovaWindow]::GetSystemMetrics([NovaWindow]::SM_CXSMICON)
        $scy = [NovaWindow]::GetSystemMetrics([NovaWindow]::SM_CYSMICON)
        $script:IconBig   = [NovaWindow]::LoadImage([IntPtr]::Zero, $LogoIco, [NovaWindow]::IMAGE_ICON, $cx,  $cy,  [NovaWindow]::LR_LOADFROMFILE)
        $script:IconSmall = [NovaWindow]::LoadImage([IntPtr]::Zero, $LogoIco, [NovaWindow]::IMAGE_ICON, $scx, $scy, [NovaWindow]::LR_LOADFROMFILE)
        if ($script:IconBig -eq [IntPtr]::Zero) {
            Write-Log "LoadImage 失败（$LogoIco），跳过任务栏图标设置"
            $script:IconTries = 40
            return
        }
        Write-Log "已加载 nova-logo.ico：big=$script:IconBig small=$script:IconSmall"
    }

    $script:IconTries++
    # WM_GETICON 只读不写：读回来的句柄等于我们设的 → 图标还是我们的，只计数不重发
    $cur = [NovaWindow]::SendMessage($h, [NovaWindow]::WM_GETICON, [NovaWindow]::ICON_BIG, [IntPtr]::Zero)
    if ($cur -eq $script:IconBig) {
        $script:IconConfirm++
        if ($script:IconConfirm -eq 8) { Write-Log '窗口图标已稳定为 nova-logo.ico，停止盯守' }
        return
    }
    # 不一致（或还没设过）→ 大小图标一起设
    [void][NovaWindow]::SendMessage($h, [NovaWindow]::WM_SETICON, [NovaWindow]::ICON_SMALL, $script:IconSmall)
    [void][NovaWindow]::SendMessage($h, [NovaWindow]::WM_SETICON, [NovaWindow]::ICON_BIG,   $script:IconBig)
    Write-Log "已设置窗口图标 WM_SETICON（第 $script:IconTries 次，读回=$cur）：hwnd=$h"
}

# ---------------------------------------------------------------------------
# JSON 读写（UTF-8 无 BOM）
# ---------------------------------------------------------------------------
# 数据文件统一 UTF-8 **无 BOM** 落盘：带 BOM 会让某些工具/前端把 BOM 当内容读出来。
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

# 读 JSON；文件不存在 / 为空 / 解析失败都回落到 $Default，绝不抛异常打断请求。
function Read-Json([string]$Path, $Default) {
    if (-not (Test-Path $Path)) { return $Default }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Log "读取 $Path 失败：$($_.Exception.Message)"
        return $Default
    }
}

$DefaultSettings = [pscustomobject]@{ iconSize = 64; cols = 6; theme = 'dark' }

# 读取应用列表并按 sort 升序返回；文件缺失/损坏时返回空数组（绝不返回 $null，调用方可直接遍历）。
function Get-Apps {
    $a = Read-Json $AppsFile $null
    if ($null -eq $a) { return ,@() }
    $list = @($a) | Where-Object { $_ -and $_.path } | Sort-Object { [int]$_.sort }
    # 前置逗号：PowerShell 会把单元素数组自动拆成标量，返回后 $apps += ... 会报
    # 「PSObject 不包含 op_Addition」——必须强制保持数组形态。
    return ,@($list)
}

# 落盘应用列表：sort 重写为当前顺序(0..n)，kind 可选保留；空列表写 "[]" 而非 "null"。
function Save-Apps($apps) {
    $i = 0
    $out = @()
    foreach ($a in $apps) {
        $o = [pscustomobject]@{ name = [string]$a.name; path = [string]$a.path; sort = $i }
        if ($a.PSObject.Properties['kind']) { $o | Add-Member -NotePropertyName 'kind' -NotePropertyValue ([string]$a.kind) }
        $out += $o
        $i++
    }
    $json = if ($out.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject @($out) -Depth 6 }
    Write-Utf8NoBom $AppsFile $json
}

# 读外观设置；缺哪个字段补哪个默认值（iconSize 64 / cols 6 / theme dark），保证前端拿到的齐全。
function Get-Settings {
    $s = Read-Json $SetFile $null
    $r = [pscustomobject]@{ iconSize = 64; cols = 6; theme = 'dark' }
    if ($s) {
        if ($s.PSObject.Properties['iconSize']) { $r.iconSize = [int]$s.iconSize }
        if ($s.PSObject.Properties['cols'])     { $r.cols     = [int]$s.cols }
        if ($s.PSObject.Properties['theme'])    { $r.theme    = [string]$s.theme }
    }
    return $r
}

# 写外观设置（整体覆盖）。
function Save-Settings($s) {
    Write-Utf8NoBom $SetFile (ConvertTo-Json -InputObject $s -Depth 4)
}

# ---------------------------------------------------------------------------
# 图标缓存
# ---------------------------------------------------------------------------
# .lnk 解析目标：返回快捷方式指向的实际文件（不存在/非 .lnk/解析失败都返回 $null）
function Resolve-LinkTarget([string]$LnkPath) {
    if ([string]::IsNullOrWhiteSpace($LnkPath) -or $LnkPath -notlike '*.lnk') { return $null }
    $sh = $null
    try { $sh = New-Object -ComObject WScript.Shell } catch { return $null }
    try {
        $lnk = $sh.CreateShortcut($LnkPath)
        $t = [string]$lnk.TargetPath
        if ([string]::IsNullOrWhiteSpace($t) -or -not (Test-Path -LiteralPath $t)) { return $null }
        return $t
    } catch { return $null } finally {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) } catch { }
    }
}

# 图标缓存键 = 路径(小写)的 MD5 前 16 位：路径变（重命名/移动）即换键，保证图标与名字不错位。
function Get-IconKey([string]$AppPath) {
    return [System.BitConverter]::ToString(
               [System.Security.Cryptography.MD5]::Create().ComputeHash(
                   [System.Text.Encoding]::UTF8.GetBytes($AppPath.ToLower()))).Replace('-', '').Substring(0, 16)
}

# 取图标字节：先查 Icons 缓存（命中直接返回）→ 未命中现场提取并回写缓存。
function Get-IconBytes([string]$AppPath, [int]$Size) {
    if (-not (Test-Path -LiteralPath $AppPath)) { return $null }
    $key  = Get-IconKey $AppPath
    $file = Join-Path $IconDir "$key-$Size.png"
    if (Test-Path -LiteralPath $file) {
        try { return [System.IO.File]::ReadAllBytes($file) } catch { }
    }
    $bytes = $null
    try { $bytes = [NovaIcon]::Png($AppPath, $Size) } catch { Write-Log "取图标失败 $AppPath : $($_.Exception.Message)" }
    # .lnk 本体不是 PE 文件，PrivateExtractIcons 提不出图标 → 解析到快捷方式指向的
    # 实际目标再提一次（这就是「到应用的实际位置去提取」；IconLocation 未单独设置时
    # 图标就挂在目标 exe 上）。缓存文件仍以快捷方式路径为键，页面请求方式不变。
    if (-not $bytes) {
        $target = Resolve-LinkTarget $AppPath
        if ($target) {
            try { $bytes = [NovaIcon]::Png($target, $Size) } catch { }
            if ($bytes) { Write-Log "快捷方式本体提不出图标，已改从目标提取：$AppPath -> $target" }
        }
    }
    if ($bytes) { try { [System.IO.File]::WriteAllBytes($file, $bytes) } catch { } }
    return $bytes
}

# ---------------------------------------------------------------------------
# 启动图标预热：宿主起来后，Icons 目录里缺哪张就补哪张
# ---------------------------------------------------------------------------
# 为什么要在启动时预热：提取是惰性的——页面请求 /api/icon 才去提，第一次打开网格时
# 每个图标都要现场提取一次（壳图标提取对每张都要枚举资源，几十毫秒起步），冷启动观感
# 是图标逐个「蹦」出来。启动后把缺的补齐，下次打开就是秒显。
# 预热不阻塞启动：只把「缺的」排进队列，由主循环空闲节拍（每 1.5s）每拍补几张，
# 期间随时让位给真实请求（请求路径的 Get-IconBytes 会先走，预热补到时命中缓存直接返回）。
function New-IconPreheatQueue {
    # 要预热的尺寸 = 大图 256 + 当前网格设置的图标尺寸（网格真实会请求的那张）
    $sizes = New-Object System.Collections.Generic.List[int]
    $sizes.Add(256)
    $is = 0
    try { $is = [int](Get-Settings).iconSize } catch { }
    if ($is -gt 0 -and -not $sizes.Contains($is)) { $sizes.Add($is) }

    $q = New-Object System.Collections.Generic.List[object]
    foreach ($a in (Get-Apps)) {
        $p = [string]$a.path
        if (-not $p -or $p -like 'shell:*') { continue }      # shell: 方案没有本地文件，无从提取
        if (-not (Test-Path -LiteralPath $p)) { continue }    # 失效项留给打开时的提示
        foreach ($s in $sizes) {
            $f = Join-Path $IconDir "$(Get-IconKey $p)-$s.png"
            if (Test-Path -LiteralPath $f) { continue }       # Icons 目录已读到，跳过
            $q.Add([pscustomobject]@{ path = $p; size = $s })
        }
    }
    return ,$q
}

# 空闲节拍调用：从预热队列头部取最多 $Batch 张补提，避免一次提太多卡住主循环。
function Process-IconPreheat([System.Collections.Generic.List[object]]$Queue, [int]$Batch = 6) {
    if (-not $Queue -or $Queue.Count -le 0) { return }
    $n = 0
    while ($Queue.Count -gt 0 -and $n -lt $Batch) {
        $item = $Queue[0]; $Queue.RemoveAt(0)
        [void](Get-IconBytes ([string]$item.path) ([int]$item.size))
        $n++
    }
    if ($Queue.Count -eq 0) { Write-Log "图标预热完成（本拍补提 $n 张）" }
}

# ---------------------------------------------------------------------------
# HTTP 响应helper
# ---------------------------------------------------------------------------
# 注意：$script:ApiToken 在脚本作用域下就是 param 里的 $ApiToken 本身，
#       这里绝不能再写 "$script:ApiToken = ''" 之类的初始化——那会把命令行传入的 token 清空。

# 统一的响应出口：写 Content-Type / 禁缓存 / 写 body / 关流，任何一步失败都不抛（连接可能已断）。
function Send-Bytes($ctx, $Bytes, [string]$Mime) {
    $resp = $ctx.Response
    try {
        $resp.ContentType  = $Mime
        $resp.Headers['Cache-Control'] = 'no-store'
        $len = 0
        if ($null -ne $Bytes) { $len = [int]$Bytes.Length }
        $resp.ContentLength64 = $len
        if ($len -gt 0) {
            $resp.OutputStream.Write($Bytes, 0, $len)
            $resp.OutputStream.Flush()
        }
    } catch {
        Write-Log "响应写出失败（$Mime，len=$len）：$($_.Exception.Message)"
    } finally {
        try { $resp.Close() } catch { }
    }
}

# Send-Bytes 的四个便捷封装：纯文本 / JSON / 带状态码的文本 / 空响应（只置状态码、不含 body）。
function Send-Text($ctx, [string]$Text, [string]$Mime = 'text/plain; charset=utf-8') {
    Send-Bytes $ctx ([System.Text.Encoding]::UTF8.GetBytes($Text)) $Mime
}

function Send-Json($ctx, $Obj) {
    $json = ConvertTo-Json -InputObject $Obj -Depth 8 -Compress
    Send-Text $ctx $json 'application/json; charset=utf-8'
}

function Send-Status($ctx, [int]$Code, [string]$Text) {
    try { $ctx.Response.StatusCode = $Code } catch { }
    Send-Text $ctx $Text
}

function Send-Empty($ctx, [int]$Code) {
    try { $ctx.Response.StatusCode = $Code; $ctx.Response.ContentLength64 = 0 } catch { }
    try { $ctx.Response.Close() } catch { }
}

# HttpListenerRequest.QueryString 用系统 ANSI(GBK) 解码百分号转义，中文参数会乱码。
# 因此改为取原始 Query 串，再用 [uri]::UnescapeDataString 按 UTF-8 自行解码。
function Get-Query($req) {
    $h = @{}
    $raw = $req.Url.Query
    if ([string]::IsNullOrEmpty($raw)) { return $h }
    if ($raw[0] -eq '?') { $raw = $raw.Substring(1) }
    foreach ($pair in $raw.Split('&')) {
        if ([string]::IsNullOrEmpty($pair)) { continue }
        $idx = $pair.IndexOf('=')
        if ($idx -lt 0) { $k = $pair; $v = '' }
        else { $k = $pair.Substring(0, $idx); $v = $pair.Substring($idx + 1) }
        # 关键：浏览器 URLSearchParams 按 application/x-www-form-urlencoded 规则
        # 把「空格」编成 '+'，把真正的 '+' 编成 '%2B'。而 [uri]::UnescapeDataString
        # 只解 %XX、不认 '+'，于是 "C:\Program Files\..." 会被解成 "C:\Program+Files\..."
        # → Test-Path 失败 → 添加被静默丢弃。必须先还原 '+' 为空格，再解 %XX；
        # 这个顺序不会误伤文件名里真的含 '+' 的情况（它传来的是字面量 %2B）。
        if ($k) {
            $kk = [uri]::UnescapeDataString($k.Replace('+', ' '))
            $vv = [uri]::UnescapeDataString($v.Replace('+', ' '))
            $h[$kk] = $vv
        }
    }
    return $h
}

# 读取 POST 的 JSON 请求体（批量添加用）
function Read-JsonBody($req) {
    try {
        if (-not $req.HasEntityBody) { return $null }
        $sr  = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
        $txt = $sr.ReadToEnd()
        $sr.Dispose()
        if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
        return ($txt | ConvertFrom-Json)
    } catch {
        Write-Log "读取请求体失败：$($_.Exception.Message)"
        return $null
    }
}

# ---------------------------------------------------------------------------
# 核心动作
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 把「拖进来的东西」解析成真实文件路径
# ---------------------------------------------------------------------------
# 浏览器出于安全考虑**不暴露拖入文件的绝对路径**：webkitGetAsEntry().fullPath 拿到的只是
# 文件名（形如 /Chrome.lnk），非标准的 file.path 更是只有 Electron / WebView2 才给。
# 所以页面只能把文件**名**报上来，由宿主在常见位置按名字找回来。
# 覆盖面：用户桌面、公共桌面、用户/所有用户开始菜单、开始菜单 Programs、快速启动、下载。
# 快捷方式绝大多数就是从这几处拖出来的，实测足够；找不到时页面会提示改用「添加应用」。
# ⚠ 必须用 [Environment]::GetFolderPath（走 shell API）而**不要**读 $env:APPDATA / $env:USERPROFILE：
#   某些运行环境下这些环境变量是空的（本机实测：$env:ProgramFiles、$env:APPDATA 都取不到），
#   而 Join-Path 收到空 Path 会直接抛「无法将参数绑定到参数"Path"，因为该参数是空值」，
#   把整个请求打成 500。GetFolderPath 走的是 shell API，在这些环境下仍返回正确路径。
function Join-Safe([string]$Base, [string]$Child) {
    if ([string]::IsNullOrWhiteSpace($Base) -or [string]::IsNullOrWhiteSpace($Child)) { return '' }
    try { return (Join-Path $Base $Child) } catch { return '' }
}

function Get-ShortcutSearchRoots {
    $roots = New-Object System.Collections.ArrayList
    $dirs = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('StartMenu'),
        [Environment]::GetFolderPath('CommonStartMenu'),
        [Environment]::GetFolderPath('Programs'),
        (Join-Safe ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Internet Explorer\Quick Launch'),
        (Join-Safe ([Environment]::GetFolderPath('UserProfile'))     'Downloads')
    )
    foreach ($d in $dirs) {
        if (-not [string]::IsNullOrWhiteSpace($d)) {
            if (Test-Path -LiteralPath $d -PathType Container) { [void]$roots.Add($d) }
        }
    }
    return @($roots)
}

# 目录索引：文件名(小写) → 路径列表；去扩展名(小写) → 路径列表。
# 建一次缓存 60 秒 —— 一次拖入多个文件时会反复调用，不能每次都重扫开始菜单。
$script:ShortcutIndex      = $null
$script:ShortcutIndexAt    = [datetime]::MinValue
function Build-ShortcutIndex {
    if ($script:ShortcutIndex -and ((Get-Date) - $script:ShortcutIndexAt).TotalSeconds -lt 60) {
        return $script:ShortcutIndex
    }
    $byName = @{}
    $byBase = @{}
    foreach ($root in (Get-ShortcutSearchRoots)) {
        # 开始菜单层级较深（Programs\厂商\应用.lnk），桌面/下载只扫浅层，免得撞上大目录
        $depth = if ($root -like '*Start Menu*') { 4 } else { 2 }
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Depth $depth -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $k = $f.Name.ToLower()
            if (-not $byName.ContainsKey($k)) { $byName[$k] = New-Object System.Collections.ArrayList }
            [void]$byName[$k].Add($f.FullName)
            $b = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToLower()
            if ($b) {
                if (-not $byBase.ContainsKey($b)) { $byBase[$b] = New-Object System.Collections.ArrayList }
                [void]$byBase[$b].Add($f.FullName)
            }
        }
    }
    $script:ShortcutIndex   = [pscustomobject]@{ byName = $byName; byBase = $byBase }
    $script:ShortcutIndexAt = Get-Date
    Write-Log "快捷方式索引已建立：$($byName.Count) 个文件名 / $($byBase.Count) 个基名"
    return $script:ShortcutIndex
}

# 外壳只负责兜异常：路径解析牵扯文件系统枚举，任何一处意外都不该把整个请求打成 500 ——
# 最差也要能回一句「没找到」，让用户知道该改用「添加应用」。
function Resolve-AppRef([string]$Ref, [string]$Hint = '') {
    try { return Resolve-AppRefInner $Ref $Hint }
    catch {
        Write-Log "解析路径异常（$Ref / $Hint）：$($_.Exception.Message)"
        return $null
    }
}

function Resolve-AppRefInner([string]$Ref, [string]$Hint = '') {
    $cands = @()
    foreach ($c in @($Ref, $Hint)) {
        if (-not [string]::IsNullOrWhiteSpace($c)) { $cands += $c.Trim().Trim('"') }
    }
    if ($cands.Count -eq 0) { return $null }

    # ① shell: 原样返回（UWP）
    foreach ($c in $cands) { if ($c -like 'shell:*') { return $c } }

    # ② 真·绝对路径且存在 → 规范化后返回（顺带把 8.3 短名 / 相对路径统一掉）
    foreach ($c in $cands) {
        try {
            if ([System.IO.Path]::IsPathRooted($c) -and (Test-Path -LiteralPath $c)) {
                return (Get-Item -LiteralPath $c).FullName
            }
        } catch { }
    }

    # ③ 只拿到文件名 → 在常见位置按名字找回
    $want = @()
    foreach ($c in $cands) {
        $rooted = $false
        try { $rooted = [System.IO.Path]::IsPathRooted($c) } catch { }
        # 已经是绝对路径的，② 里就判过了：不存在就是真的没有，不再按名字另猜一个
        if ($rooted) { continue }
        try { $leaf = Split-Path $c -Leaf } catch { $leaf = $c }
        $leaf = ([string]$leaf).Trim()
        if ($leaf) { $want += $leaf }
    }
    $want = @($want | Select-Object -Unique)
    if ($want.Count -eq 0) { return $null }

    $idx = Build-ShortcutIndex
    foreach ($n in $want) {
        $hits = @()
        $lk = $n.ToLower()
        if ($idx.byName.ContainsKey($lk)) { $hits += $idx.byName[$lk] }
        if (-not $hits.Count) {
            # 名字对不上时退一步按基名匹配：拖来 Chrome.exe、桌面只有 Chrome.lnk 也能接上
            $lb = [System.IO.Path]::GetFileNameWithoutExtension($n).ToLower()
            if ($lb -and $idx.byBase.ContainsKey($lb)) { $hits += $idx.byBase[$lb] }
        }
        if ($hits.Count) {
            # 快捷方式优先（启动行为与用户双击一致），其次按路径排序取稳定结果
            $lnk  = @($hits | Where-Object { $_ -like '*.lnk' } | Sort-Object)
            $pick = if ($lnk.Count) { $lnk[0] } else { (@($hits | Sort-Object))[0] }
            Write-Log "按名称解析：$n → $pick"
            return $pick
        }
    }
    Write-Log "按名称解析失败：$($want -join '、')（已搜索桌面 / 开始菜单 / 快速启动 / 下载）"
    return $null
}

# 按路径添加一个应用：校验存在性（shell: 协议跳过）、规范化为绝对路径、按路径去重，追加到列表末尾并落盘，
# 顺带预热图标缓存；成功返回 { name, path, iconOk }，已存在返回原条目，路径非法/文件不存在返回 $null。
function Add-AppPath([string]$Path, [string]$Name, [string]$Kind = '') {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $Path = $Path.Trim().Trim('"')
    $isShell = $Path -like 'shell:*'
    if (-not $isShell) {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        # 规范化到绝对路径，避免相对路径 / 8.3 短名重复写入
        try { $full = (Get-Item -LiteralPath $Path).FullName } catch { $full = $Path }
    } else {
        $full = $Path
    }

    $apps = Get-Apps
    foreach ($a in $apps) { if ($a.path -ieq $full) { return $a } }   # 已存在则不重复

    if ([string]::IsNullOrWhiteSpace($Name)) {
        if ($isShell) { $Name = $Path } else { $Name = [System.IO.Path]::GetFileNameWithoutExtension($full) }
    }
    $apps += [pscustomobject]@{ name = $Name; path = $full; sort = $apps.Count; kind = $Kind }
    Save-Apps $apps
    $icon = if (-not $isShell) { Get-IconBytes $full 256 } else { $null }   # 预热图标缓存（shell: 方案无本地文件）
    Write-Log "添加应用：$Name -> $full"
    return [pscustomobject]@{ name = $Name; path = $full; iconOk = [bool]$icon }
}

# ---------------------------------------------------------------------------
# 启动后把新窗口拉到前台
# ---------------------------------------------------------------------------
# 为什么需要这一步：宿主是后台进程，受前台锁限制，它拉起的应用拿不到前台资格，
# 新窗口会停在 launcher 后面（「应用藏在软件后端」的观感）；前台锁的绕过手法见 ForceForeground。
# 找窗口用「启动前后拍快照取差集」，不按进程找：
#   · .lnk 要经 shell 中转，Start-Process -PassThru 拿到的进程常常不是真正拥有窗口的那个；
#   · shell:AppsFolder\<AUMID>（UWP）是交给 explorer 拉起，窗口更不在 explorer 进程里。
# 差集只要求「这张脸以前没见过」，与谁创建它无关，两种情况都覆盖。
function Bring-NewWindowToFront {
    param(
        [IntPtr[]]$Before   = @(),
        [int]$TimeoutMs     = 2500,
        [int]$LaunchedPid   = 0
    )

    $own    = Get-NovaWin
    $ownPid = if ($own -ne [IntPtr]::Zero) { [NovaWindow]::PidOf($own) } else { 0 }
    $selfPid = [uint32]$PID

    # 启动前就存在的窗口一律排除；我们自己（宿主 / 浏览器）的窗口也排除
    $skip = @{}
    foreach ($h in $Before) { $skip[$h.ToInt64()] = $true }
    # 宿主自己的控制台宿主进程名，避免把「窗口一闪而过的黑框」当成目标
    $skipProc = @('powershell', 'pwsh', 'conhost', 'WindowsTerminal')

    $cands    = @{}
    $touched  = $null      # 上一次强制置前的目标
    $lastNew  = $null      # 上一次发现新窗口的时刻
    $t0       = Get-Date
    $deadline = $t0.AddMilliseconds($TimeoutMs)

    while ((Get-Date) -lt $deadline) {
        $now = @([NovaWindow]::SnapshotTopLevel(120, 80))
        foreach ($h in $now) {
            $k = $h.ToInt64()
            if ($skip.ContainsKey($k)) { continue }
            $skip[$k] = $true                     # 每张脸只看一次
            $pidOf = [NovaWindow]::PidOf($h)
            if ($pidOf -eq $ownPid -or $pidOf -eq $selfPid) { continue }
            $pn = [NovaWindow]::ProcNameOf($pidOf)
            if ($skipProc -contains $pn) { continue }
            $rc = New-Object 'NovaWindow+RECT'
            [NovaWindow]::GetWindowRect($h, [ref]$rc) | Out-Null
            $cands[$k] = [pscustomobject]@{
                h     = $h
                pid   = $pidOf
                area  = ([long]($rc.R - $rc.L)) * ([long]($rc.B - $rc.T))
                title = [NovaWindow]::TitleOf($h)
                proc  = $pn
            }
            $lastNew = Get-Date
            Write-Log "发现新窗口：$($cands[$k].title)（$pn pid=$pidOf $($rc.R - $rc.L)x$($rc.B - $rc.T)）"
        }

        # 选目标：优先「进程就是被启动的那个」，同档取面积最大（启动闪屏通常明显小于主窗口，
        # 后出现的主窗口会自然胜出，不用特意等待）
        $best = $null
        foreach ($c in $cands.Values) {
            if (-not $best) { $best = $c; continue }
            $bm = ($LaunchedPid -gt 0 -and $best.pid -eq $LaunchedPid)
            $cm = ($LaunchedPid -gt 0 -and $c.pid     -eq $LaunchedPid)
            if ($cm -and -not $bm) { $best = $c }
            elseif ($cm -eq $bm -and $c.area -gt $best.area) { $best = $c }
        }

        if ($best) {
            if ($touched -eq $null -or $touched.ToInt64() -ne $best.h.ToInt64()) {
                $ok = [NovaWindow]::ForceForeground($best.h)
                $touched = $best.h
                $z = [NovaWindow]::ZOrderIndexOf($best.h)
                Write-Log "置前：$($best.title)（$($best.proc)，键盘焦点=$ok，z序=$z）"
            }
            # 命中后再多观察 0.7s：让后出现的主窗口有机会取代闪屏，之后收工
            if ($lastNew -and ((Get-Date) - $lastNew).TotalMilliseconds -gt 700) { break }
        } else {
            $el = ((Get-Date) - $t0).TotalMilliseconds
            # 已经运行中的单实例应用不会产生新窗口：启动进程多半很快退出，此时别干等满超时
            if ($el -gt 800 -and $LaunchedPid -gt 0 -and (Get-Process -Id $LaunchedPid -ErrorAction SilentlyContinue) -eq $null) { break }
            if ($el -gt 1400) { break }
        }
        Start-Sleep -Milliseconds 120
    }

    if ($touched -ne $null) {
        # 有些应用初始化完会自己抢一次焦点，收尾再压一次，确保它是前台
        [NovaWindow]::ForceForeground($touched) | Out-Null
        return $cands.Values | Where-Object { $_.h -eq $touched } | Select-Object -First 1
    }
    Write-Log "启动后未捕捉到新窗口（应用可能已在运行，或窗口不满足可见+有标题）"
    return $null
}

# 启动一个应用：shell:（UWP/商店）交 explorer 拉起，其余走 Start-Process（EXE/LNK 皆可、带工作目录）。
# 启动前后各拍一次顶层窗口快照，交 Bring-NewWindowToFront 取差集把新窗口拉到前台；
# 返回 { ok, msg }——文件不存在或启动异常时 ok=$false 并带上原因。
function Launch-App($item) {
    $p = [string]$item.path
    # UWP / 商店应用：路径为 shell:AppsFolder\<AUMID>，需经 explorer 拉起
    if ($p -like 'shell:*') {
        $before = @([NovaWindow]::SnapshotTopLevel(120, 80))
        try {
            Start-Process explorer.exe -ArgumentList $p | Out-Null
            Write-Log "启动(shell):$p"
        } catch {
            Write-Log "启动失败 $p : $($_.Exception.Message)"
            return [pscustomobject]@{ ok = $false; msg = $_.Exception.Message }
        }
        $w = Bring-NewWindowToFront -Before $before
        $tail = if ($w) { '' } else { '（窗口已就绪但未捕捉到，可能已在运行）' }
        return [pscustomobject]@{ ok = $true; msg = "已启动 $($item.name)$tail" }
    }
    if (-not (Test-Path -LiteralPath $p)) {
        return [pscustomobject]@{ ok = $false; msg = '文件不存在，可能已被移动或删除' }
    }
    $before = @([NovaWindow]::SnapshotTopLevel(120, 80))
    $proc = $null
    try {
        # Start-Process 默认走 ShellExecute：EXE / LNK 均可
        $wd = Split-Path -Parent $p
        if ($wd -and (Test-Path -LiteralPath $wd)) {
            $proc = Start-Process -FilePath $p -WorkingDirectory $wd -PassThru
        } else {
            $proc = Start-Process -FilePath $p -PassThru
        }
        Write-Log "启动：$p"
    } catch {
        Write-Log "启动失败 $p : $($_.Exception.Message)"
        return [pscustomobject]@{ ok = $false; msg = $_.Exception.Message }
    }
    $lp = 0
    if ($proc) { try { $lp = [int]$proc.Id } catch { $lp = 0 } }
    $w = Bring-NewWindowToFront -Before $before -LaunchedPid $lp
    $tail = if ($w) { '' } else { '（未捕捉到新窗口，可能已在运行）' }
    return [pscustomobject]@{ ok = $true; msg = "已启动 $($item.name)$tail" }
}

# ---------------------------------------------------------------------------
# 文件选择对话框（独立 STA 线程）
# 注意：HttpListener 回调运行于线程池(MTA)线程，而 WinForms 模态对话框必须在
# STA 线程运行；若直接在主回调里 ShowDialog() 会抛 ThreadStateException → 顶层
# catch 捕获后返回 500，页面即“添加应用报错”。故放到独立 STA 线程并等待其结束。
# ---------------------------------------------------------------------------
function Show-OpenFileDialog {
    $pack = [System.Collections.Hashtable]::Synchronized(@{
        files = [System.Collections.ArrayList]::new()
        error = ''
        evt   = New-Object System.Threading.ManualResetEvent($false)
    })
    $sb = {
        param($pack)
        try {
            $d = New-Object System.Windows.Forms.OpenFileDialog
            $d.Title = '选择要添加到 Nova Launcher 的应用'
            $d.Filter = '应用程序 (*.exe;*.lnk;*.bat;*.cmd)|*.exe;*.lnk;*.bat;*.cmd|所有文件 (*.*)|*.*'
            $d.Multiselect = $true
            $d.RestoreDirectory = $true
            $d.CheckFileExists = $true
            if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                foreach ($f in $d.FileNames) { [void]$pack.files.Add($f) }
            }
        } catch {
            $pack.error = $_.Exception.Message
        } finally {
            $pack.evt.Set()
        }
    }
    $th = New-Object System.Threading.Thread($sb)
    $th.SetApartmentState([System.Threading.ApartmentState]::STA)
    $th.Start($pack)
    $pack.evt.WaitOne() | Out-Null
    if ($pack.error) { Write-Log "文件选择对话框异常：$($pack.error)" }
    return $pack.files
}

# ---------------------------------------------------------------------------
# 枚举已安装应用（开始菜单快捷方式 + 注册表卸载项 + UWP/商店应用）
# 去重按“可启动路径”进行；返回 { name, path, kind, src }
# ---------------------------------------------------------------------------
function Get-InstalledApps {
    $seen = @{}
    $apps = [System.Collections.ArrayList]::new()

    # 1) 开始菜单 .lnk：解析出真实目标 exe（最可靠、可直接启动）
    # 用 .NET 已知文件夹 API 取路径，避免某些环境下 $env:APPDATA/$env:ProgramData
    # 未注入（PowerShell 宿主进程环境被裁剪）导致 Join-Path 收到 $null 抛错。
    $smDirs = @(
        (Join-Path ([System.Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path ([System.Environment]::GetFolderPath('CommonApplicationData')) 'Microsoft\Windows\Start Menu\Programs')
    )
    $shellCom = $null
    try { $shellCom = New-Object -ComObject WScript.Shell } catch { $shellCom = $null }
    foreach ($dir in $smDirs) {
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem -Path $dir -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if (-not $shellCom) { return }
                $lnk = $shellCom.CreateShortcut($_.FullName)
                $target = [string]$lnk.TargetPath
                if ([string]::IsNullOrWhiteSpace($target)) { return }
                if ($target -notlike '*.exe') { return }   # 只收录可执行程序，过滤 .chm/.url/.txt 等文档类目标
                if ($seen.ContainsKey($target)) { return }
                $seen[$target] = $true
                [void]$apps.Add([pscustomobject]@{ name = $_.BaseName; path = $target; kind = 'lnk'; src = '开始菜单' })
            } catch { }
        }
    }
    if ($shellCom) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shellCom) } catch { } }

    # 2) 注册表“程序和功能”项：取 DisplayIcon 中的 exe
    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
        $icon = [string]$_.DisplayIcon
        $exe  = ''
        if ($icon -match '^"{0,1}([^",]*\.exe)"{0,1}') { $exe = $Matches[1] }
        elseif ($icon -match '([^",]*\.exe)') { $exe = $Matches[1] }
        if ([string]::IsNullOrWhiteSpace($exe)) { return }
        $exe = $exe.Trim('"')
        if (-not (Test-Path -LiteralPath $exe)) { return }
        if ($seen.ContainsKey($exe)) { return }
        $seen[$exe] = $true
        [void]$apps.Add([pscustomobject]@{ name = [string]$_.DisplayName; path = $exe; kind = 'registry'; src = '程序和功能' })
    }

    # 3) Get-StartApps：既返回 UWP(商店) 应用，也返回经典应用的 AppID。
    #    - UWP：AppID 形如 AUMID（PackageFamily!App，不含反斜杠），启动走 shell:AppsFolder\<AUMID>
    #    - 经典：AppID 实为可执行文件路径（含反斜杠），直接按路径收录，并与开始菜单项按路径去重
    try {
        Get-StartApps -ErrorAction SilentlyContinue | ForEach-Object {
            $aid = [string]$_.AppID
            if ([string]::IsNullOrWhiteSpace($aid)) { return }
            if ($aid -match '\\') {
                if ($aid -notlike '*.exe') { return }
                if (-not (Test-Path -LiteralPath $aid)) { return }
                $launch = $aid
                $kind   = 'startapp'
            } else {
                $launch = "shell:AppsFolder\$aid"
                $kind   = 'uwp'
            }
            if ($seen.ContainsKey($launch)) { return }
            $seen[$launch] = $true
            [void]$apps.Add([pscustomobject]@{ name = [string]$_.Name; path = $launch; kind = $kind; src = '已安装应用' })
        }
    } catch { }

    # 按名称去重：同一应用可能同时出现在「开始菜单(.lnk → exe)」与「Get-StartApps(AUMID)」两处，
    # 路径不同但实为同一程序（如 ACDSee、Adobe Creative Cloud）；保留先出现的，开始菜单/注册表的
    # exe 路径更直接、可启动性更好，故优先。
    $final = [System.Collections.ArrayList]::new()
    $seenName = @{}
    foreach ($a in $apps) {
        $key = ([string]$a.name).Trim().ToLower()
        if ($key -and $seenName.ContainsKey($key)) { continue }
        if ($key) { $seenName[$key] = $true }
        [void]$final.Add($a)
    }

    # 4) 附加「使用频率」与「安装时间」
    #    频率：UserAssist 启动次数 + FeatureUsage(AppSwitched/AppLaunch) 次数（1 分钟缓存）
    #    安装时间：注册表 InstallDate 优先 → 目标 exe 创建时间 → UWP 包目录创建时间
    $usage = Get-UsageIndex
    $inst  = Get-InstallInfo
    foreach ($a in $final) {
        $p     = [string]$a.path
        $lower = $p.ToLower()
        $freq  = 0
        $dt    = $null

        if ($lower -like 'shell:appsfolder\*') {
            # UWP：FeatureUsage 里存的就是 AUMID；包族名 = AUMID 中 '!' 之前的部分
            $aid = $p.Substring($p.IndexOf('\') + 1).ToLower()
            if ($usage.ContainsKey($aid)) { $freq += [int]$usage[$aid] }
            $pfn = ($aid -split '!')[0]
            if ($inst.byPfn.ContainsKey($pfn)) { $dt = $inst.byPfn[$pfn] }
        } else {
            if ($usage.ContainsKey($lower)) { $freq += [int]$usage[$lower] }
            $fn = ($lower -split '\\')[-1]
            if ($usage.ContainsKey($fn)) { $freq += [int]$usage[$fn] }
            if ($inst.byExe.ContainsKey($lower)) { $dt = $inst.byExe[$lower] }
            if (-not $dt) {
                $nm = ([string]$a.name).Trim().ToLower()
                if ($inst.byName.ContainsKey($nm)) { $dt = $inst.byName[$nm] }
            }
            if (-not $dt) {
                try { if (Test-Path -LiteralPath $p) { $dt = (Get-Item -LiteralPath $p).CreationTime } } catch { }
            }
        }

        $a | Add-Member -NotePropertyName freq         -NotePropertyValue $freq -Force
        $a | Add-Member -NotePropertyName installedAt  -NotePropertyValue $(if ($dt) { $dt.ToString('yyyy-MM-dd') } else { '' }) -Force
        $a | Add-Member -NotePropertyName installedRaw -NotePropertyValue $(if ($dt) { $dt.Ticks } else { [long]0 }) -Force
    }

    return $final
}

# ---------------------------------------------------------------------------
# ROT13 解码：UserAssist 的“值名”是 ROT13 编码的（只旋转字母 A-Z / a-z）
# ---------------------------------------------------------------------------
function ConvertFrom-Rot13([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return '' }
    $ch = $s.ToCharArray()
    for ($i = 0; $i -lt $ch.Length; $i++) {
        $c = [int]$ch[$i]
        if     ($c -ge 65  -and $c -le 77)  { $ch[$i] = [char]($c + 13) }   # A-M
        elseif ($c -ge 78  -and $c -le 90)  { $ch[$i] = [char]($c - 13) }   # N-Z
        elseif ($c -ge 97  -and $c -le 109) { $ch[$i] = [char]($c + 13) }   # a-m
        elseif ($c -ge 110 -and $c -le 122) { $ch[$i] = [char]($c - 13) }   # n-z
    }
    return (-join $ch)
}

# ---------------------------------------------------------------------------
# 使用次数累加（键统一小写）
# ---------------------------------------------------------------------------
function Add-UsageCount($table, $key, $n) {
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    $k = $key.Trim().ToLower()
    $v = 0
    if ($table.ContainsKey($k)) { $v = [int]$table[$k] }
    $table[$k] = $v + [int]$n
}

# ---------------------------------------------------------------------------
# 构建“使用频率索引”
#   来源1：UserAssist（HKCU\...\Explorer\UserAssist\{GUID}\Count）
#          —— 64 位系统记录长度 72 字节，偏移 4 处为 DWORD 启动次数
#   来源2：FeatureUsage\AppSwitched / AppLaunch（经典应用记 exe 路径，UWP 记 AUMID）
#   索引键同时收录「小写全路径 / 小写文件名 / 小写 AUMID」，便于按不同来源命中
# ---------------------------------------------------------------------------
function Get-UsageIndex {
    $idx = @{}

    # 1) UserAssist：最权威的“程序被启动过多少次”
    try {
        $uaRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
        if (Test-Path $uaRoot) {
            Get-ChildItem -Path $uaRoot -ErrorAction SilentlyContinue | ForEach-Object {
                $ck = Join-Path $_.PSPath 'Count'
                if (-not (Test-Path $ck)) { return }
                $item = Get-Item -Path $ck -ErrorAction SilentlyContinue
                if (-not $item) { return }
                foreach ($vn in $item.GetValueNames()) {
                    try {
                        $raw = $item.GetValue($vn)
                        if (-not ($raw -is [byte[]]) -or $raw.Length -lt 8) { continue }
                        $cnt = [System.BitConverter]::ToUInt32($raw, 4)
                        if ($cnt -le 0) { continue }
                        $dec = ConvertFrom-Rot13 $vn
                        $fn  = ($dec -split '\\')[-1]
                        if ($fn -notlike '*.exe') { continue }
                        Add-UsageCount $idx $fn $cnt
                    } catch { }
                }
            }
        }
    } catch { }

    # 2) FeatureUsage：任务栏/开始菜单的切换与启动计数（含 UWP 的 AUMID）
    foreach ($sub in @('AppSwitched', 'AppLaunch')) {
        try {
            $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\$sub"
            if (-not (Test-Path $p)) { continue }
            $item = Get-Item -Path $p -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            foreach ($vn in $item.GetValueNames()) {
                try {
                    $raw = $item.GetValue($vn)
                    $cnt = 0
                    if ($raw -is [byte[]] -and $raw.Length -ge 4) { $cnt = [System.BitConverter]::ToUInt32($raw, 0) }
                    else { try { $cnt = [int]$raw } catch { $cnt = 0 } }
                    if ($cnt -le 0) { continue }
                    Add-UsageCount $idx $vn $cnt
                    $fn = ($vn -split '\\')[-1]
                    if ($fn -like '*.exe') { Add-UsageCount $idx $fn $cnt }
                } catch { }
            }
        } catch { }
    }

    return $idx
}

# ---------------------------------------------------------------------------
# 构建“安装时间索引”：byName（显示名）/ byExe（exe 全路径）/ byPfn（UWP 包族名）
# ---------------------------------------------------------------------------
function Get-InstallInfo {
    $byName = @{}; $byExe = @{}; $byPfn = @{}

    # 1) 注册表卸载项的 InstallDate（形如 "20240315"），最接近真实安装日期
    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    try {
        Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = [string]$_.DisplayName
            $id = [string]$_.InstallDate
            if ([string]::IsNullOrWhiteSpace($dn) -or $id -notmatch '^\d{8}$') { return }
            try { $dt = [datetime]::ParseExact($id, 'yyyyMMdd', $null) } catch { return }
            $k = ($dn -replace '\s+', ' ').Trim().ToLower()
            if ($k -and -not $byName.ContainsKey($k)) { $byName[$k] = $dt }
            $ic = [string]$_.DisplayIcon
            if ($ic -match '([A-Za-z]:\\[^",]*\.exe)') {
                $ex = $Matches[1].Trim('"').ToLower()
                if (-not $byExe.ContainsKey($ex)) { $byExe[$ex] = $dt }
            }
        }
    } catch { }

    # 2) UWP / 商店应用：包安装目录的创建时间
    try {
        Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object {
            $pfn = [string]$_.PackageFamilyName
            $loc = [string]$_.InstallLocation
            if ([string]::IsNullOrWhiteSpace($pfn) -or [string]::IsNullOrWhiteSpace($loc)) { return }
            try {
                if (Test-Path -LiteralPath $loc) { $byPfn[$pfn.ToLower()] = (Get-Item -LiteralPath $loc).CreationTime }
            } catch { }
        }
    } catch { }

    return [pscustomobject]@{ byName = $byName; byExe = $byExe; byPfn = $byPfn }
}

# ---------------------------------------------------------------------------
# 带缓存的枚举：面板每次改排序 / 搜索都会请求，避免重复全量扫描（60 秒内复用）
# ---------------------------------------------------------------------------
$script:InstalledCache   = $null
$script:InstalledCacheAt = [datetime]::MinValue
function Get-InstalledAppsCached {
    $now = Get-Date
    if ($script:InstalledCache -and ($now - $script:InstalledCacheAt).TotalSeconds -lt 60) {
        return $script:InstalledCache
    }
    $script:InstalledCache   = Get-InstalledApps
    $script:InstalledCacheAt = $now
    return $script:InstalledCache
}

# ---------------------------------------------------------------------------
# 请求分发
# ---------------------------------------------------------------------------
function Handle-Request($ctx) {
    $req   = $ctx.Request
    $path  = $req.Url.AbsolutePath
    $query = Get-Query $req

    # 网页本身：不带 token 也能拿（页面里没有 token，拿到也没用）
    if ($path -eq '/' -or $path -ieq '/index.html') {
        if (-not (Test-Path $HtmlPath)) { Send-Status $ctx 500 "缺少 nova-launcher.html"; return }
        Send-Bytes $ctx ([System.IO.File]::ReadAllBytes($HtmlPath)) 'text/html; charset=utf-8'
        return
    }
    # 应用图标：--app 模式下窗口 / 任务栏 / Alt-Tab 的图标来自页面 favicon（此前一直 404，
    # 所以任务栏里是浏览器默认图标）。与页面一样不需要 token —— 图标没有敏感信息，
    # 而 <link rel="icon"> 里拼 token 反而会把图标内容写进浏览器历史/缓存键。
    if ($path -ieq '/favicon.ico' -or $path -ieq '/nova-logo.ico') {
        if (Test-Path $LogoIco) { Send-Bytes $ctx ([System.IO.File]::ReadAllBytes($LogoIco)) 'image/x-icon' }
        else { Send-Empty $ctx 404 }
        return
    }

    # 其余接口一律校验 token
    if ($query['t'] -ne $script:ApiToken) { Send-Status $ctx 403 'forbidden'; return }

    $i = -1
    if ($query['i']) { [int]::TryParse([string]$query['i'], [ref]$i) | Out-Null }

    switch -Regex ($path) {

        '^/api/ping$' {
            # 顺手用页面报回的 innerHeight 反推自绘标题栏高度（必须在最大化之前算，见函数注释）
            Update-NovaCsdHeight ([string]$query['ih']) ([string]$query['dpr'])
            Invoke-StartupMaximize        # 页面能发心跳说明窗口已经在了，顺手把全屏补上
            Invoke-NovaWindowGuard        # 心跳也是一次守门时机，贴近用户操作（如从任务栏还原）
            # 回报当前形态：守门可能已在背后纠正过窗口，前端据此同步「最大化/还原」图标，
            # 否则用户从任务栏还原后按钮图标会停在旧形态。
            $hp = Get-NovaWin
            $sp = if ($hp -ne [IntPtr]::Zero) { Get-NovaWinState $hp } else { 'unknown' }
            Send-Json $ctx ([pscustomobject]@{ ok = $true; state = $sp })
            return
        }

        '^/api/state$' {
            # 页面初始化会先拉状态，这里是最早能确认窗口存在的时机
            Update-NovaCsdHeight ([string]$query['ih']) ([string]$query['dpr'])
            Invoke-StartupMaximize
            $apps = Get-Apps
            $out  = @()
            foreach ($a in $apps) {
                $exists = if ($a.path -like 'shell:*') { $true } else { (Test-Path -LiteralPath $a.path) }
                $out += [pscustomobject]@{ name = $a.name; path = $a.path; exists = $exists; kind = ([string]$a.kind) }
            }
            Send-Json $ctx ([pscustomobject]@{ apps = @($out); settings = (Get-Settings); dataDir = $DataDir })
            return
        }

        '^/api/checkapps$' {
            # 一键检查所有已添加应用是否仍有效（设置抽屉用）。
            # 比 /api/state 的浅检查更进一步：.lnk 会解析实际目标——快捷方式文件还在、
            # 但目标已被卸载/挪走的情况，浅检查报「有效」，这里能揪出来。
            $apps = Get-Apps
            $bad  = @()
            $okN  = 0
            for ($idx = 0; $idx -lt $apps.Count; $idx++) {
                $p = [string]$apps[$idx].path
                $why = ''
                if ([string]::IsNullOrWhiteSpace($p)) { $why = '路径为空' }
                elseif ($p -like 'shell:*') { $okN++; continue }   # UWP/商店应用走系统协议，无法也不需要验证
                elseif (-not (Test-Path -LiteralPath $p)) { $why = '文件不存在' }
                elseif ($p -like '*.lnk' -and -not (Resolve-LinkTarget $p)) { $why = '快捷方式目标不存在' }
                else { $okN++; continue }
                $bad += [pscustomobject]@{ i = $idx; name = [string]$apps[$idx].name; path = $p; reason = $why }
            }
            Send-Json $ctx ([pscustomobject]@{ ok = $true; total = $apps.Count; okCount = $okN; bad = @($bad) })
            return
        }

        '^/api/icon$' {
            # 任意路径图标：供“已安装应用”面板使用（shell: 方案无本地图标）
            $custom = [string]$query['p']
            if ($custom) {
                $size = 256
                if ($query['s']) { [int]::TryParse($query['s'], [ref]$size) | Out-Null }
                if ($size -lt 16 -or $size -gt 512) { $size = 256 }
                if ($custom -notmatch '^shell:') {
                    $bytes = Get-IconBytes $custom $size
                    if ($bytes) { Send-Bytes $ctx $bytes 'image/png'; return }
                }
                Send-Status $ctx 404 'no icon'; return
            }
            $apps = Get-Apps
            if ($i -lt 0 -or $i -ge $apps.Count) { Send-Status $ctx 404 'no such app'; return }
            $size = 256
            if ($query['s']) { [int]::TryParse($query['s'], [ref]$size) | Out-Null }
            if ($size -lt 16 -or $size -gt 512) { $size = 256 }
            $bytes = Get-IconBytes ([string]$apps[$i].path) $size
            if (-not $bytes) { Send-Status $ctx 404 'no icon'; return }
            Send-Bytes $ctx $bytes 'image/png'
            return
        }

        '^/api/installed$' {
            # 枚举系统已安装应用（开始菜单 .lnk + 注册表卸载项 + UWP/商店应用）
            $apps = @(Get-InstalledAppsCached)
            $sort = [string]$query['sort']
            $q    = [string]$query['q']
            if ($q) {
                # 转义 like 的模式字符 [ ，避免用户输入方括号时报错
                $q = $q -replace '\[', '[[]'
                $apps = @($apps | Where-Object { ($_.name -like "*$q*") -or ($_.path -like "*$q*") })
            }
            switch ($sort) {
                # 默认：使用频率从高到低（freq 为 0 的按名称排在后面）
                'freq'      { $apps = @($apps | Sort-Object @{ e = { [int]$_.freq } ; Descending = $true }, { $_.name }) }
                # 安装时间从新到旧（未知时间的排最后）
                'installed' { $apps = @($apps | Sort-Object @{ e = { [long]$_.installedRaw } ; Descending = $true }, { $_.name }) }
                'name'      { $apps = @($apps | Sort-Object { $_.name }) }
                'path'      { $apps = @($apps | Sort-Object { $_.path }) }
                'kind'      { $apps = @($apps | Sort-Object { $_.kind }, { $_.name }) }
                'src'       { $apps = @($apps | Sort-Object { $_.src }, { $_.name }) }
                default     { $apps = @($apps | Sort-Object @{ e = { [int]$_.freq } ; Descending = $true }, { $_.name }) }
            }
            Send-Json $ctx ([pscustomobject]@{ count = $apps.Count; apps = @($apps) })
            return
        }

        '^/api/launch$' {
            $apps = Get-Apps
            if ($i -lt 0 -or $i -ge $apps.Count) { Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = '应用不存在' }); return }
            Send-Json $ctx (Launch-App $apps[$i])
            return
        }

        '^/api/pick$' {
            $files = Show-OpenFileDialog
            if (-not $files -or $files.Count -eq 0) {
                Send-Json $ctx ([pscustomobject]@{ ok = $false; cancelled = $true; msg = '已取消' })
                return
            }
            $added = @(); $failed = @()
            foreach ($f in $files) {
                $r = Add-AppPath $f '' ''
                if ($r) { $added += $r.name } else { $failed += (Split-Path $f -Leaf) }
            }
            Send-Json $ctx ([pscustomobject]@{ ok = ($added.Count -gt 0); added = @($added); failed = @($failed); msg = ("已添加 " + ($added -join '、')) })
            return
        }

        '^/api/add$' {
            $dropP = [string]$query['p']; $dropN = [string]$query['n']
            $rp = Resolve-AppRef $dropP $dropN
            if ($rp) { $dropP = $rp }
            $r = Add-AppPath $dropP $dropN ([string]$query['k'])
            if ($r) { Send-Json $ctx ([pscustomobject]@{ ok = $true; name = $r.name; path = $r.path; msg = "已添加 $($r.name)" }) }
            else    { Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = '未找到该文件（已查桌面 / 开始菜单 / 快速启动 / 下载）' }) }
            return
        }

        # 批量添加：一次请求、逐个落盘，并逐项回报成功/失败原因。
        # 前端「添加选中」走这里，杜绝 N 次请求中失败项被静默吞掉。
        '^/api/addbatch$' {
            $body  = Read-JsonBody $req
            $items = @()
            if ($body -and $body.PSObject.Properties['items'] -and $body.items) { $items = @($body.items) }
            $okItems = @(); $badItems = @()
            foreach ($it in $items) {
                $p = [string]$it.p; $n = [string]$it.n; $k = [string]$it.k
                # 拖入的项通常只有一个裸文件名（浏览器不给绝对路径）→ 先按名称解析成真实路径。
                # 只在「原路径本来就用不了」时才解析：否则会白跑一趟，还会把 $k（uwp/lnk 之类）
                # 在下面一并清掉，丢掉商店应用的来源标记。
                $usable = $false
                if ($p -like 'shell:*') { $usable = $true }
                else {
                    try { if ([System.IO.Path]::IsPathRooted($p) -and (Test-Path -LiteralPath $p)) { $usable = $true } } catch { }
                }
                if (-not $usable) {
                    $rp = Resolve-AppRef $p $n
                    if ($rp) {
                        $p = $rp
                        if ([string]::IsNullOrWhiteSpace($n)) {
                            try { $n = [System.IO.Path]::GetFileNameWithoutExtension($p) } catch { $n = $p }
                        }
                        $k = ''
                    }
                }
                $r = Add-AppPath $p $n $k
                if ($r) {
                    $okItems += [pscustomobject]@{ name = $r.name; path = $r.path }
                } else {
                    $why = '无效路径'
                    if ([string]::IsNullOrWhiteSpace($p)) {
                        # 拖入时浏览器只给得出文件名，解析失败是最常见的失败原因，说清楚去哪找过了
                        $why = '未找到（已查桌面 / 开始菜单 / 快速启动 / 下载，可改用「添加应用」手动选择）'
                    } elseif ($p -notlike 'shell:*' -and -not (Test-Path -LiteralPath $p)) {
                        $why = '文件不存在或已被移动'
                    }
                    if ([string]::IsNullOrWhiteSpace($n)) { try { $n = Split-Path $p -Leaf } catch { $n = $p } }
                    $badItems += [pscustomobject]@{ name = $n; path = $p; why = $why }
                }
            }
            Write-Log "批量添加：成功 $($okItems.Count) 个，失败 $($badItems.Count) 个"
            Send-Json $ctx ([pscustomobject]@{
                ok          = ($okItems.Count -gt 0)
                added       = $okItems.Count
                addedItems  = @($okItems)
                failed      = @($badItems)
                failedCount = $badItems.Count
            })
            return
        }

        '^/api/remove$' {
            $apps = Get-Apps
            if ($i -lt 0 -or $i -ge $apps.Count) { Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = '应用不存在' }); return }
            $name = $apps[$i].name
            $rest = @()
            for ($k = 0; $k -lt $apps.Count; $k++) { if ($k -ne $i) { $rest += $apps[$k] } }
            Save-Apps $rest
            Write-Log "移除应用：$name"
            Send-Json $ctx ([pscustomobject]@{ ok = $true; msg = "已移除 $name" })
            return
        }

        '^/api/rename$' {
            # 重命名**只改 Nova 里的显示名，不动磁盘上的快捷方式文件**（与 /api/remove 同一原则）。
            # 定位优先用 p（路径稳定），拿不到再退回 i —— 行号会随拖拽排序变化，不宜作为主键。
            $newName = ([string]$query['n']).Trim()
            if (-not $newName) { Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = '名称不能为空' }); return }
            if ($newName.Length -gt 60) { $newName = $newName.Substring(0, 60) }

            $apps = Get-Apps
            $n = @($apps).Count
            $idx = -1
            $wantPath = [string]$query['p']
            if ($wantPath) {
                for ($k = 0; $k -lt $n; $k++) { if ([string]$apps[$k].path -eq $wantPath) { $idx = $k; break } }
            }
            if ($idx -lt 0 -and $i -ge 0 -and $i -lt $n) { $idx = $i }
            if ($idx -lt 0) { Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = '应用不存在' }); return }

            $old = [string]$apps[$idx].name
            if ($old -ne $newName) {
                $apps[$idx].name = $newName
                Save-Apps $apps
                Write-Log "重命名：$old -> $newName"
            }
            Send-Json $ctx ([pscustomobject]@{ ok = $true; name = $newName; msg = "已重命名为 $newName" })
            return
        }

        '^/api/move$' {
            $from = -1; $to = -1
            [int]::TryParse([string]$query['from'], [ref]$from) | Out-Null
            [int]::TryParse([string]$query['to'],   [ref]$to)   | Out-Null
            # 注意：这里**不能**写 $apps = @(Get-Apps)。
            # Get-Apps 用 `return ,@($list)` 保持数组形态（见其注释），而 @() 包裹「返回数组的函数调用」
            # 得到的是「1 个元素」的数组（唯一元素就是那个数组本身），于是 $apps.Count 恒为 1，
            # 下面任何 $to -ge 1 的拖拽都会被判成「索引越界」→ 排序永远存不进 apps.json，
            # 前端却已经本地重排 → 图标（按行号取）与名字整体错位。
            # 实测：$a = f → .Count=3；@(f) → .Count=1；@($a) → .Count=3。
            $apps = Get-Apps
            $n = @($apps).Count
            if ($from -lt 0 -or $from -ge $n -or $to -lt 0 -or $to -ge $n) {
                Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = '索引越界' }); return
            }
            $list = New-Object System.Collections.ArrayList
            foreach ($a in $apps) { [void]$list.Add($a) }
            $item = $list[$from]
            $list.RemoveAt($from)
            $list.Insert($to, $item)
            Save-Apps @($list)
            Send-Json $ctx ([pscustomobject]@{ ok = $true })
            return
        }

        '^/api/setting$' {
            $k = [string]$query['k']; $v = [string]$query['v']
            $s = Get-Settings
            switch ($k) {
                'iconSize' { $n = 64; if ([int]::TryParse($v, [ref]$n)) { $s.iconSize = [Math]::Max(36, [Math]::Min(160, $n)) } }
                'cols'     { $n = 6;  if ([int]::TryParse($v, [ref]$n)) { $s.cols     = [Math]::Max(3,  [Math]::Min(12, $n)) } }
                'theme'    { if ($v -eq 'light' -or $v -eq 'dark') { $s.theme = $v } }
            }
            Save-Settings $s
            Send-Json $ctx ([pscustomobject]@{ ok = $true; settings = $s })
            return
        }

        '^/api/reveal$' {
            # 带 i / p → 在资源管理器里**选中**该快捷方式（图标右键菜单的「打开文件位置」）；
            # 不带参数 → 打开数据目录（设置里的「打开数据目录」按钮，保持原行为）
            $tgt = [string]$query['p']
            if (-not $tgt -and $query['i']) {
                $idx = -1; [int]::TryParse([string]$query['i'], [ref]$idx) | Out-Null
                $apps = Get-Apps
                if ($idx -ge 0 -and $idx -lt @($apps).Count) { $tgt = [string]$apps[$idx].path }
            }
            try {
                if ($tgt -and $tgt -notlike 'shell:*' -and (Test-Path -LiteralPath $tgt)) {
                    Start-Process explorer.exe -ArgumentList ('/select,"' + $tgt + '"')
                } else {
                    Start-Process explorer.exe -ArgumentList "`"$DataDir`""
                }
            } catch { }
            Send-Json $ctx ([pscustomobject]@{ ok = $true })
            return
        }

        '^/api/win$' {
            $op = [string]$query['op']
            $hwnd = Get-NovaWin
            if ($hwnd -eq [IntPtr]::Zero -or -not [NovaWindow]::IsWindow($hwnd)) {
                Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = '未找到浏览器窗口' })
                return
            }
            switch ($op) {
                'state' {
                    # 一并返回 hwnd / bar：排查「多个同名窗口 / 选错窗口 / 标题栏没藏住」时，
                    # 外部可以直接对着句柄量尺寸、看自绘标题栏高度算得对不对
                    Send-Json $ctx ([pscustomobject]@{ ok = $true; state = (Get-NovaWinState $hwnd); hwnd = $hwnd.ToInt64(); bar = $script:CsdHeight })
                    return
                }
                'pwshot' {
                    # 诊断：PrintWindow(PW_RENDERFULLCONTENT) 离屏渲染窗口当前帧 → .temp\nova-pw.png
                    # 不受遮挡/焦点影响，也不拍到其他窗口；用于验证浏览器是否真的画出了新布局
                    try {
                        $r4 = New-Object 'NovaWindow+RECT'
                        [void][NovaWindow]::GetWindowRect($hwnd, [ref]$r4)
                        $w4 = $r4.R - $r4.L; $h4 = $r4.B - $r4.T
                        if ($w4 -le 0 -or $h4 -le 0) { throw "窗口尺寸异常 ${w4}x${h4}" }
                        $bmp4 = New-Object System.Drawing.Bitmap($w4, $h4)
                        $g4 = [System.Drawing.Graphics]::FromImage($bmp4)
                        $hdc4 = $g4.GetHdc()
                        [void][NovaWindow]::PrintWindow($hwnd, $hdc4, 2)  # 2 = PW_RENDERFULLCONTENT
                        $g4.ReleaseHdc($hdc4)
                        $g4.Dispose()
                        $tmpDir4 = Join-Path (Split-Path $ScriptDir -Parent) '.temp'
                        if (-not (Test-Path $tmpDir4)) { New-Item -ItemType Directory -Path $tmpDir4 | Out-Null }
                        $pwPath = Join-Path $tmpDir4 'nova-pw.png'
                        $bmp4.Save($pwPath, [System.Drawing.Imaging.ImageFormat]::Png)
                        $bmp4.Dispose()
                        Send-Json $ctx ([pscustomobject]@{ ok = $true; path = $pwPath; w = $w4; h = $h4 })
                    } catch {
                        Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = $_.Exception.Message })
                    }
                    return
                }
                'rect' {
                    # 诊断：返回窗口矩形 / 客户区 / 工作区 / 判定状态 / 样式，用于排查切换后窗口位置异常
                    $r = New-Object 'NovaWindow+RECT'
                    [void][NovaWindow]::GetWindowRect($hwnd, [ref]$r)
                    $c = New-Object 'NovaWindow+RECT'
                    [void][NovaWindow]::GetClientRect($hwnd, [ref]$c)
                    $scr2 = [System.Windows.Forms.Screen]::FromHandle($hwnd)
                    if (-not $scr2) { $scr2 = [System.Windows.Forms.Screen]::PrimaryScreen }
                    $wa2 = $scr2.WorkingArea
                    $style2 = [NovaWindow]::GetWindowLong($hwnd, [NovaWindow]::GWL_STYLE)
                    Send-Json $ctx ([pscustomobject]@{
                        ok = $true; state = (Get-NovaWinState $hwnd); hwnd = $hwnd.ToInt64(); bar = $script:CsdHeight
                        rect = @{ l = $r.L; t = $r.T; r = $r.R; b = $r.B; w = ($r.R - $r.L); h = ($r.B - $r.T) }
                        client = @{ w = ($c.R - $c.L); h = ($c.B - $c.T) }
                        work = @{ x = $wa2.X; y = $wa2.Y; w = $wa2.Width; h = $wa2.Height }
                        style = $style2
                        page = @{ ih = "$( $script:LastPageIh )"; dpr = "$( $script:LastPageDpr )" }
                    })
                    return
                }
                'front' {
                    # 诊断：把本窗口抬到最前（复用启动应用时的 ForceForeground）。
                    # 屏幕抓屏 / 命中测试都要求 Nova 在最前才可靠，外部脚本没有前台资格，
                    # 只能借宿主进程（它刚收到过 HTTP 请求，有输入资格）来置前。
                    [NovaWindow]::ForceForeground($hwnd) | Out-Null
                    Send-Json $ctx ([pscustomobject]@{ ok = $true })
                    return
                }
                'noregn' {
                    # 诊断（M34）：清除 region，验证「region 裁剪是否导致 Chromium 布局视口
                    # 不跟随 resize」。调用后观察两次心跳的 innerHeight 是否追上客户区。
                    [void][NovaWindow]::SetWindowRgn($hwnd, [IntPtr]::Zero, $true)
                    Send-Json $ctx ([pscustomobject]@{ ok = $true })
                    return
                }
                'hit' {
                    # 诊断：对 CSD 区 / 页面区各取一个屏幕点做 WindowFromPoint。
                    # region 裁掉的 CSD 区应当**不命中**本窗口（落到背后），页面区应当命中。
                    # 这是验证「标题条是否真的被裁掉」的硬判据（不受遮挡/PrintWindow 干扰）。
                    [NovaWindow]::ForceForeground($hwnd) | Out-Null
                    Start-Sleep -Milliseconds 200
                    $rh = New-Object 'NovaWindow+RECT'
                    [void][NovaWindow]::GetWindowRect($hwnd, [ref]$rh)
                    $csd = Get-NovaCsd
                    # ⚠ PowerShell 陷阱：逗号（数组构造）优先级**高于** + ，
                    # 写 @( $a + $b, $c ) 会被解析成 @( $a + ($b, $c) ) → 报 op_Addition。
                    # 所以先把每个 y 算成标量，再组装数组。
                    $y1 = $rh.T + [int]($csd / 2)
                    $y2 = $rh.T + $csd + 20
                    $y3 = $rh.T + [int](($rh.B - $rh.T) / 2)
                    $names = @('csd-zone', 'page-top', 'page-mid')
                    $ys = @($y1, $y2, $y3)
                    $hits = @()
                    for ($i = 0; $i -lt $names.Count; $i++) {
                        $pt = New-Object 'NovaWindow+POINT'
                        $pt.x = $rh.L + 300; $pt.y = [int]$ys[$i]
                        $hw = [NovaWindow]::WindowFromPoint($pt)
                        # WindowFromPoint 命中 Chrome 渲染**子窗口** → 归到根窗口再比对
                        $root = if ($hw -ne [IntPtr]::Zero) { [NovaWindow]::GetAncestor($hw, [NovaWindow]::GA_ROOT) } else { [IntPtr]::Zero }
                        $hits += [pscustomobject]@{ name = $names[$i]; y = $pt.y; isNova = ($root -eq $hwnd); hwnd = $hw.ToInt64() }
                    }
                    Send-Json $ctx ([pscustomobject]@{ ok = $true; csd = $csd; rectT = $rh.T; hits = $hits })
                    return
                }
                'min' {
                    [NovaWindow]::ShowWindow($hwnd, [NovaWindow]::SW_MINIMIZE) | Out-Null
                    Send-Json $ctx ([pscustomobject]@{ ok = $true; state = 'minimized' })
                    return
                }
                'max' {
                    # 全屏 ⇄ 窗口化 切换（两种形态都无边框：铺满工作区 ⇄ 居中小窗）。
                    # **最小化不是一种形态**：此时点按钮应当回到最小化前的形态而不是翻转
                    #（否则最小化前是全屏、还原后莫名变小窗，还会露出自绘标题条）。
                    $st = Get-NovaWinState $hwnd
                    if ($st -eq 'minimized') {
                        if ($script:WantWindowed) { Set-NovaWinMaximized $hwnd -Windowed } else { Set-NovaWinMaximized $hwnd }
                    } elseif ($st -eq 'maximized') {
                        Set-NovaWinMaximized $hwnd -Windowed
                    } else {
                        Set-NovaWinMaximized $hwnd
                    }
                    Start-Sleep -Milliseconds 80      # 等 SetWindowPos 落定再回报状态，避免前端拿到过渡值
                    Send-Json $ctx ([pscustomobject]@{ ok = $true; state = (Get-NovaWinState $hwnd) })
                    return
                }
                'move' {
                    # 窗口化拖动移动（M36）：页面在自绘标题栏按住左键拖动时，随 pointermove
                    # 把「窗口新左上角(物理px)」发来，这里只平移、不改尺寸/层级/焦点。
                    # 为何不用页面 CSS -webkit-app-region:drag：本项目 --app 窗被外部剥了
                    # WS_CAPTION 又 SetWindowRgn 裁过顶栏，实测该属性不触发系统拖动（还会把
                    # 标题栏变成非客户区、吞掉 DOM 鼠标事件），故改「页面记位移×dpr→宿主
                    # SetWindowPos」显式拖动；localhost 单请求仅一次 SetWindowPos，~1-3ms 跟手。
                    # 拖动不改变窗口形态，守门 Invoke-NovaWindowGuard 只在形态/样式异常时重摆，
                    # 故不会把拖走的窗口又居中拉回。
                    # SWP_NOSIZE 保尺寸 · SWP_NOZORDER 不动 z 序 · SWP_NOACTIVATE 拖动中不改焦点。
                    $mx = 0; $my = 0
                    [void][int]::TryParse([string]$query['x'], [ref]$mx)
                    [void][int]::TryParse([string]$query['y'], [ref]$my)
                    $mfl = [uint32]([NovaWindow]::SWP_NOSIZE -bor [NovaWindow]::SWP_NOZORDER -bor [NovaWindow]::SWP_NOACTIVATE)
                    [NovaWindow]::SetWindowPos($hwnd, [IntPtr]::Zero, $mx, $my, 0, 0, $mfl) | Out-Null
                    Send-Json $ctx ([pscustomobject]@{ ok = $true })
                    return
                }
                'close' {
                    # 关窗即可：页面随之消失 → 心跳停止 → 宿主 25 秒后自行退出
                    [NovaWindow]::PostMessage($hwnd, [NovaWindow]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                    Send-Json $ctx ([pscustomobject]@{ ok = $true; state = 'closing' })
                    return
                }
                default {
                    Send-Json $ctx ([pscustomobject]@{ ok = $false; msg = "未知窗口操作：$op" })
                    return
                }
            }
        }

        '^/api/quit$' {
            Send-Json $ctx ([pscustomobject]@{ ok = $true })
            Write-Log '收到退出指令，宿主结束'
            $script:Running = $false
            return
        }

        default { Send-Status $ctx 404 'not found' }
    }
}

# ---------------------------------------------------------------------------
# 启动
# ---------------------------------------------------------------------------
$script:ApiToken = if ($ApiToken) { $ApiToken } else { [Guid]::NewGuid().ToString('N') }

if ($Port -le 0) {
    $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $Port = ([System.Net.IPEndpoint]$probe.LocalEndpoint).Port
    $probe.Stop()
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try {
    $listener.Start()
} catch {
    Write-Log "端口 $Port 启动失败：$($_.Exception.Message)"
    [void][System.Windows.Forms.MessageBox]::Show("Nova Launcher 启动失败：`n$($_.Exception.Message)", 'Nova Launcher', 'OK', 'Error')
    exit 1
}

$url = "http://127.0.0.1:$Port/?t=$script:ApiToken"
Write-Utf8NoBom $RunFile (ConvertTo-Json -InputObject ([pscustomobject]@{
    port = $Port; token = $script:ApiToken; pid = $PID; url = $url; dataDir = $DataDir
}) -Depth 4)
Write-Log "宿主启动：port=$Port pid=$PID"

if (-not $NoBrowser) {
    # 同样改用 .NET 已知文件夹 API 取基础目录，避免 $env:ProgramFiles 等未注入时 Join-Path 抛错
    $bases = @(
        [System.Environment]::GetFolderPath('ProgramFiles'),
        [System.Environment]::GetFolderPath('ProgramFilesX86'),
        [System.Environment]::GetFolderPath('LocalApplicationData')
    ) | Where-Object { $_ }
    $cands = @()
    foreach ($b in $bases) {
        $cands += (Join-Path $b 'Microsoft\Edge\Application\msedge.exe')
        $cands += (Join-Path $b 'Google\Chrome\Application\chrome.exe')
    }
    $edge = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($edge) {
        # --app：无地址栏 / 无标签页的独立应用窗口，观感接近原生
        # 独立 user-data-dir：避免影响用户日常浏览器配置，也不会弹「恢复页面」
        # 初始尺寸直接给「主屏工作区大小」而不是固定 1180x780 —— 紧接着就要去掉标题栏铺满工作区，
        # 一开始就开这么大，用户看到的是「原地去边框」而不是「小窗口突然撑大」的跳变。
        # 用 WorkingArea（已扣掉任务栏）而不是 Bounds，免得开头那一瞬把任务栏压在下面。
        $mon = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        if (-not $mon) { $mon = New-Object System.Drawing.Rectangle 0, 0, 1280, 800 }
        # ⚠ 这里**必须**自己拼一整条命令行字符串传进去，不能给 -ArgumentList 一个数组。
        #   PowerShell 5.1 的 Start-Process 在把数组元素序列化成命令行时，会把
        #   '--user-data-dir=' + 路径 这种「等号开头」的项拆成 `--user-data-dir=` 和路径两段
        #   （命令行里凭空多一个空格）→ 浏览器收到空值的 --user-data-dir，直接退回**用户自己的
        #   Chrome 配置**：BrowserProfile 目录建不出来、扩展/书签/登录态全被借走。
        #   实测证据：进程命令行里是 `--user-data-dir= D:\...\BrowserProfile`（等号后有空档）。
        #
        # M31.3（2026-09-13）：最大化⇄窗口化切换后，页面底部偶尔长期停留在未光栅化的
        #   纯色 (32,32,32)——Chromium 的「原生窗口遮挡检测」(CalculateNativeWinOcclusion)
        #   在窗口被其他窗口盖住/带 region 裁剪时会暂停瓦片光栅化，半成品帧无限期滞留。
        #   禁用该特性后 Chrome 即使被遮挡也持续光栅化，resize 后立即出完整画面。
        $profileDir = Join-Path $DataDir 'BrowserProfile'
        $argLine = '--app="' + $url + '"' +
                   ' --window-size=' + $mon.Width + ',' + $mon.Height +
                   ' --no-first-run --no-default-browser-check' +
                   ' --disable-features=CalculateNativeWinOcclusion' +
                   ' --user-data-dir="' + $profileDir + '"'
        Start-Process -FilePath $edge -ArgumentList $argLine | Out-Null
        Write-Log "打开窗口：$edge（配置目录 $profileDir）"
    } else {
        Start-Process $url
        Write-Log '未找到 Edge/Chrome，使用默认浏览器打开'
    }
}

# 主循环：1.5s 轮询一次，前端 3s 心跳一次；窗口关闭超过 25s 自动退出，避免残留进程
$script:Running = $true
$lastSeen = Get-Date
$async = $listener.BeginGetContext($null, $null)

# 启动图标预热：Icons 缺的排进队列，主循环空闲节拍分批补提（不阻塞请求处理）
$script:PreheatQueue = New-IconPreheatQueue
if ($script:PreheatQueue.Count -gt 0) {
    Write-Log "图标预热：Icons 目录缺 $($script:PreheatQueue.Count) 张，启动后按空闲节拍到应用实际位置补提"
}

while ($script:Running -and $listener.IsListening) {
    if ($async.AsyncWaitHandle.WaitOne(1500)) {
        try { $ctx = $listener.EndGetContext($async) } catch { break }
        try { $async = $listener.BeginGetContext($null, $null) } catch { }
        $lastSeen = Get-Date
        try { Handle-Request $ctx }
        catch {
            Write-Log "处理请求异常：$($_.Exception.Message)"
            try { Send-Status $ctx 500 'internal error' } catch { }
        }
    } else {
        Process-IconPreheat $script:PreheatQueue   # 空闲节拍补提缺失图标（每拍最多几张）
        Invoke-StartupMaximize             # 空闲节拍里补切全屏（等窗口出现，不阻塞请求）
        Invoke-NovaWindowGuard             # 空闲节拍里守门：样式/几何被外部改回就重摆（见函数注释）
        Set-NovaWindowIcon                 # 空闲节拍里盯任务栏图标：被浏览器覆盖就重设（见函数注释）
        if (((Get-Date) - $lastSeen).TotalSeconds -gt 25) {
            Write-Log '前端心跳中断（窗口已关闭），宿主自动退出'
            break
        }
    }
}

try { $listener.Stop(); $listener.Close() } catch { }
if (Test-Path $RunFile) { Remove-Item $RunFile -Force -ErrorAction SilentlyContinue }
Write-Log '宿主已停止'
