using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Neve.Core;

namespace Neve.Windows;

internal sealed class OverlayWindow : Window
{
    internal System.Drawing.Rectangle PhysicalBounds { get; }
    internal double Scale { get; private set; } = 1;
    internal SnowModel Model { get; private set; }
    internal SnowView Canvas { get; private set; }
    private HwndSource? source;

    internal OverlayWindow(System.Drawing.Rectangle bounds, SnowSettings settings)
    {
        PhysicalBounds = bounds;
        Model = new(Math.Max(1, bounds.Width), Math.Max(1, bounds.Height), settings);
        Canvas = new(Model) { ClipToBounds = true, IsHitTestVisible = false };
        Title = "Neve no Windows";
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true; ResizeMode = ResizeMode.NoResize;
        Left = bounds.X; Top = bounds.Y; Width = bounds.Width; Height = bounds.Height;
        Content = Canvas;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            Native.MakeClickThrough(handle);
            source = HwndSource.FromHwnd(handle); source?.AddHook(WindowMessage);
            Native.SetWindowPos(handle, (nint)(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x0010);
        };
        Loaded += (_, _) => Align();
        Closed += (_, _) => { source?.RemoveHook(WindowMessage); source = null; Content = null; };
    }
    private nint WindowMessage(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == 0x0084) { handled = true; return (nint)(-1); } // HTTRANSPARENT
        if (message == 0x0021) { handled = true; return (nint)3; } // MA_NOACTIVATE
        if (message == 0x02E0) Dispatcher.BeginInvoke(new Action(Align)); // WM_DPICHANGED
        return 0;
    }
    private void Align()
    {
        if (source is null) return;
        var b = PhysicalBounds;
        Native.SetWindowPos(source.Handle, (nint)(-1), b.X, b.Y, b.Width, b.Height, 0x0010);
        Scale = Math.Max(1, VisualTreeHelper.GetDpi(this).DpiScaleX);
        double width = b.Width / Scale, height = b.Height / Scale;
        if (Math.Abs(Model.Width - width) < 0.1 && Math.Abs(Model.Height - height) < 0.1) return;
        var settings = Model.Settings;
        Model = new(width, height, settings);
        Canvas = new(Model) { ClipToBounds = true, IsHitTestVisible = false };
        Content = Canvas;
    }
    internal void UpdateWindows(IReadOnlyList<WindowGeometry> windows)
    {
        var b = PhysicalBounds;
        var local = windows.Select(w => new WindowGeometry(w.Id, new(
            (w.Bounds.X - b.X) / Scale, (w.Bounds.Y - b.Y) / Scale, w.Bounds.Width / Scale, w.Bounds.Height / Scale))).ToArray();
        Model.UpdateWindows(local);
    }
}
