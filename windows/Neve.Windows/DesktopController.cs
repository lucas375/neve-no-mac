using Microsoft.Win32;
using System.Windows;
using System.Windows.Threading;
using Neve.Core;
using Forms = System.Windows.Forms;

namespace Neve.Windows;

internal sealed class DesktopController : IDisposable
{
    private readonly Application app;
    private readonly Forms.NotifyIcon tray;
    private readonly System.Drawing.Icon trayIcon;
    private readonly DispatcherTimer timer;
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly List<OverlayWindow> overlays = [];
    private SettingsWindow? settingsWindow;
    private double lastFrame, lastScan;
    private long? frontWindow;
    private bool sessionHidden, suspended;
    private bool Visible => Running && !sessionHidden && !suspended;
    internal bool Running { get; private set; } = true;
    internal SnowSettings Settings { get; private set; } = Preferences.Load();

    internal DesktopController(Application application)
    {
        app = application;
        trayIcon = MakeTrayIcon();
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Ajustes…", null, (_, _) => OpenSettings());
        menu.Items.Add("Pausar / continuar", null, (_, _) => SetRunning(!Running));
        menu.Items.Add("Tratores em todas as janelas", null, (_, _) => PloughAll());
        menu.Items.Add("Sair", null, (_, _) => Quit());
        tray = new Forms.NotifyIcon { Icon = trayIcon, Text = "Neve no Windows · Clique para ajustar", ContextMenuStrip = menu, Visible = true };
        tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) OpenSettings(); };
        timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromSeconds(1.0 / 60) };
        timer.Tick += Tick;
        SystemEvents.DisplaySettingsChanged += DisplayChanged;
        SystemEvents.SessionSwitch += SessionChanged;
        SystemEvents.PowerModeChanged += PowerChanged;
        RebuildDisplays(); timer.Start();
    }
    private void RebuildDisplays()
    {
        foreach (var overlay in overlays) overlay.Close(); overlays.Clear();
        foreach (var screen in Forms.Screen.AllScreens.Take(8))
        {
            var overlay = new OverlayWindow(screen.Bounds, Settings);
            overlays.Add(overlay);
            if (overlays.Count == 1) app.MainWindow = overlay;
            overlay.Show(); if (!Visible) overlay.Hide();
        }
        lastScan = 0;
    }
    private void Tick(object? sender, EventArgs e)
    {
        double now = clock.Elapsed.TotalSeconds, dt = Math.Min(0.05, now - lastFrame); lastFrame = now;
        if (!Visible) return;
        bool lowPower = Native.BatterySaver;
        double interval = Native.GetAsyncKeyState(0x01) < 0 ? 1.0 / 60 : (lowPower ? 0.1 : 1.0 / 30);
        if ((Settings.Accumulation || Settings.Snowman) && now - lastScan >= interval * 0.9)
        {
            ScanWindows(); lastScan = now;
        }
        if (lowPower && dt < 0.025) { timer.Interval = TimeSpan.FromSeconds(1.0 / 30); }
        else if (!lowPower && timer.Interval.TotalSeconds > 0.02) timer.Interval = TimeSpan.FromSeconds(1.0 / 60);
        foreach (var overlay in overlays)
        {
            overlay.Model.Step(dt, lowPower ? 0.5 : 1);
            overlay.Canvas.InvalidateVisual();
        }
    }
    private void ScanWindows()
    {
        var windows = Native.ReadWindows();
        long foreground = Native.GetForegroundWindow().ToInt64();
        if (windows.Exists(w => w.Id == foreground)) frontWindow = foreground;
        foreach (var overlay in overlays) overlay.UpdateWindows(windows);
    }
    internal bool SetSettings(SnowSettings settings)
    {
        Settings = settings.Normalize();
        foreach (var overlay in overlays) { overlay.Model.Settings = Settings; overlay.Canvas.RefreshPiles(); }
        lastScan = 0; return Preferences.Save(Settings);
    }
    internal void SetRunning(bool enabled) { Running = enabled; ApplyVisibility(); }
    private void ApplyVisibility()
    {
        foreach (var overlay in overlays) { if (Visible) overlay.Show(); else overlay.Hide(); }
        lastFrame = clock.Elapsed.TotalSeconds; lastScan = 0;
        if (Visible) timer.Start(); else timer.Stop();
    }
    internal void PloughFront()
    {
        ScanWindows();
        if (frontWindow is { } id) foreach (var overlay in overlays) overlay.Model.StartPlough(id);
    }
    internal void PloughAll() { ScanWindows(); foreach (var overlay in overlays) overlay.Model.StartAllPloughs(); }
    internal void PloughGround() { foreach (var overlay in overlays) overlay.Model.StartPlough(); }
    internal void Clear() { foreach (var overlay in overlays) { overlay.Model.Clear(); overlay.Canvas.RefreshPiles(); } }
    internal void OpenSettings()
    {
        if (settingsWindow is null)
        {
            ScanWindows(); settingsWindow = new(this); settingsWindow.Closed += (_, _) => settingsWindow = null;
        }
        settingsWindow.Show(); settingsWindow.Activate();
    }
    internal void Quit() => app.Shutdown();
    private void DisplayChanged(object? sender, EventArgs e) => app.Dispatcher.BeginInvoke(new Action(RebuildDisplays));
    private void SessionChanged(object sender, SessionSwitchEventArgs e) => app.Dispatcher.BeginInvoke(new Action(() =>
    {
        switch (e.Reason)
        {
            case SessionSwitchReason.SessionLock:
            case SessionSwitchReason.SessionLogoff:
            case SessionSwitchReason.RemoteDisconnect:
            case SessionSwitchReason.ConsoleDisconnect: sessionHidden = true; break;
            case SessionSwitchReason.SessionUnlock:
            case SessionSwitchReason.SessionLogon:
            case SessionSwitchReason.RemoteConnect:
            case SessionSwitchReason.ConsoleConnect: sessionHidden = false; break;
        }
        ApplyVisibility();
    }));
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) => app.Dispatcher.BeginInvoke(new Action(() =>
    {
        if (e.Mode == PowerModes.Suspend) suspended = true;
        if (e.Mode == PowerModes.Resume) suspended = false;
        ApplyVisibility();
    }));
    private static System.Drawing.Icon MakeTrayIcon()
    {
        using var bitmap = new System.Drawing.Bitmap(32, 32);
        using var graphics = System.Drawing.Graphics.FromImage(bitmap);
        graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        graphics.Clear(System.Drawing.Color.Transparent);
        using var pen = new System.Drawing.Pen(System.Drawing.Color.FromArgb(88, 217, 249), 2) { StartCap = System.Drawing.Drawing2D.LineCap.Round, EndCap = System.Drawing.Drawing2D.LineCap.Round };
        for (int i = 0; i < 6; i++)
        {
            double a = i * Math.PI / 3;
            float X(double r, double angle) => 16 + (float)(Math.Cos(angle) * r);
            float Y(double r, double angle) => 16 + (float)(Math.Sin(angle) * r);
            graphics.DrawLine(pen, 16, 16, X(13, a), Y(13, a));
            foreach (int sign in new[] { -1, 1 })
                graphics.DrawLine(pen, X(8, a), Y(8, a), X(8, a) - (float)(Math.Cos(a + sign * Math.PI / 3) * 5), Y(8, a) - (float)(Math.Sin(a + sign * Math.PI / 3) * 5));
        }
        nint handle = bitmap.GetHicon();
        try { using var borrowed = System.Drawing.Icon.FromHandle(handle); return (System.Drawing.Icon)borrowed.Clone(); }
        finally { Native.DestroyIcon(handle); }
    }
    public void Dispose()
    {
        timer.Stop(); timer.Tick -= Tick;
        SystemEvents.DisplaySettingsChanged -= DisplayChanged;
        SystemEvents.SessionSwitch -= SessionChanged;
        SystemEvents.PowerModeChanged -= PowerChanged;
        settingsWindow?.Close(); foreach (var overlay in overlays) overlay.Close(); overlays.Clear();
        tray.Visible = false; tray.ContextMenuStrip?.Dispose(); tray.Dispose(); trayIcon.Dispose();
    }
}
