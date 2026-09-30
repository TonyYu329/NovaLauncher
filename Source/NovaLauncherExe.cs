// NovaLauncher.exe - portable wrapper for NovaLauncher.bat's launch command.
// WinExe target: no console window flash. Icon embedded via /win32icon.
// Portable layout: exe must sit next to the data\ folder (keep source ASCII).
// On launch it also self-registers the app identity: (re)creates the Start Menu
// shortcut + retargets taskbar pins to point at THIS exe with AUMID NovaLauncher.App,
// so "Pin to taskbar" always resolves to the copy the user actually ran.
// Build (run from Source\):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /out:NovaLauncher.exe /win32icon:data\nova-logo.ico /r:System.Windows.Forms.dll NovaLauncherExe.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

static class NovaLauncher
{
    static void Main(string[] args)
    {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        string ps1 = Path.Combine(exeDir, "data", "NovaLauncher.ps1");

        if (!File.Exists(ps1))
        {
            System.Windows.Forms.MessageBox.Show(
                "NovaLauncher.ps1 not found.\n\n" +
                "Please place NovaLauncher.exe in the Source folder,\n" +
                "next to the data folder.\n\n" +
                "Searched:\n" + ps1,
                "Nova Launcher", System.Windows.Forms.MessageBoxButtons.OK,
                System.Windows.Forms.MessageBoxIcon.Warning);
            return;
        }

        // Self-register THIS exe as the app identity BEFORE launching powershell, so that
        // "Pin to taskbar" and the Start Menu resolve to the copy the user actually ran.
        // Fixes the bug where pinning one portable copy launched a DIFFERENT copy's data
        // (two copies share AUMID "NovaLauncher.App"; identity must point to the running exe).
        string exePath = Assembly.GetExecutingAssembly().Location;
        if (string.IsNullOrEmpty(exePath)) exePath = Path.Combine(exeDir, "NovaLauncher.exe");
        try { RegisterAppIdentity(exePath, exeDir); } catch { }

        string extra = string.Join(" ", args);
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe", // resolved from PATH, same as the bat's "where powershell.exe"
            Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + ps1 + "\"" +
                        (extra.Length > 0 ? " " + extra : ""),
            WorkingDirectory = exeDir,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        try
        {
            Process.Start(psi);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            System.Windows.Forms.MessageBox.Show(
                "powershell.exe not found on PATH.\n\n" +
                "Windows PowerShell 5.1+ is required.",
                "Nova Launcher", System.Windows.Forms.MessageBoxButtons.OK,
                System.Windows.Forms.MessageBoxIcon.Error);
        }
    }

    // ===================== App identity self-registration =====================
    // The UI window lives in powershell.exe which declares AUMID "NovaLauncher.App".
    // Windows resolves "Pin to taskbar" / taskbar icon through a Start Menu shortcut
    // that carries the same AUMID and points to the exe. We (re)create that shortcut
    // pointing to the CURRENTLY RUNNING exe on every launch, and retarget any existing
    // taskbar pins that belong to this app, so the pin always launches the copy the
    // user just ran (works on a fresh PC and with multiple portable copies).
    const string AppUserModelId = "NovaLauncher.App";
    const uint GPS_READWRITE = 0x2;
    const short VT_LPWSTR = 31;
    static readonly Guid PKEY_AUMID_fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
    const int PKEY_AUMID_pid = 5;

    [StructLayout(LayoutKind.Sequential)]
    struct PROPERTYKEY { public Guid fmtid; public int pid; }

