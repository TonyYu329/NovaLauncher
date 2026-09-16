<#
=============================================================================
Nova Launcher M40 - WinForms 无边框 + WebView2Controller 架构
重构目标：彻底移除 Chrome --app / HttpListener / SetWindowRgn / CSD，
从根源消除顶部黑边与点击穿透；启用毛玻璃主题；生产级 DPI 与异步初始化。

技术栈：PowerShell 5.1 -STA | WinForms Form(None) | CoreWebView2Controller
       | GetDpiForWindow + WM_DPICHANGED | Form.Shown + Timer 异步初始化
       | DWM Mica/Acrylic 毛玻璃 | postMessage 通信

编码要求：本文件必须保存为 UTF-8 带 BOM（PowerShell 5.1 无 BOM 会按 GBK 解码）。
=============================================================================
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# 强制隐藏控制台窗口（Windows Terminal 可能忽略 -WindowStyle Hidden，用 Win32 API 兜底）
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NovaConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
}
"@
$__consoleHwnd = [NovaConsole]::GetConsoleWindow()
if ($__consoleHwnd -ne [IntPtr]::Zero) { [NovaConsole]::ShowWindow($__consoleHwnd, 0) | Out-Null }

# 抑制 libpng 等原生库的控制台警告输出
try { [Console]::SetOut([System.IO.TextWriter]::Null) } catch { }
try { [Console]::SetError([System.IO.TextWriter]::Null) } catch { }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$DataDir   = $ScriptDir
$IconDir   = Join-Path $DataDir 'Icons'
$AppsFile  = Join-Path $DataDir 'apps.json'
$SetFile   = Join-Path $DataDir 'settings.json'
$LogFile   = Join-Path $DataDir 'host.log'

foreach ($d in @($DataDir, $IconDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# 加载 WebView2 Core DLL（net462 版本）
$webview2Dll = Join-Path $DataDir 'lib\Microsoft.Web.WebView2.Core.dll'
if (-not (Test-Path $webview2Dll)) {
    [void][System.Windows.Forms.MessageBox]::Show("缺少 WebView2 运行库：`n$webview2Dll", 'Nova Launcher', 'OK', 'Error')
    exit 1
}
Add-Type -Path $webview2Dll

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

# ---------------------------------------------------------------------------
# NovaIcon: 真实图标提取
#   ① PrivateExtractIcons —— 仅对 PE 文件（.exe/.dll）与 .ico 有效，取的是
#      程序内嵌的大图，最清晰，所以优先走它（.exe/.lnk 维持原有观感）。
#   ② Shell 原生图标（IShellItemImageFactory::GetImage + ICONONLY）
#      —— 文件夹、.pdf/.txt 等非 PE 文件走这条，拿到与资源管理器一致的系统图标。
# ---------------------------------------------------------------------------
if (-not ('NovaIcon' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
public static class NovaIcon {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint PrivateExtractIcons(string szFileName, int nIconIndex, int cxIcon, int cyIcon, IntPtr[] phicon, uint[] piconid, uint nIcons, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    // ---- Shell 原生图标（Vista+）----
    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemImageFactory {
        void GetImage(SIZE size, int flags, out IntPtr phbm);
    }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx; public int cy; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(string pszPath, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAP { public int bmType; public int bmWidth; public int bmHeight; public int bmWidthBytes; public ushort bmPlanes; public ushort bmBitsPixel; public IntPtr bmBits; }
    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER { public int biSize; public int biWidth; public int biHeight; public short biPlanes; public short biBitCount; public int biCompression; public int biSizeImage; public int biXPelsPerMeter; public int biYPelsPerMeter; public int biClrUsed; public int biClrImportant; }
    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFO { public BITMAPINFOHEADER bmiHeader; }
    [DllImport("gdi32.dll")] private static extern int GetObject(IntPtr h, int c, ref BITMAP b);
    [DllImport("gdi32.dll")] private static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint lines, IntPtr bits, ref BITMAPINFO bi, uint usage);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr h);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr h, IntPtr hdc);

    private const int SIIGBF_ICONONLY = 0x04;   // 只要图标，不要缩略图（快且确定）
    private static readonly Guid IID_IShellItemImageFactory = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");

    public static byte[] Png(string path, int size) {
        byte[] r = PePng(path, size);
        if (r != null) return r;
        return ShellPng(path, size);
    }

    /// PE 文件内嵌图标（.exe/.dll/.ico），取最大可用帧
    private static byte[] PePng(string path, int size) {
        int[] tries = new int[] { size, 256, 128, 96, 64, 48, 32 };
        foreach (int s in tries) {
            if (s <= 0) continue;
            IntPtr[] h = new IntPtr[1];
            uint[] id = new uint[1];
            uint n = 0;
            try { n = PrivateExtractIcons(path, 0, s, s, h, id, 1, 0); } catch { continue; }
            if (n == 0 || h[0] == IntPtr.Zero) continue;
            try {
                using (Icon ic = Icon.FromHandle(h[0]))
                using (Bitmap bm = ic.ToBitmap())
                using (MemoryStream ms = new MemoryStream()) {
                    bm.Save(ms, ImageFormat.Png);
                    return ms.ToArray();
                }
            } catch { } finally { DestroyIcon(h[0]); }
        }
        return null;
    }

    /// 系统 Shell 图标：文件夹 → 文件夹图标；各类文件 → 资源管理器里同样的关联图标
    private static byte[] ShellPng(string path, int size) {
        if (string.IsNullOrEmpty(path) || size <= 0) return null;
        IntPtr hbm = IntPtr.Zero;
        object com = null;
        try {
            Guid iid = IID_IShellItemImageFactory;
            try { SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out com); } catch { return null; }
            IShellItemImageFactory f = com as IShellItemImageFactory;
            if (f == null) return null;
            SIZE sz = new SIZE(); sz.cx = size; sz.cy = size;
            try { f.GetImage(sz, SIIGBF_ICONONLY, out hbm); } catch { return null; }
            if (hbm == IntPtr.Zero) return null;
            using (Bitmap bm = FromHBitmap(hbm)) {
                if (bm == null) return null;
                using (MemoryStream ms = new MemoryStream()) {
                    bm.Save(ms, ImageFormat.Png);
                    return ms.ToArray();
                }
            }
        } catch { return null; } finally {
            if (hbm != IntPtr.Zero) { try { DeleteObject(hbm); } catch { } }
            if (com != null) { try { Marshal.ReleaseComObject(com); } catch { } }
        }
    }

    /// HBITMAP → 32bpp ARGB Bitmap。不能直接用 Bitmap.FromHbitmap：那条路会丢掉 alpha，
    /// 图标边缘会变成黑块。用 GetDIBits 拷贝原始像素才能保住透明通道。
    private static Bitmap FromHBitmap(IntPtr hbm) {
        BITMAP bm = new BITMAP();
        if (GetObject(hbm, Marshal.SizeOf(typeof(BITMAP)), ref bm) == 0) return null;
        int w = bm.bmWidth, h = bm.bmHeight;
        if (w <= 0 || h <= 0) return null;
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        bool ok = false;
        try {
            BITMAPINFO bi = new BITMAPINFO();
            bi.bmiHeader.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER));
            bi.bmiHeader.biWidth = w;
            bi.bmiHeader.biHeight = -h;   // 负数 = 自顶向下，与 GDI+ 扫描线顺序一致
            bi.bmiHeader.biPlanes = 1;
            bi.bmiHeader.biBitCount = 32;
            bi.bmiHeader.biCompression = 0;   // BI_RGB
            IntPtr hdc = GetDC(IntPtr.Zero);
            try { ok = GetDIBits(hdc, hbm, 0, (uint)h, bd.Scan0, ref bi, 0) != 0; }
            finally { ReleaseDC(IntPtr.Zero, hdc); }
        } finally { bmp.UnlockBits(bd); }
        if (!ok) { bmp.Dispose(); return null; }
        return bmp;
    }
}
'@
}

# ---------------------------------------------------------------------------
# NovaWindow: Win32 窗口工具（仅保留 Launch-App 前台拉起所需）
# ---------------------------------------------------------------------------
if (-not ('NovaWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class NovaWindow {
    public const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOZORDER = 0x0004, SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040;
    public const int SW_MINIMIZE = 6, SW_RESTORE = 9;
    public const uint SPI_GETFOREGROUNDLOCKTIMEOUT = 0x2000, SPI_SETFOREGROUNDLOCKTIMEOUT = 0x2001, SPIF_SENDCHANGE = 0x0002;
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1), HWND_NOTOPMOST = new IntPtr(-2);
    public const byte VK_MENU = 0x12; public const uint KEYEVENTF_KEYUP = 0x0002;
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    public delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint p1, IntPtr p2, uint winIni);
    [DllImport("user32.dll", EntryPoint = "PeekMessageW")] public static extern bool PeekMessage(out MSG m, IntPtr h, uint min, uint max, uint remove);
    [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public static bool ForceForeground(IntPtr h) {
        if (h == IntPtr.Zero || !IsWindow(h)) return false;
        uint oldTimeout = 0; bool timeoutChanged = false;
        uint fgTid = 0, myTid = GetCurrentThreadId(); bool attached = false; bool focused = false;
        try {
            MSG msg; PeekMessage(out msg, IntPtr.Zero, 0, 0, 0);
            if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
            SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_NOACTIVATE);
            SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_NOACTIVATE);
            IntPtr fg = GetForegroundWindow(); uint fgPid = 0;
            if (fg != IntPtr.Zero) fgTid = GetWindowThreadProcessId(fg, out fgPid);
            if (fgTid != 0 && fgTid != myTid) attached = AttachThreadInput(myTid, fgTid, true);
            IntPtr t = Marshal.AllocHGlobal(4);
            try {
                if (SystemParametersInfo(SPI_GETFOREGROUNDLOCKTIMEOUT, 0, t, 0)) {
                    oldTimeout = (uint)Marshal.ReadInt32(t);
                    if (oldTimeout != 0 && SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, IntPtr.Zero, SPIF_SENDCHANGE)) timeoutChanged = true;
                }
            } finally { Marshal.FreeHGlobal(t); }
            focused = SetForegroundWindow(h);
            if (!focused) { keybd_event(VK_MENU, 0, 0, UIntPtr.Zero); keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); focused = SetForegroundWindow(h); }
            BringWindowToTop(h); return focused;
        } catch { return false; } finally {
            if (timeoutChanged) { IntPtr t2 = Marshal.AllocHGlobal(4); try { Marshal.WriteInt32(t2, (int)oldTimeout); SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, t2, SPIF_SENDCHANGE); } finally { Marshal.FreeHGlobal(t2); } }
            if (attached) AttachThreadInput(myTid, fgTid, false);
        }
    }
    public static IntPtr[] SnapshotTopLevel(int minW, int minH) {
        System.Collections.Generic.List<IntPtr> list = new System.Collections.Generic.List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr p) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(512); GetWindowTextW(h, sb, sb.Capacity);
            if (sb.Length == 0) return true;
            RECT r; if (!GetWindowRect(h, out r)) return true;
            if ((r.R - r.L) < minW || (r.B - r.T) < minH) return true;
            list.Add(h); return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
    public static uint PidOf(IntPtr h) { uint pid = 0; GetWindowThreadProcessId(h, out pid); return pid; }
    public static string ProcNameOf(uint pid) { try { return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { return ""; } }
}
'@
}

