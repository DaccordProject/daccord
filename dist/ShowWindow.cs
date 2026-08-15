// Brings a window to the foreground by handle.
//
// The SimplySign probe needs this because the app's window is not its
// MainWindowHandle, so PowerShell's usual AppActivate (which takes a process
// id) cannot reach it.
using System;
using System.Runtime.InteropServices;

public class WinShow
{
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int cmd);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);

    private const int SW_RESTORE = 9;

    public static void Raise(IntPtr window)
    {
        ShowWindow(window, SW_RESTORE);
        SetForegroundWindow(window);
    }
}