    [StructLayout(LayoutKind.Explicit)]
    struct PropVariant
    {
        [FieldOffset(0)] public short vt;
        [FieldOffset(8)] public IntPtr ptr;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        void GetCount(out uint c);
        void GetAt(uint i, out PROPERTYKEY pk);
        void GetValue(ref PROPERTYKEY pk, out PropVariant pv);
        void SetValue(ref PROPERTYKEY pk, ref PropVariant pv);
        void Commit();
    }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short wHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport, Guid("0000010B-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPersistFile
    {
        void GetClassID(out Guid pClassID);
        int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    class ShellLink { }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHGetPropertyStoreFromParsingName(string path, IntPtr bindCtx, uint flags,
        ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

    static void RegisterAppIdentity(string exePath, string exeDir)
    {
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

        // Start Menu registration only: this is what Windows resolves the app AUMID
        // against when the user pins the running window to the taskbar, so the pin
        // always targets the copy that is actually running.
        // We deliberately do NOT rewrite existing taskbar pins here: re-saving a
        // pinned .lnk through IShellLink can strip Explorer's pin metadata and leave
        // a broken pin. User-created pins resolve through this registration instead.
        string smDir = Path.Combine(appData, "Microsoft", "Windows", "Start Menu", "Programs");
        if (Directory.Exists(smDir))
            EnsureShortcut(Path.Combine(smDir, "NovaLauncher.lnk"), exePath, exeDir, false);
    }

    static void EnsureShortcut(string lnkPath, string exePath, string exeDir, bool force)
    {
        if (!force)
        {
            string t = ReadTarget(lnkPath);
            string a = ReadAumid(lnkPath);
            if (string.Equals(t, exePath, StringComparison.OrdinalIgnoreCase) && a == AppUserModelId) return;
        }
        IShellLinkW link = (IShellLinkW)new ShellLink();
        try
        {
            link.SetPath(exePath);
            link.SetArguments("");
            link.SetWorkingDirectory(exeDir);
            link.SetIconLocation(exePath, 0);
            link.SetShowCmd(1); // SW_SHOWNORMAL
            link.SetDescription("Nova Launcher");
            ((IPersistFile)link).Save(lnkPath, false);
        }
        finally { Marshal.ReleaseComObject(link); }
        WriteAumid(lnkPath, AppUserModelId); // must be AFTER Save (Save clears extended props)
    }

    static string ReadTarget(string lnkPath)
    {
        IntPtr pfd = Marshal.AllocHGlobal(1024);
        IShellLinkW link = (IShellLinkW)new ShellLink();
        try
        {
            ((IPersistFile)link).Load(lnkPath, 0); // STGM_READ
            StringBuilder sb = new StringBuilder(1024);
            link.GetPath(sb, sb.Capacity, pfd, 0);
            return sb.ToString();
        }
        catch { return null; }
        finally { Marshal.ReleaseComObject(link); Marshal.FreeHGlobal(pfd); }
    }

    static string ReadAumid(string lnkPath)
    {
        try
        {
            IPropertyStore store; Guid iid = typeof(IPropertyStore).GUID;
            SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, 0, ref iid, out store);
            try
            {
                PROPERTYKEY pk = new PROPERTYKEY(); pk.fmtid = PKEY_AUMID_fmtid; pk.pid = PKEY_AUMID_pid;
                PropVariant pv; store.GetValue(ref pk, out pv);
                if (pv.vt == VT_LPWSTR && pv.ptr != IntPtr.Zero) return Marshal.PtrToStringUni(pv.ptr);
                return null;
            }
            finally { Marshal.ReleaseComObject(store); }
        }
        catch { return null; }
    }

    static void WriteAumid(string lnkPath, string aumid)
    {
        IPropertyStore store; Guid iid = typeof(IPropertyStore).GUID;
        SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, GPS_READWRITE, ref iid, out store);
        try
        {
            PROPERTYKEY pk = new PROPERTYKEY(); pk.fmtid = PKEY_AUMID_fmtid; pk.pid = PKEY_AUMID_pid;
            PropVariant pv = new PropVariant();
            pv.vt = VT_LPWSTR;
            pv.ptr = Marshal.StringToCoTaskMemUni(aumid);
            try { store.SetValue(ref pk, ref pv); store.Commit(); }
            finally { Marshal.FreeCoTaskMem(pv.ptr); }
        }
        finally { Marshal.ReleaseComObject(store); }
    }
}