# ---------------------------------------------------------------------------
# DPI: Per-Monitor V2 + GetDpiForWindow（禁止 GetDpiForSystem）
# ---------------------------------------------------------------------------
if (-not ('DpiNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DpiNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
    public static readonly IntPtr PMV2 = new IntPtr(-4);
    public const int WM_DPICHANGED = 0x02E0;
}
'@
}
try {
    if ([DpiNative]::SetProcessDpiAwarenessContext([DpiNative]::PMV2)) { $script:DpiAware = $true }
    elseif ([DpiNative]::SetProcessDPIAware()) { $script:DpiAware = $true }

} catch { }

function Get-NovaDpiScale([IntPtr]$hwnd) {
    if ($script:DpiAware -and $hwnd -ne [IntPtr]::Zero) {
        $dpi = [DpiNative]::GetDpiForWindow($hwnd)
        if ($dpi -gt 0) { return $dpi / 96.0 }
    }
    return 1.0
}

# ---------------------------------------------------------------------------
# DWM 毛玻璃：Mica (Win11) / Acrylic / 传统毛玻璃降级
# ---------------------------------------------------------------------------
if (-not ('DwmGlass' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DwmGlass {
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    public const int DWMWA_SYSTEMBACKDROP_TYPE = 38;
    public const int DWMSBT_MAINWINDOW = 2;
    public const int DWMSBT_TRANSIENTWINDOW = 3;
    public const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref MARGINS m);
    [StructLayout(LayoutKind.Sequential)] public struct MARGINS { public int L, T, R, B; }

    // 旧版亚克力 API：可设置色调为完全透明，只保留模糊
    [DllImport("user32.dll")] public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);
    [StructLayout(LayoutKind.Sequential)] public struct AccentPolicy {
        public int AccentState;
        public int AccentFlags;
        public uint GradientColor;
        public int AnimationId;
    }
    [StructLayout(LayoutKind.Sequential)] public struct WindowCompositionAttributeData {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }
    public const int WCA_ACCENT_POLICY = 19;
    public const int ACCENT_DISABLED = 0;
    public const int ACCENT_ENABLE_BLURBEHIND = 3;
    public const int ACCENT_ENABLE_ACRYLICBLURBEHIND = 4;

    public static int SetAcrylicBlur(IntPtr hwnd, uint gradientColor) {
        AccentPolicy accent = new AccentPolicy();
        accent.AccentState = ACCENT_ENABLE_ACRYLICBLURBEHIND;
        accent.AccentFlags = 2;
        accent.GradientColor = gradientColor;
        accent.AnimationId = 0;
        IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(accent));
        Marshal.StructureToPtr(accent, ptr, false);
        WindowCompositionAttributeData data = new WindowCompositionAttributeData();
        data.Attribute = WCA_ACCENT_POLICY;
        data.Data = ptr;
        data.SizeOfData = Marshal.SizeOf(accent);
        int hr = SetWindowCompositionAttribute(hwnd, ref data);
        Marshal.FreeHGlobal(ptr);
        return hr;
    }
    public static int SetBlurBehind(IntPtr hwnd, uint gradientColor) {
        AccentPolicy accent = new AccentPolicy();
        accent.AccentState = ACCENT_ENABLE_BLURBEHIND;
        accent.AccentFlags = 2;
        accent.GradientColor = gradientColor;
        accent.AnimationId = 0;
        IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(accent));
        Marshal.StructureToPtr(accent, ptr, false);
        WindowCompositionAttributeData data = new WindowCompositionAttributeData();
        data.Attribute = WCA_ACCENT_POLICY;
        data.Data = ptr;
        data.SizeOfData = Marshal.SizeOf(accent);
        int hr = SetWindowCompositionAttribute(hwnd, ref data);
        Marshal.FreeHGlobal(ptr);
        return hr;
    }
    public static void DisableAcrylicBlur(IntPtr hwnd) {
        AccentPolicy accent = new AccentPolicy();
        accent.AccentState = ACCENT_DISABLED;
        accent.AccentFlags = 0;
        accent.GradientColor = 0;
        accent.AnimationId = 0;
        IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(accent));
        Marshal.StructureToPtr(accent, ptr, false);
        WindowCompositionAttributeData data = new WindowCompositionAttributeData();
        data.Attribute = WCA_ACCENT_POLICY;
        data.Data = ptr;
        data.SizeOfData = Marshal.SizeOf(accent);
        SetWindowCompositionAttribute(hwnd, ref data);
        Marshal.FreeHGlobal(ptr);
    }
}
'@
}

# 任务栏图标：AppUserModelID + WM_SETICON 强制设置
if (-not ('NovaTaskbar' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NovaTaskbar {
    [DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr LoadImage(IntPtr hInst, string lpszName, uint uType, int cx, int cy, uint fuLoad);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
    public const uint WM_SETICON = 0x0080;
    public static readonly IntPtr ICON_SMALL = (IntPtr)0;
    public static readonly IntPtr ICON_BIG = (IntPtr)1;
    public const uint IMAGE_ICON = 1;
    public const uint LR_LOADFROMFILE = 0x00000010;
    public const uint LR_DEFAULTSIZE = 0x00000040;
}
'@
}

function Set-NovaTaskbarIcon([string]$iconPath) {
    # 设置 AppUserModelID，让 Windows 把本进程识别为独立应用
    [NovaTaskbar]::SetCurrentProcessExplicitAppUserModelID("NovaLauncher.App") | Out-Null
    # 加载 16px 小图标和 32px 大图标
    $hSmall = [NovaTaskbar]::LoadImage([IntPtr]::Zero, $iconPath, [NovaTaskbar]::IMAGE_ICON, 16, 16, [NovaTaskbar]::LR_LOADFROMFILE)
    $hBig = [NovaTaskbar]::LoadImage([IntPtr]::Zero, $iconPath, [NovaTaskbar]::IMAGE_ICON, 32, 32, [NovaTaskbar]::LR_LOADFROMFILE)
    if ($hSmall -ne [IntPtr]::Zero) {
        [NovaTaskbar]::SendMessage($form.Handle, [NovaTaskbar]::WM_SETICON, [NovaTaskbar]::ICON_SMALL, $hSmall) | Out-Null
    }
    if ($hBig -ne [IntPtr]::Zero) {
        [NovaTaskbar]::SendMessage($form.Handle, [NovaTaskbar]::WM_SETICON, [NovaTaskbar]::ICON_BIG, $hBig) | Out-Null
    }
    Write-Log "任务栏图标已设置: $iconPath (small=$hSmall big=$hBig)"
}

function Enable-NovaGlass([IntPtr]$hwnd) {
    $m = New-Object DwmGlass+MARGINS
    $m.L = -1; $m.T = -1; $m.R = -1; $m.B = -1
    [DwmGlass]::DwmExtendFrameIntoClientArea($hwnd, [ref]$m) | Out-Null
    $val = [DwmGlass]::DWMSBT_MAINWINDOW
    $hr = [DwmGlass]::DwmSetWindowAttribute($hwnd, [DwmGlass]::DWMWA_SYSTEMBACKDROP_TYPE, [ref]$val, 4)
    if ($hr -ne 0) {
        $val = [DwmGlass]::DWMSBT_TRANSIENTWINDOW
        [DwmGlass]::DwmSetWindowAttribute($hwnd, [DwmGlass]::DWMWA_SYSTEMBACKDROP_TYPE, [ref]$val, 4) | Out-Null
    }
    Write-Log "毛玻璃已启用 (hr=$hr)"
}

function Disable-NovaGlass([IntPtr]$hwnd) {
    $m = New-Object DwmGlass+MARGINS
    $m.L = 0; $m.T = 0; $m.R = 0; $m.B = 0
    [DwmGlass]::DwmExtendFrameIntoClientArea($hwnd, [ref]$m) | Out-Null
    $val = 0  # DWMSBT_NONE
    [DwmGlass]::DwmSetWindowAttribute($hwnd, [DwmGlass]::DWMWA_SYSTEMBACKDROP_TYPE, [ref]$val, 4) | Out-Null
    Write-Log "毛玻璃已禁用"
}

# 根据 glassEnabled / windowOpacity 设置 DWM 窗口背景（系统级、实时）
#   windowOpacity<100  → 纯透明框架（DWMSBT_NONE）：桌面清晰透出，前端叠“背景”膜
#   glassEnabled       → 系统 Mica/亚克力；否则完全不透明
#
# 背景模糊（bgBlur）**不在这里处理**：DWM 的 Mica/亚克力材质会把窗口背景整块顶掉
# （实测：背后放纯红窗口，透过任何 DWMSBT 材质红色分量都是 0），一旦启用，透明度滑块
# 就再也无法让桌面透出来。所以“背景模糊”改由前端一层雾面膜实现（见 nova-launcher.html
# 的 applyStyle），模糊只改膜的色调浓度、不碰不透明度，两个滑块互不干扰。
function Set-NovaDwmBackground([IntPtr]$hwnd, [bool]$glassEnabled, [int]$windowOpacity, [bool]$isDark = $true) {
    # 深浅色标题栏；不使用已在 Win11 退化为纯色的经典 SetWindowCompositionAttribute 亚克力
    $darkVal = if ($isDark) { 1 } else { 0 }
    [DwmGlass]::DwmSetWindowAttribute($hwnd, [DwmGlass]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$darkVal, 4) | Out-Null
    [DwmGlass]::DisableAcrylicBlur($hwnd)
    $m = New-Object DwmGlass+MARGINS

    if ($windowOpacity -lt 100) {
        # 纯透明框架：不启用任何系统模糊，桌面清晰透出
        $m.L = -1; $m.T = -1; $m.R = -1; $m.B = -1
        [DwmGlass]::DwmExtendFrameIntoClientArea($hwnd, [ref]$m) | Out-Null
        $none = 1  # DWMSBT_NONE
        [DwmGlass]::DwmSetWindowAttribute($hwnd, [DwmGlass]::DWMWA_SYSTEMBACKDROP_TYPE, [ref]$none, 4) | Out-Null
        $style = if ($glassEnabled) { "毛玻璃色调+透明" } else { "透明" }
        Write-Log "透明框架已启用（背景透明度 $windowOpacity%，$style）"
    } elseif ($glassEnabled) {
        Enable-NovaGlass $hwnd
    } else {
        Disable-NovaGlass $hwnd
    }
}

# ---------------------------------------------------------------------------
# NovaForm: 子类化 Form，拦截 WM_DPICHANGED（跨屏 DPI 切换）
# ---------------------------------------------------------------------------
if (-not ('NovaForm' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Windows.Forms;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public class NovaForm : Form {
    public Action NovaDpiChanged;
    public Action<string[]> NovaFilesDropped;
    public Action<bool> NovaDragState;
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern void DragAcceptFiles(IntPtr hWnd, bool fAccept);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern uint DragQueryFile(IntPtr hDrop, uint iFile, StringBuilder lpszFile, uint cch);
    [DllImport("shell32.dll")] static extern void DragFinish(IntPtr hDrop);
    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        IntPtr style = GetWindowLongPtr(this.Handle, -16);
        SetWindowLongPtr(this.Handle, -16, new IntPtr(style.ToInt64() | 0x20000));
    }
    public void EnableNovaFileDrop() {
        DragAcceptFiles(this.Handle, true);
    }
    public void DisableNovaFileDrop() { try { DragAcceptFiles(this.Handle, false); } catch { } }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0233) {
            try {
                uint count = DragQueryFile(m.WParam, 0xFFFFFFFF, null, 0);
                var files = new List<string>();
                for (uint i = 0; i < count; i++) {
                    StringBuilder sb = new StringBuilder(32768);
                    uint len = DragQueryFile(m.WParam, i, sb, (uint)sb.Capacity);
                    if (len > 0) files.Add(sb.ToString());
                }
                DragFinish(m.WParam);
                if (NovaFilesDropped != null && files.Count > 0) NovaFilesDropped(files.ToArray());
            } catch { try { DragFinish(m.WParam); } catch { } }
            m.Result = IntPtr.Zero; return;
        }
        if (m.Msg == 0x02E0) {
            RECT rc = (RECT)Marshal.PtrToStructure(m.LParam, typeof(RECT));
            this.Location = new Point(rc.Left, rc.Top);
            this.Size = new Size(rc.Right - rc.Left, rc.Bottom - rc.Top);
            if (NovaDpiChanged != null) NovaDpiChanged();
            m.Result = IntPtr.Zero; return;
        }
        base.WndProc(ref m);
    }
}
'@
}

