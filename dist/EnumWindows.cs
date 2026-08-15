// Lists every top-level window on the station, with its owning pid.
//
// Used by the SimplySign Windows probe. PowerShell's Get-Process exposes only
// MainWindowHandle, which is 0 for a tray application that has not opened a
// window - and that single value is what made v0.2.10-rc.2 conclude the
// runner had no desktop. Enumerating properly distinguishes "no desktop" from
// "the app simply has no window yet".
//
// Lives in its own file because a PowerShell here-string cannot be indented,
// and everything inside a YAML block scalar must be.
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WinEnum
{
    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumProc callback, IntPtr param);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int max);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder text, int max);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    private delegate bool EnumProc(IntPtr window, IntPtr param);

    public static List<string> All()
    {
        var rows = new List<string>();
        EnumWindows((window, param) =>
        {
            uint pid;
            GetWindowThreadProcessId(window, out pid);
            var title = new StringBuilder(256);
            GetWindowText(window, title, title.Capacity);
            var cls = new StringBuilder(256);
            GetClassName(window, cls, cls.Capacity);
            rows.Add(string.Format("pid={0}\tvisible={1}\thwnd={2}\tclass={3}\ttitle={4}",
                                   pid, IsWindowVisible(window), window, cls, title));
            return true;
        }, IntPtr.Zero);
        return rows;
    }
}
