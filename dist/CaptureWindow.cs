// Captures a single window's own pixels by handle, via PrintWindow.
//
// Used by the SimplySign Windows probe. Capturing the whole desktop shows
// whatever is on top - on a CI runner that is the agent's console - and
// forcing SimplySign's window to the front is unreliable from a background
// process. PrintWindow asks the window to draw itself, so z-order stops
// mattering.
using System;
using System.Drawing;
using System.Runtime.InteropServices;

public class WinCapture
{
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] private static extern bool SwitchToThisWindow(IntPtr window, bool altTab);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    // PW_RENDERFULLCONTENT - needed for anything drawing outside plain GDI.
    private const uint FullContent = 0x00000002;

    public static void Raise(IntPtr window)
    {
        SwitchToThisWindow(window, true);
    }

    public static string Save(IntPtr window, string path)
    {
        RECT r;
        if (!GetWindowRect(window, out r)) return "GetWindowRect failed";
        int w = r.Right - r.Left, h = r.Bottom - r.Top;
        if (w <= 0 || h <= 0) return "window has no area: " + w + "x" + h;

        using (var bmp = new Bitmap(w, h))
        {
            using (var g = Graphics.FromImage(bmp))
            {
                IntPtr dc = g.GetHdc();
                bool ok = PrintWindow(window, dc, FullContent);
                g.ReleaseHdc(dc);
                if (!ok) return "PrintWindow failed";
            }
            bmp.Save(path);
        }
        return "saved " + w + "x" + h + " to " + path;
    }
}