# ---------------------------------------------------------------------------
# NovaDrop: 宿主自建 OLE 拖放目标（IDropTarget）
#   背景：WebView2 子窗口（Chrome_WidgetWin_0 等）覆盖整个客户区，其自带的
#   drop target 会吞掉从资源管理器拖来的文件。关闭 AllowExternalDrop 后
#   WebView2 交出落点，由本类在「主窗口 + 全部子窗口」上 RegisterDragDrop，
#   直接取 CF_HDROP 绝对路径，并在拖拽悬停时回调前端显示遮罩。
# ---------------------------------------------------------------------------
if (-not ('NovaDrop' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class NovaDrop {
    [StructLayout(LayoutKind.Sequential)] public struct POINTL { public int x; public int y; }

    public const uint DROPEFFECT_NONE = 0;
    public const uint DROPEFFECT_LINK = 4;

    // IDropTarget 的 GDI/COM 坐标点必须用结构体传值，不可退化成 long（会导致签名不匹配、回调不触发）
    [ComImport, Guid("00000122-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IDropTarget {
        [PreserveSig] int DragEnter([MarshalAs(UnmanagedType.Interface)] object pDataObj, uint grfKeyState, POINTL pt, ref uint pdwEffect);
        [PreserveSig] int DragOver(uint grfKeyState, POINTL pt, ref uint pdwEffect);
        [PreserveSig] int DragLeave();
        [PreserveSig] int Drop([MarshalAs(UnmanagedType.Interface)] object pDataObj, uint grfKeyState, POINTL pt, ref uint pdwEffect);
    }

    [DllImport("ole32.dll")] private static extern int RegisterDragDrop(IntPtr hwnd, IDropTarget pDropTarget);
    [DllImport("ole32.dll")] private static extern int RevokeDragDrop(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWndParent, EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder sb, int max);

    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    // 静态字段持有委托与接口实例，防止 GC 回收后 COM 回调访问违例
    private static DropTargetImpl _impl;
    private static EnumProc _enumProc;
    private static Control _ui;
    private static Action<string> _onLog;
    private static readonly HashSet<IntPtr> _registered = new HashSet<IntPtr>();

    public static void Install(IntPtr formHwnd, Control ui, Action<string[]> onFiles, Action<bool> onDragState, Action<string> onLog) {
        _ui = ui;
        _onLog = onLog;
        _impl = new DropTargetImpl(ui, onFiles, onDragState, onLog);
        _enumProc = new EnumProc(OnChild);
        _registered.Clear();
        TryRegister(formHwnd);
    }

    /// 枚举主窗口及其全部子窗口并注册拖放目标；返回本次新注册的数量
    public static int RegisterAll(IntPtr formHwnd) {
        int before = _registered.Count;
        TryRegister(formHwnd);
        try { EnumChildWindows(formHwnd, _enumProc, IntPtr.Zero); }
        catch (Exception ex) { Log("EnumChildWindows 失败：" + ex.Message); }
        return _registered.Count - before;
    }

    private static bool OnChild(IntPtr hWnd, IntPtr lParam) { TryRegister(hWnd); return true; }

    private static void TryRegister(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero || _impl == null) return;
        if (_registered.Contains(hWnd)) {
            if (IsWindow(hWnd)) return;
            _registered.Remove(hWnd);   // 窗口已销毁，句柄可能被复用，需重新注册
        }
        int hr;
        try {
            hr = RegisterDragDrop(hWnd, _impl);
            if (hr != 0) {
                // 多半是 WebView2 关闭外部拖放前留下的旧注册，先撤销再重试
                int rv = RevokeDragDrop(hWnd);
                Log("RegisterDragDrop 失败 0x" + hr.ToString("X8") + "，RevokeDragDrop 0x" + rv.ToString("X8") + "，重试 " + Describe(hWnd));
                hr = RegisterDragDrop(hWnd, _impl);
            }
        } catch (Exception ex) { Log("RegisterDragDrop 异常 " + Describe(hWnd) + "：" + ex.Message); return; }

        if (hr == 0) { _registered.Add(hWnd); Log("已注册拖放目标 " + Describe(hWnd)); }
        else { Log("注册拖放目标失败 " + Describe(hWnd) + " hr=0x" + hr.ToString("X8")); }
    }

    private static string Describe(IntPtr hWnd) {
        string cls = "";
        try { StringBuilder sb = new StringBuilder(256); GetClassNameW(hWnd, sb, 256); cls = sb.ToString(); } catch { }
        return "hwnd=0x" + hWnd.ToInt64().ToString("X") + " [" + cls + "]";
    }

    private static void Log(string msg) { if (_onLog != null) { try { _onLog(msg); } catch { } } }

    private class DropTargetImpl : IDropTarget {
        private readonly Control _ui;
        private readonly Action<string[]> _files;
        private readonly Action<bool> _drag;
        private readonly Action<string> _log;
        private bool _accepting;

        public DropTargetImpl(Control ui, Action<string[]> files, Action<bool> drag, Action<string> log) {
            _ui = ui; _files = files; _drag = drag; _log = log;
        }

        private static IDataObject AsWinData(object pDataObj) {
            if (pDataObj == null) return null;
            IDataObject d = pDataObj as IDataObject;
            if (d == null) d = new DataObject(pDataObj);
            return d;
        }
        private static bool HasFiles(object pDataObj) {
            try { IDataObject d = AsWinData(pDataObj); return d != null && d.GetDataPresent(DataFormats.FileDrop); }
            catch { return false; }
        }

        // 必须在 Drop 返回前把路径取出来：返回后 IDataObject 随时可能被释放
        private static string[] Extract(object pDataObj) {
            try {
                IDataObject d = AsWinData(pDataObj);
                if (d == null || !d.GetDataPresent(DataFormats.FileDrop)) return null;
                return d.GetData(DataFormats.FileDrop) as string[];
            } catch { return null; }
        }

        private void Post(Action a) {
            if (a == null) return;
            try {
                if (_ui != null && _ui.IsHandleCreated) _ui.BeginInvoke(a);
                else a();
            } catch { }
        }
        private void Notify(bool active) {
            if (_drag == null) return;
            Post((Action)(() => { try { _drag(active); } catch { } }));
        }

        public int DragEnter(object pDataObj, uint grfKeyState, POINTL pt, ref uint pdwEffect) {
            _accepting = HasFiles(pDataObj);
            pdwEffect = _accepting ? DROPEFFECT_LINK : DROPEFFECT_NONE;
            if (_accepting) Notify(true);
            return 0;
        }
        public int DragOver(uint grfKeyState, POINTL pt, ref uint pdwEffect) {
            pdwEffect = _accepting ? DROPEFFECT_LINK : DROPEFFECT_NONE;
            return 0;
        }
        public int DragLeave() {
            _accepting = false;
            Notify(false);
            return 0;
        }
        public int Drop(object pDataObj, uint grfKeyState, POINTL pt, ref uint pdwEffect) {
            string[] files = Extract(pDataObj);
            _accepting = false;
            pdwEffect = DROPEFFECT_LINK;
            Notify(false);
            if (files != null && files.Length > 0 && _files != null) {
                if (_log != null) { try { _log("Drop 收到 " + files.Length + " 项"); } catch { } }
                Post((Action)(() => { try { _files(files); } catch { } }));
            }
            return 0;
        }
    }
}
'@
}

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

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

# ---------------------------------------------------------------------------
# 数据：apps.json / settings.json
# ---------------------------------------------------------------------------
function Get-Apps {
    $a = Read-Json $AppsFile $null
    if ($null -eq $a) { return ,@() }
    $list = @($a) | Where-Object { $_ -and $_.path } | Sort-Object { [int]$_.sort }
    return ,@($list)
}

function Save-Apps($apps) {
    $i = 0; $out = @()
    foreach ($a in $apps) {
        $o = [pscustomobject]@{ name = [string]$a.name; path = [string]$a.path; sort = $i }
        if ($a.PSObject.Properties['kind']) { $o | Add-Member -NotePropertyName 'kind' -NotePropertyValue ([string]$a.kind) }
        $out += $o; $i++
    }
    $json = if ($out.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject @($out) -Depth 6 }
    Write-Utf8NoBom $AppsFile $json
}

function Get-Settings {
    $s = Read-Json $SetFile $null
    $r = [pscustomobject]@{ iconSize = 64; cols = 6; theme = 'dark'; win = $null; glassEnabled = $true; glassIntensity = 50; bgStyle = 'mica'; windowOpacity = 100; bgBlur = 0; bgImageEnabled = $false; bgImagePath = ''; bgImageMode = 'cover'; iconFontFamily = 'system'; iconFontSize = 12; iconFontColor = '#ececf1'; iconFontWeight = 600 }
    if ($s) {
        if ($s.PSObject.Properties['iconSize'])      { $r.iconSize      = [int]$s.iconSize }
        if ($s.PSObject.Properties['cols'])          { $r.cols          = [int]$s.cols }
        if ($s.PSObject.Properties['theme'])         { $r.theme         = [string]$s.theme }
        if ($s.PSObject.Properties['win'])           { $r.win           = $s.win }
        if ($s.PSObject.Properties['glassEnabled'])  { $r.glassEnabled  = [bool]$s.glassEnabled }
        if ($s.PSObject.Properties['glassIntensity']){ $r.glassIntensity= [int]$s.glassIntensity }
        if ($s.PSObject.Properties['bgStyle'])       { $r.bgStyle       = [string]$s.bgStyle }
        if ($s.PSObject.Properties['windowOpacity']) { $r.windowOpacity = [int]$s.windowOpacity }
        if ($s.PSObject.Properties['bgBlur'])        { $r.bgBlur        = [int]$s.bgBlur }
        if ($s.PSObject.Properties['bgImageEnabled']){ $r.bgImageEnabled= [bool]$s.bgImageEnabled }
        if ($s.PSObject.Properties['bgImagePath'])   { $r.bgImagePath   = [string]$s.bgImagePath }
        if ($s.PSObject.Properties['bgImageMode'])   { $r.bgImageMode   = [string]$s.bgImageMode }
        if ($s.PSObject.Properties['iconFontFamily']){ $r.iconFontFamily= [string]$s.iconFontFamily }
        if ($s.PSObject.Properties['iconFontSize'])  { $r.iconFontSize  = [int]$s.iconFontSize }
        if ($s.PSObject.Properties['iconFontColor']) { $r.iconFontColor = [string]$s.iconFontColor }
        if ($s.PSObject.Properties['iconFontWeight']){ $r.iconFontWeight= [int]$s.iconFontWeight }
    }
    return $r
}

function Save-Settings($s) {
    Write-Utf8NoBom $SetFile (ConvertTo-Json -InputObject $s -Depth 4)
}

# ---------------------------------------------------------------------------
# 图标缓存
# ---------------------------------------------------------------------------
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

function Get-IconKey([string]$AppPath) {
    return [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($AppPath.ToLower()))).Replace('-', '').Substring(0, 16)
}

