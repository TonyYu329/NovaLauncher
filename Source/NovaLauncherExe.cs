// NovaLauncher.exe - portable wrapper for NovaLauncher.bat's launch command.
// WinExe target: no console window flash. Icon embedded via /win32icon.
// Portable layout: exe must sit next to the data\ folder (keep source ASCII).
// Build (run from Source\):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /out:NovaLauncher.exe /win32icon:data\nova-logo.ico /r:System.Windows.Forms.dll NovaLauncherExe.cs
using System;
using System.Diagnostics;
using System.IO;

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
}
