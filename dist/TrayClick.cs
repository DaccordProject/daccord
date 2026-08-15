// Finds a notification-area ("tray") icon by name and clicks it.
//
// Needed because SimplySign Desktop keeps its windows hidden until it is asked
// for one, on Windows exactly as on Linux: the probe found WinForms windows
// belonging to the process, all with visible=False, and neither a second
// launch nor SwitchToThisWindow brought one up. On Linux the way in was a
// right-click on the tray icon followed by "Connect with cloud"; this is the
// same move on Windows.
//
// UI Automation is used to locate the icon (its position depends on how many
// other icons are present) and the click is synthesised at its centre, because
// the Invoke pattern maps to a left click and the menu we want is the
// right-click one.
using System;
using System.Runtime.InteropServices;
using System.Windows.Automation;

public class TrayClick
{
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint x, uint y, uint data, IntPtr extra);

    private const uint LeftDown = 0x0002, LeftUp = 0x0004;
    private const uint RightDown = 0x0008, RightUp = 0x0010;

    // Enumerates every button in the notification area, including the overflow
    // ("hidden icons") flyout, so the caller can see what is actually there.
    public static string[] List()
    {
        var found = new System.Collections.Generic.List<string>();
        foreach (var root in Roots())
        {
            var buttons = root.FindAll(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button));
            foreach (AutomationElement b in buttons)
            {
                var r = b.Current.BoundingRectangle;
                found.Add(b.Current.Name + "\t@" + (int)r.X + "," + (int)r.Y);
            }
        }
        return found.ToArray();
    }

    private static System.Collections.Generic.List<AutomationElement> Roots()
    {
        var roots = new System.Collections.Generic.List<AutomationElement>();
        var desktop = AutomationElement.RootElement;
        foreach (var cls in new[] { "Shell_TrayWnd", "NotifyIconOverflowWindow", "TopLevelWindowForOverflowXamlIsland" })
        {
            var els = desktop.FindAll(TreeScope.Children,
                new PropertyCondition(AutomationElement.ClassNameProperty, cls));
            foreach (AutomationElement e in els) roots.Add(e);
        }
        return roots;
    }

    // Returns the description of what it clicked, or null if no icon matched.
    public static string Click(string nameFragment, bool rightClick)
    {
        foreach (var root in Roots())
        {
            var buttons = root.FindAll(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button));
            foreach (AutomationElement b in buttons)
            {
                if (b.Current.Name == null ||
                    b.Current.Name.IndexOf(nameFragment, StringComparison.OrdinalIgnoreCase) < 0) continue;

                var r = b.Current.BoundingRectangle;
                int x = (int)(r.X + r.Width / 2), y = (int)(r.Y + r.Height / 2);
                SetCursorPos(x, y);
                System.Threading.Thread.Sleep(300);
                if (rightClick)
                {
                    mouse_event(RightDown, 0, 0, 0, IntPtr.Zero);
                    mouse_event(RightUp, 0, 0, 0, IntPtr.Zero);
                }
                else
                {
                    mouse_event(LeftDown, 0, 0, 0, IntPtr.Zero);
                    mouse_event(LeftUp, 0, 0, 0, IntPtr.Zero);
                }
                return b.Current.Name + " @" + x + "," + y;
            }
        }
        return null;
    }
}