function Get-IconBytes([string]$AppPath, [int]$Size) {
    if (-not (Test-Path -LiteralPath $AppPath)) { return $null }
    $key = Get-IconKey $AppPath
    $file = Join-Path $IconDir "$key-$Size.png"
    if (Test-Path -LiteralPath $file) {
        try { return [System.IO.File]::ReadAllBytes($file) } catch { }
    }
    $bytes = $null
    try { $bytes = [NovaIcon]::Png($AppPath, $Size) } catch { Write-Log "取图标失败 $AppPath : $($_.Exception.Message)" }
    if (-not $bytes) {
        $target = Resolve-LinkTarget $AppPath
        if ($target) {
            try { $bytes = [NovaIcon]::Png($target, $Size) } catch { }
        }
    }
    if ($bytes) { try { [System.IO.File]::WriteAllBytes($file, $bytes) } catch { } }
    return $bytes
}

function New-IconPreheatQueue {
    $sizes = New-Object System.Collections.Generic.List[int]
    $sizes.Add(256)
    $is = 0
    try { $is = [int](Get-Settings).iconSize } catch { }
    if ($is -gt 0 -and -not $sizes.Contains($is)) { $sizes.Add($is) }
    $q = New-Object System.Collections.Generic.List[object]
    foreach ($a in (Get-Apps)) {
        $p = [string]$a.path
        if (-not $p -or $p -like 'shell:*') { continue }
        if (-not (Test-Path -LiteralPath $p)) { continue }
        foreach ($s in $sizes) {
            $f = Join-Path $IconDir "$(Get-IconKey $p)-$s.png"
            if (Test-Path -LiteralPath $f) { continue }
            $q.Add([pscustomobject]@{ path = $p; size = $s })
        }
    }
    return ,$q
}

function Process-IconPreheat([System.Collections.Generic.List[object]]$Queue, [int]$Batch = 6) {
    if (-not $Queue -or $Queue.Count -le 0) { return }
    $n = 0
    while ($Queue.Count -gt 0 -and $n -lt $Batch) {
        $item = $Queue[0]; $Queue.RemoveAt(0)
        [void](Get-IconBytes ([string]$item.path) ([int]$item.size))
        $n++
    }
    if ($Queue.Count -eq 0) { Write-Log "图标预热完成" }
}

# ---------------------------------------------------------------------------
# 路径解析（拖入文件名 → 真实路径）
# ---------------------------------------------------------------------------
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
        (Join-Safe ([Environment]::GetFolderPath('UserProfile')) 'Downloads')
    )
    foreach ($d in $dirs) {
        if (-not [string]::IsNullOrWhiteSpace($d) -and (Test-Path -LiteralPath $d -PathType Container)) { [void]$roots.Add($d) }
    }
    return @($roots)
}

$script:ShortcutIndex = $null
$script:ShortcutIndexAt = [datetime]::MinValue
function Build-ShortcutIndex {
    if ($script:ShortcutIndex -and ((Get-Date) - $script:ShortcutIndexAt).TotalSeconds -lt 60) { return $script:ShortcutIndex }
    $byName = @{}; $byBase = @{}
    foreach ($root in (Get-ShortcutSearchRoots)) {
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
    $script:ShortcutIndex = [pscustomobject]@{ byName = $byName; byBase = $byBase }
    $script:ShortcutIndexAt = Get-Date
    return $script:ShortcutIndex
}

function Resolve-AppRef([string]$Ref, [string]$Hint = '') {
    try { return Resolve-AppRefInner $Ref $Hint } catch { return $null }
}

function Resolve-AppRefInner([string]$Ref, [string]$Hint = '') {
    $cands = @()
    foreach ($c in @($Ref, $Hint)) { if (-not [string]::IsNullOrWhiteSpace($c)) { $cands += $c.Trim().Trim('"') } }
    if ($cands.Count -eq 0) { return $null }
    foreach ($c in $cands) { if ($c -like 'shell:*') { return $c } }
    foreach ($c in $cands) {
        try { if ([System.IO.Path]::IsPathRooted($c) -and (Test-Path -LiteralPath $c)) { return (Get-Item -LiteralPath $c).FullName } } catch { }
    }
    $want = @()
    foreach ($c in $cands) {
        $rooted = $false
        try { $rooted = [System.IO.Path]::IsPathRooted($c) } catch { }
        if ($rooted) { continue }
        try { $leaf = Split-Path $c -Leaf } catch { $leaf = $c }
        $leaf = ([string]$leaf).Trim()
        if ($leaf) { $want += $leaf }
    }
    $want = @($want | Select-Object -Unique)
    if ($want.Count -eq 0) { return $null }
    $idx = Build-ShortcutIndex
    foreach ($n in $want) {
        $hits = @(); $lk = $n.ToLower()
        if ($idx.byName.ContainsKey($lk)) { $hits += $idx.byName[$lk] }
        if (-not $hits.Count) {
            $lb = [System.IO.Path]::GetFileNameWithoutExtension($n).ToLower()
            if ($lb -and $idx.byBase.ContainsKey($lb)) { $hits += $idx.byBase[$lb] }
        }
        if ($hits.Count) {
            $lnk = @($hits | Where-Object { $_ -like '*.lnk' } | Sort-Object)
            $pick = if ($lnk.Count) { $lnk[0] } else { (@($hits | Sort-Object))[0] }
            return $pick
        }
    }
    return $null
}

function Add-AppPath([string]$Path, [string]$Name, [string]$Kind = '') {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $Path = $Path.Trim().Trim('"')
    $isShell = $Path -like 'shell:*'
    if (-not $isShell) {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        try { $full = (Get-Item -LiteralPath $Path).FullName } catch { $full = $Path }
    } else { $full = $Path }
    $apps = Get-Apps
    foreach ($a in $apps) { if ($a.path -ieq $full) { return $a } }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        if ($isShell) { $Name = $Path } else { $Name = [System.IO.Path]::GetFileNameWithoutExtension($full) }
    }
    $apps += [pscustomobject]@{ name = $Name; path = $full; sort = $apps.Count; kind = $Kind }
    Save-Apps $apps
    $icon = if (-not $isShell) { Get-IconBytes $full 256 } else { $null }
    Write-Log "添加应用：$Name -> $full"
    return [pscustomobject]@{ name = $Name; path = $full; iconOk = [bool]$icon }
}

# ---------------------------------------------------------------------------
# 启动应用 + 前台拉起
# ---------------------------------------------------------------------------
function Bring-NewWindowToFront {
    param([IntPtr[]]$Before = @(), [int]$TimeoutMs = 2500, [int]$LaunchedPid = 0)
    $selfPid = [uint32]$PID
    $cands = @{}
    foreach ($h in $Before) { $cands[$h.ToInt64()] = $true }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $touched = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $cur = @([NovaWindow]::SnapshotTopLevel(120, 80))
        foreach ($h in $cur) {
            $key = $h.ToInt64()
            if ($cands.ContainsKey($key)) { continue }
            $winPid = [NovaWindow]::PidOf($h)
            if ($winPid -eq $selfPid) { continue }
            if ($LaunchedPid -gt 0 -and $winPid -ne $LaunchedPid) {
                $pn = [NovaWindow]::ProcNameOf($winPid)
                if ($pn -and $pn -notlike 'explorer' -and $pn -notlike 'searchhost') { continue }
            }
            $touched = $h
            break
        }
        if ($touched -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 80
    }
    if ($touched -ne [IntPtr]::Zero) {
        [NovaWindow]::ForceForeground($touched) | Out-Null
        return $touched
    }
    return $null
}

function Launch-App($item) {
    $p = [string]$item.path
    if ($p -like 'shell:*') {
        $before = @([NovaWindow]::SnapshotTopLevel(120, 80))
        try { Start-Process explorer.exe -ArgumentList $p | Out-Null; Write-Log "启动(shell):$p" }
        catch { return [pscustomobject]@{ ok = $false; msg = $_.Exception.Message } }
        $w = Bring-NewWindowToFront -Before $before
        $tail = if ($w) { '' } else { '（窗口已就绪但未捕捉到，可能已在运行）' }
        return [pscustomobject]@{ ok = $true; msg = "已启动 $($item.name)$tail" }
    }
    if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]@{ ok = $false; msg = '文件不存在，可能已被移动或删除' } }
    # 文件夹：交给资源管理器打开（Start-Process -FilePath 对目录无效）
    $isDir = $false
    try { $isDir = (Get-Item -LiteralPath $p -ErrorAction Stop).PSIsContainer } catch { }
    if ($isDir) {
        $before = @([NovaWindow]::SnapshotTopLevel(120, 80))
        try { Start-Process explorer.exe -ArgumentList $p | Out-Null; Write-Log "启动(文件夹):$p" }
        catch { return [pscustomobject]@{ ok = $false; msg = $_.Exception.Message } }
        $w = Bring-NewWindowToFront -Before $before
        $tail = if ($w) { '' } else { '（窗口已就绪但未捕捉到，可能已在运行）' }
        return [pscustomobject]@{ ok = $true; msg = "已打开文件夹 $($item.name)$tail" }
    }
    $before = @([NovaWindow]::SnapshotTopLevel(120, 80))
    $proc = $null
    try {
        $wd = Split-Path -Parent $p
        if ($wd -and (Test-Path -LiteralPath $wd)) { $proc = Start-Process -FilePath $p -WorkingDirectory $wd -PassThru }
        else { $proc = Start-Process -FilePath $p -PassThru }
        Write-Log "启动：$p"
    } catch { return [pscustomobject]@{ ok = $false; msg = $_.Exception.Message } }
    $lp = 0
    if ($proc) { try { $lp = [int]$proc.Id } catch { $lp = 0 } }
    $w = Bring-NewWindowToFront -Before $before -LaunchedPid $lp
    $tail = if ($w) { '' } else { '（未捕捉到新窗口，可能已在运行）' }
    return [pscustomobject]@{ ok = $true; msg = "已启动 $($item.name)$tail" }
}

