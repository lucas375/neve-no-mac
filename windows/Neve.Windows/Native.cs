using System.Runtime.InteropServices;
using Neve.Core;

namespace Neve.Windows;

internal static class Native
{
    private const int GwlExStyle = -20;
    private const long ToolWindow = 0x80, Transparent = 0x20, Layered = 0x80000, NoActivate = 0x08000000;
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct PowerStatus
    {
        public byte Ac, BatteryFlag, BatteryLifePercent, Saver;
        public uint BatteryLifeTime, BatteryFullLifeTime;
    }
    private delegate bool EnumWindow(nint window, nint param);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindow callback, nint param);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint process);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLong64(nint window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern nint SetWindowLong64(nint window, int index, nint value);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowLong32(nint window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] private static extern int SetWindowLong32(nint window, int index, int value);
    private static nint GetWindowLongPtr(nint window, int index) => nint.Size == 8 ? GetWindowLong64(window, index) : (nint)GetWindowLong32(window, index);
    private static nint SetWindowLongPtr(nint window, int index, nint value) => nint.Size == 8 ? SetWindowLong64(window, index, value) : (nint)SetWindowLong32(window, index, value.ToInt32());
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint window, out Rect rect);
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] private static extern int WindowBounds(nint window, int attribute, out Rect rect, int size);
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] private static extern int WindowFlag(nint window, int attribute, out int flag, int size);
    [DllImport("user32.dll")] internal static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern nint GetTopWindow(nint parent);
    [DllImport("user32.dll")] private static extern nint GetWindow(nint window, uint command);
    [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(nint window);
    [DllImport("kernel32.dll")] private static extern bool GetSystemPowerStatus(out PowerStatus status);
    [DllImport("user32.dll")] internal static extern bool DestroyIcon(nint icon);

    internal static bool BatterySaver => GetSystemPowerStatus(out var status) && status.Saver == 1;
    internal static void MakeClickThrough(nint window)
    {
        long style = GetWindowLongPtr(window, GwlExStyle).ToInt64();
        SetWindowLongPtr(window, GwlExStyle, (nint)(style | Transparent | Layered | ToolWindow | NoActivate));
    }
    internal static List<WindowGeometry> ReadWindows()
    {
        List<WindowGeometry> result = [];
        uint ownProcess = (uint)Environment.ProcessId;
        EnumWindow callback = (handle, _) =>
        {
            if (!IsWindowVisible(handle) || IsIconic(handle)) return true;
            GetWindowThreadProcessId(handle, out uint process);
            if (process == ownProcess || (GetWindowLongPtr(handle, GwlExStyle).ToInt64() & ToolWindow) != 0) return true;
            if (WindowFlag(handle, 14, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            if (WindowBounds(handle, 9, out var rect, Marshal.SizeOf<Rect>()) != 0 && !GetWindowRect(handle, out rect)) return true;
            if (rect.Right - rect.Left >= 90 && rect.Bottom - rect.Top >= 28)
                result.Add(new(handle.ToInt64(), new(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top)));
            return result.Count < 128;
        };
        EnumWindows(callback, 0);
        GC.KeepAlive(callback);
        // EnumWindows finds safe candidates; the explicit Z-order walk determines occlusion.
        var byHandle = result.ToDictionary(w => w.Id);
        List<WindowGeometry> ordered = [];
        HashSet<nint> visited = [];
        for (nint current = GetTopWindow(0); current != 0 && visited.Count < 2048 && visited.Add(current); current = GetWindow(current, 2))
            if (byHandle.TryGetValue(current.ToInt64(), out var geometry)) ordered.Add(geometry);
        return ordered;
    }
}