# ---------------------------------------------------------------------------
# 文件选择对话框（直接在 UI 线程显示，与 pickImage 一致，避免跨线程崩溃）
# ---------------------------------------------------------------------------
function Show-OpenFileDialog {
    param(
        [string]$Title = '选择要添加到 Nova Launcher 的应用',
        [switch]$Single
    )
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = $Title
    $d.Filter = '应用程序 (*.exe;*.lnk;*.bat;*.cmd)|*.exe;*.lnk;*.bat;*.cmd|所有文件 (*.*)|*.*'
    $d.Multiselect = (-not $Single)
    $d.RestoreDirectory = $true
    $d.CheckFileExists = $true
    $files = [System.Collections.ArrayList]::new()
    $owner = if ($form) { $form } else { $null }
    try {
        if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
            foreach ($f in $d.FileNames) { [void]$files.Add($f) }
        }
    } finally { try { $d.Dispose() } catch { } }
    # 必须用 ,$files 返回：不加逗号 PowerShell 会把 ArrayList 展开，
    # 单元素时退化成字符串，$files[0] 会取到路径的第一个字符。
    return ,$files
}

# ---------------------------------------------------------------------------
# 已安装应用枚举
# ---------------------------------------------------------------------------
function ConvertFrom-Rot13([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return '' }
    $ch = $s.ToCharArray()
    for ($i = 0; $i -lt $ch.Length; $i++) {
        $c = [int]$ch[$i]
        if     ($c -ge 65  -and $c -le 77)  { $ch[$i] = [char]($c + 13) }
        elseif ($c -ge 78  -and $c -le 90)  { $ch[$i] = [char]($c - 13) }
        elseif ($c -ge 97  -and $c -le 109) { $ch[$i] = [char]($c + 13) }
        elseif ($c -ge 110 -and $c -le 122) { $ch[$i] = [char]($c - 13) }
    }
    return (-join $ch)
}

function Add-UsageCount($table, $key, $n) {
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    $k = $key.Trim().ToLower(); $v = 0
    if ($table.ContainsKey($k)) { $v = [int]$table[$k] }
    $table[$k] = $v + [int]$n
}

function Get-UsageIndex {
    $idx = @{}
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
                        $fn = ($dec -split '\\')[-1]
                        if ($fn -notlike '*.exe') { continue }
                        Add-UsageCount $idx $fn $cnt
                    } catch { }
                }
            }
        }
    } catch { }
    foreach ($sub in @('AppSwitched', 'AppLaunch')) {
        try {
            $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\$sub"
            if (-not (Test-Path $p)) { continue }
            $item = Get-Item -Path $p -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            foreach ($vn in $item.GetValueNames()) {
                try {
                    $raw = $item.GetValue($vn); $cnt = 0
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

function Get-InstallInfo {
    $byName = @{}; $byExe = @{}; $byPfn = @{}
    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    try {
        Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
            $dn = [string]$_.DisplayName; $id = [string]$_.InstallDate
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
    try {
        Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object {
            $pfn = [string]$_.PackageFamilyName; $loc = [string]$_.InstallLocation
            if ([string]::IsNullOrWhiteSpace($pfn) -or [string]::IsNullOrWhiteSpace($loc)) { return }
            try { if (Test-Path -LiteralPath $loc) { $byPfn[$pfn.ToLower()] = (Get-Item -LiteralPath $loc).CreationTime } } catch { }
        }
    } catch { }
    return [pscustomobject]@{ byName = $byName; byExe = $byExe; byPfn = $byPfn }
}

function Get-InstalledApps {
    $seen = @{}
    $apps = [System.Collections.ArrayList]::new()
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
                if ([string]::IsNullOrWhiteSpace($target) -or $target -notlike '*.exe') { return }
                if ($seen.ContainsKey($target)) { return }
                $seen[$target] = $true
                [void]$apps.Add([pscustomobject]@{ name = $_.BaseName; path = $target; kind = 'lnk'; src = '开始菜单' })
            } catch { }
        }
    }
    if ($shellCom) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shellCom) } catch { } }
    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
        $icon = [string]$_.DisplayIcon; $exe = ''
        if ($icon -match '^"{0,1}([^",]*\.exe)"{0,1}') { $exe = $Matches[1] }
        elseif ($icon -match '([^",]*\.exe)') { $exe = $Matches[1] }
        if ([string]::IsNullOrWhiteSpace($exe)) { return }
        $exe = $exe.Trim('"')
        if (-not (Test-Path -LiteralPath $exe)) { return }
        if ($seen.ContainsKey($exe)) { return }
        $seen[$exe] = $true
        [void]$apps.Add([pscustomobject]@{ name = [string]$_.DisplayName; path = $exe; kind = 'registry'; src = '程序和功能' })
    }
    try {
        Get-StartApps -ErrorAction SilentlyContinue | ForEach-Object {
            $aid = [string]$_.AppID
            if ([string]::IsNullOrWhiteSpace($aid)) { return }
            if ($aid -match '\\') {
                if ($aid -notlike '*.exe' -or -not (Test-Path -LiteralPath $aid)) { return }
                $launch = $aid; $kind = 'startapp'
            } else { $launch = "shell:AppsFolder\$aid"; $kind = 'uwp' }
            if ($seen.ContainsKey($launch)) { return }
            $seen[$launch] = $true
            [void]$apps.Add([pscustomobject]@{ name = [string]$_.Name; path = $launch; kind = $kind; src = '已安装应用' })
        }
    } catch { }
    $final = [System.Collections.ArrayList]::new()
    $seenName = @{}
    foreach ($a in $apps) {
        $key = ([string]$a.name).Trim().ToLower()
        if ($key -and $seenName.ContainsKey($key)) { continue }
        if ($key) { $seenName[$key] = $true }
        [void]$final.Add($a)
    }
    $usage = Get-UsageIndex; $inst = Get-InstallInfo
    foreach ($a in $final) {
        $p = [string]$a.path; $lower = $p.ToLower(); $freq = 0; $dt = $null
        if ($lower -like 'shell:appsfolder\*') {
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
            if (-not $dt) { try { if (Test-Path -LiteralPath $p) { $dt = (Get-Item -LiteralPath $p).CreationTime } } catch { } }
        }
        $a | Add-Member -NotePropertyName 'freq' -NotePropertyValue $freq -Force
        $a | Add-Member -NotePropertyName 'installedAt' -NotePropertyValue $(if ($dt) { $dt.ToString('yyyy-MM-dd') } else { '' }) -Force
        $a | Add-Member -NotePropertyName 'installedRaw' -NotePropertyValue $(if ($dt) { $dt.Ticks } else { [long]0 }) -Force
    }
    return $final
}

$script:InstalledCache = $null
$script:InstalledCacheAt = [datetime]::MinValue
function Get-InstalledAppsCached {
    $now = Get-Date
    if ($script:InstalledCache -and ($now - $script:InstalledCacheAt).TotalSeconds -lt 60) { return $script:InstalledCache }
    $script:InstalledCache = Get-InstalledApps
    $script:InstalledCacheAt = $now
    return $script:InstalledCache
}

# ---------------------------------------------------------------------------
# 窗口层：WinForms 无边框 Form
# ---------------------------------------------------------------------------
$script:WantWindowed = $false
$script:WinClientW = 1180
$script:WinClientH = 780

$form = New-Object NovaForm
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar   = $true
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::FromArgb(16, 16, 20)
$form.Icon            = New-Object System.Drawing.Icon((Join-Path $DataDir 'nova-logo.ico'))
$form.Text            = 'Nova Launcher'
# 使用纯 WM_DROPFILES 文件拖放；不注册 IDropTarget，不设置 AllowDrop。
try { $form.EnableNovaFileDrop(); Write-Log 'NovaForm 已启用 WM_DROPFILES 文件拖放' } catch { Write-Log "启用 WM_DROPFILES 失败：$($_.Exception.Message)" }
# 强制设置任务栏图标（AppUserModelID + WM_SETICON）
Set-NovaTaskbarIcon (Join-Path $DataDir 'nova-logo.ico')

$form.NovaDpiChanged = {
    if ($script:WebController) { $script:WebController.Bounds = $form.ClientRectangle }
}

# ---------------------------------------------------------------------------
# 文件拖放落点处理（由 NovaDrop 的 IDropTarget 回调，WM_DROPFILES 作为回退）
# 拿到的是资源管理器给的完整绝对路径，直接记录到 apps.json，不做任何搜索解析。
# 支持任意文件与文件夹：可执行类（.exe/.lnk/.bat/.cmd）直接启动，
# 其余文件交给系统默认关联程序打开，文件夹用资源管理器打开。
# ---------------------------------------------------------------------------
$form.NovaFilesDropped = {
    param([string[]]$files)

    if (-not $files -or $files.Count -eq 0) { return }
    Write-Log "收到文件拖拽：共 $($files.Count) 项"

    $added = @()
    $failed = @()
    $runnable = @('.exe', '.lnk', '.bat', '.cmd')

    foreach ($file in $files) {
        $full = [string]$file
        try {
            if ([string]::IsNullOrWhiteSpace($full)) {
                throw '拖拽路径为空'
            }
            if (-not (Test-Path -LiteralPath $full)) {
                throw '文件不存在或已被移动'
            }

            $item = $null
            try { $item = Get-Item -LiteralPath $full -ErrorAction Stop; $full = $item.FullName } catch { }

            if ($item -and $item.PSIsContainer) {
                $name = [System.IO.Path]::GetFileName($full.TrimEnd('\'))
                $kind = 'folder'
            } else {
                $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
                $name = [System.IO.Path]::GetFileNameWithoutExtension($full)
                $kind = if ($runnable -contains $ext) { $ext.TrimStart('.') } else { 'file' }
            }

            if ([string]::IsNullOrWhiteSpace($name)) { $name = $full }
            Write-Log "拖拽处理[$kind]：$full"

            $r = Add-AppPath $full $name $kind
            if ($r) {
                $added += [pscustomobject]@{ name = [string]$r.name; path = [string]$r.path; kind = $kind }
                Write-Log "拖拽添加成功：$name -> $full"
            } else {
                throw 'Add-AppPath 返回失败'
            }
        } catch {
            $reason = $_.Exception.Message
            $failed += [pscustomobject]@{ path = $full; reason = $reason }
            Write-Log "拖拽添加失败：$full；原因：$reason"
        }
    }

    Write-Log "文件拖拽处理完成：成功 $($added.Count) 个，失败 $($failed.Count) 个"

    # 通知前端刷新应用列表（op 必须与前端 nova-launcher.html 的监听分支一致）
    if ($script:WebView) {
        try {
            $payload = @{
                op          = 'appsChanged'
                added       = $added.Count
                failed      = $failed.Count
                items       = @($added)
                failedItems = @($failed)
            } | ConvertTo-Json -Depth 8 -Compress
            $script:WebView.PostWebMessageAsString($payload)
            Write-Log "已通知前端刷新应用列表（成功 $($added.Count)，失败 $($failed.Count)）"
        } catch {
            Write-Log "通知前端刷新失败：$($_.Exception.Message)"
        }
    }
}

# 拖拽悬停状态 -> 前端遮罩显示/隐藏（AllowExternalDrop 关闭后页面收不到 dragenter）
$form.NovaDragState = {
    param([bool]$active)
    if (-not $script:WebView) { return }
    try {
        $payload = @{ op = 'dragState'; active = [bool]$active } | ConvertTo-Json -Depth 4 -Compress
        $script:WebView.PostWebMessageAsString($payload)
    } catch { }
}

function Set-NovaWindowLayout([switch]$Windowed) {
    $wa = [System.Windows.Forms.Screen]::FromHandle($form.Handle).WorkingArea

    if (-not $wa) { $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
    $dpr = Get-NovaDpiScale $form.Handle
    if ($Windowed) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $cw = [int]($script:WinClientW * $dpr)
        $ch = [int]($script:WinClientH * $dpr)
        $cw = [Math]::Min($cw, $wa.Width)
        $ch = [Math]::Min($ch, $wa.Height)
        $form.Size = New-Object System.Drawing.Size($cw, $ch)
        $lx = $wa.X + [int](($wa.Width - $cw) / 2)
        $ly = $wa.Y + [int](($wa.Height - $ch) / 2)

        $form.Location = New-Object System.Drawing.Point($lx, $ly)

    } else {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.Location = New-Object System.Drawing.Point($wa.X, $wa.Y)
        $form.Size = New-Object System.Drawing.Size($wa.Width, $wa.Height)
    }
    $script:WantWindowed = [bool]$Windowed
}

$form.Add_Resize({
    if ($script:WebController) { $script:WebController.Bounds = $form.ClientRectangle }
})

# ---------------------------------------------------------------------------
# WebView2 层：异步初始化（Form.Shown + Timer 轮询，不阻塞 UI）
# ---------------------------------------------------------------------------
$script:WebController = $null
$script:WebView = $null
$script:InitStep = 0
$script:InitEnvTask = $null
$script:InitCtrlTask = $null
$script:InitEnvironment = $null
$script:InitTimer = $null
$script:PreheatQueue = $null
$script:DropRegTimer = $null

function Start-NovaWebViewInit {
    $script:InitStep = 0
    $script:InitTimer = New-Object System.Windows.Forms.Timer
    $script:InitTimer.Interval = 50
    $script:InitTimer.Add_Tick({ Step-NovaWebViewInit })
    $script:InitTimer.Start()
}

# WebView2 在导航、缩放、DPI 变化时会重建子窗口，导致已注册的拖放目标丢失。
# 用低频定时器幂等重注册（已注册过的窗口会被跳过，不会重复 RegisterDragDrop）。
function Start-NovaDropRegTimer {
    if ($script:DropRegTimer) { return }
    $script:DropRegTimer = New-Object System.Windows.Forms.Timer
    $script:DropRegTimer.Interval = 1500
    $script:DropRegTimer.Add_Tick({
        try {
            $n = [NovaDrop]::RegisterAll($form.Handle)
            if ($n -gt 0) { Write-Log "拖放目标补注册：新增 $n 个窗口" }
        } catch { }
    })
    $script:DropRegTimer.Start()
}

function Step-NovaWebViewInit {
    try {
        switch ($script:InitStep) {
            0 {
            
                $profileDir = Join-Path $DataDir 'WebView2Profile'
                if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
                $script:InitEnvTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $profileDir, $null)
                $script:InitStep = 1

            }
            1 {
                if ($script:InitEnvTask.IsCompleted) {

                    if ($script:InitEnvTask.IsFaulted) {
                        Write-Log "CreateAsync error: $($script:InitEnvTask.Exception.InnerException.Message)"
                        $script:InitTimer.Stop(); return
                    }
                    $script:InitEnvironment = $script:InitEnvTask.Result
                    $script:InitCtrlTask = $script:InitEnvironment.CreateCoreWebView2ControllerAsync($form.Handle)
                    $script:InitStep = 2

                }
            }
            2 {
                if ($script:InitCtrlTask.IsCompleted) {

                    if ($script:InitCtrlTask.IsFaulted) {
                        Write-Log "CreateController error: $($script:InitCtrlTask.Exception.InnerException.Message)"
                        $script:InitTimer.Stop(); return
                    }
                    $script:WebController = $script:InitCtrlTask.Result
                    $script:WebView = $script:WebController.CoreWebView2
                    # 关键：关闭 WebView2 自带的外部拖放。否则 WebView2 会在自己的子窗口
                    # （Chrome_WidgetWin_0 等，覆盖整个客户区）上注册 OLE drop target，
                    # 吞掉从资源管理器拖来的文件，宿主的 IDropTarget / WM_DROPFILES 永远收不到。
                    try {
                        $script:WebController.AllowExternalDrop = $false
                        Write-Log "AllowExternalDrop 已设为 $($script:WebController.AllowExternalDrop)"
                    } catch { Write-Log "设置 AllowExternalDrop 失败：$($_.Exception.Message)" }
                    # WM_DROPFILES 作为回退路径保留（正常情况下由下面的 IDropTarget 接管）
                    try { $form.EnableNovaFileDrop(); Write-Log 'WebView2 初始化后重新启用 WM_DROPFILES 文件拖放' } catch { Write-Log "WebView2 初始化后启用文件拖放失败：$($_.Exception.Message)" }
                    # 在「主窗口 + 全部子窗口」上注册宿主自建拖放目标，直接拿 CF_HDROP 绝对路径
                    try {
                        [NovaDrop]::Install($form.Handle, $form,
                            $form.NovaFilesDropped, $form.NovaDragState,
                            [Action[string]]{ param($m) Write-Log $m })
                        $n = [NovaDrop]::RegisterAll($form.Handle)
                        Write-Log "宿主拖放目标安装完成，本次新注册 $n 个窗口"
                    } catch { Write-Log "安装宿主拖放目标失败：$($_.Exception.Message)" }
                    try { $script:WebController.DefaultBackgroundColor = [System.Drawing.Color]::Transparent } catch { Write-Log "Transparent bg not supported: $($_.Exception.Message)" }
                    $script:WebController.Bounds = $form.ClientRectangle
                    $script:WebController.IsVisible = $true
                    Register-NovaVirtualHost
                    Register-NovaWebMessage
                    $script:WebView.Navigate('https://nova.app/nova-launcher.html')
                    $script:InitTimer.Stop()
                    $script:InitTimer.Dispose()
                    $script:InitStep = 3
                    Write-Log "WebView2 初始化完成"
                    $script:PreheatQueue = New-IconPreheatQueue
                    Start-NovaDropRegTimer
                    Initialize-NovaDebugHook
                }
            }
        }
    } catch {
        Write-Log "Step-NovaWebViewInit error: $($_.Exception.Message)"
        $script:InitTimer.Stop()
    }
}
function Register-NovaVirtualHost {
    $kind = [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow
    $script:WebView.SetVirtualHostNameToFolderMapping('nova.app', $DataDir, $kind)
}

# ---------------------------------------------------------------------------
# 调试钩子（仅当 DataDir\DEBUG.flag 存在时启用；验证用，正式发布不创建该文件）
# 写 JS 到 debug-js.txt -> 后端用 CDP Runtime.evaluate 执行；内容为 __SHOT__ 则页面截图存 debug-shot.png
# ---------------------------------------------------------------------------
function Invoke-NovaCdp([string]$method, [string]$paramsJson) {
    # 在 UI 线程上边泵消息边等待，避免 .GetResult() 死锁，也不跨 PowerShell runspace
    $task = $script:WebView.CallDevToolsProtocolMethodAsync($method, $paramsJson)
    $guard = 0
    while (-not $task.IsCompleted -and $guard -lt 600) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 15
        $guard++
    }
    if (-not $task.IsCompleted) { throw "CDP 调用超时: $method" }
    if ($task.IsFaulted) { throw $task.Exception.InnerException.Message }
    return [string]$task.Result
}

function Initialize-NovaDebugHook {
    if (-not (Test-Path (Join-Path $DataDir 'DEBUG.flag'))) { return }
    try {
        $script:DebugTimer = New-Object System.Windows.Forms.Timer
        $script:DebugTimer.Interval = 700
        $script:DebugTimer.Add_Tick({
            $jsFile = Join-Path $DataDir 'debug-js.txt'
            if (-not (Test-Path $jsFile)) { return }
            $js = ''
            try { $js = [IO.File]::ReadAllText($jsFile) } catch { return }
            try { Remove-Item $jsFile -Force -ErrorAction SilentlyContinue } catch {}
            if ([string]::IsNullOrWhiteSpace($js)) { return }
            try {
                if ($js.Trim() -eq '__SHOT__') {
                    $raw = Invoke-NovaCdp 'Page.captureScreenshot' '{"format":"png","captureBeyondViewport":true}'
                    $obj = $raw | ConvertFrom-Json
                    $shotPath = Join-Path $DataDir 'debug-shot.png'
                    [IO.File]::WriteAllBytes($shotPath, [Convert]::FromBase64String([string]$obj.data))
                    Write-Log "DEBUG 截图已保存: $shotPath"
                } else {
                    $p = @{ expression = $js; returnByValue = $true } | ConvertTo-Json -Depth 5 -Compress
                    $raw = Invoke-NovaCdp 'Runtime.evaluate' $p
                    $outFile = Join-Path $DataDir 'debug-result.txt'
                    [IO.File]::WriteAllText($outFile, [string]$raw, [Text.Encoding]::UTF8)
                    Write-Log "DEBUG JS 执行完成"
                }
            } catch { Write-Log "DEBUG 钩子失败: $($_.Exception.Message)" }
        })
        $script:DebugTimer.Start()
        Write-Log "DEBUG 调试钩子已启用"
    } catch { Write-Log "DEBUG 钩子初始化失败: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
# 通信层：postMessage 分发
# ---------------------------------------------------------------------------
function Invoke-NovaApi([string]$op, $data) {
    switch ($op) {
        'state' {
            $apps = Get-Apps
            $out = @()
            foreach ($a in $apps) {
                $exists = if ($a.path -like 'shell:*') { $true } else { (Test-Path -LiteralPath $a.path) }
                $out += [pscustomobject]@{ name = $a.name; path = $a.path; exists = $exists; kind = ([string]$a.kind) }
            }
            $st = if ($script:WantWindowed) { 'windowed' } else { 'maximized' }
            return [pscustomobject]@{ apps = @($out); settings = (Get-Settings); state = $st; dpr = (Get-NovaDpiScale $form.Handle) }
        }
        'ping' {
            return [pscustomobject]@{ ok = $true; state = $(if ($script:WantWindowed) { 'windowed' } else { 'maximized' }) }
        }
        'checkapps' {
            $apps = Get-Apps; $bad = @(); $okN = 0
            for ($idx = 0; $idx -lt $apps.Count; $idx++) {
                $p = [string]$apps[$idx].path; $why = ''
                if ([string]::IsNullOrWhiteSpace($p)) { $why = '路径为空' }
                elseif ($p -like 'shell:*') { $okN++; continue }
                elseif (-not (Test-Path -LiteralPath $p)) { $why = '文件不存在' }
                elseif ($p -like '*.lnk' -and -not (Resolve-LinkTarget $p)) { $why = '快捷方式目标不存在' }
                else { $okN++; continue }
                $bad += [pscustomobject]@{ i = $idx; name = [string]$apps[$idx].name; path = $p; reason = $why }
            }
            return [pscustomobject]@{ ok = $true; total = $apps.Count; okCount = $okN; bad = @($bad) }
        }
        'icon' {
            $custom = [string]$data.p
            if ($custom) {
                $size = 256
                if ($data.s) { [int]::TryParse([string]$data.s, [ref]$size) | Out-Null }
                if ($size -lt 16 -or $size -gt 512) { $size = 256 }
                if ($custom -notmatch '^shell:') {
                    $bytes = Get-IconBytes $custom $size
                    if ($bytes) {
                        $b64 = [Convert]::ToBase64String($bytes)
                        return [pscustomobject]@{ ok = $true; dataUri = "data:image/png;base64,$b64" }
                    }
                }
                return [pscustomobject]@{ ok = $false; msg = 'no icon' }
            }
            $apps = Get-Apps; $i = -1
            if ($null -ne $data.i) { [int]::TryParse([string]$data.i, [ref]$i) | Out-Null }
            if ($i -lt 0 -or $i -ge $apps.Count) { return [pscustomobject]@{ ok = $false; msg = 'no such app' } }
            $size = 256
            if ($data.s) { [int]::TryParse([string]$data.s, [ref]$size) | Out-Null }
            if ($size -lt 16 -or $size -gt 512) { $size = 256 }
            $bytes = Get-IconBytes ([string]$apps[$i].path) $size
            if (-not $bytes) { return [pscustomobject]@{ ok = $false; msg = 'no icon' } }
            $b64 = [Convert]::ToBase64String($bytes)
            return [pscustomobject]@{ ok = $true; dataUri = "data:image/png;base64,$b64" }
        }
        'installed' {
            $apps = @(Get-InstalledAppsCached)
            $sort = [string]$data.sort; $q = [string]$data.q
            if ($q) {
                $q = $q -replace '\[', '[[]'
                $apps = @($apps | Where-Object { ($_.name -like "*$q*") -or ($_.path -like "*$q*") })
            }
            switch ($sort) {
                'freq'      { $apps = @($apps | Sort-Object @{ e = { [int]$_.freq }; Descending = $true }, { $_.name }) }
                'installed' { $apps = @($apps | Sort-Object @{ e = { [long]$_.installedRaw }; Descending = $true }, { $_.name }) }
                'name'      { $apps = @($apps | Sort-Object { $_.name }) }
                'path'      { $apps = @($apps | Sort-Object { $_.path }) }
                'kind'      { $apps = @($apps | Sort-Object { $_.kind }, { $_.name }) }
                'src'       { $apps = @($apps | Sort-Object { $_.src }, { $_.name }) }
                default     { $apps = @($apps | Sort-Object @{ e = { [int]$_.freq }; Descending = $true }, { $_.name }) }
            }
            return [pscustomobject]@{ count = $apps.Count; apps = @($apps) }
        }
        'launch' {
            $apps = Get-Apps; $i = -1
            if ($null -ne $data.i) { [int]::TryParse([string]$data.i, [ref]$i) | Out-Null }
            if ($i -lt 0 -or $i -ge $apps.Count) { return [pscustomobject]@{ ok = $false; msg = '应用不存在' } }
            return (Launch-App $apps[$i])
        }
        'pick' {
            $files = Show-OpenFileDialog
            if (-not $files -or $files.Count -eq 0) { return [pscustomobject]@{ ok = $false; cancelled = $true; msg = '已取消' } }
            $added = @(); $failed = @()
            foreach ($f in $files) {
                $r = Add-AppPath $f '' ''
                if ($r) { $added += $r.name } else { $failed += (Split-Path $f -Leaf) }
            }
            return [pscustomobject]@{ ok = ($added.Count -gt 0); added = @($added); failed = @($failed); msg = ("已添加 " + ($added -join '、')) }
        }
        'pickImage' {
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = '图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|所有文件|*.*'
            $dlg.Title = '选择背景图片'
            $dlg.Multiselect = $false
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $bgDir = Join-Path $DataDir 'bgimages'
                if (-not (Test-Path $bgDir)) { New-Item -ItemType Directory -Path $bgDir -Force | Out-Null }
                $ext = [System.IO.Path]::GetExtension($dlg.FileName)
                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                $destName = "bg_$stamp$ext"
                $destPath = Join-Path $bgDir $destName
                Copy-Item -LiteralPath $dlg.FileName -Destination $destPath -Force
                return [pscustomobject]@{ ok = $true; path = $destName; fullPath = $destPath }
            }
            return [pscustomobject]@{ ok = $false; cancelled = $true }
        }
        'add' {
            $dropP = [string]$data.p; $dropN = [string]$data.n
            $rp = Resolve-AppRef $dropP $dropN
            if ($rp) { $dropP = $rp }
            $r = Add-AppPath $dropP $dropN ([string]$data.k)
            if ($r) { return [pscustomobject]@{ ok = $true; name = $r.name; path = $r.path; msg = "已添加 $($r.name)" } }
            else { return [pscustomobject]@{ ok = $false; msg = '未找到该文件（已查桌面 / 开始菜单 / 快速启动 / 下载）' } }
        }
        'addbatch' {
            $items = @()
            if ($data -and $data.PSObject.Properties['items'] -and $data.items) { $items = @($data.items) }
            $okItems = @(); $badItems = @()
            foreach ($it in $items) {
                $p = [string]$it.p; $n = [string]$it.n; $k = [string]$it.k
                $usable = $false
                if ($p -like 'shell:*') { $usable = $true }
                else { try { if ([System.IO.Path]::IsPathRooted($p) -and (Test-Path -LiteralPath $p)) { $usable = $true } } catch { } }
                if (-not $usable) {
                    $rp = Resolve-AppRef $p $n
                    if ($rp) {
                        $p = $rp
                        if ([string]::IsNullOrWhiteSpace($n)) { try { $n = [System.IO.Path]::GetFileNameWithoutExtension($p) } catch { $n = $p } }
                        $k = ''
                    }
                }
                $r = Add-AppPath $p $n $k
                if ($r) { $okItems += [pscustomobject]@{ name = $r.name; path = $r.path } }
                else {
                    $why = '无效路径'
                    if ([string]::IsNullOrWhiteSpace($p)) { $why = '未找到（已查桌面 / 开始菜单 / 快速启动 / 下载，可改用「添加应用」手动选择）' }
                    elseif ($p -notlike 'shell:*' -and -not (Test-Path -LiteralPath $p)) { $why = '文件不存在或已被移动' }
                    if ([string]::IsNullOrWhiteSpace($n)) { try { $n = Split-Path $p -Leaf } catch { $n = $p } }
                    $badItems += [pscustomobject]@{ name = $n; path = $p; why = $why }
                }
            }
            Write-Log "批量添加：成功 $($okItems.Count) 个，失败 $($badItems.Count) 个"
            return [pscustomobject]@{ ok = ($okItems.Count -gt 0); added = $okItems.Count; addedItems = @($okItems); failed = @($badItems); failedCount = $badItems.Count }
        }
        'remove' {
            $apps = Get-Apps; $i = -1
            if ($null -ne $data.i) { [int]::TryParse([string]$data.i, [ref]$i) | Out-Null }
            if ($i -lt 0 -or $i -ge $apps.Count) { return [pscustomobject]@{ ok = $false; msg = '应用不存在' } }
            $name = $apps[$i].name; $rest = @()
            for ($k = 0; $k -lt $apps.Count; $k++) { if ($k -ne $i) { $rest += $apps[$k] } }
            Save-Apps $rest
            Write-Log "移除应用：$name"
            return [pscustomobject]@{ ok = $true; msg = "已移除 $name" }
        }
        'rename' {
            $newName = ([string]$data.n).Trim()
            if (-not $newName) { return [pscustomobject]@{ ok = $false; msg = '名称不能为空' } }
            if ($newName.Length -gt 60) { $newName = $newName.Substring(0, 60) }
            $apps = Get-Apps; $n = @($apps).Count; $idx = -1
            $wantPath = [string]$data.p
            if ($wantPath) { for ($k = 0; $k -lt $n; $k++) { if ([string]$apps[$k].path -eq $wantPath) { $idx = $k; break } } }
            if ($idx -lt 0 -and $null -ne $data.i) { [int]::TryParse([string]$data.i, [ref]$idx) | Out-Null }
            if ($idx -lt 0 -or $idx -ge $n) { return [pscustomobject]@{ ok = $false; msg = '应用不存在' } }
            $old = [string]$apps[$idx].name
            if ($old -ne $newName) { $apps[$idx].name = $newName; Save-Apps $apps; Write-Log "重命名：$old -> $newName" }
            return [pscustomobject]@{ ok = $true; name = $newName; msg = "已重命名为 $newName" }
        }
        'pickone' {
            # 右键菜单「选择应用」：选一个可执行文件，返回其绝对路径供 editpath 使用
            $files = Show-OpenFileDialog -Title '选择应用' -Single
            if (-not $files -or $files.Count -eq 0) { return [pscustomobject]@{ ok = $false; cancelled = $true; msg = '已取消' } }
            return [pscustomobject]@{ ok = $true; path = [string]$files[0] }
        }
        'editpath' {
            # 右键菜单「选择应用」/「编辑应用地址」：改写指定应用的路径，并同步 kind
            $apps = Get-Apps; $n = @($apps).Count; $idx = -1
            # 注意：索引 0 必须能通过，不能用 if($data.i)（PowerShell 里 if(0) 为 false）
            if ($null -ne $data.i) { [int]::TryParse([string]$data.i, [ref]$idx) | Out-Null }
            if ($idx -lt 0 -or $idx -ge $n) { return [pscustomobject]@{ ok = $false; msg = '应用不存在' } }

            $newPath = ([string]$data.p).Trim().Trim('"')
            if ([string]::IsNullOrWhiteSpace($newPath)) { return [pscustomobject]@{ ok = $false; msg = '路径不能为空' } }

            $isDir = $false
            if ($newPath -notlike 'shell:*') {
                if (-not (Test-Path -LiteralPath $newPath)) { return [pscustomobject]@{ ok = $false; msg = '文件不存在或已被移动' } }
                try { $item = Get-Item -LiteralPath $newPath -ErrorAction Stop; $newPath = $item.FullName; $isDir = $item.PSIsContainer } catch { }
            }

            $old = [string]$apps[$idx].path
            if ($old -ine $newPath) {
                $ext = [System.IO.Path]::GetExtension($newPath).ToLowerInvariant()
                $k = if ($isDir) { 'folder' } elseif (@('.exe', '.lnk', '.bat', '.cmd') -contains $ext) { $ext.TrimStart('.') } else { 'file' }
                # 名称跟随新路径重算（命名规则与 Add-AppPath 一致），否则会出现
                # 地址指向新程序、标题还是旧名字的割裂状态
                $newName = if ($newPath -like 'shell:*') { $newPath } elseif ($isDir) { [System.IO.Path]::GetFileName($newPath.TrimEnd('\')) } else { [System.IO.Path]::GetFileNameWithoutExtension($newPath) }
                if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $newPath }
                $oldName = [string]$apps[$idx].name

                $apps[$idx].path = $newPath
                $apps[$idx].name = $newName
                if ($apps[$idx].PSObject.Properties['kind']) { $apps[$idx].kind = $k }
                else { $apps[$idx] | Add-Member -NotePropertyName 'kind' -NotePropertyValue $k }
                Save-Apps $apps
                Write-Log "编辑地址：$old -> $newPath（名称 $oldName -> $newName，kind=$k）"
            }
            return [pscustomobject]@{ ok = $true; path = $newPath; msg = '路径已更新' }
        }
        'move' {
            $from = -1; $to = -1
            [int]::TryParse([string]$data.from, [ref]$from) | Out-Null
            [int]::TryParse([string]$data.to, [ref]$to) | Out-Null
            $apps = Get-Apps; $n = @($apps).Count
            if ($from -lt 0 -or $from -ge $n -or $to -lt 0 -or $to -ge $n) { return [pscustomobject]@{ ok = $false; msg = '索引越界' } }
            $list = New-Object System.Collections.ArrayList
            foreach ($a in $apps) { [void]$list.Add($a) }
            $item = $list[$from]; $list.RemoveAt($from); $list.Insert($to, $item)
            Save-Apps @($list)
            return [pscustomobject]@{ ok = $true }
        }
        'setting' {
            $k = [string]$data.k; $v = $data.v; $s = Get-Settings
            if ($k -eq 'all') {
                $s = $v | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                Set-NovaDwmBackground $form.Handle $s.glassEnabled ([int]$s.windowOpacity) ($s.theme -ne 'light')
                Save-Settings $s
                return [pscustomobject]@{ ok = $true; settings = $s }
            }
            $v = [string]$v
            switch ($k) {
                'iconSize' { $n = 64; if ([int]::TryParse($v, [ref]$n)) { $s.iconSize = [Math]::Max(36, [Math]::Min(160, $n)) } }
                'cols'     { $n = 6;  if ([int]::TryParse($v, [ref]$n)) { $s.cols     = [Math]::Max(3,  [Math]::Min(12, $n)) } }
                'theme'    { if ($v -eq 'light' -or $v -eq 'dark') { $s.theme = $v; Set-NovaDwmBackground $form.Handle $s.glassEnabled ([int]$s.windowOpacity) ($s.theme -ne 'light') } }
                'glassEnabled' {
                    $s.glassEnabled = ($v -eq 'true' -or $v -eq 'True')
                    Set-NovaDwmBackground $form.Handle $s.glassEnabled ([int]$s.windowOpacity) ($s.theme -ne 'light')
                }
                'glassIntensity' { $n = 50; if ([int]::TryParse($v, [ref]$n)) { $s.glassIntensity = [Math]::Max(0, [Math]::Min(100, $n)) } }
                'bgStyle' { if ($v -eq 'mica' -or $v -eq 'liquid') { $s.bgStyle = $v } }
                'windowOpacity' {
                    $n = 100; if ([int]::TryParse($v, [ref]$n)) { $s.windowOpacity = [Math]::Max(20, [Math]::Min(100, $n)) }
                    Set-NovaDwmBackground $form.Handle $s.glassEnabled ([int]$s.windowOpacity) ($s.theme -ne 'light')
                }
                'bgBlur' {
                    # 背景模糊是纯前端效果（雾面膜浓度），不碰 DWM，也不碰透明度，这里只负责存值
                    $n = 0; if ([int]::TryParse($v, [ref]$n)) { $s.bgBlur = [Math]::Max(0, [Math]::Min(100, $n)) }
                }
                'bgImageEnabled' { $s.bgImageEnabled = ($v -eq 'true' -or $v -eq 'True') }
                'bgImagePath' { $s.bgImagePath = $v }
                'bgImageMode' { if ($v -in @('cover','contain','100% auto','repeat','100% 100%')) { $s.bgImageMode = $v } }
                'iconFontFamily' { $s.iconFontFamily = $v }
                'iconFontSize' { $n = 12; if ([int]::TryParse($v, [ref]$n)) { $s.iconFontSize = [Math]::Max(10, [Math]::Min(24, $n)) } }
                'iconFontColor' { $s.iconFontColor = $v }
                'iconFontWeight' { $n = 600; if ([int]::TryParse($v, [ref]$n)) { $s.iconFontWeight = $n } }
            }
            Save-Settings $s
            return [pscustomobject]@{ ok = $true; settings = $s }
        }
        'reveal' {
            $tgt = [string]$data.p
            if (-not $tgt -and $null -ne $data.i) {
                $idx = -1; [int]::TryParse([string]$data.i, [ref]$idx) | Out-Null
                $apps = Get-Apps
                if ($idx -ge 0 -and $idx -lt @($apps).Count) { $tgt = [string]$apps[$idx].path }
            }
            try {
                if ($tgt -and $tgt -notlike 'shell:*' -and (Test-Path -LiteralPath $tgt)) {
                    Start-Process explorer.exe -ArgumentList ('/select,"' + $tgt + '"')
                } else { Start-Process explorer.exe -ArgumentList "`"$DataDir`"" }
            } catch { }
            return [pscustomobject]@{ ok = $true }
        }
        'win' {
            $op2 = [string]$data.op
            switch ($op2) {
                'state' {
                    return [pscustomobject]@{ ok = $true; state = $(if ($script:WantWindowed) { 'windowed' } else { 'maximized' }) }
                }
                'rect' {
                    $r = $form.Bounds
                    return [pscustomobject]@{ ok = $true; rect = @{ l = $r.X; t = $r.Y; w = $r.Width; h = $r.Height } }
                }
                'min' {
                    $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
                    return [pscustomobject]@{ ok = $true; state = 'minimized' }
                }
                'max' {
                    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
                        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                    }
                    if ($script:WantWindowed) { Set-NovaWindowLayout } else { Set-NovaWindowLayout -Windowed }
                    return [pscustomobject]@{ ok = $true; state = $(if ($script:WantWindowed) { 'windowed' } else { 'maximized' }) }
                }
                'move' {
                    $mx = 0; $my = 0
                    [void][int]::TryParse([string]$data.x, [ref]$mx)
                    [void][int]::TryParse([string]$data.y, [ref]$my)
                    $form.Location = New-Object System.Drawing.Point($mx, $my)
                    return [pscustomobject]@{ ok = $true }
                }
                'close' {
                    $form.Close()
                    return [pscustomobject]@{ ok = $true; state = 'closing' }
                }
                default { return [pscustomobject]@{ ok = $false; msg = "未知窗口操作：$op2" } }
            }
        }
        'quit' {
            Write-Log '收到退出指令'
            $form.Close()
            return [pscustomobject]@{ ok = $true }
        }
        default {
            return [pscustomobject]@{ ok = $false; msg = "未知 op: $op" }
        }
    }
}

function Register-NovaWebMessage {
    $script:WebView.add_WebMessageReceived({
        param($sender, $e)
        try {
            $msg = $e.WebMessageAsJson | ConvertFrom-Json
            $id = $msg.id; $op = [string]$msg.op; $data = $msg.data
            $result = Invoke-NovaApi $op $data
            $resp = @{ id = $id; ok = $true; data = $result } | ConvertTo-Json -Depth 10 -Compress
        } catch {

            $resp = @{ id = $id; ok = $false; msg = $_.Exception.Message } | ConvertTo-Json -Compress
        }
        try { $sender.PostWebMessageAsJson($resp) } catch { Write-Log "PostWebMessageAsJson 失败: $($_.Exception.Message)" }
    })
}

# 图标预热定时器（WebView2 初始化完成后启动）
$preheatTimer = New-Object System.Windows.Forms.Timer
$preheatTimer.Interval = 1500
$preheatTimer.Add_Tick({
    if ($script:PreheatQueue) { Process-IconPreheat $script:PreheatQueue 6 }
})

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
try {
    $settings = Get-Settings
    if ($settings.win -and $settings.win.state -eq 'windowed') { $script:WantWindowed = $true }

    $form.Add_Shown({

        if ($script:InitStep -eq 0) {
            Set-NovaWindowLayout -Windowed:$script:WantWindowed
            Set-NovaDwmBackground $form.Handle $settings.glassEnabled ([int]$settings.windowOpacity) ($settings.theme -ne 'light')
            Start-NovaWebViewInit
            $preheatTimer.Start()
        }
    })

    $form.Add_FormClosed({
        try { $form.DisableNovaFileDrop() } catch { }
        try { if ($script:DropRegTimer) { $script:DropRegTimer.Stop(); $script:DropRegTimer.Dispose(); $script:DropRegTimer = $null } } catch { }
        try {
            $preheatTimer.Stop()
            if ($script:WebController) { $script:WebController.Close() }
        } catch { }
        # 保存窗口状态
        try {
            $s = Get-Settings
            if (-not $s.PSObject.Properties['win']) { $s | Add-Member -NotePropertyName 'win' -NotePropertyValue ([pscustomobject]@{}) }
            $s.win.state = if ($script:WantWindowed) { 'windowed' } else { 'maximized' }
            Save-Settings $s
        } catch { }
    })

    [System.Windows.Forms.Application]::Run($form)
} finally {
    try { if ($script:WebController) { $script:WebController.Close() } } catch { }
}
